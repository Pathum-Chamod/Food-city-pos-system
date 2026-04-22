import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

enum SalesReportRange { today, last7Days, last30Days, specificDate, customDateRange }

class _SalesReportScreenState extends State<SalesReportScreen> {
  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _success = Color(0xFF1FCF9A);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);

  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  SalesReportRange _selectedRange = SalesReportRange.today;
  DateTime? _selectedDate;
  // Custom date range
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _previousSummary;
  List<Map<String, dynamic>> _dailyTrend = [];
  List<Map<String, dynamic>> _hourlyTrend = [];
  List<Map<String, dynamic>> _cashierBreakdown = [];
  List<Map<String, dynamic>> _productPerformance = [];
  List<Map<String, dynamic>> _slowMovers = [];
  int? _hoveredBarIndex;
  final ScrollController _trendChartScrollController = ScrollController();
  int _contentVersion = 0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page => _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft => _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _panelAlt => _isDark ? const Color(0xFF0B1729) : const Color(0xFFFCFDFE);
  Color get _surfaceAlt => _isDark ? const Color(0xFF0A1628) : const Color(0xFFF7F9FC);
  Color get _border => _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary => _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary => _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _muted => _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _shadow => Colors.black.withOpacity(_isDark ? 0.24 : 0.05);

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _trendChartScrollController.dispose();
    super.dispose();
  }

  bool get _showHourlyView =>
      _selectedRange == SalesReportRange.today ||
      _selectedRange == SalesReportRange.specificDate;

  ({DateTime start, DateTime end}) _currentRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (_selectedRange) {
      case SalesReportRange.last30Days:
        return (start: todayStart.subtract(const Duration(days: 29)), end: now);
      case SalesReportRange.last7Days:
        return (start: todayStart.subtract(const Duration(days: 6)), end: now);
      case SalesReportRange.specificDate:
        final picked = _selectedDate ?? todayStart;
        return (
          start: DateTime(picked.year, picked.month, picked.day),
          end: DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999),
        );
      case SalesReportRange.customDateRange:
        final s = _customRangeStart ?? todayStart.subtract(const Duration(days: 6));
        final e = _customRangeEnd ?? now;
        return (
          start: DateTime(s.year, s.month, s.day),
          end: DateTime(e.year, e.month, e.day, 23, 59, 59, 999),
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
        ? await DatabaseHelper.instance.getHourlySalesSummaryForDay(day: current.start)
        : <Map<String, dynamic>>[];

    final cashierBreakdown = await DatabaseHelper.instance.getCashierBreakdownSummary(
      start: current.start,
      end: current.end,
      limit: 20,
    );

    final productPerformance = await DatabaseHelper.instance.getProductPerformanceSummary(
      start: current.start,
      end: current.end,
      limit: 10,
    );

    final slowMovers = await DatabaseHelper.instance.getSlowMovingProductsSummary(
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
      _hasLoadedOnce = true;
      _contentVersion += 1;
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
      helpText: 'Select sales summary date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedDate = picked;
      _selectedRange = SalesReportRange.specificDate;
    });
    await _loadReport();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final initialStart = _customRangeStart ?? today.subtract(const Duration(days: 6));
    final initialEnd   = _customRangeEnd   ?? today;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: today,
      helpText: 'Select date range',
      saveText: 'APPLY',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _brand,
            onPrimary: Colors.white,
            surface: _panel,
            onSurface: _textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _customRangeStart = picked.start;
      _customRangeEnd   = picked.end;
      _selectedRange    = SalesReportRange.customDateRange;
    });
    await _loadReport();
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
    final exponent = (math.log(value) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
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

  String _formatFullDateFromRaw(String raw) {
    try {
      final date = DateTime.parse(raw);
      return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
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
      case SalesReportRange.last30Days:
        return '${_formatDate(start)} → ${_formatDate(end)}';
      case SalesReportRange.specificDate:
        return 'Selected Date • ${_formatDate(_selectedDate ?? end)}';
      case SalesReportRange.customDateRange:
        return '${_formatDate(start)} → ${_formatDate(end)}';
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
    if (value > 0) return Icons.trending_up_rounded;
    if (value < 0) return Icons.trending_down_rounded;
    return Icons.horizontal_rule_rounded;
  }

  List<Map<String, dynamic>> _filledDailyTrend() {
    final current = _currentRange();
    final start = DateTime(current.start.year, current.start.month, current.start.day);
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

  BoxDecoration _panelDecoration({Color? color, double radius = 26}) {
    return BoxDecoration(
      color: color ?? _panel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: _shadow,
          blurRadius: _isDark ? 28 : 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  Widget _buildPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    Color? color,
  }) {
    return Container(
      padding: padding,
      decoration: _panelDecoration(color: color),
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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
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

  Widget _buildTopHero(Map<String, dynamic>? summary) {
    final netSales = ((summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final transactions = ((summary?['transaction_count'] as num?) ?? 0).toInt();
    final itemsSold = ((summary?['items_sold'] as num?) ?? 0).toInt();
    final refunds = ((summary?['refund_total'] as num?) ?? 0).toDouble();
    final averageSale = ((summary?['average_sale_value'] as num?) ?? 0).toDouble();
    final cashSales = ((summary?['cash_sales'] as num?) ?? 0).toDouble();
    final cardSales = ((summary?['card_sales'] as num?) ?? 0).toDouble();
    final discounts = ((summary?['total_discounts'] as num?) ?? 0).toDouble();
    final currentNet = ((_summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final previousNet = ((_previousSummary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final deltaPct = _percentChange(currentNet, previousNet);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isDark
              ? const [Color(0xFF0F1C31), Color(0xFF14243C), Color(0xFF0B1729)]
              : const [Color(0xFFFFFFFF), Color(0xFFF5FBF9), Color(0xFFF7FAFF)],
        ),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _shadow,
            blurRadius: _isDark ? 32 : 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1050;

              final heroLeft = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildCapsule(
                        icon: Icons.bar_chart_rounded,
                        label: 'Store Sales Workspace',
                        color: _brand,
                      ),
                      // Only show delta badge for multi-day ranges (not Today)
                      if (_selectedRange != SalesReportRange.today)
                        _buildDeltaBadge(deltaPct),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sales Report',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete view of sales, cashiers, payment mix, product performance, and slow movers.',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: _brand.withOpacity(_isDark ? 0.16 : 0.10),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _brand.withOpacity(0.22)),
                        ),
                        child: const Icon(
                          Icons.payments_rounded,
                          color: _brand,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Net sales after refunds',
                              style: TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatMoney(netSales),
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 36,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '$transactions transactions • $itemsSold items sold • refunds ${_formatMoney(refunds)}',
                              style: TextStyle(
                                color: _textSecondary,
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

              final heroRight = Column(
                crossAxisAlignment: isWide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: isWide ? WrapAlignment.end : WrapAlignment.start,
                    children: [
                      _buildRangeChip(SalesReportRange.today, 'Today'),
                      _buildRangeChip(SalesReportRange.last7Days, '7 Days'),
                      _buildRangeChip(SalesReportRange.last30Days, '30 Days'),
                      _buildDateChip(),
                      _buildDateRangeChip(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: _loadReport,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand.withOpacity(_isDark ? 0.16 : 0.10),
                      foregroundColor: _brand,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh Report'),
                  ),
                ],
              );

              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heroLeft, const SizedBox(height: 20), heroRight],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: heroLeft),
                  const SizedBox(width: 22),
                  Expanded(flex: 5, child: heroRight),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1200
                  ? 4
                  : constraints.maxWidth >= 720
                      ? 2
                      : 1;
              const spacing = 12.0;
              final itemWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              final overallProfit = ((summary?['estimated_profit'] as num?) ?? 0).toDouble();
              final cards = [
                _buildMetricCard(
                  title: 'Transactions',
                  value: '$transactions',
                  subtitle: 'Completed bills in range',
                  icon: Icons.receipt_long_rounded,
                  color: _blue,
                ),
                _buildMetricCard(
                  title: 'Items Sold',
                  value: '$itemsSold',
                  subtitle: 'Total units sold',
                  icon: Icons.shopping_bag_rounded,
                  color: _success,
                ),
                _buildMetricCard(
                  title: 'Average Sale',
                  value: _formatMoney(averageSale),
                  subtitle: 'Average bill value',
                  icon: Icons.stacked_line_chart_rounded,
                  color: _warning,
                ),
                _buildMetricCard(
                  title: 'Overall Profit',
                  value: _formatMoney(overallProfit),
                  subtitle: 'Estimated profit after costs',
                  icon: Icons.trending_up_rounded,
                  color: overallProfit >= 0 ? _success : _danger,
                ),
              ];

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [for (final card in cards) SizedBox(width: itemWidth, child: card)],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCapsule({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
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

  Widget _buildDeltaBadge(double deltaPct) {
    final color = _deltaColor(deltaPct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_deltaIcon(deltaPct), size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Text(
            'vs previous',
            style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeChip(SalesReportRange value, String label) {
    final selected = _selectedRange == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (_selectedRange == value) return;
        setState(() {
          _selectedRange = value;
          if (value != SalesReportRange.specificDate) {
            _selectedDate = null;
          }
        });
        _loadReport();
      },
      showCheckmark: false,
      selectedColor: _brand.withOpacity(_isDark ? 0.16 : 0.10),
      backgroundColor: _surfaceAlt,
      side: BorderSide(color: selected ? _brand.withOpacity(0.25) : _border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        color: selected ? _brand : _textPrimary,
        fontWeight: FontWeight.w800,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDateChip() {
    final selected = _selectedRange == SalesReportRange.specificDate;
    final label = _selectedDate == null ? 'Pick Date' : _formatDate(_selectedDate!);
    return ActionChip(
      avatar: Icon(
        Icons.calendar_month_rounded,
        size: 18,
        color: selected ? Colors.white : _textPrimary,
      ),
      label: Text(label),
      onPressed: _pickSpecificDate,
      backgroundColor: selected ? _blue : _surfaceAlt,
      side: BorderSide(color: selected ? _blue.withOpacity(0.35) : _border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _textPrimary,
        fontWeight: FontWeight.w800,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDateRangeChip() {
    final selected = _selectedRange == SalesReportRange.customDateRange;
    String label = 'Date Range';
    if (selected && _customRangeStart != null && _customRangeEnd != null) {
      label =
          '${_formatDate(_customRangeStart!).substring(5)} → ${_formatDate(_customRangeEnd!).substring(5)}';
    }
    return ActionChip(
      avatar: Icon(
        Icons.date_range_rounded,
        size: 18,
        color: selected ? Colors.white : _textPrimary,
      ),
      label: Text(label),
      onPressed: _pickDateRange,
      backgroundColor: selected ? _brand : _surfaceAlt,
      side: BorderSide(color: selected ? _brand.withOpacity(0.35) : _border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _textPrimary,
        fontWeight: FontWeight.w800,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.18)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w900, fontSize: 22, height: 1.05),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontWeight: FontWeight.w600, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendPanel() {
    final currentNet  = ((_summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final previousNet = ((_previousSummary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final deltaPct    = _percentChange(currentNet, previousNet);
    final deltaColor  = _deltaColor(deltaPct);
    final filledTrend = _filledDailyTrend();

    // ── Best / Weakest calculations ────────────────────────────────────────
    final activePoints = _showHourlyView ? _hourlyTrend : filledTrend;

    Map<String, dynamic>? bestPoint;
    Map<String, dynamic>? weakestPoint;

    if (_showHourlyView && _hourlyTrend.isNotEmpty) {
      bestPoint = (_hourlyTrend.cast<Map<String, dynamic>>()).reduce(
        (a, b) => (((a['net_after_refunds'] as num?) ?? 0).toDouble() >=
                    ((b['net_after_refunds'] as num?) ?? 0).toDouble())
            ? a : b,
      );
      // Weakest HOUR with sales > 0
      final withSales = _hourlyTrend
          .where((r) => ((r['net_after_refunds'] as num?) ?? 0).toDouble() > 0)
          .toList();
      if (withSales.isNotEmpty) {
        weakestPoint = (withSales.cast<Map<String, dynamic>>()).reduce(
          (a, b) => (((a['net_after_refunds'] as num?) ?? 0).toDouble() <=
                      ((b['net_after_refunds'] as num?) ?? 0).toDouble())
              ? a : b,
        );
      }
    } else if (filledTrend.isNotEmpty) {
      bestPoint = (filledTrend.cast<Map<String, dynamic>>()).reduce(
        (a, b) => (((a['net_after_refunds'] as num?) ?? 0).toDouble() >=
                    ((b['net_after_refunds'] as num?) ?? 0).toDouble())
            ? a : b,
      );
      // Weakest DAY with sales > 0
      final withSales = filledTrend
          .where((r) => ((r['net_after_refunds'] as num?) ?? 0).toDouble() > 0)
          .toList();
      if (withSales.isNotEmpty) {
        weakestPoint = withSales.reduce(
          (a, b) => (((a['net_after_refunds'] as num?) ?? 0).toDouble() <=
                      ((b['net_after_refunds'] as num?) ?? 0).toDouble())
              ? a : b,
        );
      }
    }

    final dailyMax  = filledTrend.fold<double>(0, (m, r) =>
        math.max(m, ((r['net_after_refunds'] as num?) ?? 0).toDouble()));
    final hourlyMax = _hourlyTrend.fold<double>(0, (m, r) =>
        math.max(m, ((r['net_after_refunds'] as num?) ?? 0).toDouble()));

    // ── Label helpers for best/weakest ──────────────────────────────────────
    String bestLabel = '';
    String weakestLabel = '';
    if (_showHourlyView) {
      bestLabel    = bestPoint == null ? '—'
          : '${_formatHourLabel((bestPoint['hour'] as num?)?.toInt() ?? 0)}  '
            '${_formatCompactMoney(((bestPoint['net_after_refunds'] as num?) ?? 0).toDouble())}';
      weakestLabel = weakestPoint == null ? '—'
          : '${_formatHourLabel((weakestPoint['hour'] as num?)?.toInt() ?? 0)}  '
            '${_formatCompactMoney(((weakestPoint['net_after_refunds'] as num?) ?? 0).toDouble())}';
    } else {
      bestLabel    = bestPoint == null ? '—'
          : '${_formatShortDate((bestPoint['sales_date'] ?? '').toString())}  '
            '${_formatCompactMoney(((bestPoint['net_after_refunds'] as num?) ?? 0).toDouble())}';
      weakestLabel = weakestPoint == null ? '—'
          : '${_formatShortDate((weakestPoint['sales_date'] ?? '').toString())}  '
            '${_formatCompactMoney(((weakestPoint['net_after_refunds'] as num?) ?? 0).toDouble())}';
    }

    // ── Stat cards for right sidebar ─────────────────────────────────────────
    final stats = <_TrendStat>[
      _TrendStat(
        label: 'This period',
        value: _formatCompactMoney(currentNet),
        fullValue: _formatMoney(currentNet),
        icon: Icons.payments_outlined,
        color: _success,
      ),
      _TrendStat(
        label: 'Previous period',
        value: _formatCompactMoney(previousNet),
        fullValue: _formatMoney(previousNet),
        icon: Icons.history_toggle_off_rounded,
        color: _blue,
      ),
      _TrendStat(
        label: _showHourlyView ? 'Best hour' : 'Best day',
        value: bestLabel,
        fullValue: bestLabel,
        icon: Icons.emoji_events_outlined,
        color: _warning,
      ),
      _TrendStat(
        label: _showHourlyView ? 'Weakest hour' : 'Weakest day (>0)',
        value: weakestLabel,
        fullValue: weakestLabel,
        icon: Icons.trending_down_rounded,
        color: _danger,
      ),
    ];

    return _buildPanel(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          final widePanelHeight = _showHourlyView ? 430.0 : 440.0;

          // ── Chart area ───────────────────────────────────────────────────
          final chartWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                title: 'Trend & Pace',
                subtitle: _showHourlyView
                    ? 'Hourly sales movement for the selected day.'
                    : 'Daily sales movement across the selected range.',
                trailing: _buildCapsule(
                  icon: _showHourlyView ? Icons.schedule_rounded : Icons.date_range_rounded,
                  label: _showHourlyView ? 'Hourly view' : 'Daily view',
                  color: _blue,
                ),
              ),
              const SizedBox(height: 16),
              _buildBarChart(
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
                color: _blue,
                emptyMessage: _showHourlyView
                    ? 'No hourly sales recorded for the selected day.'
                    : 'No daily sales found for the selected range.',
              ),
            ],
          );

          // ── Right sidebar stats ──────────────────────────────────────────
          Widget statCard(_TrendStat s) {
            return Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: s.color.withOpacity(_isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: s.color.withOpacity(0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(s.icon, size: 13, color: s.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    s.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            );
          }

          final sideBarItems = <Widget>[
            Container(
              constraints: const BoxConstraints(minHeight: 62),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: deltaColor.withOpacity(_isDark ? 0.12 : 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: deltaColor.withOpacity(0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(_deltaIcon(deltaPct), size: 16, color: deltaColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${deltaPct >= 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: deltaColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'vs previous period',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ...stats.map(statCard),
          ];

          Widget sideBar({required bool distributeHeight}) {
            if (distributeHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: sideBarItems,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sideBarItems.length; i++) ...[
                  sideBarItems[i],
                  if (i < sideBarItems.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          }

          if (isWide) {
            return SizedBox(
              height: widePanelHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: chartWidget),
                  const SizedBox(width: 16),
                  SizedBox(width: 210, child: sideBar(distributeHeight: true)),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chartWidget,
              const SizedBox(height: 14),
              sideBar(distributeHeight: false),
            ],
          );
        },
      ),
    );
  }

  // _buildInsightTile was replaced by the compact stat strip in _buildTrendPanel.
  // Kept as a no-op guard so any stale references compile cleanly.
  // ignore: unused_element
  Widget _buildInsightTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
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
      return _buildEmptyState(icon: Icons.bar_chart_rounded, title: emptyMessage);
    }

    final safeMax    = _roundChartMax(maxValue);
    final tickValues = List<double>.generate(5, (i) => safeMax - ((safeMax / 4) * i));
    final baseSlotWidth  = points.length >= 24 ? 34.0
        : points.length >= 16 ? 40.0
        : points.length >= 10 ? 50.0 : 62.0;
    final baseBarWidth   = points.length >= 24 ? 18.0 : 22.0;
    const chartHeight = 240.0;
    const yAxisWidth  = 52.0;
    final step = points.length <= 8 ? 1
        : points.length <= 14 ? 2
        : points.length <= 22 ? 3 : 4;

    final hoveredIndex = (_hoveredBarIndex != null &&
            _hoveredBarIndex! >= 0 &&
            _hoveredBarIndex! < points.length)
        ? _hoveredBarIndex
        : null;
    final hoveredPoint = hoveredIndex == null ? null : points[hoveredIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Legend row ───────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildMiniLegend(label: 'Net sales after refunds', color: color),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final availablePlotWidth =
                  math.max(220.0, constraints.maxWidth - yAxisWidth - 12);
              final effectivePointCount = math.min(points.length, 30);
              final slotWidth = math.max(
                baseSlotWidth,
                availablePlotWidth / effectivePointCount,
              ).toDouble();
              final plotWidth = slotWidth * points.length;
              final barWidth = math.min(slotWidth * 0.56, baseBarWidth + 6).toDouble();
              const tooltipWidth = 108.0;

              return SizedBox(
                height: chartHeight + 46,
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
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: const MaterialScrollBehavior().copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                            PointerDeviceKind.unknown,
                          },
                        ),
                        child: Scrollbar(
                          controller: _trendChartScrollController,
                          thumbVisibility: plotWidth > availablePlotWidth,
                          trackVisibility: plotWidth > availablePlotWidth,
                          notificationPredicate: (notification) =>
                              notification.metrics.axis == Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: _trendChartScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: plotWidth,
                              height: chartHeight + 46,
                              child: Stack(
                                children: [
                              // Gridlines
                              Positioned(
                                left: 0, right: 0, top: 0, bottom: 42,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    for (int i = 0; i < tickValues.length; i++)
                                      Container(height: 1, color: _border),
                                  ],
                                ),
                              ),
                              // Bars
                              Positioned(
                                left: 0, right: 0, top: 0, bottom: 42,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (var i = 0; i < points.length; i++)
                                      SizedBox(
                                        width: slotWidth,
                                        child: Builder(
                                          builder: (context) {
                                            final point  = points[i];
                                            final value  = valueBuilder(point);
                                            final ratio  = (value / safeMax).clamp(0.0, 1.0);
                                            final barH   = math.max(8.0, ratio * (chartHeight - 8));
                                            final isSelected = hoveredIndex == i;
                                            final isPeak = value == maxValue && maxValue > 0;

                                            return Align(
                                              alignment: Alignment.bottomCenter,
                                              child: MouseRegion(
                                                cursor: SystemMouseCursors.click,
                                                onEnter: (_) => setState(() => _hoveredBarIndex = i),
                                                onExit: (_) {
                                                  setState(() {
                                                    if (_hoveredBarIndex == i) {
                                                      _hoveredBarIndex = null;
                                                    }
                                                  });
                                                },
                                                child: GestureDetector(
                                                  onTap: () => setState(() =>
                                                      _hoveredBarIndex =
                                                          _hoveredBarIndex == i ? null : i),
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 160),
                                                    width: isSelected ? barWidth + 5 : barWidth,
                                                    height: barH,
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(999),
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                        colors: isPeak
                                                            ? [
                                                                color.withOpacity(0.74),
                                                                color,
                                                              ]
                                                            : isSelected
                                                                ? [
                                                                    color.withOpacity(0.70),
                                                                    color,
                                                                  ]
                                                                : [
                                                                    color.withOpacity(value <= 0 ? 0.18 : 0.38),
                                                                    color.withOpacity(value <= 0 ? 0.26 : 0.82),
                                                                  ],
                                                      ),
                                                      boxShadow: isSelected || isPeak
                                                          ? [
                                                              BoxShadow(
                                                                color: color.withOpacity(0.35),
                                                                blurRadius: 18,
                                                                offset: const Offset(0, 8),
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
                              // X-axis labels
                              Positioned(
                                left: 0, right: 0, bottom: 0, height: 28,
                                child: Row(
                                  children: [
                                    for (var i = 0; i < points.length; i++)
                                      SizedBox(
                                        width: slotWidth,
                                        child: Center(
                                          child: (points.length <= 10 ||
                                                  i % step == 0 ||
                                                  i == points.length - 1)
                                              ? Text(
                                                  labelBuilder(points[i]),
                                                  maxLines: 1,
                                                  textAlign: TextAlign.center,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: hoveredIndex == i
                                                        ? color
                                                        : _textSecondary,
                                                    fontSize: 11,
                                                    fontWeight: hoveredIndex == i
                                                        ? FontWeight.w900
                                                        : FontWeight.w700,
                                                    height: 1.1,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Tooltip tooltip near hovered bar
                              if (hoveredPoint != null && hoveredIndex != null)
                                Positioned(
                                  left: ((hoveredIndex * slotWidth) +
                                              (slotWidth / 2) -
                                              (tooltipWidth / 2))
                                          .clamp(0.0, math.max(0.0, plotWidth - tooltipWidth))
                                          .toDouble(),
                                  top: 8,
                                  child: SizedBox(
                                    width: tooltipWidth,
                                    child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(_isDark ? 0.95 : 0.98),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: color.withOpacity(0.5)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            tooltipLabelBuilder(hoveredPoint),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatMoney(valueBuilder(hoveredPoint)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
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
                          ),
                        ),
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

  Widget _buildCompositionPanel(Map<String, dynamic>? summary) {
    final cashSales    = ((summary?['cash_sales'] as num?) ?? 0).toDouble();
    final cardSales    = ((summary?['card_sales'] as num?) ?? 0).toDouble();
    final discounts    = ((summary?['total_discounts'] as num?) ?? 0).toDouble();
    final refunds      = ((summary?['refund_total'] as num?) ?? 0).toDouble();
    final grossSales   = ((summary?['gross_sales'] as num?) ?? 0).toDouble();
    final totalPayments   = cashSales + cardSales;
    final netAfterRefunds = ((summary?['net_after_refunds'] as num?) ?? 0).toDouble();
    final cashPct  = totalPayments <= 0 ? 0.0 : (cashSales / totalPayments) * 100.0;
    final cardPct  = totalPayments <= 0 ? 0.0 : (cardSales / totalPayments) * 100.0;
    final retainedPct = totalPayments <= 0 ? 0.0 : (netAfterRefunds / totalPayments) * 100.0;
    final dominantMethod = cashSales >= cardSales ? 'Cash' : 'Card';
    final dominantColor  = cashSales >= cardSales ? _blue : _success;
    const sectionHeaderGap = 20.0;

    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Composition',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'How revenue was collected, and where it was reduced.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            // ── SECTION A: Donut pie chart for cash/card ────────────────
            Widget sectionA = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section label
                Row(
                  children: [
                    Container(
                      width: 3, height: 14,
                      decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'HOW CUSTOMERS PAID',
                      style: TextStyle(
                        color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: sectionHeaderGap),

                // Donut chart centred with legend
                Center(
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(200, 200),
                          painter: _DonutChartPainter(
                            values: [cashSales, cardSales],
                            colors: [_blue, _success],
                            baseColor: _border,
                            strokeWidth: 26,
                          ),
                        ),
                        // Centre label
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatCompactMoney(totalPayments),
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Total',
                              style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Dominant method badge
                if (totalPayments > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: dominantColor.withOpacity(_isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: dominantColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          dominantMethod == 'Cash' ? Icons.payments_outlined : Icons.credit_card_rounded,
                          size: 14, color: dominantColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$dominantMethod dominant — ${(dominantMethod == 'Cash' ? cashPct : cardPct).toStringAsFixed(1)}% of revenue',
                          style: TextStyle(color: dominantColor, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                if (totalPayments > 0) const SizedBox(height: 12),

                // Cash detail
                _buildDonutLegendRow(
                  icon: Icons.payments_outlined,
                  label: 'Cash',
                  amount: cashSales,
                  pct: cashPct,
                  color: _blue,
                ),
                const SizedBox(height: 10),
                // Card detail
                _buildDonutLegendRow(
                  icon: Icons.credit_card_rounded,
                  label: 'Card',
                  amount: cardSales,
                  pct: cardPct,
                  color: _success,
                ),
              ],
            );

            // ── SECTION B: Revenue journey waterfall ────────────────────────
            Widget sectionB = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _brand,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'REVENUE JOURNEY',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: sectionHeaderGap),

                _buildWaterfallStep(
                  icon: Icons.arrow_circle_up_rounded,
                  label: 'Gross Sales',
                  amount: grossSales,
                  color: _brand,
                  isStart: true,
                ),
                _buildWaterfallConnector(),
                _buildWaterfallStep(
                  icon: Icons.local_offer_outlined,
                  label: 'Discounts Given',
                  amount: discounts,
                  color: _warning,
                  isReduction: true,
                ),
                _buildWaterfallConnector(),
                _buildWaterfallStep(
                  icon: Icons.replay_rounded,
                  label: 'Refunds Issued',
                  amount: refunds,
                  color: _danger,
                  isReduction: true,
                ),
                _buildWaterfallConnector(isFinal: true),
                _buildWaterfallStep(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Net Revenue',
                  amount: netAfterRefunds,
                  color: _success,
                  isFinal: true,
                  retainedPct: retainedPct,
                ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sectionA),
                  const SizedBox(width: 20),
                  Container(width: 1, color: _border, margin: EdgeInsets.zero),
                  const SizedBox(width: 20),
                  Expanded(child: sectionB),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionA,
                const SizedBox(height: 20),
                Container(height: 1, color: _border),
                const SizedBox(height: 20),
                sectionB,
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Single payment method row (Cash or Card) in the composition panel.
  Widget _buildPaymentMethodRow({
    required IconData icon,
    required String label,
    required double amount,
    required double pct,
    required Color color,
    required bool isZero,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(_isDark ? 0.15 : 0.09),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: TextStyle(
                        color: isZero ? _muted : color,
                        fontWeight: FontWeight.w900,
                        fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: _border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      isZero ? color.withOpacity(0.2) : color.withOpacity(0.8)),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatMoney(amount),
                style: TextStyle(
                    color: isZero ? _muted : _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Donut legend row — used in the composition panel pie chart section.
  Widget _buildDonutLegendRow({
    required IconData icon,
    required String label,
    required double amount,
    required double pct,
    required Color color,
  }) {
    final isZero = amount <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.07 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(_isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 13,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(amount),
                style: TextStyle(
                  color: isZero ? _muted : _textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: isZero ? _muted : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A single step in the revenue waterfall.
  Widget _buildWaterfallStep({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
    bool isStart = false,
    bool isReduction = false,
    bool isFinal = false,
    double retainedPct = 0,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: isFinal ? 94 : 66),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: isFinal ? 18 : 14,
      ),
      decoration: BoxDecoration(
        color: isFinal
            ? color.withOpacity(_isDark ? 0.12 : 0.07)
            : _surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFinal ? color.withOpacity(0.28) : _border,
          width: isFinal ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isFinal ? _textPrimary : _textSecondary,
                fontWeight: isFinal ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isReduction)
                    Text(
                      '−  ',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 14),
                    ),
                  Text(
                    _formatMoney(amount),
                    style: TextStyle(
                      color: isFinal ? color : _textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: isFinal ? 16 : 14,
                    ),
                  ),
                ],
              ),
              if (isFinal && retainedPct > 0)
                Text(
                  '${retainedPct.toStringAsFixed(1)}% retained',
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Thin vertical connector between waterfall steps.
  Widget _buildWaterfallConnector({bool isFinal = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 5, bottom: 5),
      child: Row(
        children: [
          Container(
            width: 1.5,
            height: 20,
            color: isFinal
                ? _success.withOpacity(0.4)
                : _border,
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownPanel() {
    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Cashier breakdown',
            subtitle: 'Who sold the most and who handled refunds in this range.',
            trailing: _buildCapsule(
              icon: Icons.groups_rounded,
              label: '${_cashierBreakdown.length} cashiers',
              color: _blue,
            ),
          ),
          const SizedBox(height: 12),
          if (_cashierBreakdown.isEmpty)
            _buildEmptyState(icon: Icons.groups_rounded, title: 'No cashier data found for this range.')
          else
            ..._cashierBreakdown.asMap().entries.map((entry) => _buildCashierRow(entry.value, entry.key)),
        ],
      ),
    );
  }

  Widget _buildCashierRow(Map<String, dynamic> row, int index) {
    final cashierName = (row['cashier_name'] ?? 'Unknown').toString();
    final saleCount = (row['sale_count'] as num?)?.toInt() ?? 0;
    final refundCount = (row['refund_count'] as num?)?.toInt() ?? 0;
    final netAfterRefunds = ((row['net_after_refunds'] as num?) ?? 0).toDouble();
    final avgSale = saleCount <= 0 ? 0.0 : netAfterRefunds / saleCount;
    final rankColor = _textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 12),
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
                  style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _withMetaDividers([
                    _buildMetaText('$saleCount sales'),
                    _buildMetaText('$refundCount refunds', color: refundCount > 0 ? _danger : _textSecondary),
                    _buildMetaText('Avg ${_formatMoney(avgSale)}'),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(netAfterRefunds),
                style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Net after refunds',
                style: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductsPanel() {
    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Top products',
            subtitle: 'Best sellers ranked by net sales after refunds.',
            trailing: _buildCapsule(
              icon: Icons.inventory_2_rounded,
              label: '${_productPerformance.length} items',
              color: _brand,
            ),
          ),
          const SizedBox(height: 12),
          if (_productPerformance.isEmpty)
            _buildEmptyState(icon: Icons.inventory_2_rounded, title: 'No product sales found for this range.')
          else
            ..._productPerformance.asMap().entries.map((entry) => _buildProductRow(entry.value, entry.key)),
        ],
      ),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> row, int index) {
    final productName = (row['product_name'] ?? 'Unknown Item').toString();
    final barcode = (row['barcode'] ?? '').toString();
    final netQty = (row['net_quantity_sold'] as num?)?.toInt() ?? 0;
    final refundedQty = (row['refunded_quantity'] as num?)?.toInt() ?? 0;
    final netSales = ((row['net_sales_after_refunds'] as num?) ?? 0).toDouble();
    final estimatedProfit = ((row['estimated_profit'] as num?) ?? 0).toDouble();
    final marginPercent = ((row['margin_percent'] as num?) ?? 0).toDouble();
    final rankColor = _textSecondary;
    final profitColor = estimatedProfit >= 0 ? _textSecondary : _danger;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 12),
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
                  style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _withMetaDividers([
                    if (barcode.isNotEmpty) _buildMetaText(barcode),
                    _buildMetaText('Sold $netQty'),
                    if (refundedQty > 0) _buildMetaText('Refunded $refundedQty', color: _danger),
                    _buildMetaText('Margin ${marginPercent.toStringAsFixed(1)}%', color: _success),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(netSales),
                style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Profit ${_formatMoney(estimatedProfit)}',
                style: TextStyle(color: profitColor, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlowMoversPanel() {
    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Slow movers',
            subtitle: 'Products still in stock but barely moving.',
            trailing: _buildCapsule(
              icon: Icons.hourglass_bottom_rounded,
              label: '${_slowMovers.length} items',
              color: _warning,
            ),
          ),
          const SizedBox(height: 12),
          if (_slowMovers.isEmpty)
            _buildEmptyState(icon: Icons.hourglass_bottom_rounded, title: 'No slow movers found for this range.')
          else
            ..._slowMovers.asMap().entries.map((entry) => _buildSlowMoverRow(entry.value, entry.key)),
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
    final statusColor = isDeadStock ? _danger : _textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12),
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
                  style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: _withMetaDividers([
                    if (barcode.isNotEmpty) _buildMetaText(barcode),
                    _buildMetaText(quantitySold <= 0 ? 'No sales' : 'Sold $quantitySold', color: quantitySold <= 0 ? _danger : _textSecondary),
                    _buildMetaText('Stock $stock'),
                    if (isDeadStock) _buildMetaText('Dead stock', color: _danger),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMoney(stockValue),
                style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Stock value',
                style: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _withMetaDividers(List<Widget> items) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }
      widgets.add(items[i]);
    }
    return widgets;
  }

  Widget _buildMetaText(String label, {Color? color, FontWeight weight = FontWeight.w700}) {
    return Text(
      label,
      style: TextStyle(
        color: color ?? _textSecondary,
        fontWeight: weight,
        fontSize: 12,
      ),
    );
  }

  Widget _buildMiniLegend({required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _brand.withOpacity(_isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _brand, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    Widget box({required double height}) {
      return Container(
        height: height,
        decoration: _panelDecoration(color: _panel),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        box(height: 310),
        const SizedBox(height: 16),
        box(height: 520),
        const SizedBox(height: 16),
        box(height: 360),
        const SizedBox(height: 16),
        box(height: 420),
      ],
    );
  }

  Widget _buildDashboardBody(Map<String, dynamic>? summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildTopHero(summary),
            const SizedBox(height: 16),
            _buildTrendPanel(),
            const SizedBox(height: 16),
            _buildCompositionPanel(summary),
            const SizedBox(height: 16),
            _buildBreakdownPanel(),
            const SizedBox(height: 16),
            if (!isWide) ...[
              _buildProductsPanel(),
              const SizedBox(height: 16),
              _buildSlowMoversPanel(),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildProductsPanel()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSlowMoversPanel()),
                ],
              ),
            ],
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
        backgroundColor: _page,
        foregroundColor: _textPrimary,
        title: Text(
          'Sales Report',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _isLoading ? null : _loadReport,
            icon: Icon(Icons.refresh_rounded, color: _textPrimary),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_hasLoadedOnce && _isLoading
          ? _buildLoadingState()
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _loadReport,
                  child: _buildDashboardBody(summary),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data holder for compact trend stat strip
// ─────────────────────────────────────────────────────────────────────────────

class _TrendStat {
  final String label;
  final String value;
  final String fullValue;
  final IconData icon;
  final Color color;

  const _TrendStat({
    required this.label,
    required this.value,
    required this.fullValue,
    required this.icon,
    required this.color,
  });
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
  final Color baseColor;
  final double strokeWidth;

  const _DonutChartPainter({
    required this.values,
    required this.colors,
    required this.baseColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = baseColor
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
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
