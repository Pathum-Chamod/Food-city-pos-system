import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/pos_feature_flags.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../widgets/admin_dialogs.dart';

class RefundTransactionScreen extends StatefulWidget {
  final int originalSaleId;

  const RefundTransactionScreen({
    super.key,
    required this.originalSaleId,
  });

  @override
  State<RefundTransactionScreen> createState() =>
      _RefundTransactionScreenState();
}

class _RefundTransactionScreenState extends State<RefundTransactionScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;

  Map<String, dynamic>? _saleSummary;
  List<Map<String, dynamic>> _refundableItems = [];
  final Map<String, int> _selectedQty = {};

  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRefundableData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadRefundableData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final summary =
          await DatabaseHelper.instance.getTransactionSummary(widget.originalSaleId);
      final items =
          await DatabaseHelper.instance.getRefundableItemsForSale(widget.originalSaleId);

      if (!mounted) return;

      setState(() {
        _saleSummary = summary;
        _refundableItems = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $h:$min';
    } catch (_) {
      return raw;
    }
  }

  int _selectedFor(String barcode) => _selectedQty[barcode] ?? 0;

  void _increaseQty(String barcode, int refundableQty) {
    final current = _selectedFor(barcode);
    if (current >= refundableQty) return;

    setState(() {
      _selectedQty[barcode] = current + 1;
    });
  }

  void _decreaseQty(String barcode) {
    final current = _selectedFor(barcode);
    if (current <= 0) return;

    setState(() {
      final newQty = current - 1;
      if (newQty <= 0) {
        _selectedQty.remove(barcode);
      } else {
        _selectedQty[barcode] = newQty;
      }
    });
  }

  double get _refundTotal {
    double total = 0;

    for (final item in _refundableItems) {
      final barcode = (item['barcode'] ?? '').toString();
      final unitPrice = ((item['unit_price'] as num?) ?? 0).toDouble();
      final qty = _selectedFor(barcode);

      total += unitPrice * qty;
    }

    return total;
  }

  List<Map<String, dynamic>> get _selectedRefundItems {
    return _refundableItems
        .map((item) {
          final barcode = (item['barcode'] ?? '').toString();
          final qty = _selectedFor(barcode);

          if (qty <= 0) return null;

          return {
            'barcode': barcode,
            'product_name': (item['product_name'] ?? 'Unknown').toString(),
            'unit_price': ((item['unit_price'] as num?) ?? 0).toDouble(),
            'quantity': qty,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> _processRefund() async {
    if (_isProcessing) return;

    final selectedItems = _selectedRefundItems;
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one item to refund.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refund reason is required.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (PosFeatureFlags.enableShiftManagement) {
      final cashierName =
          context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
      final openShift =
          await DatabaseHelper.instance.getOpenShiftForCashier(cashierName);

      if (openShift == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open a shift before processing refunds.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    AdminDialogs.showPinDialog(context, () {
      _processRefundAfterApproval(selectedItems);
    });
  }

  Future<void> _processRefundAfterApproval(
    List<Map<String, dynamic>> selectedItems,
  ) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final cashierName =
          context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

      final refundSaleId = await DatabaseHelper.instance.processRefundFromSale(
        originalSaleId: widget.originalSaleId,
        refundItems: selectedItems,
        cashierName: cashierName,
        refundReason: _reasonController.text.trim(),
      );

      await SyncService().syncNow();
      await SyncService().refreshProductsFromBackend();

      if (!mounted) return;

      Navigator.pop(context, refundSaleId);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _saleSummary;
    final hasRefundableQty = _refundableItems.any(
      (item) => ((item['refundable_quantity'] as num?)?.toInt() ?? 0) > 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Refund Items'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : summary == null
              ? const Center(child: Text('Transaction not found'))
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.grey[100],
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Original Sale #${summary['id']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Cashier: ${(summary['cashier_name'] ?? 'Unknown').toString()}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Date/Time: ${_formatDateTime((summary['created_at'] ?? '').toString())}',
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _refundableItems.isEmpty
                          ? const Center(
                              child: Text('No items found for this sale'),
                            )
                          : ListView.builder(
                              itemCount: _refundableItems.length,
                              itemBuilder: (context, index) {
                                final item = _refundableItems[index];
                                final barcode =
                                    (item['barcode'] ?? '').toString();
                                final name =
                                    (item['product_name'] ?? 'Unknown').toString();
                                final unitPrice =
                                    ((item['unit_price'] as num?) ?? 0).toDouble();
                                final originalQty =
                                    (item['original_quantity'] as num?)?.toInt() ?? 0;
                                final refundedQty =
                                    (item['refunded_quantity'] as num?)?.toInt() ?? 0;
                                final refundableQty =
                                    (item['refundable_quantity'] as num?)?.toInt() ?? 0;
                                final selectedQty = _selectedFor(barcode);

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text('Barcode: $barcode'),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Unit Price: Rs. ${unitPrice.toStringAsFixed(2)}',
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 6,
                                          children: [
                                            Text('Sold: $originalQty'),
                                            Text('Already Refunded: $refundedQty'),
                                            Text('Remaining: $refundableQty'),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            IconButton(
                                              onPressed: selectedQty > 0
                                                  ? () => _decreaseQty(barcode)
                                                  : null,
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                              ),
                                            ),
                                            Text(
                                              '$selectedQty',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: refundableQty > selectedQty
                                                  ? () => _increaseQty(
                                                        barcode,
                                                        refundableQty,
                                                      )
                                                  : null,
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              'Refund: Rs. ${(unitPrice * selectedQty).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.red[50],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _reasonController,
                            decoration: const InputDecoration(
                              labelText: 'Refund Reason',
                              hintText: 'Enter reason for refund',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Refund Total: Rs. ${_refundTotal.toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: (!hasRefundableQty || _isProcessing)
                                ? null
                                : _processRefund,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: Text(
                              _isProcessing
                                  ? 'PROCESSING...'
                                  : 'PROCESS LINKED REFUND',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}