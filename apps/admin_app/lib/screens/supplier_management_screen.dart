import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../models/supplier.dart';
import '../providers/admin_provider.dart';
import '../widgets/app_snackbar.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({super.key, required this.supplier});

  final Supplier supplier;

  @override
  State<SupplierManagementScreen> createState() =>
      _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  String _search = '';
  String _filter = 'all';

  List<Product> _getFilteredProducts(List<Product> products) {
    final query = _search.trim().toLowerCase();

    return products.where((product) {
      final matchesSearch =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);

      final matchesFilter = switch (_filter) {
        'low_stock' => product.stock > 0 && product.stock <= 10,
        'out_of_stock' => product.stock <= 0,
        _ => true,
      };

      return matchesSearch && matchesFilter;
    }).toList()
      ..sort((a, b) {
        if (a.stock == b.stock) {
          return a.name.compareTo(b.name);
        }
        return a.stock.compareTo(b.stock);
      });
  }

  void _showReceiveStockDialog({String? initialBarcode}) {
    String? selectedBarcode = initialBarcode;
    final qtyController = TextEditingController();
    final costController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final provider = context.read<AdminProvider>();
          final products = provider.products;
          final selectedProduct = products.cast<Product?>().firstWhere(
            (p) => p?.barcode == selectedBarcode,
            orElse: () => null,
          );

          final qty = double.tryParse(qtyController.text.trim()) ?? 0.0;
          final cost = double.tryParse(costController.text.trim()) ?? 0.0;
          final projectedStock = selectedProduct != null
              ? selectedProduct.stock + qty
              : null;

          return AlertDialog(
            title: Text('Receive from\n${widget.supplier.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select Product',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    initialValue: selectedBarcode,
                    items: products
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p.barcode,
                            child: Text(p.name),
                          ),
                        )
                        .toList(),
                    onChanged: isSubmitting
                        ? null
                        : (val) => setDialogState(() => selectedBarcode = val),
                  ),
                  const SizedBox(height: 14),
                  if (selectedProduct != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedProduct.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text('Barcode: ${selectedProduct.barcode}'),
                          const SizedBox(height: 6),
                          Text('Current Stock: ${selectedProduct.stock}'),
                          if (qty > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Projected Stock: $projectedStock',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  TextField(
                    controller: qtyController,
                    enabled: !isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Quantity Received',
                      border: OutlineInputBorder(),
                      hintText: 'Enter received quantity',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: costController,
                    enabled: !isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Total Cost (Rs.)',
                      border: OutlineInputBorder(),
                      hintText: 'Enter total supplier cost',
                    ),
                  ),
                  if (qty > 0 && cost > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Estimated Unit Cost: Rs. ${(cost / qty).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (selectedBarcode == null) {
                          AppSnackBar.show(
                            context,
                            message: 'Please select a product.',
                            backgroundColor: Colors.red,
                          );
                          return;
                        }

                        final qty =
                            double.tryParse(qtyController.text.trim()) ?? 0.0;
                        final cost =
                            double.tryParse(costController.text.trim()) ?? -1;

                        if (qty <= 0) {
                          AppSnackBar.show(
                            context,
                            message: 'Quantity must be greater than 0.',
                            backgroundColor: Colors.red,
                          );
                          return;
                        }

                        if (cost < 0) {
                          AppSnackBar.show(
                            context,
                            message: 'Please enter a valid cost.',
                            backgroundColor: Colors.red,
                          );
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                        });

                        final success = await provider.receiveStock(
                          selectedBarcode!,
                          qty,
                          int.parse(widget.supplier.id.toString()),
                          cost,
                        );

                        if (!context.mounted) return;

                        if (success && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          AppSnackBar.show(
                            context,
                            message: 'Stock added successfully!',
                            backgroundColor: Colors.green,
                          );
                        } else {
                          setDialogState(() {
                            isSubmitting = false;
                          });
                          AppSnackBar.show(
                            context,
                            message: 'Failed to add stock.',
                            backgroundColor: Colors.red,
                          );
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Stock',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String value, String label) {
    final isSelected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final filteredProducts = _getFilteredProducts(provider.products);
    final lowStockCount = provider.products
        .where((p) => p.stock > 0 && p.stock <= 10)
        .length;
    final outOfStockCount = provider.products.where((p) => p.stock <= 0).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              await provider.fetchProducts();
              await provider.fetchSuppliers();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReceiveStockDialog,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Receive Stock'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.fetchProducts();
          await provider.fetchSuppliers();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[900],
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.local_shipping,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.supplier.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Supplier ID: ${widget.supplier.id}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Phone: ${widget.supplier.phone}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Use this screen to receive stock faster against this supplier and focus on low-stock items first.',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                _buildSummaryCard(
                  title: 'Products',
                  value: provider.products.length.toString(),
                  icon: Icons.inventory_2,
                  color: Colors.blue,
                ),
                _buildSummaryCard(
                  title: 'Low Stock',
                  value: lowStockCount.toString(),
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
                _buildSummaryCard(
                  title: 'Out of Stock',
                  value: outOfStockCount.toString(),
                  icon: Icons.cancel,
                  color: Colors.red,
                ),
                _buildSummaryCard(
                  title: 'Quick Receive',
                  value: 'Open',
                  icon: Icons.add_box_outlined,
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search product name or barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          setState(() {
                            _search = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _search = value;
                });
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterButton('all', 'All Products'),
                _buildFilterButton('low_stock', 'Low Stock'),
                _buildFilterButton('out_of_stock', 'Out of Stock'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Supplier Receiving Workspace',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This is a supplier-focused receiving step. It does not create full purchase orders yet, but it improves the stock receive flow from the blueprint.',
              style: TextStyle(color: Colors.grey[700], height: 1.35),
            ),
            const SizedBox(height: 12),
            if (provider.isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredProducts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No products found for this supplier workspace.',
                    ),
                  ),
                ),
              )
            else
              ...filteredProducts.map(
                (product) {
                  final isLowStock = product.stock > 0 && product.stock <= 10;
                  final isOutOfStock = product.stock <= 0;
                  final Color statusColor = isOutOfStock
                      ? Colors.red
                      : isLowStock
                          ? Colors.orange
                          : Colors.green;
                  final String statusText = isOutOfStock
                      ? 'Out of Stock'
                      : isLowStock
                          ? 'Low Stock'
                          : 'In Stock';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.blue[50],
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
                                    Text(
                                      'Barcode: ${product.barcode}',
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Rs. ${product.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Stock: ${product.stock}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showReceiveStockDialog(
                                initialBarcode: product.barcode,
                              ),
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Receive Stock for This Product'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
