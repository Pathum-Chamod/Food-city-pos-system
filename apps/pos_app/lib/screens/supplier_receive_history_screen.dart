import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../models/stock_receipt_record.dart';
import '../services/supplier_service.dart';

class SupplierReceiveHistoryScreen extends StatefulWidget {
  const SupplierReceiveHistoryScreen({
    super.key,
    this.supplier,
  });

  final PosSupplier? supplier;

  @override
  State<SupplierReceiveHistoryScreen> createState() =>
      _SupplierReceiveHistoryScreenState();
}

class _SupplierReceiveHistoryScreenState
    extends State<SupplierReceiveHistoryScreen> {
  final SupplierService _supplierService = SupplierService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<StockReceiptRecord> _receipts = const [];
  Map<String, dynamic> _summary = const {};

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

    final receipts = await _supplierService.getReceiveHistory(
      supplierId: widget.supplier?.id,
      search: _searchController.text.trim(),
    );
    final summary = await _supplierService.getReceiveSummary(
      supplierId: widget.supplier?.id,
    );

    if (!mounted) return;

    setState(() {
      _receipts = receipts;
      _summary = summary;
      _isLoading = false;
    });
  }

  String _formatDate(String raw) {
    try {
      final date = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year} '
          '${two(date.hour)}:${two(date.minute)}';
    } catch (_) {
      return raw;
    }
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 180,
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.supplier == null
        ? 'Receive History'
        : '${widget.supplier!.name} History';

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by product or barcode',
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
                  onSubmitted: (_) => _loadData(),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSummaryCard(
                        label: 'Receipts',
                        value: ((_summary['receipt_count'] as num?) ?? 0)
                            .toInt()
                            .toString(),
                        icon: Icons.receipt_long,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                        label: 'Units Received',
                        value: ((_summary['total_units'] as num?) ?? 0)
                            .toInt()
                            .toString(),
                        icon: Icons.inventory_2_outlined,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                        label: 'Supplier Spend',
                        value:
                            'Rs. ${(((_summary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                        icon: Icons.payments_outlined,
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _receipts.isEmpty
                    ? const Center(
                        child: Text('No receive history recorded yet.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _receipts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final receipt = _receipts[index];

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              receipt.productName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Barcode: ${receipt.barcode}',
                                              style: TextStyle(
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.10),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '+${receipt.quantity}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _buildTag(receipt.supplierName),
                                      _buildTag(
                                        'Rs. ${receipt.cost.toStringAsFixed(2)}',
                                      ),
                                      _buildTag(_formatDate(receipt.createdAt)),
                                    ],
                                  ),
                                  if (receipt.cashierName.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Processed by: ${receipt.cashierName}',
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ],
                                  if (receipt.referenceNote.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Note: ${receipt.referenceNote}',
                                      style: TextStyle(color: Colors.grey[800]),
                                    ),
                                  ],
                                ],
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

  Widget _buildTag(String text) {
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
