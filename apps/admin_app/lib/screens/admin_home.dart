import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';
import '../providers/admin_provider.dart';
import 'inventory_history_screen.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _currentIndex = 0;

  String _inventorySearch = '';
  String _stockFilter = 'all';

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
                    value: adjustmentType,
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

                  Navigator.pop(dialogContext);

                  final message = adjustmentType == 'increase'
                      ? 'Stock adjustment prepared: +$qty for ${product.name}'
                      : adjustmentType == 'decrease'
                      ? 'Stock adjustment prepared: -$qty for ${product.name}'
                      : 'Exact stock prepared: set ${product.name} to $qty';

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      backgroundColor: Colors.blue,
                    ),
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
    String supplierName,
  ) {
    String? selectedBarcode;
    final qtyController = TextEditingController();
    final costController = TextEditingController();
    final products = context.read<AdminProvider>().products;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
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
                  items: products
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.barcode,
                          child: Text(p.name),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedBarcode = val),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity Received',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total Cost (Rs.)',
                    border: OutlineInputBorder(),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                if (selectedBarcode != null &&
                    qtyController.text.isNotEmpty &&
                    costController.text.isNotEmpty) {
                  final qty = int.tryParse(qtyController.text) ?? 0;
                  final cost = double.tryParse(costController.text) ?? 0.0;

                  if (qty > 0) {
                    final success = await context
                        .read<AdminProvider>()
                        .receiveStock(
                          selectedBarcode!,
                          qty,
                          int.parse(supplierId.toString()),
                          cost,
                        );

                    if (success && dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stock added successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  }
                }
              },
              child: const Text(
                'Save Stock',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final filteredProducts = _getFilteredProducts(provider.products);

    final totalProducts = provider.products.length;
    final inStockCount = provider.products.where((p) => p.stock > 10).length;
    final lowStockCount = provider.products
        .where((p) => p.stock > 0 && p.stock <= 10)
        .length;
    final outOfStockCount = provider.products.where((p) => p.stock <= 0).length;

    final List<Widget> pages = [
      // PAGE 1: Dashboard
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

      // PAGE 2: Inventory List
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

      // PAGE 3: Suppliers
      provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: provider.suppliers.length,
              itemBuilder: (context, index) {
                final supplier = provider.suppliers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.local_shipping, color: Colors.white),
                    ),
                    title: Text(
                      supplier['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Phone: ${supplier['phone']}'),
                    trailing: ElevatedButton(
                      onPressed: () => _showReceiveStockDialog(
                        context,
                        supplier['id'],
                        supplier['name'],
                      ),
                      child: const Text('Receive'),
                    ),
                  ),
                );
              },
            ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Cloud Control'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
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
