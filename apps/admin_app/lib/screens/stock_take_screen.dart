import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../models/stock_adjustment_request.dart';
import '../providers/admin_provider.dart';
import '../services/stock_take_session_service.dart';
import '../utils/product_name_helper.dart';
import '../widgets/app_snackbar.dart';
import 'stock_take_history_screen.dart';

class StockTakeScreen extends StatefulWidget {
  const StockTakeScreen({super.key});

  @override
  State<StockTakeScreen> createState() => _StockTakeScreenState();
}

class _StockTakeScreenState extends State<StockTakeScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sessionNameController = TextEditingController(
    text: 'Main Store Count',
  );

  final StockTakeSessionService _sessionService = StockTakeSessionService();
  static const double _quantityEpsilon = 0.000001;
  final Map<String, double> _countedQuantities = <String, double>{};

  String _filter = 'all';
  bool _isApplying = false;
  bool _restoredDraftHandled = false;
  String _sessionStartedAt = DateTime.now().toIso8601String();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AdminProvider>().fetchProducts();
      await _checkSavedDraft();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _searchController.dispose();
    _sessionNameController.dispose();
    super.dispose();
  }

  Future<void> _checkSavedDraft() async {
    if (_restoredDraftHandled) return;
    _restoredDraftHandled = true;

    final draft = await _sessionService.loadDraft();
    if (!mounted || draft == null) return;

    final shouldRestore =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Resume Saved Stock Take?'),
            content: Text(
              'A saved stock take draft was found for "${draft.sessionName}".\n\nDo you want to restore it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Discard'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;

    if (shouldRestore) {
      setState(() {
        _sessionNameController.text = draft.sessionName;
        _sessionStartedAt = draft.startedAtIso;
        _countedQuantities
          ..clear()
          ..addAll(draft.countedQuantities);
      });

      AppSnackBar.show(
        context,
        message: 'Restored draft: ${draft.sessionName}',
        backgroundColor: Colors.green,
      );
    } else {
      await _sessionService.clearDraft();
    }
  }

  Future<void> _saveDraft({bool showMessage = true}) async {
    if (_countedQuantities.isEmpty) {
      await _sessionService.clearDraft();
      if (showMessage && mounted) {
        AppSnackBar.show(context, message: 'No counts to save yet.');
      }
      return;
    }

    final draft = StockTakeDraft(
      sessionName: _sessionNameController.text.trim().isEmpty
          ? 'Stock Take Session'
          : _sessionNameController.text.trim(),
      startedAtIso: _sessionStartedAt,
      countedQuantities: Map<String, double>.from(_countedQuantities),
    );

    await _sessionService.saveDraft(draft);

    if (showMessage && mounted) {
      AppSnackBar.show(
        context,
        message: 'Stock take draft saved.',
        backgroundColor: Colors.green,
      );
    }
  }

  Future<void> _clearDraft() async {
    await _sessionService.clearDraft();
  }

  void _saveDraftSilently() {
    _saveDraft(showMessage: false);
  }

  bool _isWeighted(Product product) =>
      product.quantityType == ProductQuantityType.weight;

  double? _parseQuantity(String raw, {required bool weighted}) {
    final value = double.tryParse(raw.trim());
    if (value == null || value < 0) return null;
    if (!weighted && (value - value.roundToDouble()).abs() > _quantityEpsilon) {
      return null;
    }
    return value;
  }

  bool _quantitiesEqual(num a, num b) =>
      (a.toDouble() - b.toDouble()).abs() < _quantityEpsilon;

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final quantity = value.toDouble();
    if ((quantity - quantity.roundToDouble()).abs() < _quantityEpsilon) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatProductQuantity(Product product, num value) =>
      '${_formatQuantity(value)} ${product.unitLabel}';

  List<Product> _getFilteredProducts(List<Product> products) {
    final query = _searchController.text.trim().toLowerCase();

    return products.where((product) {
      final countedQty = _countedQuantities[product.barcode];
      final hasCount = countedQty != null;
      final hasDiscrepancy =
          hasCount && !_quantitiesEqual(countedQty, product.stock);

      final matchesQuery =
          query.isEmpty || ProductNameHelper.matches(product, query);

      final matchesFilter = switch (_filter) {
        'counted' => hasCount,
        'discrepancies' => hasDiscrepancy,
        'uncounted' => !hasCount,
        _ => true,
      };

      return matchesQuery && matchesFilter;
    }).toList();
  }

  void _incrementByBarcode(List<Product> products) {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) return;

    Product? matchedProduct;
    for (final product in products) {
      if (product.barcode == barcode) {
        matchedProduct = product;
        break;
      }
    }

    if (matchedProduct == null) {
      AppSnackBar.show(
        context,
        message: 'Barcode not found.',
        backgroundColor: Colors.red,
      );
      _barcodeController.clear();
      return;
    }

    if (_isWeighted(matchedProduct)) {
      _barcodeController.clear();
      _showSetCountDialog(matchedProduct);
      return;
    }

    setState(() {
      _countedQuantities.update(
        matchedProduct!.barcode,
        (value) => value + 1.0,
        ifAbsent: () => 1.0,
      );
    });
    _saveDraftSilently();

    _barcodeController.clear();

    AppSnackBar.show(
      context,
      message: 'Counted 1 x ${ProductNameHelper.primary(matchedProduct)}',
    );
  }

  Future<void> _showSetCountDialog(Product product) async {
    final controller = TextEditingController(
      text: _countedQuantities.containsKey(product.barcode)
          ? _countedQuantities[product.barcode].toString()
          : '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Set Count\n${ProductNameHelper.primary(product)}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(
            decimal: _isWeighted(product),
          ),
          inputFormatters: _isWeighted(product)
              ? <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}$')),
                ]
              : <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
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
            onPressed: () {
              setState(() {
                _countedQuantities.remove(product.barcode);
              });
              _saveDraftSilently();
              Navigator.pop(dialogContext);
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = _parseQuantity(
                controller.text,
                weighted: _isWeighted(product),
              );
              if (qty == null || qty < 0) {
                AppSnackBar.show(
                  context,
                  message: 'Enter a valid quantity.',
                  backgroundColor: Colors.red,
                );
                return;
              }

              setState(() {
                _countedQuantities[product.barcode] = qty;
              });
              _saveDraftSilently();
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameSession() async {
    final controller = TextEditingController(text: _sessionNameController.text);

    final saved =
        await showDialog<bool>(
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
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;

    if (!saved) return;

    setState(() {
      _sessionNameController.text = controller.text.trim().isEmpty
          ? 'Stock Take Session'
          : controller.text.trim();
    });
    _saveDraftSilently();
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockTakeHistoryScreen(sessionService: _sessionService),
      ),
    );
  }

  Future<void> _applyDiscrepancies(List<Product> products) async {
    final adminProvider = context.read<AdminProvider>();

    final discrepancies = products
        .where((product) => _countedQuantities.containsKey(product.barcode))
        .where(
          (product) => !_quantitiesEqual(
            _countedQuantities[product.barcode]!,
            product.stock,
          ),
        )
        .toList();

    if (discrepancies.isEmpty) {
      AppSnackBar.show(context, message: 'No discrepancies to apply.');
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Apply Stock Take'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session: ${_sessionNameController.text.trim()}'),
                const SizedBox(height: 8),
                Text('Discrepancy items: ${discrepancies.length}'),
                const SizedBox(height: 8),
                const Text(
                  'This will update each counted item to the exact counted quantity using the existing stock adjustment flow.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Uncounted items will not be changed.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _isApplying = true;
    });

    var successCount = 0;
    final failedProducts = <String>[];
    final appliedAt = DateTime.now().toIso8601String();
    final historyLines = <StockTakeHistoryLine>[];

    for (final product in discrepancies) {
      final countedQty = _countedQuantities[product.barcode];
      if (countedQty == null) continue;

      final request = StockAdjustmentRequest(
        barcode: product.barcode,
        adjustmentType: 'set_exact',
        quantity: countedQty,
        reason: 'Stock take reconciliation • $appliedAt',
      );

      final success = await adminProvider.adjustStock(request);

      historyLines.add(
        StockTakeHistoryLine(
          barcode: product.barcode,
          productName: ProductNameHelper.primary(product),
          systemStock: product.stock,
          countedStock: countedQty,
          applied: success,
        ),
      );

      if (success) {
        successCount += 1;
      } else {
        failedProducts.add(ProductNameHelper.primary(product));
      }
    }

    await adminProvider.fetchProducts();

    await _sessionService.addHistoryEntry(
      StockTakeHistoryEntry(
        id: appliedAt,
        sessionName: _sessionNameController.text.trim().isEmpty
            ? 'Stock Take Session'
            : _sessionNameController.text.trim(),
        startedAtIso: _sessionStartedAt,
        appliedAtIso: appliedAt,
        totalProducts: products.length,
        countedItems: _countedQuantities.length,
        discrepancyItems: discrepancies.length,
        appliedItems: successCount,
        lines: historyLines,
      ),
    );

    if (!mounted) return;

    setState(() {
      _isApplying = false;
      for (final product in discrepancies) {
        _countedQuantities.remove(product.barcode);
      }
      _sessionStartedAt = DateTime.now().toIso8601String();
    });

    if (_countedQuantities.isEmpty) {
      await _clearDraft();
    } else {
      await _saveDraft(showMessage: false);
    }

    final message = failedProducts.isEmpty
        ? 'Stock take applied for $successCount items.'
        : 'Applied $successCount items. Failed: ${failedProducts.length}';

    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: failedProducts.isEmpty ? Colors.green : Colors.orange,
    );
  }

  Future<void> _clearCounts() async {
    setState(() {
      _countedQuantities.clear();
      _sessionStartedAt = DateTime.now().toIso8601String();
    });
    await _clearDraft();
  }

  void _incrementProduct(Product product) {
    setState(() {
      _countedQuantities.update(
        product.barcode,
        (value) => value + 1.0,
        ifAbsent: () => 1.0,
      );
    });
    _saveDraftSilently();
  }

  void _decrementProduct(Product product) {
    final countedQty = _countedQuantities[product.barcode];
    if (countedQty == null || countedQty <= 0) return;

    setState(() {
      final nextQty = countedQty - 1.0;
      if (nextQty <= _quantityEpsilon) {
        _countedQuantities.remove(product.barcode);
      } else {
        _countedQuantities[product.barcode] = nextQty;
      }
    });
    _saveDraftSilently();
  }

  Widget _buildTopStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 22,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 28,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String value, String label) {
    final selected = _filter == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filter = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE9DDF8) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFFD5C1F2) : Colors.grey.shade300,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? const Color(0xFF6F4BB8) : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCountIconButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color: onTap == null ? Colors.grey : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final countedQty = _countedQuantities[product.barcode];
    final hasCount = countedQty != null;
    final discrepancy = hasCount ? countedQty - product.stock : null;

    Color discrepancyColor = Colors.grey;
    String discrepancyText = 'Not counted';

    if (hasCount) {
      if (_quantitiesEqual(discrepancy!, 0)) {
        discrepancyColor = Colors.green;
        discrepancyText = 'Matched';
      } else if (discrepancy > 0) {
        discrepancyColor = Colors.blue;
        discrepancyText = '+${_formatQuantity(discrepancy)}';
      } else {
        discrepancyColor = Colors.orange;
        discrepancyText = _formatQuantity(discrepancy);
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                        ProductNameHelper.primary(product),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (ProductNameHelper.sinhala(product) != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          ProductNameHelper.sinhala(product)!,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Barcode: ${product.barcode}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (hasCount)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Counted: ${_formatProductQuantity(product, countedQty)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMiniPill(
                  'System: ${_formatProductQuantity(product, product.stock)}',
                  Colors.grey,
                ),
                _buildMiniPill(
                  hasCount ? 'Counted: $countedQty' : 'Counted: —',
                  Colors.indigo,
                ),
                _buildMiniPill(discrepancyText, discrepancyColor),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildCountIconButton(
                  icon: Icons.remove,
                  onTap: hasCount && countedQty > 0
                      ? () => _decrementProduct(product)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSetCountDialog(product),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Set Count'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildCountIconButton(
                  icon: Icons.add,
                  onTap: () => _incrementProduct(product),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final products = List<Product>.from(admin.products);
    final filteredProducts = _getFilteredProducts(products);

    final countedItems = _countedQuantities.length;
    final discrepancyCount = products.where((product) {
      final countedQty = _countedQuantities[product.barcode];
      return countedQty != null && !_quantitiesEqual(countedQty, product.stock);
    }).length;

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Stock Take'),
        actions: [
          IconButton(
            tooltip: 'Session History',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Refresh Products',
            onPressed: admin.isLoading
                ? null
                : () => context.read<AdminProvider>().fetchProducts(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;

            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Column(
                      children: [
                        if (isCompact) ...[
                          InkWell(
                            onTap: _renameSession,
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.inventory_2_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Session',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _sessionNameController.text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.edit_outlined),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _saveDraft(),
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Save Draft'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _renameSession,
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.inventory_2_outlined),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Session',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _sessionNameController.text,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.edit_outlined),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: () => _saveDraft(),
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Save Draft'),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (isCompact) ...[
                          TextField(
                            controller: _barcodeController,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _incrementByBarcode(products),
                            decoration: const InputDecoration(
                              labelText: 'Count by Barcode',
                              hintText: 'Scan or type barcode',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.qr_code_scanner),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _incrementByBarcode(products),
                              icon: const Icon(Icons.add),
                              label: const Text('Count Item'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _barcodeController,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) =>
                                      _incrementByBarcode(products),
                                  decoration: const InputDecoration(
                                    labelText: 'Count by Barcode',
                                    hintText: 'Scan or type barcode',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.qr_code_scanner),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _incrementByBarcode(products),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Count'),
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Search Product',
                            hintText: 'Name or barcode',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, statConstraints) {
                            final cardWidth =
                                (statConstraints.maxWidth - 20) / 3;

                            return Row(
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildTopStatCard(
                                    label: 'Products',
                                    value: products.length.toString(),
                                    icon: Icons.inventory_2_outlined,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildTopStatCard(
                                    label: 'Counted',
                                    value: countedItems.toString(),
                                    icon: Icons
                                        .playlist_add_check_circle_outlined,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildTopStatCard(
                                    label: 'Diffs',
                                    value: discrepancyCount.toString(),
                                    icon: Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildFilterTab('all', 'All'),
                            const SizedBox(width: 8),
                            _buildFilterTab('counted', 'Counted'),
                            const SizedBox(width: 8),
                            _buildFilterTab('discrepancies', 'Discrepancies'),
                            const SizedBox(width: 8),
                            _buildFilterTab('uncounted', 'Uncounted'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (admin.isLoading && products.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filteredProducts.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('No products found for this view.'),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList.separated(
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        return _buildProductCard(product);
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: isKeyboardOpen ? 16 : 90),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        child: isKeyboardOpen
            ? const SizedBox.shrink()
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _countedQuantities.isEmpty || _isApplying
                              ? null
                              : _clearCounts,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isApplying
                              ? null
                              : () => _applyDiscrepancies(products),
                          icon: _isApplying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.fact_check_outlined),
                          label: Text(_isApplying ? 'Applying...' : 'Apply'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
