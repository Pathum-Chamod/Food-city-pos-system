import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../models/inventory_history_item.dart';
import '../providers/admin_provider.dart';

class InventoryHistoryScreen extends StatefulWidget {
  final Product product;

  const InventoryHistoryScreen({
    super.key,
    required this.product,
  });

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  bool _isLoading = true;
  List<InventoryHistoryItem> _history = [];
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    final history = await context.read<AdminProvider>().fetchInventoryHistory(
      widget.product.barcode,
    );

    if (!mounted) return;

    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  List<InventoryHistoryItem> get _filteredHistory {
    if (_selectedFilter == 'all') {
      return _history;
    }

    return _history.where((item) {
      switch (_selectedFilter) {
        case 'sales':
          return item.type == 'sale' || item.type == 'refund';
        case 'stock_in':
          return item.type == 'stock_in';
        case 'adjustments':
          return item.type == 'adjustment';
        case 'price_updates':
          return item.type == 'price_update';
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _selectedFilter = value;
          });
        },
      ),
    );
  }

  String _emptyMessageTitle() {
    switch (_selectedFilter) {
      case 'sales':
        return 'No sales history found';
      case 'stock_in':
        return 'No stock receipts found';
      case 'adjustments':
        return 'No stock adjustments found';
      case 'price_updates':
        return 'No price updates found';
      default:
        return 'No inventory history available';
    }
  }

  String _emptyMessageSubtitle() {
    switch (_selectedFilter) {
      case 'sales':
        return 'Sales and refunds will appear here';
      case 'stock_in':
        return 'Stock receive records will appear here';
      case 'adjustments':
        return 'Manual adjustments will appear here';
      case 'price_updates':
        return 'Price changes will appear here';
      default:
        return 'Stock movements will appear here';
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final filteredHistory = _filteredHistory;

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('All', 'all'),
                  _buildFilterChip('Sales', 'sales'),
                  _buildFilterChip('Stock In', 'stock_in'),
                  _buildFilterChip('Adjustments', 'adjustments'),
                  _buildFilterChip('Price Updates', 'price_updates'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadHistory,
              child: _isLoading
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : filteredHistory.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 140),
                            Center(
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.history,
                                    size: 54,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _emptyMessageTitle(),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _emptyMessageSubtitle(),
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: filteredHistory.length,
                          itemBuilder: (context, index) {
                            final item = filteredHistory[index];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: CircleAvatar(
                                  backgroundColor: item.color.withOpacity(0.12),
                                  child: Icon(
                                    item.icon,
                                    color: item.color,
                                  ),
                                ),
                                title: Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${item.subtitle}\n${item.dateText}',
                                  ),
                                ),
                                trailing: Text(
                                  item.quantityText,
                                  style: TextStyle(
                                    color: item.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
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
    );
  }
}