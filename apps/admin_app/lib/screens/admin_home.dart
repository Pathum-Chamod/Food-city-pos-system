import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../models/stock_adjustment_request.dart';
import '../providers/admin_provider.dart';
import 'inventory_history_screen.dart';
import 'stock_take_screen.dart';
import 'supplier_management_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _currentIndex = 0;

  String _inventorySearch = '';
  String _stockFilter = 'all';
  String _supplierSearch = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchProducts();
      context.read<AdminProvider>().fetchDashboardStats();
      context.read<AdminProvider>().fetchSuppliers();
    });
  }

  void _showEditPriceDialog(
    BuildContext context,
    String barcode,
    String name,
    double currentPrice,
  ) {
    final priceController = TextEditingController(
      text: currentPrice.toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update Price\n$name'),
        content: TextField(
          controller: priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'New Price (Rs.)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPrice = double.tryParse(priceController.text);
              if (newPrice != null) {
                final success = await context
                    .read<AdminProvider>()
                    .updateProductPrice(barcode, newPrice);
                if (success && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Price updated in Cloud!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('Push Update'),
          ),
        ],
      ),
    );
  }

  void _showProductActionsSheet(Product product) {
    final statusText = _getStockStatus(product);
    final statusColor = _getStockStatusColor(product);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Barcode: ${product.barcode}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 10),
                Row(
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
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Stock: ${product.stock}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      'Rs. ${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.edit, color: Colors.blue),
                  ),
                  title: const Text('Update Price'),
                  subtitle: const Text('Change selling price in cloud'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditPriceDialog(
                      this.context,
                      product.barcode,
                      product.name,
                      product.price,
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(Icons.tune, color: Colors.orange),
                  ),
                  title: const Text('Adjust Stock'),
                  subtitle: const Text('Manual stock correction'),
                  onTap: () {
                    Navigator.pop(context);
                    _showStockAdjustmentDialog(product);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEDE7F6),
                    child: Icon(Icons.history, color: Colors.deepPurple),
                  ),
                  title: const Text('View History'),
                  subtitle: const Text('Inventory movement timeline'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (_) => InventoryHistoryScreen(product: product),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStockAdjustmentDialog(Product product) {
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    String adjustmentType = 'increase';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final enteredQty = int.tryParse(qtyController.text.trim()) ?? 0;

          int resultingStock = product.stock;
          if (adjustmentType == 'increase') {
            resultingStock = product.stock + enteredQty;
          } else if (adjustmentType == 'decrease') {
            resultingStock = product.stock - enteredQty;
          } else if (adjustmentType == 'set_exact') {
            resultingStock = enteredQty;
          }

          return AlertDialog(
            title: Text('Adjust Stock\n${product.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                          'Barcode: ${product.barcode}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Current Stock: ${product.stock}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: adjustmentType,
                    decoration: const InputDecoration(
                      labelText: 'Adjustment Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'increase',
                        child: Text('Increase Stock'),
                      ),
                      DropdownMenuItem(
                        value: 'decrease',
                        child: Text('Decrease Stock'),
                      ),
                      DropdownMenuItem(
                        value: 'set_exact',
                        child: Text('Set Exact Stock'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          adjustmentType = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: adjustmentType == 'set_exact'
                          ? 'Exact Stock Quantity'
                          : 'Quantity',
                      border: const OutlineInputBorder(),
                      hintText: adjustmentType == 'set_exact'
                          ? 'Enter final stock value'
                          : 'Enter quantity',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Resulting Stock: $resultingStock',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason / Note',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. damaged items, manual correction',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: adjustmentType == 'increase'
                      ? Colors.green
                      : adjustmentType == 'decrease'
                          ? Colors.orange
                          : Colors.blue,
                ),
                onPressed: () {
                  final qty = int.tryParse(qtyController.text.trim()) ?? -1;
                  final reason = reasonController.text.trim();

                  if (qty < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid quantity.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (adjustmentType != 'set_exact' && qty == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Quantity must be greater than 0.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (adjustmentType == 'decrease' && qty > product.stock) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cannot reduce more than current stock.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enter a reason for this adjustment.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  showDialog(
                    context: context,
                    builder: (confirmContext) {
                      final actionText = adjustmentType == 'increase'
                          ? 'Increase by $qty'
                          : adjustmentType == 'decrease'
                              ? 'Decrease by $qty'
                              : 'Set exact stock to $qty';

                      return AlertDialog(
                        title: const Text('Confirm Stock Adjustment'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Action: $actionText'),
                            const SizedBox(height: 6),
                            Text('Current Stock: ${product.stock}'),
                            const SizedBox(height: 6),
                            Text('Resulting Stock: $resultingStock'),
                            const SizedBox(height: 12),
                            Text('Reason: $reason'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmContext),
                            child: const Text('Back'),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              final adjustmentRequest = StockAdjustmentRequest(
                                barcode: product.barcode,
                                adjustmentType: adjustmentType,
                                quantity: qty,
                                reason: reason,
                              );

                              final success = await context
                                  .read<AdminProvider>()
                                  .adjustStock(adjustmentRequest);

                              if (!mounted) return;

                              Navigator.pop(confirmContext);
                              Navigator.pop(dialogContext);

                              if (success) {
                                final message = adjustmentType == 'increase'
                                    ? 'Stock increased successfully.'
                                    : adjustmentType == 'decrease'
                                        ? 'Stock decreased successfully.'
                                        : 'Exact stock updated successfully.';

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Failed to save stock adjustment.',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            child: const Text('Confirm'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text(
                  'Save Adjustment',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showReceiveStockDialog(
    BuildContext context,
    dynamic supplierId,
    String supplierName, {
    String? initialBarcode,
  }) {
    String? selectedBarcode = initialBarcode;
    final qtyController = TextEditingController();
    final costController = TextEditingController();
    final products = context.read<AdminProvider>().products;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final selectedProduct = products.cast<Product?>().firstWhere(
            (p) => p?.barcode == selectedBarcode,
            orElse: () => null,
          );

          final qty = int.tryParse(qtyController.text.trim()) ?? 0;
          final cost = double.tryParse(costController.text.trim()) ?? 0.0;
          final projectedStock = selectedProduct != null
              ? selectedProduct.stock + qty
              : null;

          return AlertDialog(
            title: Text('Receive from\n$supplierName'),
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
                          (p) => DropdownMenuItem(
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
                    keyboardType: TextInputType.number,
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select a product.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final qty =
                            int.tryParse(qtyController.text.trim()) ?? 0;
                        final cost =
                            double.tryParse(costController.text.trim()) ?? -1;

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
                              content: Text('Please enter a valid cost.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                        });

                        final success = await context
                            .read<AdminProvider>()
                            .receiveStock(
                              selectedBarcode!,
                              qty,
                              int.parse(supplierId.toString()),
                              cost,
                            );

                        if (!context.mounted) return;

                        if (success && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Stock added successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          setDialogState(() {
                            isSubmitting = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to add stock.'),
                              backgroundColor: Colors.red,
                            ),
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

  void _showQuickRestockSupplierPicker(Product product) {
    final suppliers = context.read<AdminProvider>().suppliers;

    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No suppliers available.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose supplier for\n${product.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...suppliers.map(
                  (supplier) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.local_shipping, color: Colors.white),
                    ),
                    title: Text(
                      supplier.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Phone: ${supplier.phone}'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showReceiveStockDialog(
                        context,
                        supplier.id,
                        supplier.name,
                        initialBarcode: product.barcode,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Product> _getFilteredProducts(List<Product> products) {
    final query = _inventorySearch.trim().toLowerCase();

    return products.where((product) {
      final matchesSearch =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);

      final matchesFilter = switch (_stockFilter) {
        'in_stock' => product.stock > 10,
        'low_stock' => product.stock > 0 && product.stock <= 10,
        'out_of_stock' => product.stock <= 0,
        _ => true,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  String _getStockStatus(Product product) {
    if (product.stock <= 0) return 'Out of Stock';
    if (product.stock <= 10) return 'Low Stock';
    return 'In Stock';
  }

  Color _getStockStatusColor(Product product) {
    if (product.stock <= 0) return Colors.red;
    if (product.stock <= 10) return Colors.orange;
    return Colors.green;
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _stockFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _stockFilter = value;
          });
        },
      ),
    );
  }

  Widget _buildInventorySummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockSection(List<Product> products) {
    final lowStockProducts =
        products.where((p) => p.stock > 0 && p.stock <= 10).toList()
          ..sort((a, b) => a.stock.compareTo(b.stock));

    final outOfStockProducts = products.where((p) => p.stock <= 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Inventory Alerts',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (lowStockProducts.isEmpty && outOfStockProducts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All products are stocked well right now.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (outOfStockProducts.isNotEmpty) ...[
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${outOfStockProducts.length} product(s) are out of stock',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...outOfStockProducts
                .take(5)
                .map(
                  (product) => _buildInventoryAlertTile(
                    product: product,
                    color: Colors.red,
                    badgeText: 'Stock: 0',
                  ),
                ),
            if (outOfStockProducts.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Text(
                  '+${outOfStockProducts.length - 5} more out of stock item(s)',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            const SizedBox(height: 6),
          ],

          if (lowStockProducts.isNotEmpty) ...[
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${lowStockProducts.length} product(s) are low in stock',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...lowStockProducts
                .take(5)
                .map(
                  (product) => _buildInventoryAlertTile(
                    product: product,
                    color: Colors.orange,
                    badgeText: 'Stock: ${product.stock}',
                  ),
                ),
            if (lowStockProducts.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '+${lowStockProducts.length - 5} more low stock item(s)',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildInventoryAlertTile({
    required Product product,
    required Color color,
    required String badgeText,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(Icons.inventory_2, color: color),
        ),
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Barcode: ${product.barcode}'),
        trailing: SizedBox(
          width: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _showQuickRestockSupplierPicker(product),
                child: const Text(
                  'Restock',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        onTap: () => _showProductActionsSheet(product),
      ),
    );
  }

  List<dynamic> _getFilteredSuppliers(List<dynamic> suppliers) {
    final query = _supplierSearch.trim().toLowerCase();
    if (query.isEmpty) return suppliers;

    return suppliers.where((supplier) {
      final name = supplier.name.toString().toLowerCase();
      final phone = supplier.phone.toString().toLowerCase();
      final id = supplier.id.toString().toLowerCase();
      return name.contains(query) || phone.contains(query) || id.contains(query);
    }).toList();
  }

  Widget _buildSupplierSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final filteredProducts = _getFilteredProducts(provider.products);
    final filteredSuppliers = _getFilteredSuppliers(provider.suppliers);

    final totalProducts = provider.products.length;
    final inStockCount = provider.products.where((p) => p.stock > 10).length;
    final lowStockCount = provider.products
        .where((p) => p.stock > 0 && p.stock <= 10)
        .length;
    final outOfStockCount = provider.products.where((p) => p.stock <= 0).length;

    final List<Widget> pages = [
      RefreshIndicator(
        onRefresh: () async {
          await provider.fetchDashboardStats();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 4,
              color: Colors.blue[900],
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      size: 50,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Today's Revenue",
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rs. ${provider.todayTotalSales.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.inventory_2,
                            size: 30,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${provider.products.length}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Products',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.receipt_long,
                            size: 30,
                            color: Colors.green,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${provider.cashierBreakdown.fold<int>(0, (sum, c) => sum + int.parse(c['transaction_count'].toString()))}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Transactions',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildLowStockSection(provider.products),
            const SizedBox(height: 16),
            const Text(
              'Sales by Employee',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (provider.cashierBreakdown.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No sales today yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              )
            else
              ...provider.cashierBreakdown.map(
                (cashier) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: const Icon(Icons.person, color: Colors.blue),
                    ),
                    title: Text(
                      cashier['cashier_name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${cashier['transaction_count']} transactions',
                    ),
                    trailing: Text(
                      'Rs. ${double.parse(cashier['total_sales'].toString()).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),

      provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by product name or barcode',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _inventorySearch.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _inventorySearch = '';
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
                            _inventorySearch = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.7,
                        children: [
                          _buildInventorySummaryCard(
                            title: 'Total Products',
                            value: '$totalProducts',
                            icon: Icons.inventory_2,
                            color: Colors.blue,
                          ),
                          _buildInventorySummaryCard(
                            title: 'In Stock',
                            value: '$inStockCount',
                            icon: Icons.check_circle,
                            color: Colors.green,
                          ),
                          _buildInventorySummaryCard(
                            title: 'Low Stock',
                            value: '$lowStockCount',
                            icon: Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          _buildInventorySummaryCard(
                            title: 'Out of Stock',
                            value: '$outOfStockCount',
                            icon: Icons.cancel,
                            color: Colors.red,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildFilterChip('All', 'all'),
                            _buildFilterChip('In Stock', 'in_stock'),
                            _buildFilterChip('Low Stock', 'low_stock'),
                            _buildFilterChip('Out of Stock', 'out_of_stock'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await provider.fetchProducts();
                    },
                    child: filteredProducts.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 140),
                              Center(
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 54,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'No products found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Try changing search or filter',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = filteredProducts[index];
                              final statusColor = _getStockStatusColor(product);
                              final statusText = _getStockStatus(product);

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                elevation: 2,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      _showProductActionsSheet(product),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: Colors.blue[50],
                                              child: const Icon(
                                                Icons.inventory,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    product.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Barcode: ${product.barcode}',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              'Rs. ${product.price.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: Colors.green,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withOpacity(
                                                  0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Stock: ${product.stock}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),

      provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await provider.fetchSuppliers();
                await provider.fetchProducts();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white24,
                              child: Icon(
                                Icons.factory_outlined,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Supplier Management',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This blueprint step improves the supplier side by giving each supplier a focused receiving workspace. Full purchase orders can come next.',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SupplierInfoPill(
                              label: 'Suppliers',
                              value: '${provider.suppliers.length}',
                            ),
                            _SupplierInfoPill(
                              label: 'Low Stock Items',
                              value: '$lowStockCount',
                            ),
                            _SupplierInfoPill(
                              label: 'Out of Stock',
                              value: '$outOfStockCount',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSupplierSummaryCard(
                          title: 'Suppliers',
                          value: '${provider.suppliers.length}',
                          icon: Icons.local_shipping,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildSupplierSummaryCard(
                          title: 'Receive Ready',
                          value: 'Yes',
                          icon: Icons.add_box_outlined,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search supplier name, phone or ID',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _supplierSearch.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                setState(() {
                                  _supplierSearch = '';
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
                        _supplierSearch = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (filteredSuppliers.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('No suppliers found.'),
                        ),
                      ),
                    )
                  else
                    ...filteredSuppliers.map(
                      (supplier) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: Color(0xFFEDE7F6),
                                    child: Icon(
                                      Icons.local_shipping,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          supplier.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text('Phone: ${supplier.phone}'),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Supplier ID: ${supplier.id}',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                SupplierManagementScreen(
                                              supplier: supplier,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.dashboard_outlined),
                                      label: const Text('Open Workspace'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _showReceiveStockDialog(
                                        context,
                                        supplier.id,
                                        supplier.name,
                                      ),
                                      icon: const Icon(Icons.add_box_outlined),
                                      label: const Text('Receive'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Cloud Control'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Stock Take',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StockTakeScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'Suppliers',
          ),
        ],
      ),
    );
  }
}

class _SupplierInfoPill extends StatelessWidget {
  const _SupplierInfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
