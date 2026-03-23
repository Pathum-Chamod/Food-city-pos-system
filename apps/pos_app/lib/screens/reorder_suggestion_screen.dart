import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../models/purchase_order_item.dart';
import '../models/reorder_suggestion.dart';
import '../services/purchase_order_service.dart';
import '../services/supplier_service.dart';
import 'purchase_order_list_screen.dart';

class ReorderSuggestionScreen extends StatefulWidget {
  const ReorderSuggestionScreen({
    super.key,
    required this.cashierName,
    this.initialSupplier,
  });

  final String cashierName;
  final PosSupplier? initialSupplier;

  @override
  State<ReorderSuggestionScreen> createState() => _ReorderSuggestionScreenState();
}

class _ReorderSuggestionScreenState extends State<ReorderSuggestionScreen> {
  final SupplierService _supplierService = SupplierService();
  final PurchaseOrderService _purchaseOrderService = PurchaseOrderService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController(
    text: 'Reorder suggestion draft',
  );

  bool _isLoading = true;
  bool _isSaving = false;
  List<PosSupplier> _suppliers = const [];
  List<ReorderSuggestion> _suggestions = const [];
  Map<String, dynamic> _summary = const {};
  final Map<String, bool> _selected = <String, bool>{};
  final Map<String, int> _quantities = <String, int>{};
  final Map<String, double> _unitCosts = <String, double>{};
  String _filter = 'all';
  PosSupplier? _selectedSupplier;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final suppliers = await _purchaseOrderService.getSuppliers(refreshFromBackend: false);
    final suggestions = await _supplierService.getReorderSuggestions(
      search: _searchController.text.trim(),
      limit: 300,
    );
    final summary = await _supplierService.getReorderSuggestionSummary(
      search: _searchController.text.trim(),
    );

    PosSupplier? resolvedSupplier = widget.initialSupplier;
    if (resolvedSupplier == null && suppliers.isNotEmpty) {
      resolvedSupplier = suppliers.first;
    } else if (resolvedSupplier != null && suppliers.isNotEmpty) {
      final initial = resolvedSupplier;
      for (final supplier in suppliers) {
        if (supplier.id == initial.id) {
          resolvedSupplier = supplier;
          break;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _suppliers = suppliers;
      _suggestions = suggestions;
      _summary = summary;
      _selectedSupplier = resolvedSupplier;
      for (final suggestion in suggestions) {
        _selected.putIfAbsent(
          suggestion.barcode,
          () => suggestion.isOutOfStock || suggestion.isHighDemand,
        );
        _quantities.putIfAbsent(suggestion.barcode, () => suggestion.suggestedQuantity);
        _unitCosts.putIfAbsent(suggestion.barcode, () => suggestion.lastUnitCost);
      }
      _isLoading = false;
    });
  }

  List<ReorderSuggestion> get _filteredSuggestions {
    return _suggestions.where((item) {
      switch (_filter) {
        case 'out':
          return item.isOutOfStock;
        case 'high':
          return item.isHighDemand;
        case 'selected':
          return _selected[item.barcode] == true;
        default:
          return true;
      }
    }).toList();
  }

  int get _selectedCount => _selected.values.where((value) => value).length;

  int get _selectedUnits {
    var total = 0;
    for (final item in _suggestions) {
      if (_selected[item.barcode] == true) {
        total += _quantities[item.barcode] ?? item.suggestedQuantity;
      }
    }
    return total;
  }

  double get _selectedCost {
    var total = 0.0;
    for (final item in _suggestions) {
      if (_selected[item.barcode] == true) {
        final qty = _quantities[item.barcode] ?? item.suggestedQuantity;
        final unitCost = _unitCosts[item.barcode] ?? item.lastUnitCost;
        total += qty * unitCost;
      }
    }
    return total;
  }

  Future<void> _createDraftPo() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a supplier first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedItems = _suggestions.where((item) => _selected[item.barcode] == true).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one suggestion.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final items = <PurchaseOrderItem>[];
    for (final suggestion in selectedItems) {
      final qty = _quantities[suggestion.barcode] ?? suggestion.suggestedQuantity;
      final unitCost = _unitCosts[suggestion.barcode] ?? suggestion.lastUnitCost;
      if (qty <= 0) continue;
      items.add(
        PurchaseOrderItem(
          barcode: suggestion.barcode,
          productName: suggestion.productName,
          quantity: qty,
          receivedQuantity: 0,
          unitCost: unitCost,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All selected quantities are zero.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final orderNumber = _purchaseOrderService.generateOrderNumber();
    final reference = _referenceController.text.trim().isEmpty
        ? 'Reorder suggestion draft'
        : _referenceController.text.trim();

    await _purchaseOrderService.saveOrder(
      orderNumber: orderNumber,
      supplier: _selectedSupplier!,
      status: 'draft',
      referenceNote: reference,
      items: items,
      createdBy: widget.cashierName,
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Draft PO $orderNumber created with ${items.length} item(s).'),
        backgroundColor: Colors.green,
      ),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderListScreen(
          cashierName: widget.cashierName,
          initialSupplier: _selectedSupplier,
        ),
      ),
    );

    await _loadData();
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
      },
    );
  }

  Widget _infoPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSuggestions = _filteredSuggestions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder Suggestions'),
        actions: [
          IconButton(
            tooltip: 'Refresh suggestions',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _createDraftPo,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.description_outlined),
        label: Text(_isSaving ? 'Creating...' : 'Create Draft PO'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Low-Stock Reorder Planner',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Suggestions are based on current stock, recent 30-day sold units, and the latest known receive cost on this store machine. Choose a supplier, review quantities, and create a draft purchase order.',
                      style: TextStyle(color: Colors.grey[700], height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<PosSupplier>(
                      initialValue: _selectedSupplier,
                      isExpanded: true,
                      items: _suppliers
                          .map(
                            (supplier) => DropdownMenuItem<PosSupplier>(
                              value: supplier,
                              child: Text(supplier.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSupplier = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Supplier for Draft PO',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'PO Reference / Note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _loadData(),
                      decoration: InputDecoration(
                        hintText: 'Search suggestions by product or barcode',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          onPressed: _loadData,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _summaryCard(
                    label: 'Suggested Items',
                    value: (_summary['item_count'] ?? 0).toString(),
                    color: Colors.blue,
                    icon: Icons.playlist_add_check_circle_outlined,
                  ),
                  const SizedBox(width: 10),
                  _summaryCard(
                    label: 'Out of Stock',
                    value: (_summary['out_of_stock_count'] ?? 0).toString(),
                    color: Colors.red,
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(width: 10),
                  _summaryCard(
                    label: 'Estimated Cost',
                    value: 'Rs. ${((_summary['estimated_cost'] as num?) ?? 0).toDouble().toStringAsFixed(2)}',
                    color: Colors.green,
                    icon: Icons.payments_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _filterChip('all', 'All'),
                _filterChip('out', 'Out of Stock'),
                _filterChip('high', 'High Demand'),
                _filterChip('selected', 'Selected'),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selected: $_selectedCount item(s) • $_selectedUnits units',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      'Rs. ${_selectedCost.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredSuggestions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: Text('No reorder suggestions found.')),
              )
            else
              ...filteredSuggestions.map((item) {
                final selected = _selected[item.barcode] ?? false;
                final qty = _quantities[item.barcode] ?? item.suggestedQuantity;
                final cost = _unitCosts[item.barcode] ?? item.lastUnitCost;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: selected,
                              onChanged: (value) {
                                setState(() {
                                  _selected[item.barcode] = value ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Barcode: ${item.barcode}'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _infoPill('Stock: ${item.currentStock}', item.isOutOfStock ? Colors.red : Colors.orange),
                                      _infoPill('30d Sold: ${item.soldUnits30d}', Colors.blue),
                                      _infoPill('Target: ${item.targetStock}', Colors.indigo),
                                      _infoPill('Suggested: ${item.suggestedQuantity}', Colors.green),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: qty.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'PO Qty',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  final parsed = int.tryParse(value.trim()) ?? 0;
                                  _quantities[item.barcode] = parsed < 0 ? 0 : parsed;
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                initialValue: cost.toStringAsFixed(2),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Unit Cost',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  final parsed = double.tryParse(value.trim()) ?? 0;
                                  _unitCosts[item.barcode] = parsed < 0 ? 0 : parsed;
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}
