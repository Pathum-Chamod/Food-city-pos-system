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

enum SummaryRange { today, last7Days, last30Days, specificDate }

class _CashierSummaryScreenState extends State<CashierSummaryScreen> {
  bool _isLoading = true;
  SummaryRange _selectedRange = SummaryRange.today;
  DateTime? _selectedDate;
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
      final start =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      return (start: start, end: now);
    }

    if (_selectedRange == SummaryRange.last30Days) {
      final start =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      return (start: start, end: now);
    }

    if (_selectedRange == SummaryRange.specificDate && _selectedDate != null) {
      final picked = _selectedDate!;
      final start = DateTime(picked.year, picked.month, picked.day);
      final end = DateTime(
        picked.year,
        picked.month,
        picked.day,
        23,
        59,
        59,
        999,
      );
      return (start: start, end: end);
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

  Future<void> _pickSpecificDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _selectedDate != null && !_selectedDate!.isAfter(today)
        ? _selectedDate!
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: today,
      selectableDayPredicate: (day) {
        final normalized = DateTime(day.year, day.month, day.day);
        return !normalized.isAfter(today);
      },
      helpText: 'Select Summary Date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedDate = picked;
      _selectedRange = SummaryRange.specificDate;
    });
    _loadSummary();
  }

  String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatRangeText() {
    final range = _currentRange();
    final start = range.start;
    final end = range.end;

    if (_selectedRange == SummaryRange.today) {
      return 'Today • ${_formatDate(end)}';
    }

    if (_selectedRange == SummaryRange.specificDate && _selectedDate != null) {
      return 'Selected Date • ${_formatDate(_selectedDate!)}';
    }

    return '${_formatDate(start)} → ${_formatDate(end)}';
  }

  Widget _buildRangeChip(SummaryRange value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedRange == value,
      onSelected: (_) {
        setState(() {
          _selectedRange = value;
          if (value != SummaryRange.specificDate) {
            _selectedDate = null;
          }
        });
        _loadSummary();
      },
      selectedColor: Colors.blue.shade100,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: _selectedRange == value
            ? Colors.blue.shade200
            : Colors.grey.shade300,
      ),
      labelStyle: TextStyle(
        color: _selectedRange == value
            ? Colors.blue.shade900
            : Colors.grey.shade800,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    Color? iconColor,
    Color? valueColor,
  }) {
    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor ?? Colors.blue.shade700, size: 22),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetSalesHeroCard(Map<String, dynamic>? summary) {
    final netSales = ((summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final transactions = ((summary?['transaction_count'] as num?) ?? 0).toInt();
    final itemsSold = ((summary?['items_sold'] as num?) ?? 0).toInt();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF3FBF4), Color(0xFFE8F7EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFCFE7D4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: Colors.green,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Net Sales',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E6A39),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMoney(netSales),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF238636),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$transactions transactions • $itemsSold items sold • after refunds',
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

  Widget _buildHeaderCard() {
    final selectedDateLabel = _selectedDate == null
        ? 'Pick Date'
        : _formatDate(_selectedDate!);

    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.cashierName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatRangeText(),
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildRangeChip(SummaryRange.today, 'Today'),
              _buildRangeChip(SummaryRange.last7Days, 'Last 7 Days'),
              _buildRangeChip(SummaryRange.last30Days, 'Last 30 Days'),
              ActionChip(
                avatar: const Icon(Icons.calendar_month, size: 18),
                label: Text(selectedDateLabel),
                onPressed: _pickSpecificDate,
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _rankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFB7791F);
      case 1:
        return const Color(0xFF5B67D6);
      case 2:
        return const Color(0xFF2F855A);
      default:
        return const Color(0xFF3182CE);
    }
  }

  Widget _buildTopSellingRow(Map<String, dynamic> item, int index) {
    final productName = (item['product_name'] ?? 'Unknown').toString();
    final barcode = (item['barcode'] ?? '').toString();
    final qty = ((item['quantity_sold'] as num?) ?? 0).toInt();
    final netSales = ((item['net_sales_amount'] as num?) ?? 0).toDouble();
    final rankColor = _rankColor(index);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: index == _topItems.length - 1
                ? Colors.transparent
                : const Color(0xFFE9EDF3),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  color: rankColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  barcode,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(netSales),
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Qty sold: $qty',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopSellingCard() {
    return Container(
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Top Selling Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Best performing products in the selected range.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_topItems.length} items',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_topItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No sold items in this range.'),
              ),
            )
          else
            ..._topItems.asMap().entries.map(
                  (entry) => _buildTopSellingRow(entry.value, entry.key),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Cashier Summary'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSummary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildNetSalesHeroCard(summary),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 1100;
                      final medium = constraints.maxWidth >= 700;
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
                              label: 'Discounts Given',
                              value: _formatMoney(
                                ((summary?['total_discounts'] as num?) ?? 0),
                              ),
                              icon: Icons.local_offer_outlined,
                              iconColor: Colors.orange.shade700,
                              valueColor: Colors.orange.shade700,
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
                              iconColor: Colors.red.shade700,
                              valueColor: Colors.red.shade700,
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
                  _buildTopSellingCard(),
                ],
              ),
            ),
    );
  }
}
