
import 'package:flutter/material.dart';

import '../services/database_helper.dart';

enum InventoryHistoryFilter {
  all,
  receives,
  adjustments,
  counts,
  sales,
  refunds,
  priceChanges,
  minStock,
}

class InventoryHistoryScreen extends StatefulWidget {
  final String? initialBarcode;

  const InventoryHistoryScreen({
    super.key,
    this.initialBarcode,
  });

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _movements = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  InventoryHistoryFilter _selectedFilter = InventoryHistoryFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.initialBarcode != null && widget.initialBarcode!.trim().isNotEmpty) {
      _searchController.text = widget.initialBarcode!.trim();
    }
    _loadHistory(showLoader: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String>? get _selectedActionTypes {
    switch (_selectedFilter) {
      case InventoryHistoryFilter.receives:
        return ['stock_receive'];
      case InventoryHistoryFilter.adjustments:
        return [
          'stock_adjust_add',
          'stock_adjust_remove',
          'stock_adjust_set',
        ];
      case InventoryHistoryFilter.counts:
        return ['stock_take_reconcile'];
      case InventoryHistoryFilter.sales:
        return ['sale'];
      case InventoryHistoryFilter.refunds:
        return ['refund'];
      case InventoryHistoryFilter.priceChanges:
        return [
          'price_change_cost',
          'price_change_selling',
          'price_change_wholesale',
          'price_change_sale',
        ];
      case InventoryHistoryFilter.minStock:
        return ['min_stock_change'];
      case InventoryHistoryFilter.all:
        return null;
    }
  }

  Future<void> _loadHistory({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final movements = await DatabaseHelper.instance.getInventoryMovements(
        limit: 500,
        barcode: widget.initialBarcode,
        actionTypes: _selectedActionTypes,
        searchQuery: widget.initialBarcode == null ? _searchController.text.trim() : '',
      );

      if (!mounted) return;

      setState(() {
        _movements = movements;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load inventory history.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadHistory(showLoader: false);
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<void> _openMovementDetails(Map<String, dynamic> movement) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final rows = <MapEntry<String, String>>[
          MapEntry('Action', _movementTitle((movement['action_type'] ?? '').toString())),
          MapEntry('Product', (movement['product_name'] ?? 'Unknown product').toString()),
          MapEntry('Barcode', (movement['barcode'] ?? '-').toString()),
          MapEntry('When', _formatDateTime(movement['created_at']?.toString())),
          if ((movement['performed_by'] ?? '').toString().trim().isNotEmpty)
            MapEntry('User', movement['performed_by'].toString()),
          if (movement['stock_before'] != null || movement['stock_after'] != null)
            MapEntry(
              'Stock',
              '${movement['stock_before'] ?? '-'} → ${movement['stock_after'] ?? '-'}',
            ),
          if (movement['quantity_change'] != null)
            MapEntry('Quantity Change', movement['quantity_change'].toString()),
          if (movement['old_price'] != null || movement['new_price'] != null)
            MapEntry(
              'Price',
              'Rs. ${_asDouble(movement['old_price']).toStringAsFixed(2)} → Rs. ${_asDouble(movement['new_price']).toStringAsFixed(2)}',
            ),
          if ((movement['reason'] ?? '').toString().trim().isNotEmpty)
            MapEntry('Reason', movement['reason'].toString()),
        ];

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Activity Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.key,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                row.value,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required InventoryHistoryFilter filter,
  }) {
    final selected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: Colors.blue.shade100,
      side: BorderSide(
        color: selected ? Colors.blue.shade200 : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.blue.shade800 : Colors.grey.shade800,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) async {
        setState(() {
          _selectedFilter = filter;
        });
        await _loadHistory(showLoader: false);
      },
    );
  }


  Widget _buildActionBadge(String actionType) {
    Color accent = Colors.blue;
    String label = _movementTitle(actionType);

    if (actionType.contains('product_create')) {
      accent = Colors.blueGrey;
    } else if (actionType.contains('receive')) {
      accent = Colors.green;
    } else if (actionType.contains('adjust')) {
      accent = Colors.orange;
    } else if (actionType.contains('price')) {
      accent = Colors.purple;
    } else if (actionType.contains('stock_take')) {
      accent = Colors.teal;
    } else if (actionType.contains('refund')) {
      accent = Colors.red;
    } else if (actionType.contains('min_stock')) {
      accent = Colors.amber.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.20)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMovementTile(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final quantityChange = (movement['quantity_change'] as num?)?.toInt();
    final oldPrice = movement['old_price'] as num?;
    final newPrice = movement['new_price'] as num?;

    String subtitle = _movementSubtitle(movement);
    String trailing = _formatDateTime(movement['created_at']?.toString());
    Color accent = Colors.blue;
    IconData icon = Icons.history;

    if (actionType.contains('product_create')) {
      accent = Colors.blueGrey;
    } else if (actionType.contains('receive')) {
      accent = Colors.green;
      icon = Icons.inventory_2;
    } else if (actionType.contains('adjust')) {
      accent = Colors.orange;
      icon = Icons.tune;
    } else if (actionType.contains('price')) {
      accent = Colors.purple;
      icon = Icons.sell;
    } else if (actionType.contains('stock_take')) {
      accent = Colors.teal;
      icon = Icons.playlist_add_check_circle;
    } else if (actionType.contains('sale')) {
      accent = Colors.blue;
      icon = Icons.point_of_sale;
    } else if (actionType.contains('refund')) {
      accent = Colors.red;
      icon = Icons.undo;
    } else if (actionType.contains('min_stock')) {
      accent = Colors.amber.shade800;
      icon = Icons.warning_amber_rounded;
    }

    if (quantityChange != null) {
      final sign = quantityChange > 0 ? '+' : '';
      trailing = '$sign$quantityChange • $trailing';
    } else if (oldPrice != null || newPrice != null) {
      trailing = 'Rs. ${newPrice?.toStringAsFixed(2) ?? '0.00'} • $trailing';
    }

    return InkWell(
      onTap: () => _openMovementDetails(movement),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (movement['product_name'] ?? 'Unknown product').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _buildActionBadge(actionType),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _movementTitle(actionType),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trailing,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
    );
  }

  String _movementTitle(String actionType) {
    switch (actionType) {
      case 'product_created':
        return 'Product Created';
      case 'stock_receive':
        return 'Stock Received';
      case 'stock_adjust_add':
        return 'Stock Added';
      case 'stock_adjust_remove':
        return 'Stock Removed';
      case 'stock_adjust_set':
        return 'Stock Set';
      case 'stock_take_reconcile':
        return 'Stock Reconciled';
      case 'price_change_cost':
        return 'Cost Price Changed';
      case 'price_change_selling':
        return 'Selling Price Changed';
      case 'price_change_wholesale':
        return 'Wholesale Price Changed';
      case 'price_change_sale':
        return 'Sale Price Changed';
      case 'min_stock_change':
        return 'Minimum Stock Changed';
      case 'sale':
        return 'Sold';
      case 'refund':
        return 'Refunded';
      default:
        return actionType.replaceAll('_', ' ');
    }
  }

  String _movementSubtitle(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final stockBefore = movement['stock_before'];
    final stockAfter = movement['stock_after'];
    final oldPrice = movement['old_price'];
    final newPrice = movement['new_price'];
    final reason = (movement['reason'] ?? '').toString().trim();
    final performedBy = (movement['performed_by'] ?? '').toString().trim();

    final pieces = <String>[];

    if (actionType.startsWith('price_change')) {
      pieces.add(
        'Rs. ${_asDouble(oldPrice).toStringAsFixed(2)} → Rs. ${_asDouble(newPrice).toStringAsFixed(2)}',
      );
    } else if (stockBefore != null || stockAfter != null) {
      pieces.add('${stockBefore ?? '-'} → ${stockAfter ?? '-'}');
    }

    if (reason.isNotEmpty) {
      pieces.add(reason);
    }

    if (performedBy.isNotEmpty) {
      pieces.add(performedBy);
    }

    return pieces.join(' • ');
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}  $hour:$minute $meridiem';
  }

  @override
  Widget build(BuildContext context) {
    final totalMovements = _movements.length;
    final stockMovements = _movements.where((m) {
      final action = (m['action_type'] ?? '').toString();
      return action.startsWith('stock_') || action == 'sale' || action == 'refund';
    }).length;
    final priceMovements = _movements.where((m) {
      final action = (m['action_type'] ?? '').toString();
      return action.startsWith('price_change') || action == 'min_stock_change';
    }).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Text(
          widget.initialBarcode == null ? 'Inventory History' : 'Product History',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isRefreshing ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.initialBarcode != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Filtered to barcode: ${widget.initialBarcode}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Total Records',
                          value: totalMovements.toString(),
                          accent: Colors.blue,
                          icon: Icons.history,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Stock Records',
                          value: stockMovements.toString(),
                          accent: Colors.green,
                          icon: Icons.inventory,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          title: 'Price Records',
                          value: priceMovements.toString(),
                          accent: Colors.purple,
                          icon: Icons.sell,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.initialBarcode == null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by product, barcode, or reason',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () async {
                                        _searchController.clear();
                                        setState(() {});
                                        await _loadHistory(showLoader: false);
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _loadHistory(showLoader: false),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () => _loadHistory(showLoader: false),
                              icon: const Icon(Icons.search),
                              label: const Text('Apply Search'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(label: 'All', filter: InventoryHistoryFilter.all),
                      _buildFilterChip(label: 'Receives', filter: InventoryHistoryFilter.receives),
                      _buildFilterChip(label: 'Adjustments', filter: InventoryHistoryFilter.adjustments),
                      _buildFilterChip(label: 'Counts', filter: InventoryHistoryFilter.counts),
                      _buildFilterChip(label: 'Sales', filter: InventoryHistoryFilter.sales),
                      _buildFilterChip(label: 'Refunds', filter: InventoryHistoryFilter.refunds),
                      _buildFilterChip(label: 'Price Changes', filter: InventoryHistoryFilter.priceChanges),
                      _buildFilterChip(label: 'Min Stock', filter: InventoryHistoryFilter.minStock),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.initialBarcode == null
                                ? 'Showing ${_movements.length} history records for the current filters.'
                                : 'Showing ${_movements.length} records for barcode ${widget.initialBarcode}.',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_movements.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Center(
                        child: Text('No inventory history records match the current search or filter.'),
                      ),
                    )
                  else
                    ..._movements.map(
                      (movement) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildMovementTile(movement),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
