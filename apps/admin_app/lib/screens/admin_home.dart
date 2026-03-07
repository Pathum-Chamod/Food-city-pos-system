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
    // Fetch products and dashboard stats from the cloud when the app opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchProducts();
      context.read<AdminProvider>().fetchDashboardStats();
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
      provider.isLoading
          ? const Center(child: CircularProgressIndicator())
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
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Inventory'),
        ],
      ),
    );
  }
}
