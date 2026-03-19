import 'package:flutter/material.dart';
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../services/database_helper.dart';
import '../services/supplier_service.dart';
import 'purchase_order_editor_screen.dart';
import 'purchase_order_list_screen.dart';
import 'supplier_receive_history_screen.dart';
import 'supplier_purchase_history_screen.dart';

class SupplierWorkspaceScreen extends StatefulWidget {
  const SupplierWorkspaceScreen({
    super.key,
    required this.supplier,
    required this.cashierName,
  });

  final PosSupplier supplier;
  final String cashierName;

  @override
  State<SupplierWorkspaceScreen> createState() => _SupplierWorkspaceScreenState();
}

class _SupplierWorkspaceScreenState extends State<SupplierWorkspaceScreen> {
  final SupplierService _supplierService = SupplierService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();

  bool _isLoading = true;
  List<Product> _products = const [];
  Map<String, dynamic> _summary = const {};
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final products = await DatabaseHelper.instance.getProducts();
    final summary = await _supplierService.getReceiveSummary(
      supplierId: widget.supplier.id,
    );

    if (!mounted) return;

    setState(() {
      _products = products;
      _summary = summary;
      _isLoading = false;
    });
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();

    return _products.where((product) {
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);

      final matchesFilter = switch (_filter) {
        'low' => product.stock > 0 && product.stock <= 10,
        'out' => product.stock <= 0,
        _ => true,
      };

      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierReceiveHistoryScreen(supplier: widget.supplier),
      ),
    );
    await _loadData();
  }

  Future<void> _openPurchaseHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierPurchaseHistoryScreen(supplier: widget.supplier),
      ),
    );
  }

  Future<void> _openPurchaseOrders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderListScreen(
          cashierName: widget.cashierName,
          initialSupplier: widget.supplier,
        ),
      ),
    );
  }

  Future<void> _createPurchaseOrder() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderEditorScreen(
          cashierName: widget.cashierName,
          initialSupplier: widget.supplier,
        ),
      ),
    );
  }

  Future<void> _receiveByBarcode() async {
    final code = _barcodeController.text.trim();
    if (code.isEmpty) return;

    Product? matched;
    for (final product in _products) {
      if (product.barcode == code) {
        matched = product;
        break;
      }
    }

    if (matched == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No product found for that barcode.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _barcodeController.clear();
    await _showReceiveDialog(matched);
  }

  Future<void> _showReceiveDialog(Product product) async {
    final qtyController = TextEditingController();
    final costController = TextEditingController();
    final noteController = TextEditingController();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text('Receive Stock\n${product.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.supplier.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text('Barcode: ${product.barcode}'),
                        const SizedBox(height: 6),
                        Text('Current Stock: ${product.stock}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: qtyController,
                    enabled: !isSaving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity Received',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costController,
                    enabled: !isSaving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Total Cost (Rs.)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    enabled: !isSaving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reference Note (Optional)',
                      hintText: 'Invoice no, delivery note, remarks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                        final cost = double.tryParse(costController.text.trim()) ?? -1;

                        if (qty <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Quantity must be greater than 0.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        if (cost < 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enter a valid total cost.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() {
                          isSaving = true;
                        });

                        final success = await _supplierService.receiveStock(
                          supplier: widget.supplier,
                          product: product,
                          quantity: qty,
                          cost: cost,
                          cashierName: widget.cashierName,
                          referenceNote: noteController.text.trim(),
                        );

                        if (!mounted) return;

                        if (success) {
                          Navigator.pop(dialogContext);
                          await _loadData();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Stock received successfully.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          setDialogState(() {
                            isSaving = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to receive stock.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Receive'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
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

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
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

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          IconButton(
            tooltip: 'Purchase orders',
            onPressed: _openPurchaseOrders,
            icon: const Icon(Icons.description_outlined),
          ),
          IconButton(
            tooltip: 'Receive history',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Purchase history',
            onPressed: _openPurchaseHistory,
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: 'Refresh products',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.supplier.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.supplier.phone.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Phone: ${widget.supplier.phone}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _createPurchaseOrder,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Create PO'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openPurchaseOrders,
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('View POs'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openHistory,
                          icon: const Icon(Icons.history),
                          label: const Text('Receive History'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openPurchaseHistory,
                          icon: const Icon(Icons.insights_outlined),
                          label: const Text('Purchase History'),
                        ),
                      ],
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
                  _buildSummaryCard(
                    label: 'Receipts',
                    value: ((_summary['receipt_count'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Units Received',
                    value: ((_summary['total_units'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.inventory_2_outlined,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Receive Cost',
                    value: 'Rs. ${(((_summary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barcodeController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _receiveByBarcode(),
              decoration: InputDecoration(
                hintText: 'Quick receive by barcode',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: IconButton(
                  onPressed: _receiveByBarcode,
                  icon: const Icon(Icons.add),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search products by name or barcode',
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterChip('all', 'All'),
                _buildFilterChip('low', 'Low Stock'),
                _buildFilterChip('out', 'Out of Stock'),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No products found.')),
              )
            else
              ...filteredProducts.map(
                (product) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue.withOpacity(0.12),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Barcode: ${product.barcode}'),
                              const SizedBox(height: 4),
                              Text('Current Stock: ${product.stock}'),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _showReceiveDialog(product),
                                    icon: const Icon(Icons.add_box_outlined),
                                    label: const Text('Receive Stock'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _createPurchaseOrder,
                                    icon: const Icon(Icons.note_add_outlined),
                                    label: const Text('PO'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
