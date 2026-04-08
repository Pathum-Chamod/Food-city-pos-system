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
  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _success = Color(0xFF16A34A);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFF87171);
  static const Color _info = Color(0xFF4F8CFF);

  bool _isLoading = true;
  SummaryRange _selectedRange = SummaryRange.today;
  DateTime? _selectedDate;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _topItems = [];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _page => _isDark ? const Color(0xFF071426) : const Color(0xFFF5F7FB);
  Color get _surface => _isDark ? const Color(0xFF0F223D) : Colors.white;
  Color get _surfaceSoft => _isDark ? const Color(0xFF132A49) : const Color(0xFFF8FAFC);
  Color get _border => _isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE3EAF3);
  Color get _textPrimary => _isDark ? const Color(0xFFF3F7FD) : const Color(0xFF162033);
  Color get _textSecondary => _isDark ? const Color(0xFF9FB2CC) : const Color(0xFF667085);
  Color get _shadow => _isDark ? Colors.black.withOpacity(0.18) : const Color(0x140F172A);

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

    if (_selectedRange == SummaryRange.last30Days) {
      final start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 29));
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
      limit: 6,
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

  String _formatCompactMoney(num value) {
    final amount = value.toDouble().abs();
    if (amount >= 1000000) return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    return 'Rs. ${value.toStringAsFixed(0)}';
  }

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
      return 'Selected date • ${_formatDate(_selectedDate!)}';
    }

    return '${_formatDate(start)} → ${_formatDate(end)}';
  }

  Widget _buildShell({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildRangeChip(SummaryRange value, String label) {
    final selected = _selectedRange == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedRange = value;
          if (value != SummaryRange.specificDate) {
            _selectedDate = null;
          }
        });
        _loadSummary();
      },
      selectedColor: _brand.withOpacity(_isDark ? 0.22 : 0.14),
      backgroundColor: _surfaceSoft,
      side: BorderSide(color: selected ? _brand.withOpacity(0.35) : _border),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        color: selected ? _brand : _textPrimary,
        fontWeight: FontWeight.w700,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildHeaderCard() {
    final selectedDateLabel = _selectedDate == null
        ? 'Pick date'
        : _formatDate(_selectedDate!);

    return _buildShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 860;

              final identity = Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _brand.withOpacity(_isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.person_rounded, color: _brand, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cashierName,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Simple cashier summary for the selected period.',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final actions = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: isWide ? WrapAlignment.end : WrapAlignment.start,
                children: [
                  _buildRangeChip(SummaryRange.today, 'Today'),
                  _buildRangeChip(SummaryRange.last7Days, '7 Days'),
                  _buildRangeChip(SummaryRange.last30Days, '30 Days'),
                  ActionChip(
                    avatar: Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: _selectedRange == SummaryRange.specificDate
                          ? _brand
                          : _textSecondary,
                    ),
                    label: Text(selectedDateLabel),
                    onPressed: _pickSpecificDate,
                    backgroundColor: _surfaceSoft,
                    side: BorderSide(
                      color: _selectedRange == SummaryRange.specificDate
                          ? _brand.withOpacity(0.35)
                          : _border,
                    ),
                    labelStyle: TextStyle(
                      color: _selectedRange == SummaryRange.specificDate
                          ? _brand
                          : _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _loadSummary,
                    style: IconButton.styleFrom(
                      backgroundColor: _surfaceSoft,
                      foregroundColor: _brand,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh',
                  ),
                ],
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, const SizedBox(height: 16), actions],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: identity),
                  const SizedBox(width: 18),
                  Expanded(flex: 6, child: Align(alignment: Alignment.topRight, child: actions)),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: _brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatRangeText(),
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetSalesHero(Map<String, dynamic>? summary) {
    final netSales = ((summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final transactions = ((summary?['transaction_count'] as num?) ?? 0).toInt();
    final itemsSold = ((summary?['items_sold'] as num?) ?? 0).toInt();
    final refunds = ((summary?['refund_total'] as num?) ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: _isDark
            ? const LinearGradient(
                colors: [Color(0xFF0D203A), Color(0xFF163459)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFF7FFFC), Color(0xFFF0FBF7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _brand.withOpacity(_isDark ? 0.20 : 0.16)),
        boxShadow: [
          BoxShadow(
            color: _brand.withOpacity(_isDark ? 0.10 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _brand.withOpacity(_isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.payments_rounded, color: _brand, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Net Sales',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatMoney(netSales),
                  style: TextStyle(
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 6,
                  children: [
                    _buildInlineStat(
                      icon: Icons.receipt_long_rounded,
                      label: 'Transactions',
                      value: transactions.toString(),
                      accent: _info,
                    ),
                    _buildMetaDot(),
                    _buildInlineStat(
                      icon: Icons.shopping_bag_rounded,
                      label: 'Items sold',
                      value: itemsSold.toString(),
                      accent: _brand,
                    ),
                    _buildMetaDot(),
                    _buildInlineStat(
                      icon: Icons.undo_rounded,
                      label: 'Refunds',
                      value: _formatCompactMoney(refunds),
                      accent: _danger,
                    ),
                    _buildMetaDot(),
                    _buildInlineStat(
                      icon: Icons.schedule_rounded,
                      label: 'Range',
                      value: _formatRangeText(),
                      accent: _brand,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineStat({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetaDot() {
    return Text(
      '•',
      style: TextStyle(
        color: _textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    String? note,
  }) {
    return _buildShell(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(_isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _textPrimary,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(Map<String, dynamic>? summary) {
    final transactions = ((summary?['transaction_count'] as num?) ?? 0).toInt();
    final itemsSold = ((summary?['items_sold'] as num?) ?? 0).toInt();
    final avgSale = ((summary?['average_sale_value'] as num?) ?? 0).toDouble();
    final cashSales = ((summary?['cash_sales'] as num?) ?? 0).toDouble();
    final cardSales = ((summary?['card_sales'] as num?) ?? 0).toDouble();
    final discounts = ((summary?['total_discounts'] as num?) ?? 0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : constraints.maxWidth >= 680
                ? 2
                : 1;
        const spacing = 12.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        final items = [
          _buildMetricTile(
            label: 'Transactions',
            value: transactions.toString(),
            icon: Icons.receipt_long_rounded,
            accent: _info,
            note: 'Completed bills in selected range',
          ),
          _buildMetricTile(
            label: 'Items Sold',
            value: itemsSold.toString(),
            icon: Icons.shopping_bag_rounded,
            accent: _brand,
            note: 'Total units sold by this cashier',
          ),
          _buildMetricTile(
            label: 'Average Sale',
            value: _formatMoney(avgSale),
            icon: Icons.insights_rounded,
            accent: _warning,
          ),
          _buildMetricTile(
            label: 'Cash Sales',
            value: _formatMoney(cashSales),
            icon: Icons.payments_outlined,
            accent: _success,
          ),
          _buildMetricTile(
            label: 'Card Sales',
            value: _formatMoney(cardSales),
            icon: Icons.credit_card_rounded,
            accent: _brand,
          ),
          _buildMetricTile(
            label: 'Discounts Given',
            value: _formatMoney(discounts),
            icon: Icons.local_offer_outlined,
            accent: _warning,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final widget in items) SizedBox(width: itemWidth, child: widget),
          ],
        );
      },
    );
  }

  Widget _buildTopSellingRow(Map<String, dynamic> item, int index) {
    final productName = (item['product_name'] ?? 'Unknown').toString();
    final barcode = (item['barcode'] ?? '').toString();
    final qty = ((item['quantity_sold'] as num?) ?? 0).toInt();
    final netSales = ((item['net_sales_amount'] as num?) ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: index == _topItems.length - 1 ? Colors.transparent : _border,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '#${index + 1}',
              style: TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (barcode.isNotEmpty)
                      Text(
                        barcode,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      '•',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$qty sold',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatMoney(netSales),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSellingCard() {
    return _buildShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Selling Items',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Best performing products for this cashier in the selected range.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_topItems.length} items',
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_topItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No sold items in this range.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final height in [150.0, 180.0, 220.0, 300.0]) ...[
          Container(
            height: height,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _page,
        foregroundColor: _textPrimary,
        title: const Text('Cashier Summary'),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
              onRefresh: _loadSummary,
              color: _brand,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildNetSalesHero(summary),
                  const SizedBox(height: 16),
                  _buildMetricsGrid(summary),
                  const SizedBox(height: 16),
                  _buildTopSellingCard(),
                ],
              ),
            ),
    );
  }
}
