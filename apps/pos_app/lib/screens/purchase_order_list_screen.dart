import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../models/purchase_order.dart';
import '../services/purchase_order_service.dart';
import 'purchase_order_editor_screen.dart';

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
      width: 200,
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

  Widget _buildStatusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
                      'Purchase Order Foundation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create and manage local purchase orders on the store POS. PO statuses are now tracked locally; receiving against PO comes in the next supplier phase.',
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
                    icon: Icons.description_outlined,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Units Ordered',
                    value: ((_summary['total_units'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.inventory_2_outlined,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'PO Value',
                    value:
                        'Rs. ${(((_summary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _loadData(),
              decoration: InputDecoration(
                hintText: 'Search PO number, supplier or note',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () async {
                          _searchController.clear();
                          await _loadData();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('draft', 'Draft'),
                  const SizedBox(width: 8),
                  _buildFilterChip('ordered', 'Ordered'),
                  const SizedBox(width: 8),
                  _buildFilterChip('partially_received', 'Partially Received'),
                  const SizedBox(width: 8),
                  _buildFilterChip('received', 'Received'),
                  const SizedBox(width: 8),
                  _buildFilterChip('cancelled', 'Cancelled'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No purchase orders found.')),
              )
            else
              ..._orders.map(
                (order) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.orderNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusChip(order.status),
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _openEditor(purchaseOrderId: order.id);
                                } else if (value == 'draft' ||
                                    value == 'ordered' ||
                                    value == 'partially_received' ||
                                    value == 'received' ||
                                    value == 'cancelled') {
                                  await _updateStatus(order, value);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Open / Edit'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'draft',
                                  child: Text('Mark Draft'),
                                ),
                                const PopupMenuItem(
                                  value: 'ordered',
                                  child: Text('Mark Ordered'),
                                ),
                                const PopupMenuItem(
                                  value: 'partially_received',
                                  child: Text('Mark Partially Received'),
                                ),
                                const PopupMenuItem(
                                  value: 'received',
                                  child: Text('Mark Received'),
                                ),
                                const PopupMenuItem(
                                  value: 'cancelled',
                                  child: Text('Mark Cancelled'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          order.supplierName,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _pill('Lines: ${order.totalLines}'),
                            _pill('Units: ${order.totalUnits}'),
                            _pill('Value: Rs. ${order.totalCost.toStringAsFixed(2)}'),
                            if (order.referenceNote.isNotEmpty)
                              _pill('Note: ${order.referenceNote}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Updated: ${order.updatedAt}',
                          style: TextStyle(color: Colors.grey[700], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
