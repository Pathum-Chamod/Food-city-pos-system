import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Fetch products, dashboard stats, and suppliers from the cloud
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchProducts();
      context.read<AdminProvider>().fetchDashboardStats();
      context.read<AdminProvider>().fetchSuppliers();
    });
  }

  void _showEditPriceDialog(BuildContext context, String barcode, String name, double currentPrice) {
    final priceController = TextEditingController(text: currentPrice.toString());

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
                final success = await context.read<AdminProvider>().updateProductPrice(barcode, newPrice);
                if (success && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Price updated in Cloud!'), backgroundColor: Colors.green),
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

  void _showReceiveStockDialog(BuildContext context, dynamic supplierId, String supplierName) {
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
                  decoration: const InputDecoration(labelText: 'Select Product', border: OutlineInputBorder()),
                  isExpanded: true,
                  items: products.map((p) => DropdownMenuItem(value: p.barcode, child: Text(p.name))).toList(),
                  onChanged: (val) => setDialogState(() => selectedBarcode = val),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity Received', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Total Cost (Rs.)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                if (selectedBarcode != null && qtyController.text.isNotEmpty && costController.text.isNotEmpty) {
                  final qty = int.tryParse(qtyController.text) ?? 0;
                  final cost = double.tryParse(costController.text) ?? 0.0;
                  
                  if (qty > 0) {
                    final success = await context.read<AdminProvider>().receiveStock(
                      selectedBarcode!, qty, int.parse(supplierId.toString()), cost
                    );
                    
                    if (success && dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Stock added successfully!'), backgroundColor: Colors.green)
                        );
                      }
                    }
                  }
                }
              },
              child: const Text('Save Stock', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();

    final List<Widget> pages = [
      // PAGE 1: Dashboard
      RefreshIndicator(
        onRefresh: () async {
          await provider.fetchDashboardStats();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Revenue Card
            Card(
              elevation: 4,
              color: Colors.blue[900],
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.monetization_on, size: 50, color: Colors.white),
                    const SizedBox(height: 12),
                    const Text("Today's Revenue", style: TextStyle(fontSize: 16, color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(
                      'Rs. ${provider.todayTotalSales.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats Row
            Row(
              children: [
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.inventory_2, size: 30, color: Colors.orange),
                          const SizedBox(height: 8),
                          Text('${provider.products.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const Text('Products', style: TextStyle(color: Colors.grey)),
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
                          const Icon(Icons.receipt_long, size: 30, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            '${provider.cashierBreakdown.fold<int>(0, (sum, c) => sum + int.parse(c['transaction_count'].toString()))}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const Text('Transactions', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cashier Breakdown
            const Text('Sales by Employee', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (provider.cashierBreakdown.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No sales today yet', style: TextStyle(color: Colors.grey))),
                ),
              )
            else
              ...provider.cashierBreakdown.map((cashier) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: const Icon(Icons.person, color: Colors.blue),
                  ),
                  title: Text(cashier['cashier_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${cashier['transaction_count']} transactions'),
                  trailing: Text(
                    'Rs. ${double.parse(cashier['total_sales'].toString()).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              )),
          ],
        ),
      ),
      
      // PAGE 2: Inventory List
      RefreshIndicator(
        onRefresh: () async {
          await context.read<AdminProvider>().fetchProducts();
        },
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.products.isEmpty
                ? ListView( // Use a ListView so you can still pull-to-refresh even if empty
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No products found. Pull down to refresh.', style: TextStyle(color: Colors.grey))),
                    ],
                  )
                : ListView.builder(
                    itemCount: provider.products.length,
                    itemBuilder: (context, index) {
                      final product = provider.products[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.inventory)),
                          title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Stock: ${product.stock}  |  Barcode: ${product.barcode}'),
                          trailing: Text('Rs. ${product.price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
                          onTap: () => _showEditPriceDialog(context, product.barcode, product.name, product.price),
                        ),
                      );
                    },
                  ),
      ),
      // PAGE 3: Suppliers
      RefreshIndicator(
        onRefresh: () async {
          await context.read<AdminProvider>().fetchSuppliers();
        },
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.suppliers.isEmpty 
                ? ListView( // Use a ListView so you can still pull-to-refresh even if empty
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No suppliers found. Pull down to refresh.', style: TextStyle(color: Colors.grey))),
                    ],
                  )
                : ListView.builder(
                    itemCount: provider.suppliers.length,
                    itemBuilder: (context, index) {
                      final supplier = provider.suppliers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.orange, 
                            child: Icon(Icons.local_shipping, color: Colors.white)
                          ),
                          title: Text(supplier['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Phone: ${supplier['phone']}'),
                          trailing: ElevatedButton(
                            onPressed: () => _showReceiveStockDialog(context, supplier['id'], supplier['name'].toString()),
                            child: const Text('Receive'),
                          ),
                        ),
                      );
                    },
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh All',
            onPressed: () {
              context.read<AdminProvider>().fetchProducts();
              context.read<AdminProvider>().fetchDashboardStats();
              context.read<AdminProvider>().fetchSuppliers();
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Inventory'),
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'Suppliers'),
        ],
      ),
    );
  }
}
