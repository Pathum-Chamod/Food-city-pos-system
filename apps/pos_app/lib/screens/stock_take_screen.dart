import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';

enum StockTakeFilter {
  all,
  counted,
  discrepancies,
  uncounted,
}

class StockTakeScreen extends StatefulWidget {
  const StockTakeScreen({super.key, this.initialBarcode});

  final String? initialBarcode;

  @override
  State<StockTakeScreen> createState() => _StockTakeScreenState();
}

class _StockTakeScreenState extends State<StockTakeScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sessionNameController = TextEditingController();

  bool _isLoading = true;
  bool _isApplying = false;
  int? _sessionId;
  String _startedAt = '';
  String _searchQuery = '';
  StockTakeFilter _selectedFilter = StockTakeFilter.all;

  List<Product> _products = [];
  Map<String, int> _countedQuantities = {};

  @override
  void initState() {
    super.initState();
    _loadSession(showLoader: true);
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _searchController.dispose();
    _sessionNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSession({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final products = await DatabaseHelper.instance.getProducts();
      final session = await DatabaseHelper.instance.getOrCreateOpenStockTakeSession();
      final sessionId = (session['id'] as num).toInt();
      final items = await DatabaseHelper.instance.getStockTakeSessionItems(sessionId);

      final counted = <String, int>{};
      for (final item in items) {
        counted[(item['barcode'] ?? '').toString()] =
            (item['counted_stock'] as num?)?.toInt() ?? 0;
      }

      if (!mounted) return;

      setState(() {
        _products = products;
        _sessionId = sessionId;
        _sessionNameController.text =
            (session['session_name'] ?? 'Main Store Count').toString();
        _startedAt = (session['started_at'] ?? '').toString();
        _countedQuantities = counted;
        _isLoading = false;
      });

      if (widget.initialBarcode != null && widget.initialBarcode!.trim().isNotEmpty) {
        _barcodeController.text = widget.initialBarcode!.trim();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage('Could not load stock take session.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool get _currentUserIsManager {
    final role = context.read<AuthProvider>().currentUser?.role.toLowerCase();
    return role == 'manager';
  }

  String _buildPerformedByLabel(String? approverName) {
    final currentUser = context.read<AuthProvider>().currentUser;
    final currentName = currentUser?.name?.trim();
    if (_currentUserIsManager) {
      return (currentName == null || currentName.isEmpty)
          ? (approverName ?? 'Manager')
          : currentName;
    }
    if (currentName == null || currentName.isEmpty) {
      return approverName ?? 'Manager';
    }
    if (approverName == null || approverName.trim().isEmpty) {
      return currentName;
    }
    return '$currentName (approved by ${approverName.trim()})';
  }

  Future<String?> _requireManagerApproval(String actionLabel) async {
    if (_currentUserIsManager) {
      final managerName = context.read<AuthProvider>().currentUser?.name?.trim();
      return (managerName == null || managerName.isEmpty) ? 'Manager' : managerName;
    }

    final pinController = TextEditingController();
    String? errorText;
    bool isVerifying = false;

    final approver = await showDialog<String?>(
      context: context,
      barrierDismissible: !isVerifying,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> verify() async {
              final pin = pinController.text.trim();
              if (pin.isEmpty) {
                setDialogState(() {
                  errorText = 'Enter manager PIN.';
                });
                return;
              }

              setDialogState(() {
                isVerifying = true;
                errorText = null;
              });

              final user = await DatabaseHelper.instance.authenticateUser(pin);

              if (!dialogContext.mounted) return;

              if (user == null) {
                setDialogState(() {
                  isVerifying = false;
                  errorText = 'Invalid PIN.';
                });
                return;
              }

              final role = (user['role'] ?? '').toString().toLowerCase();
              if (role != 'manager') {
                setDialogState(() {
                  isVerifying = false;
                  errorText = 'PIN does not belong to a manager.';
                });
                return;
              }

              Navigator.pop(
                dialogContext,
                (user['name'] ?? 'Manager').toString(),
              );
            }

            return AlertDialog(
              title: const Text('Manager Approval Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter manager PIN to $actionLabel.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Manager PIN',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onSubmitted: (_) {
                      if (!isVerifying) {
                        verify();
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () => Navigator.pop(dialogContext, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isVerifying ? null : verify,
                  child: isVerifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve'),
                ),
              ],
            );
          },
        );
      },
    );

    pinController.dispose();

    if (approver == null && mounted) {
      _showMessage('Manager approval is required to continue.', isError: true);
    }

    return approver;
  }


  List<Product> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();

    return _products.where((product) {
      final countedQty = _countedQuantities[product.barcode];
      final hasCount = countedQty != null;
      final hasDiscrepancy = hasCount && countedQty != product.stock;

      final matchesSearch = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case StockTakeFilter.counted:
          return hasCount;
        case StockTakeFilter.discrepancies:
          return hasDiscrepancy;
        case StockTakeFilter.uncounted:
          return !hasCount;
        case StockTakeFilter.all:
          return true;
      }
    }).toList();
  }

  int get _countedItems => _countedQuantities.length;
  int get _discrepancyItems => _products.where((product) {
        final countedQty = _countedQuantities[product.barcode];
        return countedQty != null && countedQty != product.stock;
      }).length;
  int get _matchedItems => _products.where((product) {
        final countedQty = _countedQuantities[product.barcode];
        return countedQty != null && countedQty == product.stock;
      }).length;
  int get _uncountedItems => _products.length - _countedItems;

  Future<void> _renameSession() async {
    if (_sessionId == null) return;
    final controller = TextEditingController(text: _sessionNameController.text);
    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Session Name'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Session Name',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    if (!saved) return;

    final newName = controller.text.trim().isEmpty
        ? 'Main Store Count'
        : controller.text.trim();
    final ok = await DatabaseHelper.instance.renameStockTakeSession(
      _sessionId!,
      newName,
    );

    if (!mounted) return;

    if (ok) {
      setState(() {
        _sessionNameController.text = newName;
      });
      _showMessage('Session name updated.');
    } else {
      _showMessage('Could not update session name.', isError: true);
    }
  }

  Future<void> _saveCount(Product product, int countedQty) async {
    if (_sessionId == null) return;

    final success = await DatabaseHelper.instance.saveStockTakeCount(
      sessionId: _sessionId!,
      product: product,
      countedQty: countedQty,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _countedQuantities[product.barcode] = countedQty;
      });
    } else {
      _showMessage('Could not save count for ${product.name}.', isError: true);
    }
  }

  Future<void> _clearCount(Product product) async {
    if (_sessionId == null) return;

    final success = await DatabaseHelper.instance.removeStockTakeCount(
      sessionId: _sessionId!,
      barcode: product.barcode,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _countedQuantities.remove(product.barcode);
      });
      _showMessage('Removed counted quantity for ${product.name}.');
    } else {
      _showMessage('Could not remove count.', isError: true);
    }
  }

  Future<void> _incrementByBarcode() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) return;

    Product? matched;
    for (final product in _products) {
      if (product.barcode == barcode) {
        matched = product;
        break;
      }
    }

    if (matched == null) {
      _showMessage('Barcode not found.', isError: true);
      _barcodeController.clear();
      return;
    }

    final nextQty = (_countedQuantities[matched.barcode] ?? 0) + 1;
    await _saveCount(matched, nextQty);
    if (!mounted) return;
    _barcodeController.clear();
    _showMessage('Counted 1 x ${matched.name}');
  }

  Future<void> _setCountDialog(Product product) async {
    final controller = TextEditingController(
      text: _countedQuantities[product.barcode]?.toString() ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Set Count\n${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Counted Quantity',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _clearCount(product);
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(controller.text.trim());
              if (qty == null || qty < 0) {
                _showMessage('Enter a valid quantity.', isError: true);
                return;
              }
              Navigator.pop(dialogContext);
              await _saveCount(product, qty);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _discardDraft() async {
    if (_sessionId == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard Current Draft?'),
            content: const Text(
              'This will remove the current stock take draft and all counted quantities in it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final ok = await DatabaseHelper.instance.discardOpenStockTakeSession(_sessionId!);
    if (!mounted) return;

    if (ok) {
      _showMessage('Stock take draft discarded.');
      await _loadSession(showLoader: true);
    } else {
      _showMessage('Could not discard stock take draft.', isError: true);
    }
  }

  Future<void> _openHistorySheet() async {
    final sessions = await DatabaseHelper.instance.getCompletedStockTakeSessions();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stock Take History',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: sessions.isEmpty
                        ? const Center(
                            child: Text('No completed stock take sessions yet.'),
                          )
                        : ListView.separated(
                            itemCount: sessions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (session['session_name'] ?? 'Stock Take Session')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Started: ${_formatDateTime(session['started_at']?.toString())}',
                                    ),
                                    Text(
                                      'Completed: ${_formatDateTime(session['completed_at']?.toString())}',
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _buildMiniChip(
                                          '${session['counted_items'] ?? 0} counted',
                                          Colors.blue,
                                        ),
                                        _buildMiniChip(
                                          '${session['discrepancy_items'] ?? 0} discrepancies',
                                          Colors.orange,
                                        ),
                                        _buildMiniChip(
                                          '${session['applied_items'] ?? 0} applied',
                                          Colors.green,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyReconciliation() async {
    if (_sessionId == null || _isApplying) return;
    if (_discrepancyItems == 0) {
      _showMessage('No discrepancies to apply.');
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Apply Stock Take'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session: ${_sessionNameController.text.trim()}'),
                const SizedBox(height: 8),
                Text('Discrepancy items: $_discrepancyItems'),
                const SizedBox(height: 8),
                const Text(
                  'This will update each counted item to the exact counted quantity using stock adjustment.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Uncounted items will not be changed.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final approverName =
        await _requireManagerApproval('apply stock take reconciliation');
    if (approverName == null) return;

    setState(() {
      _isApplying = true;
    });

    final result = await DatabaseHelper.instance.applyStockTakeSession(
      sessionId: _sessionId!,
      performedBy: _buildPerformedByLabel(approverName),
    );

    if (!mounted) return;

    setState(() {
      _isApplying = false;
    });

    if (result['success'] == true) {
      _showMessage((result['message'] ?? 'Stock take applied.').toString());
      await _loadSession(showLoader: true);
    } else {
      _showMessage(
        (result['message'] ?? 'Could not apply stock take.').toString(),
        isError: true,
      );
      await _loadSession(showLoader: false);
    }
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, StockTakeFilter filter) {
    final selected = _selectedFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = filter;
        });
      },
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade900,
      labelStyle: TextStyle(
        color: selected ? Colors.blue.shade900 : Colors.grey.shade800,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? Colors.blue.shade200 : Colors.grey.shade300,
      ),
      backgroundColor: Colors.white,
    );
  }

  Widget _buildProductTile(Product product) {
    final countedQty = _countedQuantities[product.barcode];
    final hasCount = countedQty != null;
    final difference = hasCount ? countedQty - product.stock : null;
    final isMatch = hasCount && difference == 0;
    final isDiscrepancy = hasCount && difference != 0;

    Color accent = Colors.blue;
    String stateLabel = 'Uncounted';
    if (isMatch) {
      accent = Colors.green;
      stateLabel = 'Matched';
    } else if (isDiscrepancy) {
      accent = Colors.orange;
      stateLabel = 'Discrepancy';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${product.barcode} • ${product.category}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              _buildMiniChip(stateLabel, accent),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildMiniChip('System ${product.stock}', Colors.blueGrey),
              _buildMiniChip(
                hasCount ? 'Counted $countedQty' : 'Count not set',
                hasCount ? Colors.blue : Colors.grey,
              ),
              if (difference != null)
                _buildMiniChip(
                  difference == 0
                      ? 'Diff 0'
                      : difference > 0
                          ? 'Diff +$difference'
                          : 'Diff $difference',
                  difference == 0 ? Colors.green : Colors.orange,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final nextQty = (countedQty ?? 0) + 1;
                  await _saveCount(product, nextQty);
                },
                icon: const Icon(Icons.add),
                label: const Text('Count +1'),
              ),
              OutlinedButton.icon(
                onPressed: () => _setCountDialog(product),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Set Count'),
              ),
              if (hasCount)
                OutlinedButton.icon(
                  onPressed: () => _clearCount(product),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '-';
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return isoString;
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final visibleProducts = _filteredProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Stock Take'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Rename session',
            onPressed: _renameSession,
            icon: const Icon(Icons.edit_note),
          ),
          IconButton(
            tooltip: 'History',
            onPressed: _openHistorySheet,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Discard draft',
            onPressed: _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadSession(showLoader: false),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _sessionNameController.text,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Started ${_formatDateTime(_startedAt)}',
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                            if (_isApplying)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _barcodeController,
                                decoration: InputDecoration(
                                  hintText: 'Scan or enter barcode to count +1',
                                  prefixIcon: const Icon(Icons.qr_code_scanner),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _incrementByBarcode(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _incrementByBarcode,
                              icon: const Icon(Icons.add),
                              label: const Text('Count'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Counted',
                          value: _countedItems.toString(),
                          icon: Icons.playlist_add_check_circle,
                          accent: Colors.blue,
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Matched',
                          value: _matchedItems.toString(),
                          icon: Icons.verified,
                          accent: Colors.green,
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Discrepancies',
                          value: _discrepancyItems.toString(),
                          icon: Icons.warning_amber_rounded,
                          accent: Colors.orange,
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Uncounted',
                          value: _uncountedItems.toString(),
                          icon: Icons.inventory_2_outlined,
                          accent: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search by name, barcode, or category',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _applyReconciliation,
                              icon: const Icon(Icons.done_all),
                              label: const Text('Apply'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFilterChip('All', StockTakeFilter.all),
                            _buildFilterChip('Counted', StockTakeFilter.counted),
                            _buildFilterChip(
                              'Discrepancies',
                              StockTakeFilter.discrepancies,
                            ),
                            _buildFilterChip('Uncounted', StockTakeFilter.uncounted),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (visibleProducts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Center(
                        child: Text('No products match the current filter.'),
                      ),
                    )
                  else
                    ...visibleProducts.map(
                      (product) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildProductTile(product),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
