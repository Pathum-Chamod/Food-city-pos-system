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
    // Fetch products from the "cloud" when the app opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchProducts();
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
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.analytics, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text('Live Store Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Active Products: ${provider.products.length}', style: const TextStyle(fontSize: 18)),
            const Text('Today\'s Sales: Rs. 0.00 (Syncing...)', style: TextStyle(fontSize: 18, color: Colors.grey)),
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
