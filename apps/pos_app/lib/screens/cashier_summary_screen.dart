import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class CashierSummaryScreen extends StatefulWidget {
  final String cashierName;

  const CashierSummaryScreen({
    super.key,
    required this.cashierName,
  });

  @override
  State<CashierSummaryScreen> createState() => _CashierSummaryScreenState();
}

enum SummaryRange { today, last7Days }

class _CashierSummaryScreenState extends State<CashierSummaryScreen> {
  bool _isLoading = true;
  SummaryRange _selectedRange = SummaryRange.today;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _topItems = [];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  ({DateTime start, DateTime end}) _currentRange() {
    final now = DateTime.now();

    if (_selectedRange == SummaryRange.last7Days) {
      final start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      return (start: start, end: now);
    }

    final start = DateTime(now.year, now.month, now.day);
    return (start: start, end: now);
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
    });

    final range = _currentRange();

    final summary = await DatabaseHelper.instance.getCashierSalesSummary(
      cashierName: widget.cashierName,
      start: range.start,
      end: range.end,
    );

    final topItems = await DatabaseHelper.instance.getTopSellingItemsSummary(
      cashierName: widget.cashierName,
      start: range.start,
      end: range.end,
      limit: 10,
    );

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _topItems = topItems;
      _isLoading = false;
    });
  }

  String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _formatRangeText() {
    final range = _currentRange();
    final start = range.start;
    final end = range.end;

    String formatDate(DateTime value) {
      final y = value.year.toString().padLeft(4, '0');
      final m = value.month.toString().padLeft(2, '0');
      final d = value.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    if (_selectedRange == SummaryRange.today) {
      return 'Today • ${formatDate(end)}';
    }

    return '${formatDate(start)} → ${formatDate(end)}';
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    IconData? icon,
    Color? color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null)
              Icon(icon, color: color ?? Colors.blue[700], size: 22),
            if (icon != null) const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Summary'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSummary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.cashierName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatRangeText(),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ChoiceChip(
                                label: const Text('Today'),
                                selected: _selectedRange == SummaryRange.today,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedRange = SummaryRange.today;
                                  });
                                  _loadSummary();
                                },
                              ),
                              ChoiceChip(
                                label: const Text('Last 7 Days'),
                                selected:
                                    _selectedRange == SummaryRange.last7Days,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedRange = SummaryRange.last7Days;
                                  });
                                  _loadSummary();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final medium = constraints.maxWidth >= 600;
                      final width = wide
                          ? (constraints.maxWidth - 24) / 4
                          : medium
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Net Sales',
                              value: _formatMoney(
                                ((summary?['net_sales'] as num?) ?? 0),
                              ),
                              icon: Icons.payments_outlined,
                              color: Colors.green[700],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Refund Total',
                              value: _formatMoney(
                                ((summary?['refund_total'] as num?) ?? 0),
                              ),
                              icon: Icons.assignment_return_outlined,
                              color: Colors.red[700],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Discounts Given',
                              value: _formatMoney(
                                ((summary?['total_discounts'] as num?) ?? 0),
                              ),
                              icon: Icons.local_offer_outlined,
                              color: Colors.orange[700],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Net After Refunds',
                              value: _formatMoney(
                                ((summary?['net_after_refunds'] as num?) ?? 0),
                              ),
                              icon: Icons.account_balance_wallet_outlined,
                              color: Colors.blue[700],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Cash Sales',
                              value: _formatMoney(
                                ((summary?['cash_sales'] as num?) ?? 0),
                              ),
                              icon: Icons.money,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Card Sales',
                              value: _formatMoney(
                                ((summary?['card_sales'] as num?) ?? 0),
                              ),
                              icon: Icons.credit_card,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Transactions',
                              value: ((summary?['transaction_count'] as num?) ?? 0)
                                  .toInt()
                                  .toString(),
                              icon: Icons.receipt_long_outlined,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Items Sold',
                              value: ((summary?['items_sold'] as num?) ?? 0)
                                  .toInt()
                                  .toString(),
                              icon: Icons.shopping_basket_outlined,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Top Selling Items',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_topItems.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text('No sold items in this range.'),
                              ),
                            )
                          else
                            ..._topItems.asMap().entries.map((entry) {
                              final index = entry.key;
                              final item = entry.value;
                              final productName =
                                  (item['product_name'] ?? 'Unknown').toString();
                              final barcode =
                                  (item['barcode'] ?? '').toString();
                              final qty =
                                  ((item['quantity_sold'] as num?) ?? 0).toInt();
                              final netSales =
                                  ((item['net_sales_amount'] as num?) ?? 0)
                                      .toDouble();

                              return Container(
                                margin: EdgeInsets.only(
                                  bottom: index == _topItems.length - 1 ? 0 : 12,
                                ),
                                padding: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: index == _topItems.length - 1
                                          ? Colors.transparent
                                          : const Color(0xFFE0E0E0),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.blue[50],
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            productName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            barcode,
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Qty: $qty',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatMoney(netSales),
                                          style: TextStyle(
                                            color: Colors.green[700],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
