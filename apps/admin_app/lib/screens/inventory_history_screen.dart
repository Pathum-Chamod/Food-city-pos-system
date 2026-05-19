import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../models/inventory_history_item.dart';
import '../providers/admin_provider.dart';

class InventoryHistoryScreen extends StatefulWidget {
  final Product product;

  const InventoryHistoryScreen({super.key, required this.product});

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
      product: widget.product,
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
          return item.type == 'stock_in' || item.type == 'stock_receive';
        case 'adjustments':
          return item.type == 'adjustment' ||
              item.type == 'stock_adjust_add' ||
              item.type == 'stock_adjust_remove' ||
              item.type == 'stock_adjust_set' ||
              item.type == 'min_stock_change';
        case 'price_updates':
          return item.type == 'price_update' ||
              item.type == 'price_change_selling' ||
              item.type == 'price_change_wholesale' ||
              item.type == 'price_change_sale' ||
              item.type == 'price_change_cost';
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _selectedFilter = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE8F1FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0F3D91)
                  : const Color(0xFFD7E0EE),
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F3D91).withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_rounded : icon,
                size: 16,
                color: isSelected
                    ? const Color(0xFF0F3D91)
                    : const Color(0xFF667085),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF0F3D91)
                      : const Color(0xFF344054),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
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
        return 'Manual adjustments and minimum stock changes will appear here';
      case 'price_updates':
        return 'Price changes will appear here';
      default:
        return 'Stock movements will appear here';
    }
  }

  String _formatStockQuantity(Product product, double value) {
    final safeValue = value.abs() < Product.quantityEpsilon ? 0.0 : value;
    if (!product.isWeighted ||
        (safeValue - safeValue.roundToDouble()).abs() <
            Product.quantityEpsilon) {
      return safeValue.round().toString();
    }

    return safeValue.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
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
                        'Current Stock: ${_formatStockQuantity(product, product.stock)} ${product.unitLabel}',
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'All',
                    value: 'all',
                    icon: Icons.apps_rounded,
                  ),
                  _buildFilterChip(
                    label: 'Sales',
                    value: 'sales',
                    icon: Icons.point_of_sale_rounded,
                  ),
                  _buildFilterChip(
                    label: 'Stock In',
                    value: 'stock_in',
                    icon: Icons.inventory_2_rounded,
                  ),
                  _buildFilterChip(
                    label: 'Adjustments',
                    value: 'adjustments',
                    icon: Icons.tune_rounded,
                  ),
                  _buildFilterChip(
                    label: 'Price Updates',
                    value: 'price_updates',
                    icon: Icons.sell_rounded,
                  ),
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
                              child: Icon(item.icon, color: item.color),
                            ),
                            title: Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${item.subtitle}\n${item.dateText}'),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  item.quantityText,
                                  style: TextStyle(
                                    color: item.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.unitLabel,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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
