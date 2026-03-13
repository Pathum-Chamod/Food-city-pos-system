import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class InventoryHistoryScreen extends StatelessWidget {
  final Product product;

  const InventoryHistoryScreen({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('History - ${product.name}'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Barcode: ${product.barcode}'),
                  const SizedBox(height: 8),
                  Text('Current Stock: ${product.stock}'),
                  const SizedBox(height: 8),
                  Text('Price: Rs. ${product.price.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Inventory history - Coming soon',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
