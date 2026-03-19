import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../models/stock_receipt_record.dart';
import '../models/supplier_product_history.dart';
import '../models/supplier_purchase_summary.dart';
import '../services/supplier_service.dart';

class SupplierPurchaseHistoryScreen extends StatefulWidget {
  const SupplierPurchaseHistoryScreen({
    super.key,
    this.supplier,
  });

  final PosSupplier? supplier;

  @override
  State<SupplierPurchaseHistoryScreen> createState() =>
      _SupplierPurchaseHistoryScreenState();
}

class _SupplierPurchaseHistoryScreenState
    extends State<SupplierPurchaseHistoryScreen> {
  final SupplierService _service = SupplierService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<SupplierPurchaseSummary> _supplierSummaries = const [];
  List<SupplierProductHistory> _productHistory = const [];
  List<StockReceiptRecord> _recentReceipts = const [];
  Map<String, dynamic> _overview = const {};

  bool get _isSupplierDetail => widget.supplier != null;

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

    if (_isSupplierDetail) {
      final supplier = widget.supplier!;
      final overview = await _service.getSupplierPurchaseOverview(supplier.id);
      final productHistory = await _service.getSupplierProductHistory(
        supplierId: supplier.id,
        search: _searchController.text.trim(),
      );
      final recentReceipts = await _service.getReceiveHistory(
        supplierId: supplier.id,
        search: _searchController.text.trim(),
        limit: 20,
      );

      if (!mounted) return;
      setState(() {
        _overview = overview;
        _productHistory = productHistory;
        _recentReceipts = recentReceipts;
        _isLoading = false;
      });
      return;
    }

    final summaries = await _service.getSupplierPurchaseSummaries(
      search: _searchController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _supplierSummaries = summaries;
      _isLoading = false;
    });
  }

  String _formatDate(String value) {
    if (value.trim().isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 190,
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

  Widget _pill(String text, Color color) {
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

  Widget _buildSupplierSummaryCard(SupplierPurchaseSummary summary) {
    final supplier = PosSupplier(
      id: summary.supplierId,
      name: summary.supplierName,
      phone: summary.phone,
      updatedAt: '',
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.supplierName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              summary.phone.trim().isEmpty
                  ? 'Phone not available'
                  : 'Phone: ${summary.phone}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('Receipts: ${summary.receiptCount}', Colors.blue),
                _pill('Products: ${summary.productCount}', Colors.orange),
                _pill('Units: ${summary.totalUnits}', Colors.green),
                _pill(
                  'Spend: Rs. ${summary.totalCost.toStringAsFixed(2)}',
                  Colors.deepPurple,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Last receipt: ${_formatDate(summary.lastReceivedAt)}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupplierPurchaseHistoryScreen(
                        supplier: supplier,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.insights_outlined),
                label: const Text('Open Purchase History'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductHistoryCard(SupplierProductHistory item) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Barcode: ${item.barcode}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('Receipts: ${item.receiptCount}', Colors.blue),
                _pill('Units: ${item.totalUnits}', Colors.orange),
                _pill(
                  'Avg: Rs. ${item.averageUnitCost.toStringAsFixed(2)}',
                  Colors.indigo,
                ),
                _pill(
                  'Spend: Rs. ${item.totalCost.toStringAsFixed(2)}',
                  Colors.green,
                ),
                if (item.linkedPoCount > 0)
                  _pill('PO linked: ${item.linkedPoCount}', Colors.deepPurple),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Last received: ${_formatDate(item.lastReceivedAt)}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentReceiptCard(StockReceiptRecord receipt) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              receipt.productName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Barcode: ${receipt.barcode}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('+${receipt.quantity}', Colors.green),
                _pill('Rs. ${receipt.cost.toStringAsFixed(2)}', Colors.indigo),
                if (receipt.purchaseOrderNumber?.trim().isNotEmpty ?? false)
                  _pill(receipt.purchaseOrderNumber!, Colors.orange),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${receipt.cashierName.isEmpty ? 'Unknown' : receipt.cashierName} • ${_formatDate(receipt.createdAt)}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSupplierDetail
        ? '${widget.supplier!.name} Purchase History'
        : 'Supplier Purchase History';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _loadData(),
              decoration: InputDecoration(
                hintText: _isSupplierDetail
                    ? 'Search products by name or barcode'
                    : 'Search suppliers by name or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _loadData();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isSupplierDetail) ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Review what this supplier has delivered to the store so far, which items were received most, and how much has been spent locally through stock receipts.',
                    style: TextStyle(color: Colors.grey[700], height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _summaryCard(
                      label: 'Receipts',
                      value: ((_overview['receipt_count'] as num?) ?? 0)
                          .toInt()
                          .toString(),
                      icon: Icons.receipt_long,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    _summaryCard(
                      label: 'Products',
                      value: ((_overview['product_count'] as num?) ?? 0)
                          .toInt()
                          .toString(),
                      icon: Icons.inventory_2_outlined,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    _summaryCard(
                      label: 'Supplier Spend',
                      value:
                          'Rs. ${(((_overview['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                      icon: Icons.payments_outlined,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 10),
                    _summaryCard(
                      label: 'Open POs',
                      value: ((_overview['open_order_count'] as num?) ?? 0)
                          .toInt()
                          .toString(),
                      icon: Icons.pending_actions_outlined,
                      color: Colors.deepPurple,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Last receive: ${_formatDate((_overview['last_received_at'] ?? '').toString())}',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              const Text(
                'Product Purchase History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_productHistory.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No product history found yet.')),
                  ),
                )
              else
                ..._productHistory.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildProductHistoryCard(item),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Recent Receipts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (!_isLoading && _recentReceipts.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No recent receipts found.'),
                  ),
                )
              else
                ..._recentReceipts.take(12).map(
                  (receipt) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildRecentReceiptCard(receipt),
                  ),
                ),
            ] else ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Review local supplier spend, received units, and the most active suppliers on the store machine. Open any supplier to see product-level purchase history.',
                    style: TextStyle(color: Colors.grey[700], height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_supplierSummaries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No supplier purchase history recorded yet.'),
                    ),
                  ),
                )
              else
                ..._supplierSummaries.map(
                  (summary) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildSupplierSummaryCard(summary),
                  ),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
