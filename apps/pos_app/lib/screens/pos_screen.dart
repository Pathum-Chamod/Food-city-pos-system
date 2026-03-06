import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';
import '../providers/cart_provider.dart';
import '../services/database_helper.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getProducts();
    setState(() {
      _products = products;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supermarket POS - Offline Mode'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Row(
        children: [
          // LEFT PANE: Menu View (Product Grid)
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 3 / 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _products.length,
                itemBuilder: (context, index) {
                  final product = _products[index];
                  return Card(
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        context.read<CartProvider>().addToCart(product);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(child: Text(product.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                            const SizedBox(height: 8),
                            Text('Rs. ${product.price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // RIGHT PANE: Order Cart Sidebar
          Container(
            width: 350,
            color: Colors.white,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Current Order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Consumer<CartProvider>(
                    builder: (context, cart, child) {
                      if (cart.items.isEmpty) {
                        return const Center(child: Text('Cart is empty'));
                      }
                      return ListView.builder(
                        itemCount: cart.items.length,
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          return ListTile(
                            title: Text(item.product.name),
                            subtitle: Text('${item.quantity} x Rs. ${item.product.price}'),
                            trailing: Text('Rs. ${item.total.toStringAsFixed(2)}'),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.blue[50],
                  child: Consumer<CartProvider>(
                    builder: (context, cart, child) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Total: Rs. ${cart.cartTotal.toStringAsFixed(2)}', 
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              backgroundColor: Colors.green,
                            ),
                            onPressed: cart.items.isEmpty ? null : () {
                              // Checkout logic will go here
                            },
                            child: const Text('PAY NOW', style: TextStyle(fontSize: 18, color: Colors.white)),
                          ),
                        ],
                      );
                    },
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
