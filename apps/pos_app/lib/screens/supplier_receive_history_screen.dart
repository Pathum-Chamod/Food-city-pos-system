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
  bool _isRefreshing = false;
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
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load receive history.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
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
      await _loadData();
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  String _formatDate(String raw) {
    if (raw.trim().isEmpty) return 'No date';
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
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by product or barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _loadData();
                        },
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.blue.shade700,
                    width: 1.4,
                  ),
                ),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _loadData(),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _isRefreshing ? null : _refresh,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Text(
                    'Refresh',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptCard(StockReceiptRecord receipt) {
    final totalCost = receipt.cost * receipt.quantity;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        receipt.productName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.22),
                        ),
                      ),
                      child: Text(
                        '+${receipt.quantity}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${receipt.barcode} • ${receipt.supplierName}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildMiniDetailCard(
                      'Unit Cost',
                      'Rs. ${receipt.cost.toStringAsFixed(2)}',
                    ),
                    _buildMiniDetailCard(
                      'Total Cost',
                      'Rs. ${totalCost.toStringAsFixed(2)}',
                    ),
                    _buildMiniDetailCard(
                      'Received At',
                      _formatDate(receipt.createdAt),
                    ),
                  ],
                ),
                if (receipt.cashierName.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Processed by ${receipt.cashierName.trim()}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (receipt.referenceNote.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    receipt.referenceNote.trim(),
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniDetailCard(String title, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Center(
        child: Text('No receive history recorded yet.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.supplier == null
        ? 'Supplier Receive History'
        : '${widget.supplier!.name} History';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: _isRefreshing ? null : _refresh,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Receipts',
                        value: ((_summary['receipt_count'] as num?) ?? 0)
                            .toInt()
                            .toString(),
                        icon: Icons.receipt_long_outlined,
                        accent: Colors.blue,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Units Received',
                        value: ((_summary['total_units'] as num?) ?? 0)
                            .toInt()
                            .toString(),
                        icon: Icons.inventory_2_outlined,
                        accent: Colors.green,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Supplier Spend',
                        value:
                            'Rs. ${(((_summary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                        icon: Icons.payments_outlined,
                        accent: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildToolbarCard(),
                const SizedBox(height: 18),
                Text(
                  widget.supplier == null
                      ? 'Receive Entries (${_receipts.length})'
                      : '${widget.supplier!.name} Receipts (${_receipts.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (_receipts.isEmpty)
                  _buildEmptyState()
                else
                  ..._receipts.map(
                    (receipt) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildReceiptCard(receipt),
                    ),
                  ),
              ],
            ),
    );
  }
}
