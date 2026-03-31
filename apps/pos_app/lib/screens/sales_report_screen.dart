import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

enum SalesReportRange { today, last7Days, last30Days, specificDate }

class _SalesReportScreenState extends State<SalesReportScreen> {
  static const Color _brand = Color(0xFF1E5EFF);
  static const Color _success = Color(0xFF198754);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFDC3545);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _page = Color(0xFFF4F7FB);
  static const Color _mutedSurface = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE6ECF4);
  static const Color _textPrimary = Color(0xFF162033);
  static const Color _textSecondary = Color(0xFF667085);

  bool _isLoading = true;
  SalesReportRange _selectedRange = SalesReportRange.today;
  DateTime? _selectedDate;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _previousSummary;
  List<Map<String, dynamic>> _dailyTrend = [];
  List<Map<String, dynamic>> _hourlyTrend = [];
  List<Map<String, dynamic>> _cashierBreakdown = [];
  List<Map<String, dynamic>> _productPerformance = [];
  List<Map<String, dynamic>> _slowMovers = [];
  int? _hoveredBarIndex;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  bool get _showHourlyView =>
      _selectedRange == SalesReportRange.today ||
      _selectedRange == SalesReportRange.specificDate;

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
      case SalesReportRange.specificDate:
        final picked = _selectedDate ?? todayStart;
        return (
          start: DateTime(picked.year, picked.month, picked.day),
          end: DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999),
        );
      case SalesReportRange.today:
        return (start: todayStart, end: now);
    }
  }

  ({DateTime start, DateTime end}) _previousRange() {
    final current = _currentRange();
    final duration = current.end.difference(current.start);
    final previousEnd = current.start.subtract(const Duration(milliseconds: 1));
    final previousStart = previousEnd.subtract(duration);
    return (start: previousStart, end: previousEnd);
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
    });

    final current = _currentRange();
    final previous = _previousRange();

    final summary = await DatabaseHelper.instance.getCashierSalesSummary(
      start: current.start,
      end: current.end,
    );

    final previousSummary = await DatabaseHelper.instance.getCashierSalesSummary(
      start: previous.start,
      end: previous.end,
    );

    final dailyTrend = await DatabaseHelper.instance.getSalesTrendByDay(
      start: current.start,
      end: current.end,
    );

    final hourlyTrend = _showHourlyView
        ? await DatabaseHelper.instance.getHourlySalesSummaryForDay(
            day: current.start,
          )
        : <Map<String, dynamic>>[];

    final cashierBreakdown =
        await DatabaseHelper.instance.getCashierBreakdownSummary(
      start: current.start,
      end: current.end,
      limit: 20,
    );

    final productPerformance =
        await DatabaseHelper.instance.getProductPerformanceSummary(
      start: current.start,
      end: current.end,
      limit: 10,
    );

    final slowMovers =
        await DatabaseHelper.instance.getSlowMovingProductsSummary(
      start: current.start,
      end: current.end,
      limit: 10,
    );

    if (!mounted) return;

    setState(() {
      _hoveredBarIndex = null;
      _summary = summary;
      _previousSummary = previousSummary;
      _dailyTrend = dailyTrend;
      _hourlyTrend = hourlyTrend;
      _cashierBreakdown = cashierBreakdown;
      _productPerformance = productPerformance;
      _slowMovers = slowMovers;
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
      _selectedRange = SalesReportRange.specificDate;
    });
    _loadReport();
  }

  String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _formatCompactMoney(num value) {
    final amount = value.toDouble().abs();
    if (amount >= 1000000) {
      return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    }
    return 'Rs. ${value.toStringAsFixed(0)}';
  }


  String _formatAxisMoney(num value) {
    final amount = value.toDouble().abs();
    if (amount >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toStringAsFixed(0);
  }

  double _roundChartMax(double value) {
    if (value <= 0) return 1000;
    final magnitude = math.pow(10, math.log(value) ~/ math.ln10).toDouble();
    final normalized = value / magnitude;
    double rounded;
    if (normalized <= 1) {
      rounded = 1;
    } else if (normalized <= 2) {
      rounded = 2;
    } else if (normalized <= 5) {
      rounded = 5;
    } else {
      rounded = 10;
    }
    return rounded * magnitude;
  }

  String _formatFullDateFromRaw(String raw) {
    try {
      final date = DateTime.parse(raw);
      return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatShortDate(String raw) {
    try {
      final date = DateTime.parse(raw);
      return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _formatHourLabel(int hour) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final normalized = hour % 12 == 0 ? 12 : hour % 12;
    return '$normalized$suffix';
  }

  String _formatRangeText() {
    final range = _currentRange();
    final start = range.start;
    final end = range.end;

    switch (_selectedRange) {
      case SalesReportRange.today:
        return 'Today • ${_formatDate(end)}';
      case SalesReportRange.last7Days:
        return '${_formatDate(start)} → ${_formatDate(end)}';
      case SalesReportRange.last30Days:
        return '${_formatDate(start)} → ${_formatDate(end)}';
      case SalesReportRange.specificDate:
        return 'Selected Date • ${_formatDate(_selectedDate ?? end)}';
    }
  }

  double _percentChange(double current, double previous) {
    if (previous == 0) {
      return current == 0 ? 0.0 : 100.0;
    }
    return ((current - previous) / previous) * 100.0;
  }

  Color _deltaColor(double value) {
    if (value > 0) return _success;
    if (value < 0) return _danger;
    return _textSecondary;
  }

  IconData _deltaIcon(double value) {
    if (value > 0) return Icons.arrow_upward_rounded;
    if (value < 0) return Icons.arrow_downward_rounded;
    return Icons.horizontal_rule_rounded;
  }

  List<Map<String, dynamic>> _filledDailyTrend() {
    final current = _currentRange();
    final start = DateTime(
      current.start.year,
      current.start.month,
      current.start.day,
    );
    final end = DateTime(current.end.year, current.end.month, current.end.day);

    final existingByDate = <String, Map<String, dynamic>>{
      for (final row in _dailyTrend) (row['sales_date'] ?? '').toString(): row,
    };

    final rows = <Map<String, dynamic>>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      final key = _formatDate(cursor);
      rows.add({
        'sales_date': key,
        'transaction_count': 0,
        'items_sold': 0,
        'gross_sales': 0.0,
        'total_discounts': 0.0,
        'net_sales': 0.0,
        'refund_total': 0.0,
        'net_after_refunds': 0.0,
        ...?existingByDate[key],
      });
      cursor = cursor.add(const Duration(days: 1));
    }
    return rows;
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }

  Widget _buildPill({
    required String label,
    required String value,
    required IconData icon,
    Color color = _brand,
    Color? surfaceColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: surfaceColor ?? const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeChip({
    required SalesReportRange value,
    required String label,
  }) {
    final selected = _selectedRange == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedRange = value;
          if (value != SalesReportRange.specificDate) {
            _selectedDate = null;
          }
        });
        _loadReport();
      },
      selectedColor: const Color(0xFFEAF1FF),
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? const Color(0xFFB6CBFF) : _border),
      labelStyle: TextStyle(
        color: selected ? _brand : _textPrimary,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDeltaBadge(double deltaPct) {
    final color = _deltaColor(deltaPct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_deltaIcon(deltaPct), size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'vs previous',
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(Map<String, dynamic>? summary) {
    final netSales = ((summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final transactions = ((summary?['transaction_count'] as num?) ?? 0).toInt();
    final itemsSold = ((summary?['items_sold'] as num?) ?? 0).toInt();
    final refunds = ((summary?['refund_total'] as num?) ?? 0).toDouble();
    final averageSale =
        ((summary?['average_sale_value'] as num?) ?? 0).toDouble();
    final currentNet = ((_summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final previousNet =
        ((_previousSummary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final deltaPct = _percentChange(currentNet, previousNet);
    final selectedDateLabel =
        _selectedDate == null ? 'Pick Date' : _formatDate(_selectedDate!);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1F3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F1D4ED8),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              final headerInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: const Text(
                          'Store Sales Overview',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      _buildDeltaBadge(deltaPct),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Track store performance at a glance.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatRangeText(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.76),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.payments_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Net Sales',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatMoney(netSales),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 34,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '$transactions transactions • $itemsSold items • refunds ${_formatMoney(refunds)}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.80),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );

              final actions = Column(
                crossAxisAlignment:
                    isWide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment:
                        isWide ? WrapAlignment.end : WrapAlignment.start,
                    children: [
                      _buildRangeChip(
                        value: SalesReportRange.today,
                        label: 'Today',
                      ),
                      _buildRangeChip(
                        value: SalesReportRange.last7Days,
                        label: '7 Days',
                      ),
                      _buildRangeChip(
                        value: SalesReportRange.last30Days,
                        label: '30 Days',
                      ),
                      ActionChip(
                        avatar: Icon(
                          Icons.calendar_month_rounded,
                          size: 18,
                          color: _selectedRange == SalesReportRange.specificDate
                              ? Colors.white
                              : _textPrimary,
                        ),
                        label: Text(selectedDateLabel),
                        onPressed: _pickSpecificDate,
                        backgroundColor:
                            _selectedRange == SalesReportRange.specificDate
                                ? const Color(0xFF3B82F6)
                                : Colors.white,
                        side: BorderSide(
                          color: _selectedRange == SalesReportRange.specificDate
                              ? const Color(0xFF93C5FD)
                              : Colors.white.withOpacity(0.18),
                        ),
                        labelStyle: TextStyle(
                          color: _selectedRange == SalesReportRange.specificDate
                              ? Colors.white
                              : _textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _loadReport,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.10),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    headerInfo,
                    const SizedBox(height: 22),
                    actions,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: headerInfo),
                  const SizedBox(width: 24),
                  Expanded(flex: 5, child: actions),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1000;
              final isMedium = constraints.maxWidth >= 620;
              final spacing = 12.0;
              final itemWidth = isWide
                  ? (constraints.maxWidth - (spacing * 3)) / 4
                  : isMedium
                      ? (constraints.maxWidth - spacing) / 2
                      : constraints.maxWidth;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildPill(
                      label: 'Transactions',
                      value: '$transactions',
                      icon: Icons.receipt_long_rounded,
                      color: _brand,
                      surfaceColor: Colors.white,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildPill(
                      label: 'Items Sold',
                      value: '$itemsSold',
                      icon: Icons.shopping_bag_rounded,
                      color: _success,
                      surfaceColor: Colors.white,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildPill(
                      label: 'Average Sale',
                      value: _formatMoney(averageSale),
                      icon: Icons.insights_rounded,
                      color: _warning,
                      surfaceColor: Colors.white,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildPill(
                      label: 'Refunds',
                      value: _formatMoney(refunds),
                      icon: Icons.undo_rounded,
                      color: _danger,
                      surfaceColor: Colors.white,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    Color background = _mutedSurface,
    Color foreground = _textSecondary,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightStrip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _mutedSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart({
    required List<Map<String, dynamic>> points,
    required double maxValue,
    required String Function(Map<String, dynamic>) labelBuilder,
    required String Function(Map<String, dynamic>) tooltipLabelBuilder,
    required double Function(Map<String, dynamic>) valueBuilder,
    required Color color,
    required String emptyMessage,
  }) {
    if (points.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bar_chart_rounded,
        title: emptyMessage,
      );
    }

    final safeMax = _roundChartMax(maxValue);
    final tickValues = List<double>.generate(
      5,
      (index) => safeMax - ((safeMax / 4) * index),
    );
    final slotWidth = points.length >= 24
        ? 34.0
        : points.length >= 16
            ? 40.0
            : points.length >= 10
                ? 48.0
                : 60.0;
    final barWidth = points.length >= 24 ? 18.0 : 22.0;
    final chartHeight = 240.0;
    final yAxisWidth = 58.0;
    final step = points.length <= 8
        ? 1
        : points.length <= 14
            ? 2
            : points.length <= 22
                ? 3
                : 4;
    final hoveredIndex = (_hoveredBarIndex != null &&
            _hoveredBarIndex! >= 0 &&
            _hoveredBarIndex! < points.length)
        ? _hoveredBarIndex
        : null;
    final hoveredPoint = hoveredIndex == null ? null : points[hoveredIndex];
    final hoverSummary = hoveredPoint == null
        ? 'Hover a bar to see exact date and sales.'
        : '${tooltipLabelBuilder(hoveredPoint)} • ${_formatMoney(valueBuilder(hoveredPoint))}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final availablePlotWidth =
            math.max(220.0, constraints.maxWidth - yAxisWidth - 12);
        final plotWidth = math.max(
          availablePlotWidth,
          points.length * slotWidth,
        ).toDouble();

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: _mutedSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hoverSummary,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: chartHeight + 34,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: yAxisWidth,
                      height: chartHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final tick in tickValues)
                            Text(
                              _formatAxisMoney(tick),
                              style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: plotWidth,
                          height: chartHeight + 34,
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                bottom: 34,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    for (int i = 0; i < tickValues.length; i++)
                                      Container(
                                        height: 1,
                                        color: const Color(0xFFDDE5F0),
                                      ),
                                  ],
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                bottom: 34,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (var i = 0; i < points.length; i++)
                                      SizedBox(
                                        width: slotWidth,
                                        child: Builder(
                                          builder: (context) {
                                            final point = points[i];
                                            final value = valueBuilder(point);
                                            final ratio = (value / safeMax).clamp(0.0, 1.0);
                                            final barHeight = math.max(8.0, ratio * (chartHeight - 10));
                                            final isHovered = hoveredIndex == i;
                                            final isPeak = value == maxValue && maxValue > 0;

                                            return Align(
                                              alignment: Alignment.bottomCenter,
                                              child: MouseRegion(
                                                cursor: SystemMouseCursors.click,
                                                onEnter: (_) {
                                                  setState(() {
                                                    _hoveredBarIndex = i;
                                                  });
                                                },
                                                onExit: (_) {
                                                  setState(() {
                                                    if (_hoveredBarIndex == i) {
                                                      _hoveredBarIndex = null;
                                                    }
                                                  });
                                                },
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _hoveredBarIndex = i;
                                                    });
                                                  },
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 180),
                                                    width: isHovered ? barWidth + 4 : barWidth,
                                                    height: barHeight,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                        colors: isPeak
                                                            ? [
                                                                color.withOpacity(0.72),
                                                                color,
                                                              ]
                                                            : [
                                                                color.withOpacity(value <= 0 ? 0.18 : 0.40),
                                                                color.withOpacity(value <= 0 ? 0.24 : 0.86),
                                                              ],
                                                      ),
                                                      borderRadius: BorderRadius.circular(999),
                                                      boxShadow: isHovered || isPeak
                                                          ? [
                                                              BoxShadow(
                                                                color: color.withOpacity(0.24),
                                                                blurRadius: 14,
                                                                offset: const Offset(0, 6),
                                                              ),
                                                            ]
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 28,
                                child: Row(
                                  children: [
                                    for (var i = 0; i < points.length; i++)
                                      SizedBox(
                                        width: slotWidth,
                                        child: Center(
                                          child: (points.length <= 10 || i % step == 0 || i == points.length - 1)
                                              ? Text(
                                                  labelBuilder(points[i]),
                                                  maxLines: 2,
                                                  textAlign: TextAlign.center,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: _textSecondary,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    height: 1.1,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tip: hover or tap a bar to view the exact sales amount.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrendCard() {

    final currentNet = ((_summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final previousNet =
        ((_previousSummary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final deltaPct = _percentChange(currentNet, previousNet);
    final filledTrend = _filledDailyTrend();

    Map<String, dynamic>? bestDay;
    Map<String, dynamic>? weakestDay;
    if (filledTrend.isNotEmpty) {
      bestDay = filledTrend.reduce(
        (a, b) => (((a['net_after_refunds'] as num?) ?? 0).toDouble() >=
                (((b['net_after_refunds'] as num?) ?? 0).toDouble()))
            ? a
            : b,
      );
      weakestDay = filledTrend.reduce(
        (a, b) => (((a['net_after_refunds'] as num?) ?? 0).toDouble() <=
                (((b['net_after_refunds'] as num?) ?? 0).toDouble()))
            ? a
            : b,
      );
    }

    final dailyMax = filledTrend.fold<double>(
      0,
      (max, row) => (((row['net_after_refunds'] as num?) ?? 0).toDouble() > max)
          ? ((row['net_after_refunds'] as num?) ?? 0).toDouble()
          : max,
    );

    final hourlyMax = _hourlyTrend.fold<double>(
      0,
      (max, row) => (((row['net_after_refunds'] as num?) ?? 0).toDouble() > max)
          ? ((row['net_after_refunds'] as num?) ?? 0).toDouble()
          : max,
    );

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Sales Trend',
            subtitle: _showHourlyView
                ? 'Hourly performance for the selected day.'
                : 'Daily performance across the selected range.',
            trailing: _buildBadge(
              label: '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}% vs previous',
              background: _deltaColor(deltaPct).withOpacity(0.08),
              foreground: _deltaColor(deltaPct),
              icon: _deltaIcon(deltaPct),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isSideLayout = constraints.maxWidth >= 980;

              final insightCards = [
                _buildInsightStrip(
                  label: 'Current Period',
                  value: _formatMoney(currentNet),
                  icon: Icons.payments_outlined,
                  color: _success,
                ),
                _buildInsightStrip(
                  label: 'Previous Period',
                  value: _formatMoney(previousNet),
                  icon: Icons.history_rounded,
                  color: _brand,
                ),
                if (bestDay != null)
                  _buildInsightStrip(
                    label: 'Best Day',
                    value:
                        '${_formatShortDate((bestDay['sales_date'] ?? '').toString())} • ${_formatMoney(((bestDay['net_after_refunds'] as num?) ?? 0).toDouble())}',
                    icon: Icons.emoji_events_outlined,
                    color: _warning,
                  ),
                if (weakestDay != null)
                  _buildInsightStrip(
                    label: 'Weakest Day',
                    value:
                        '${_formatShortDate((weakestDay['sales_date'] ?? '').toString())} • ${_formatMoney(((weakestDay['net_after_refunds'] as num?) ?? 0).toDouble())}',
                    icon: Icons.trending_down_rounded,
                    color: _danger,
                  ),
              ];

              Widget buildChartArea({bool expandChart = false}) {
                final chartWidget = _buildBarChart(
                  points: _showHourlyView ? _hourlyTrend : filledTrend,
                  maxValue: _showHourlyView ? hourlyMax : dailyMax,
                  labelBuilder: (row) => _showHourlyView
                      ? _formatHourLabel((row['hour'] as num?)?.toInt() ?? 0)
                      : _formatShortDate((row['sales_date'] ?? '').toString()),
                  tooltipLabelBuilder: (row) => _showHourlyView
                      ? _formatHourLabel((row['hour'] as num?)?.toInt() ?? 0)
                      : _formatFullDateFromRaw((row['sales_date'] ?? '').toString()),
                  valueBuilder: (row) =>
                      ((row['net_after_refunds'] as num?) ?? 0).toDouble(),
                  color: _brand,
                  emptyMessage: _showHourlyView
                      ? 'No hourly sales recorded for the selected day.'
                      : 'No daily sales found for the selected range.',
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _showHourlyView ? 'Hourly Sales' : 'Daily Sales',
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        _buildChartLegendDot(_brand, 'Net sales after refunds'),
                        const Text(
                          'Y axis: sales • X axis: date/time',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (expandChart)
                      Expanded(child: chartWidget)
                    else
                      chartWidget,
                  ],
                );
              }

              Widget insightsWrap() {
                final spacing = 10.0;
                final columns = constraints.maxWidth >= 1100
                    ? 4
                    : constraints.maxWidth >= 700
                        ? 2
                        : 1;
                final itemWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final card in insightCards)
                      SizedBox(width: itemWidth, child: card),
                  ],
                );
              }

              if (!isSideLayout) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildChartArea(),
                    const SizedBox(height: 16),
                    insightsWrap(),
                  ],
                );
              }

              const sideHeight = 420.0;

              return SizedBox(
                height: sideHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 8,
                      child: buildChartArea(expandChart: true),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < insightCards.length; i++) ...[
                            Expanded(child: insightCards[i]),
                            if (i != insightCards.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompositionPercentBar({
    required String label,
    required double percent,
    required Color color,
  }) {
    final normalized = (percent / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: normalized,
              minHeight: 10,
              backgroundColor: const Color(0xFFE6ECF4),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesCompositionCard(Map<String, dynamic>? summary) {
    final cashSales = ((summary?['cash_sales'] as num?) ?? 0).toDouble();
    final cardSales = ((summary?['card_sales'] as num?) ?? 0).toDouble();
    final discounts = ((summary?['total_discounts'] as num?) ?? 0).toDouble();
    final refunds = ((summary?['refund_total'] as num?) ?? 0).toDouble();
    final grossBase = ((summary?['net_sales'] as num?) ?? 0).toDouble();
    final totalPayments = cashSales + cardSales;

    final cashPct = totalPayments <= 0 ? 0.0 : (cashSales / totalPayments) * 100.0;
    final cardPct = totalPayments <= 0 ? 0.0 : (cardSales / totalPayments) * 100.0;
    final refundPct = grossBase <= 0 ? 0.0 : (refunds / grossBase) * 100.0;
    final discountPct = grossBase <= 0 ? 0.0 : (discounts / grossBase) * 100.0;

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Payment & Reductions',
            subtitle: 'Where sales came from and what reduced them.',
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              final chartSide = Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _mutedSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 182,
                      height: 182,
                      child: CustomPaint(
                        painter: _DonutChartPainter(
                          values: [cashSales, cardSales],
                          colors: const [_brand, _success],
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 104,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Payment Mix',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _formatMoney(totalPayments),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: const [
                        _LegendTag(label: 'Cash', color: _brand),
                        _LegendTag(label: 'Card', color: _success),
                      ],
                    ),
                  ],
                ),
              );

              final barsSide = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCompositionPercentBar(
                    label: 'Cash Sales • ${_formatMoney(cashSales)}',
                    percent: cashPct,
                    color: _brand,
                  ),
                  _buildCompositionPercentBar(
                    label: 'Card Sales • ${_formatMoney(cardSales)}',
                    percent: cardPct,
                    color: _success,
                  ),
                  _buildCompositionPercentBar(
                    label: 'Refunds • ${_formatMoney(refunds)}',
                    percent: refundPct,
                    color: _danger,
                  ),
                  _buildCompositionPercentBar(
                    label: 'Discounts • ${_formatMoney(discounts)}',
                    percent: discountPct,
                    color: _warning,
                  ),
                ],
              );

              if (!isWide) {
                return Column(
                  children: [
                    chartSide,
                    const SizedBox(height: 18),
                    barsSide,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 272, child: chartSide),
                  const SizedBox(width: 18),
                  Expanded(child: barsSide),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCashierRow(Map<String, dynamic> row, int index) {
    final cashierName = (row['cashier_name'] ?? 'Unknown').toString();
    final saleCount = (row['sale_count'] as num?)?.toInt() ?? 0;
    final refundCount = (row['refund_count'] as num?)?.toInt() ?? 0;
    final netAfterRefunds =
        ((row['net_after_refunds'] as num?) ?? 0).toDouble();
    final avgSale = saleCount <= 0 ? 0.0 : netAfterRefunds / saleCount;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: const TextStyle(
                  color: _brand,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cashierName,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildBadge(label: '$saleCount sales'),
                    _buildBadge(
                      label: '$refundCount refunds',
                      background: const Color(0xFFFFF1F3),
                      foreground: _danger,
                    ),
                    _buildBadge(
                      label: 'Avg ${_formatMoney(avgSale)}',
                      background: const Color(0xFFFFF8EA),
                      foreground: const Color(0xFF8A5A00),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              _formatMoney(netAfterRefunds),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _success,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashierBreakdownCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Cashier Performance',
            subtitle: 'Net sales and refund activity by cashier.',
            trailing: _buildBadge(
              label: '${_cashierBreakdown.length} cashiers',
              background: const Color(0xFFEAF1FF),
              foreground: _brand,
            ),
          ),
          const SizedBox(height: 12),
          if (_cashierBreakdown.isEmpty)
            _buildEmptyState(
              icon: Icons.groups_rounded,
              title: 'No cashier data found for this range.',
            )
          else
            ..._cashierBreakdown.asMap().entries.map(
                  (entry) => _buildCashierRow(entry.value, entry.key),
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
        return _brand;
    }
  }

  Widget _buildProductRow(Map<String, dynamic> row, int index) {
    final productName = (row['product_name'] ?? 'Unknown Item').toString();
    final barcode = (row['barcode'] ?? '').toString();
    final netQty = (row['net_quantity_sold'] as num?)?.toInt() ?? 0;
    final refundedQty = (row['refunded_quantity'] as num?)?.toInt() ?? 0;
    final netSales = ((row['net_sales_after_refunds'] as num?) ?? 0).toDouble();
    final estimatedProfit = ((row['estimated_profit'] as num?) ?? 0).toDouble();
    final marginPercent = ((row['margin_percent'] as num?) ?? 0).toDouble();
    final rankColor = _rankColor(index);
    final profitColor = estimatedProfit >= 0 ? _success : _danger;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  color: rankColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (barcode.isNotEmpty) _buildBadge(label: barcode),
                    _buildBadge(label: 'Sold $netQty'),
                    if (refundedQty > 0)
                      _buildBadge(
                        label: 'Refunded $refundedQty',
                        background: const Color(0xFFFFF1F3),
                        foreground: _danger,
                      ),
                    _buildBadge(
                      label: 'Margin ${marginPercent.toStringAsFixed(1)}%',
                      background: const Color(0xFFF0FDF4),
                      foreground: _success,
                    ),
                  ],
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
                style: const TextStyle(
                  color: _success,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Profit ${_formatMoney(estimatedProfit)}',
                style: TextStyle(
                  color: profitColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductPerformanceCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Top Products',
            subtitle: 'Best sellers by net sales after refunds.',
            trailing: _buildBadge(
              label: '${_productPerformance.length} items',
              background: const Color(0xFFEAF1FF),
              foreground: _brand,
            ),
          ),
          const SizedBox(height: 12),
          if (_productPerformance.isEmpty)
            _buildEmptyState(
              icon: Icons.inventory_2_rounded,
              title: 'No product sales found for this range.',
            )
          else
            ..._productPerformance.asMap().entries.map(
                  (entry) => _buildProductRow(entry.value, entry.key),
                ),
        ],
      ),
    );
  }

  Widget _buildSlowMoverRow(Map<String, dynamic> row, int index) {
    final productName = (row['product_name'] ?? 'Unknown Item').toString();
    final barcode = (row['barcode'] ?? '').toString();
    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    final quantitySold = (row['quantity_sold'] as num?)?.toInt() ?? 0;
    final stockValue = ((row['stock_value'] as num?) ?? 0).toDouble();
    final isDeadStock = row['is_dead_stock'] == true;
    final statusColor = isDeadStock ? _danger : _warning;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (barcode.isNotEmpty) _buildBadge(label: barcode),
                    _buildBadge(
                      label: quantitySold <= 0 ? 'No sales' : 'Sold $quantitySold',
                      background: statusColor.withOpacity(0.12),
                      foreground: statusColor,
                    ),
                    _buildBadge(label: 'Stock $stock'),
                    if (isDeadStock)
                      _buildBadge(
                        label: 'Dead Stock',
                        background: const Color(0xFFFFF1F3),
                        foreground: _danger,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(stockValue),
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Stock value',
                style: TextStyle(
                  color: _textSecondary.withOpacity(0.95),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlowMoversCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Slow Movers',
            subtitle: 'Items still in stock but barely moving.',
            trailing: _buildBadge(
              label: '${_slowMovers.length} items',
              background: const Color(0xFFFFF7E8),
              foreground: const Color(0xFF8A5A00),
            ),
          ),
          const SizedBox(height: 12),
          if (_slowMovers.isEmpty)
            _buildEmptyState(
              icon: Icons.hourglass_bottom_rounded,
              title: 'No slow movers found for this range.',
            )
          else
            ..._slowMovers.asMap().entries.map(
                  (entry) => _buildSlowMoverRow(entry.value, entry.key),
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: _mutedSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _brand, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    Widget placeholder({double height = 120}) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Column(
          children: [
            placeholder(height: 260),
            const SizedBox(height: 16),
            placeholder(height: 360),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: placeholder(height: 340)),
                const SizedBox(width: 16),
                Expanded(child: placeholder(height: 340)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: placeholder(height: 420)),
                const SizedBox(width: 16),
                Expanded(child: placeholder(height: 420)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResponsiveSplit({
    required double maxWidth,
    required Widget left,
    required Widget right,
  }) {
    if (maxWidth < 1080) {
      return Column(
        children: [
          left,
          const SizedBox(height: 16),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildDashboardBody(Map<String, dynamic>? summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOverviewCard(summary),
                const SizedBox(height: 16),
                _buildTrendCard(),
                const SizedBox(height: 16),
                _buildSalesCompositionCard(summary),
                const SizedBox(height: 16),
                _buildCashierBreakdownCard(),
                const SizedBox(height: 16),
                if (!isWide) ...[
                  _buildProductPerformanceCard(),
                  const SizedBox(height: 16),
                  _buildSlowMoversCard(),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildProductPerformanceCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSlowMoversCard()),
                    ],
                  ),
                ],
              ],
            ),
          ],
        );
      },
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
        backgroundColor: const Color(0xFF174EA6),
        foregroundColor: Colors.white,
        title: const Text(
          'Sales Report',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: _buildDashboardBody(summary),
            ),
    );
  }
}

class _LegendTag extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendTag({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  const _DonutChartPainter({
    required this.values,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final rect = Offset.zero & size;
    final strokeWidth = math.min(size.width, size.height) * 0.18;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFE7ECF3)
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2,
      math.pi * 2,
      false,
      basePaint,
    );

    if (total <= 0) return;

    double startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value <= 0) continue;

      final sweep = (value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = colors[i % colors.length]
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
