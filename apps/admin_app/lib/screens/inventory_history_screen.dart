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
    final mockHistory = [
      {
        'type': 'receive',
        'title': 'Stock Received',
        'subtitle': 'Received from supplier',
        'quantity': '+24',
        'date': 'Today, 10:15 AM',
        'icon': Icons.local_shipping,
        'color': Colors.green,
      },
      {
        'type': 'sale',
        'title': 'Sale',
        'subtitle': 'Sold through POS checkout',
        'quantity': '-3',
        'date': 'Today, 9:40 AM',
        'icon': Icons.point_of_sale,
        'color': Colors.red,
      },
      {
        'type': 'adjustment',
        'title': 'Manual Adjustment',
        'subtitle': 'Stock corrected by manager',
        'quantity': '+2',
        'date': 'Yesterday, 6:20 PM',
        'icon': Icons.tune,
        'color': Colors.orange,
      },
      {
        'type': 'price_update',
        'title': 'Price Update',
        'subtitle': 'Selling price changed',
        'quantity': 'Rs. ${product.price.toStringAsFixed(2)}',
        'date': 'Yesterday, 4:05 PM',
        'icon': Icons.edit,
        'color': Colors.blue,
      },
      {
        'type': 'refund',
        'title': 'Refund',
        'subtitle': 'Returned item added back to stock',
        'quantity': '+1',
        'date': 'Yesterday, 11:50 AM',
        'icon': Icons.assignment_return,
        'color': Colors.deepPurple,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory History'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
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
                        color: Colors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Current Stock: ${product.stock}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
              ],
            ),
          ),
          Expanded(
            child: mockHistory.isEmpty
                ? const Center(
                    child: Text(
                      'No inventory history available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: mockHistory.length,
                    itemBuilder: (context, index) {
                      final item = mockHistory[index];
                      final color = item['color'] as Color;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.12),
                            child: Icon(
                              item['icon'] as IconData,
                              color: color,
                            ),
                          ),
                          title: Text(
                            item['title'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${item['subtitle']}\n${item['date']}',
                            ),
                          ),
                          trailing: Text(
                            item['quantity'] as String,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}