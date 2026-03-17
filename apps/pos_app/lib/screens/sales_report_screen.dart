import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

enum SalesReportRange { today, last7Days, last30Days }

class _SalesReportScreenState extends State<SalesReportScreen> {
  bool _isLoading = true;
  SalesReportRange _selectedRange = SalesReportRange.today;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _cashierBreakdown = [];
  List<Map<String, dynamic>> _topItems = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  ({DateTime start, DateTime end}) _currentRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (_selectedRange) {
      case SalesReportRange.last30Days:
        return (
          start: todayStart.subtract(const Duration(days: 29)),
          end: now,
        );
      case SalesReportRange.last7Days:
        return (
          start: todayStart.subtract(const Duration(days: 6)),
          end: now,
        );
      case SalesReportRange.today:
        return (start: todayStart, end: now);
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
    });

    final range = _currentRange();

    final summary = await DatabaseHelper.instance.getCashierSalesSummary(
      start: range.start,
      end: range.end,
    );

    final cashierBreakdown =
        await DatabaseHelper.instance.getCashierBreakdownSummary(
      start: range.start,
      end: range.end,
      limit: 20,
    );

    final topItems = await DatabaseHelper.instance.getTopSellingItemsSummary(
      start: range.start,
      end: range.end,
      limit: 10,
    );

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _cashierBreakdown = cashierBreakdown;
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

    switch (_selectedRange) {
      case SalesReportRange.today:
        return 'Today • ${formatDate(end)}';
      case SalesReportRange.last7Days:
        return '${formatDate(start)} → ${formatDate(end)} • Last 7 Days';
      case SalesReportRange.last30Days:
        return '${formatDate(start)} → ${formatDate(end)} • Last 30 Days';
    }
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

  Widget _buildRangeChip({
    required SalesReportRange value,
    required String label,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedRange == value,
      onSelected: (_) {
        setState(() {
          _selectedRange = value;
        });
        _loadReport();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Report'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Store Overview',
                            style: TextStyle(
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
                              _buildRangeChip(
                                value: SalesReportRange.today,
                                label: 'Today',
                              ),
                              _buildRangeChip(
                                value: SalesReportRange.last7Days,
                                label: 'Last 7 Days',
                              ),
                              _buildRangeChip(
                                value: SalesReportRange.last30Days,
                                label: 'Last 30 Days',
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
                      final wide = constraints.maxWidth >= 1200;
                      final medium = constraints.maxWidth >= 700;
                      final width = wide
                          ? (constraints.maxWidth - 36) / 4
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
                              label: 'Gross Sales',
                              value: _formatMoney(
                                ((summary?['gross_sales'] as num?) ?? 0),
                              ),
                              icon: Icons.payments,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Discounts',
                              value: _formatMoney(
                                ((summary?['total_discounts'] as num?) ?? 0),
                              ),
                              icon: Icons.discount,
                              color: Colors.orange[800],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Net Sales',
                              value: _formatMoney(
                                ((summary?['net_sales'] as num?) ?? 0),
                              ),
                              icon: Icons.trending_up,
                              color: Colors.green[700],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Refunds',
                              value: _formatMoney(
                                ((summary?['refund_total'] as num?) ?? 0),
                              ),
                              icon: Icons.undo,
                              color: Colors.red[700],
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Net After Refunds',
                              value: _formatMoney(
                                ((summary?['net_after_refunds'] as num?) ?? 0),
                              ),
                              icon: Icons.account_balance_wallet,
                              color: Colors.teal[700],
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
                              value: '${((summary?['transaction_count'] as num?) ?? 0).toInt()}',
                              icon: Icons.receipt_long,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Items Sold',
                              value: '${((summary?['items_sold'] as num?) ?? 0).toInt()}',
                              icon: Icons.shopping_basket,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _buildMetricCard(
                              label: 'Average Sale',
                              value: _formatMoney(
                                ((summary?['average_sale_value'] as num?) ?? 0),
                              ),
                              icon: Icons.calculate,
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
                            'Cashier Breakdown',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_cashierBreakdown.isEmpty)
                            Text(
                              'No cashier data found for this range.',
                              style: TextStyle(color: Colors.grey[700]),
                            )
                          else
                            ..._cashierBreakdown.map((row) {
                              final cashierName =
                                  (row['cashier_name'] ?? 'Unknown').toString();
                              final saleCount =
                                  (row['sale_count'] as num?)?.toInt() ?? 0;
                              final refundCount =
                                  (row['refund_count'] as num?)?.toInt() ?? 0;
                              final netSales =
                                  ((row['net_sales'] as num?) ?? 0).toDouble();
                              final refundTotal =
                                  ((row['refund_total'] as num?) ?? 0)
                                      .toDouble();
                              final netAfterRefunds =
                                  ((row['net_after_refunds'] as num?) ?? 0)
                                      .toDouble();

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            cashierName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'Sales: $saleCount • Refunds: $refundCount',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 8,
                                      children: [
                                        Text(
                                          'Net: ${_formatMoney(netSales)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Refunds: ${_formatMoney(refundTotal)}',
                                          style: TextStyle(
                                            color: Colors.red[700],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'After Refunds: ${_formatMoney(netAfterRefunds)}',
                                          style: TextStyle(
                                            color: Colors.green[700],
                                            fontWeight: FontWeight.w700,
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
                            Text(
                              'No item sales found for this range.',
                              style: TextStyle(color: Colors.grey[700]),
                            )
                          else
                            ..._topItems.asMap().entries.map((entry) {
                              final index = entry.key;
                              final row = entry.value;
                              final productName =
                                  (row['product_name'] ?? 'Unknown Item')
                                      .toString();
                              final quantity =
                                  (row['quantity_sold'] as num?)?.toInt() ?? 0;
                              final amount =
                                  ((row['net_sales_amount'] as num?) ?? 0)
                                      .toDouble();

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue[50],
                                  foregroundColor: Colors.blue[900],
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text('Qty sold: $quantity'),
                                trailing: Text(
                                  _formatMoney(amount),
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.bold,
                                  ),
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
