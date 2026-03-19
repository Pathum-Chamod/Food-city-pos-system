import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../models/purchase_order.dart';
import '../services/purchase_order_service.dart';
import 'purchase_order_editor_screen.dart';
import 'purchase_order_receive_history_screen.dart';
import 'purchase_order_receive_screen.dart';

class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({
    super.key,
    required this.cashierName,
    this.initialSupplier,
  });

  final String cashierName;
  final PosSupplier? initialSupplier;

  @override
  State<PurchaseOrderListScreen> createState() => _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  final PurchaseOrderService _service = PurchaseOrderService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<PurchaseOrder> _orders = const [];
  Map<String, dynamic> _summary = const {};
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final summary = await _service.getSummary(
      supplierId: widget.initialSupplier?.id,
      status: _statusFilter,
    );
    final orders = await _service.getOrders(
      supplierId: widget.initialSupplier?.id,
      status: _statusFilter,
      search: _searchController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _orders = orders;
      _isLoading = false;
    });
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'draft':
        return 'Draft';
      case 'ordered':
        return 'Ordered';
      case 'partially_received':
        return 'Partially Received';
      case 'received':
        return 'Received';
      case 'cancelled':
        return 'Cancelled';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'ordered':
        return Colors.blue;
      case 'partially_received':
        return Colors.orange;
      case 'received':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'draft':
      default:
        return Colors.deepPurple;
    }
  }

  Future<void> _openEditor({int? purchaseOrderId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderEditorScreen(
          cashierName: widget.cashierName,
          purchaseOrderId: purchaseOrderId,
          initialSupplier: widget.initialSupplier,
        ),
      ),
    );
    await _loadData();
  }

  Future<void> _openReceive(PurchaseOrder order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderReceiveScreen(
          purchaseOrder: order,
          cashierName: widget.cashierName,
        ),
      ),
    );
    await _loadData();
  }

  Future<void> _openHistory({PurchaseOrder? order}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderReceiveHistoryScreen(
          purchaseOrder: order,
        ),
      ),
    );
    await _loadData();
  }

  Future<void> _updateStatus(PurchaseOrder order, String status) async {
    await _service.updateStatus(order.id, status);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${order.orderNumber} marked as ${_statusLabel(status)}.',
        ),
        backgroundColor: Colors.green,
      ),
    );
    await _loadData();
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) async {
        setState(() {
          _statusFilter = value;
        });
        await _loadData();
      },
    );
  }

  Widget _buildStatusPill(PurchaseOrder order) {
    final color = _statusColor(order.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(order.status),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _showQuickStatusMenu(PurchaseOrder order) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: PurchaseOrderService.statuses.map((status) {
            return ListTile(
              title: Text(_statusLabel(status)),
              trailing: order.status == status
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(sheetContext, status),
            );
          }).toList(),
        ),
      ),
    );

    if (selected == null || selected == order.status) return;
    await _updateStatus(order, selected);
  }

  Widget _buildOrderCard(PurchaseOrder order) {
    final statusColor = _statusColor(order.status);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.supplierName,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusPill(order),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Received ${order.receivedUnits} / ${order.totalUnits} units',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: order.receiveProgress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              color: statusColor,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _miniPill('Lines: ${order.totalLines}', Colors.indigo),
                _miniPill('Outstanding: ${order.outstandingUnits}', Colors.orange),
                _miniPill(
                  'Receipts: ${order.receiptCount}',
                  Colors.blueGrey,
                ),
                _miniPill(
                  'Total: Rs. ${order.totalCost.toStringAsFixed(2)}',
                  Colors.green,
                ),
              ],
            ),
            if (order.referenceNote.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Reference: ${order.referenceNote}',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
            if (order.lastReceivedAt.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Last receive: ${order.lastReceivedAt}',
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openEditor(purchaseOrderId: order.id),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                ElevatedButton.icon(
                  onPressed: order.canReceive ? () => _openReceive(order) : null,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Receive'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openHistory(order: order),
                  icon: const Icon(Icons.history),
                  label: const Text('History'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showQuickStatusMenu(order),
                  icon: const Icon(Icons.more_horiz),
                  label: const Text('Status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.initialSupplier == null
        ? 'Purchase Orders'
        : 'Purchase Orders • ${widget.initialSupplier!.name}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Receive history',
            onPressed: () => _openHistory(),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Refresh purchase orders',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New PO'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Receive Against Purchase Order',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Purchase orders can now be received line-by-line from POS_APP. Receipt history is stored locally by receipt batch, so managers can review exactly what was received and when.',
                      style: TextStyle(color: Colors.grey[700], height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSummaryCard(
                    label: 'Orders',
                    value: ((_summary['order_count'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.receipt_long,
                    color: Colors.indigo,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Ordered Units',
                    value: ((_summary['total_units'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.shopping_bag_outlined,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Received Units',
                    value: ((_summary['received_units'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.inventory_2_outlined,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'PO Value',
                    value:
                        'Rs. ${(((_summary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _loadData(),
              decoration: InputDecoration(
                hintText: 'Search PO number, supplier, reference',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _loadData,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterChip('all', 'All'),
                _buildFilterChip('draft', 'Draft'),
                _buildFilterChip('ordered', 'Ordered'),
                _buildFilterChip('partially_received', 'Partially Received'),
                _buildFilterChip('received', 'Received'),
                _buildFilterChip('cancelled', 'Cancelled'),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_orders.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Text('No purchase orders found for this view.'),
                  ),
                ),
              )
            else
              ..._orders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildOrderCard(order),
                ),
              ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}
