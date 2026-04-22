import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class OwnerSalesScreen extends StatefulWidget {
  const OwnerSalesScreen({super.key});

  @override
  State<OwnerSalesScreen> createState() => _OwnerSalesScreenState();
}

class _OwnerSalesScreenState extends State<OwnerSalesScreen> {
  String _selectedRange = 'today';
  DateTime? _specificDate;
  DateTimeRange? _customRange;

  bool get _showHourlyView =>
      _selectedRange == 'today' || _selectedRange == 'specific';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().fetchOwnerSalesReport(range: _selectedRange);
    });
  }

  Future<void> _refresh() async {
    await context.read<AdminProvider>().fetchOwnerSalesReport(
          range: _selectedRange,
          specificDate: _specificDate,
          dateRange: _customRange,
        );
  }

  Future<void> _pickSpecificDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _specificDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );

    if (picked == null || !mounted) return;

    setState(() {
      _specificDate = picked;
      _selectedRange = 'specific';
    });
    await _refresh();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange,
    );

    if (picked == null || !mounted) return;

    setState(() {
      _customRange = picked;
      _selectedRange = 'custom';
    });
    await _refresh();
  }

  Future<void> _selectRange(String value) async {
    setState(() {
      _selectedRange = value;
      if (value != 'specific') _specificDate = null;
      if (value != 'custom') _customRange = null;
    });
    await _refresh();
  }

  String _formatMoney(num value) {
    final amount = value.toDouble();
    final prefix = amount < 0 ? '-Rs. ' : 'Rs. ';
    return '$prefix${amount.abs().toStringAsFixed(2)}';
  }

  String _formatCompactMoney(num value) {
    final amount = value.toDouble().abs();
    final prefix = value.toDouble() < 0 ? '-Rs. ' : 'Rs. ';
    if (amount >= 1000000) {
      return '$prefix${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '$prefix${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '$prefix${amount.toStringAsFixed(0)}';
  }

  String _formatDateLong(DateTime date) =>
      '${date.day} ${_monthShort(date.month)} ${date.year}';

  String _formatDateShort(DateTime date) =>
      '${date.day} ${_monthShort(date.month)}';

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, months.length - 1)];
  }

  _ReportWindowDetails _resolveWindow(Map<String, dynamic> window) {
    final rangeKey = (window['range_key'] ?? _selectedRange).toString();
    final start = DateTime.tryParse((window['start_date'] ?? '').toString());
    final end = DateTime.tryParse((window['end_date'] ?? '').toString());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var fallbackStart = today;
    var fallbackEnd = today;

    switch (_selectedRange) {
      case 'last7':
        fallbackStart = today.subtract(const Duration(days: 6));
        break;
      case 'last30':
        fallbackStart = today.subtract(const Duration(days: 29));
        break;
      case 'specific':
        final picked = _specificDate ?? today;
        fallbackStart = DateTime(picked.year, picked.month, picked.day);
        fallbackEnd = fallbackStart;
        break;
      case 'custom':
        final pickedStart = _customRange?.start ?? today;
        final pickedEnd = _customRange?.end ?? today;
        fallbackStart = DateTime(
          pickedStart.year,
          pickedStart.month,
          pickedStart.day,
        );
        fallbackEnd = DateTime(pickedEnd.year, pickedEnd.month, pickedEnd.day);
        break;
      case 'today':
      default:
        break;
    }

    return _ReportWindowDetails(
      rangeKey: rangeKey,
      start: start ?? fallbackStart,
      end: end ?? fallbackEnd,
      fallbackLabel: (window['label'] ?? '').toString(),
    );
  }

  double _cashierSales(Map<String, dynamic> cashier) {
    return ((cashier['net_after_refunds'] ?? cashier['net_sales']) as num?)
            ?.toDouble() ??
        0.0;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final report = provider.ownerSalesReport;
    final summary = provider.ownerSalesSummary;
    final trend = _showHourlyView
        ? provider.ownerSalesHourlyTrend
        : provider.ownerSalesTrendReport;
    final cashiers = provider.ownerSalesCashiers;
    final topProducts = provider.ownerSalesTopProducts;
    final slowMovers = provider.ownerSalesSlowMovers;
    final window =
        Map<String, dynamic>.from((report['window'] as Map?) ?? <String, dynamic>{});
    final windowDetails = _resolveWindow(window);
    final snapshot = _SalesSnapshot.fromSummary(summary);
    final isInitialLoading = provider.isOwnerSalesLoading && report.isEmpty;
    final isRefreshing = provider.isOwnerSalesLoading && report.isNotEmpty;
    final windowLabel = windowDetails.displayLabel(
      longFormatter: _formatDateLong,
      shortFormatter: _formatDateShort,
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _HeaderCard(
              netSales: _formatMoney(snapshot.netSales),
              subtitle: _showHourlyView
                  ? 'Hourly review for ${windowDetails.shortLabel(_formatDateShort)}'
                  : 'Period review for ${windowDetails.shortLabel(_formatDateShort)}',
              windowLabel: windowLabel,
            ),
            const SizedBox(height: 16),
            _RangeBar(
              selectedRange: _selectedRange,
              helperText: windowDetails.helperLabel,
              windowLabel: windowLabel,
              specificDateLabel: _specificDate == null
                  ? 'Pick date'
                  : _formatDateLong(_specificDate!),
              customRangeLabel: _customRange == null
                  ? 'Date range'
                  : '${_formatDateShort(_customRange!.start)} - ${_formatDateLong(_customRange!.end)}',
              isRefreshing: isRefreshing,
              onRangeSelected: _selectRange,
              onPickDate: _pickSpecificDate,
              onPickRange: _pickDateRange,
            ),
            if (isRefreshing) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 4),
              ),
            ],
            if (isInitialLoading) ...[
              const SizedBox(height: 16),
              const _InitialLoadingCard(),
            ] else ...[
              const SizedBox(height: 16),
              _SalesReportContent(
                snapshot: snapshot,
                trend: trend,
                cashiers: cashiers,
                topProducts: topProducts,
                slowMovers: slowMovers,
                showHourlyView: _showHourlyView,
                formatMoney: _formatMoney,
                formatCompactMoney: _formatCompactMoney,
                cashierSales: _cashierSales,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SalesSnapshot {
  const _SalesSnapshot({
    required this.netSales,
    required this.grossSales,
    required this.transactions,
    required this.averageSale,
    required this.grossProfit,
    required this.marginPercent,
    required this.discounts,
    required this.refunds,
    required this.cashSales,
    required this.cardSales,
    required this.paymentDataComplete,
    required this.legacyUntypedPaymentSales,
    required this.itemsSold,
  });

  final double netSales;
  final double grossSales;
  final int transactions;
  final double averageSale;
  final double grossProfit;
  final double marginPercent;
  final double discounts;
  final double refunds;
  final double cashSales;
  final double cardSales;
  final bool paymentDataComplete;
  final double legacyUntypedPaymentSales;
  final int itemsSold;

  factory _SalesSnapshot.fromSummary(Map<String, dynamic> summary) {
    final legacyUntypedPaymentSales =
        (summary['legacy_untyped_payment_sales'] as num?)?.toDouble() ?? 0.0;
    return _SalesSnapshot(
      netSales: (summary['net_after_refunds'] as num?)?.toDouble() ??
          (summary['net_sales'] as num?)?.toDouble() ??
          0.0,
      grossSales: (summary['gross_sales'] as num?)?.toDouble() ?? 0.0,
      transactions: (summary['transaction_count'] as num?)?.toInt() ?? 0,
      averageSale: (summary['average_sale'] as num?)?.toDouble() ?? 0.0,
      grossProfit: (summary['gross_profit'] as num?)?.toDouble() ?? 0.0,
      marginPercent: (summary['margin_percent'] as num?)?.toDouble() ?? 0.0,
      discounts: (summary['discounts'] as num?)?.toDouble() ?? 0.0,
      refunds: (summary['refunds'] as num?)?.toDouble() ?? 0.0,
      cashSales: (summary['cash_sales'] as num?)?.toDouble() ?? 0.0,
      cardSales: (summary['card_sales'] as num?)?.toDouble() ?? 0.0,
      paymentDataComplete:
          (summary['payment_data_complete'] as bool?) ??
              (legacyUntypedPaymentSales <= 0),
      legacyUntypedPaymentSales: legacyUntypedPaymentSales,
      itemsSold: (summary['items_sold'] as num?)?.toInt() ?? 0,
    );
  }

  int get safeItemsSold => itemsSold < 0 ? 0 : itemsSold;
}

class _ReportWindowDetails {
  const _ReportWindowDetails({
    required this.rangeKey,
    required this.start,
    required this.end,
    required this.fallbackLabel,
  });

  final String rangeKey;
  final DateTime start;
  final DateTime end;
  final String fallbackLabel;

  bool get isSingleDay => DateUtils.isSameDay(start, end);

  String get helperLabel {
    switch (rangeKey) {
      case 'last7':
        return 'Rolling 7-day comparison';
      case 'last30':
        return 'Rolling 30-day review';
      case 'specific':
        return 'Single-day audit mode';
      case 'custom':
        return 'Custom date range review';
      default:
        return 'Today live trading view';
    }
  }

  String shortLabel(String Function(DateTime date) formatter) {
    if (isSingleDay) return formatter(start);
    return '${formatter(start)} - ${formatter(end)}';
  }

  String displayLabel({
    required String Function(DateTime date) longFormatter,
    required String Function(DateTime date) shortFormatter,
  }) {
    if (isSingleDay) return longFormatter(start);
    if (fallbackLabel.isNotEmpty) return fallbackLabel;
    return '${shortFormatter(start)} - ${longFormatter(end)}';
  }
}

abstract final class _SalesPalette {
  static const Color primary = Color(0xFF0F3D91);
  static const Color primaryBright = Color(0xFF2F6FE4);
  static const Color success = Color(0xFF147A5A);
  static const Color successBright = Color(0xFF12B76A);
  static const Color warning = Color(0xFFB54708);
  static const Color warningSoft = Color(0xFFFFF4D6);
  static const Color danger = Color(0xFFD92D20);
  static const Color violet = Color(0xFF7A1CAC);
}

class _SalesReportContent extends StatelessWidget {
  const _SalesReportContent({
    required this.snapshot,
    required this.trend,
    required this.cashiers,
    required this.topProducts,
    required this.slowMovers,
    required this.showHourlyView,
    required this.formatMoney,
    required this.formatCompactMoney,
    required this.cashierSales,
  });

  final _SalesSnapshot snapshot;
  final List<Map<String, dynamic>> trend;
  final List<Map<String, dynamic>> cashiers;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> slowMovers;
  final bool showHourlyView;
  final String Function(num value) formatMoney;
  final String Function(num value) formatCompactMoney;
  final double Function(Map<String, dynamic> row) cashierSales;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final childAspectRatio = constraints.maxWidth < 360 ? 1.05 : 1.22;
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
              children: [
                _MetricCard(
                  label: 'Transactions',
                  value: '${snapshot.transactions}',
                  helper: 'Completed sales',
                  icon: Icons.receipt_long_rounded,
                  color: _SalesPalette.primary,
                ),
                _MetricCard(
                  label: 'Items Sold',
                  value: '${snapshot.safeItemsSold}',
                  helper: 'Units sold in this period',
                  icon: Icons.shopping_bag_outlined,
                  color: _SalesPalette.success,
                ),
                _MetricCard(
                  label: 'Profit Margin',
                  value: '${snapshot.marginPercent.toStringAsFixed(1)}%',
                  helper: 'Profit efficiency',
                  icon: Icons.percent_rounded,
                  color: _SalesPalette.warning,
                ),
                _MetricCard(
                  label: 'Gross Profit',
                  value: formatCompactMoney(snapshot.grossProfit),
                  helper: '${snapshot.safeItemsSold} items sold',
                  icon: Icons.trending_up_rounded,
                  color: _SalesPalette.violet,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Sales Trend',
          subtitle: showHourlyView
              ? 'Hourly performance for the selected day'
              : 'Daily net sales across the selected window',
          trailing: _StatusPill(
            label: showHourlyView ? 'Hourly view' : 'Daily view',
            tone: _SalesPalette.primary,
          ),
          child: trend.isEmpty
              ? _EmptyBlock(
                  icon: showHourlyView
                      ? Icons.schedule_rounded
                      : Icons.bar_chart_rounded,
                  title:
                      showHourlyView ? 'No hourly sales yet' : 'No sales in this period',
                  subtitle: showHourlyView
                      ? 'Hourly sales will appear once this day has synced transaction timing.'
                      : 'Choose another range or wait for POS sales to sync.',
                )
              : _OwnerTrendChart(
                  points: trend,
                  formatMoney: formatMoney,
                  formatCompactMoney: formatCompactMoney,
                  isHourlyView: showHourlyView,
                ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Payment & Reductions',
          subtitle: 'Payment collection, discounts, and refunds',
          child: _PaymentReductionCard(
            cashSales: snapshot.cashSales,
            cardSales: snapshot.cardSales,
            discounts: snapshot.discounts,
            refunds: snapshot.refunds,
            grossSales: snapshot.grossSales,
            formatMoney: formatMoney,
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Cashier Summary',
          subtitle: 'Performance by cashier for this period',
          trailing: _CountBadge(label: '${cashiers.length} cashiers'),
          child: cashiers.isEmpty
              ? const _EmptyBlock(
                  icon: Icons.person_outline,
                  title: 'No cashier data yet',
                  subtitle: 'Cashier sales will appear as POS activity syncs.',
                )
              : Column(
                  children: cashiers
                      .map(
                        (cashier) => _CashierTile(
                          name: (cashier['cashier_name'] ?? 'Unknown').toString(),
                          transactions:
                              (cashier['transaction_count'] as num?)?.toInt() ?? 0,
                          refundCount:
                              (cashier['refund_count'] as num?)?.toInt() ?? 0,
                          totalSales: cashierSales(cashier),
                          averageSale:
                              (cashier['average_sale'] as num?)?.toDouble() ?? 0.0,
                          formatMoney: formatMoney,
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Top Products',
          subtitle: 'Best sellers for the selected period',
          trailing: _CountBadge(label: '${topProducts.length} products'),
          child: topProducts.isEmpty
              ? const _EmptyBlock(
                  icon: Icons.inventory_2_outlined,
                  title: 'No top products yet',
                  subtitle:
                      'Products will appear here once sales sync for the selected range.',
                )
              : Column(
                  children: topProducts
                      .asMap()
                      .entries
                      .map(
                        (entry) => _TopProductTile(
                          rank: entry.key + 1,
                          row: entry.value,
                          formatMoney: formatMoney,
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Slow Movers',
          subtitle: 'Items still in stock but barely moving',
          trailing: _CountBadge(label: '${slowMovers.length} flagged'),
          child: slowMovers.isEmpty
              ? const _EmptyBlock(
                  icon: Icons.inventory_2_outlined,
                  title: 'No slow movers found',
                  subtitle:
                      'Slow-moving items will appear once the selected period has enough sales data.',
                )
              : Column(
                  children: slowMovers
                      .asMap()
                      .entries
                      .map(
                        (entry) => _SlowMoverTile(
                          rank: entry.key + 1,
                          row: entry.value,
                          formatMoney: formatMoney,
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.netSales,
    required this.subtitle,
    required this.windowLabel,
  });

  final String netSales;
  final String subtitle;
  final String windowLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_SalesPalette.primary, _SalesPalette.primaryBright],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F3D91),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sales Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.84),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Net sales',
            style: TextStyle(
              color: Color(0xCCFFFFFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              netSales,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    windowLabel,
                    style: const TextStyle(
                      color: Colors.white,
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
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.selectedRange,
    required this.helperText,
    required this.windowLabel,
    required this.specificDateLabel,
    required this.customRangeLabel,
    required this.isRefreshing,
    required this.onRangeSelected,
    required this.onPickDate,
    required this.onPickRange,
  });

  final String selectedRange;
  final String helperText;
  final String windowLabel;
  final String specificDateLabel;
  final String customRangeLabel;
  final bool isRefreshing;
  final Future<void> Function(String value) onRangeSelected;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickRange;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: _SalesPalette.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Report Window',
                        style: TextStyle(
                          color: Color(0xFF172433),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        helperText,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isRefreshing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFD),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE3E9F3)),
              ),
              child: Text(
                windowLabel,
                style: const TextStyle(
                  color: Color(0xFF172433),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _RangeChip(
                    label: 'Today',
                    icon: Icons.today_rounded,
                    selected: selectedRange == 'today',
                    onTap: () => onRangeSelected('today'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RangeChip(
                    label: '7 Days',
                    icon: Icons.date_range_rounded,
                    selected: selectedRange == 'last7',
                    onTap: () => onRangeSelected('last7'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RangeChip(
                    label: '30 Days',
                    icon: Icons.view_week_outlined,
                    selected: selectedRange == 'last30',
                    onTap: () => onRangeSelected('last30'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _RangeChip(
                    label: specificDateLabel,
                    icon: Icons.event_rounded,
                    selected: selectedRange == 'specific',
                    onTap: onPickDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RangeChip(
                    label: customRangeLabel,
                    icon: Icons.event_note_rounded,
                    selected: selectedRange == 'custom',
                    onTap: onPickRange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _SalesPalette.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _SalesPalette.primary : const Color(0xFFD8E0EA),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : const Color(0xFF667085),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF172433),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF172433),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF7B8796),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360 || trailing == null;
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF172433),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(height: 12),
                        trailing!,
                      ],
                    ],
                  );
                }

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
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF172433),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF667085),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InitialLoadingCard extends StatelessWidget {
  const _InitialLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E9F3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          SizedBox(height: 14),
          Text(
            'Preparing the sales report...',
            style: TextStyle(
              color: Color(0xFF172433),
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Loading the latest owner sales summary, trend, payments, and product insights.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnerTrendChart extends StatelessWidget {
  const _OwnerTrendChart({
    required this.points,
    required this.formatMoney,
    required this.formatCompactMoney,
    required this.isHourlyView,
  });

  final List<Map<String, dynamic>> points;
  final String Function(num value) formatMoney;
  final String Function(num value) formatCompactMoney;
  final bool isHourlyView;

  double _valueFor(Map<String, dynamic> row) {
    return ((row['net_after_refunds'] ?? row['net_sales']) as num?)
            ?.toDouble() ??
        0.0;
  }

  int _hourFor(Map<String, dynamic> row) {
    final raw = row['hour'];
    if (raw is num) {
      return raw.toInt().clamp(0, 23);
    }
    return 0;
  }

  String _formatHourLong(int hour) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display:00 $suffix';
  }

  String _formatHourShort(int hour) {
    if (hour == 0) return '12a';
    if (hour < 12) return '${hour}a';
    if (hour == 12) return '12p';
    return '${hour - 12}p';
  }

  String _formatDailyLabel(Map<String, dynamic> row) {
    final raw = (row['label'] ?? row['sales_date'] ?? '').toString().trim();
    if (raw.isEmpty) return '--';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.day}/${parsed.month.toString().padLeft(2, '0')}';
  }

  bool _shouldShowDailyLabel(int index, int total) {
    if (total <= 8) return true;
    if (total <= 14) return index.isEven || index == total - 1;
    return index % 5 == 0 || index == total - 1;
  }

  bool _hasHourlySales(Map<String, dynamic> row) {
    final saleCount = (row['sale_count'] as num?)?.toInt() ?? 0;
    final itemsSold = (row['items_sold'] as num?)?.toInt() ?? 0;
    return saleCount > 0 || itemsSold > 0 || _valueFor(row) > 0;
  }

  bool _shouldShowHourlyLabel(int index, int total) {
    if (total <= 8) return true;
    if (total <= 12) return index.isEven || index == total - 1;
    return index % 3 == 0 || index == total - 1;
  }

  List<Map<String, dynamic>> _activeHourlyPoints() {
    if (points.isEmpty) return const [];

    final rows = points
        .map(
          (row) => {
            ...Map<String, dynamic>.from(row),
            'hour': _hourFor(row),
            'net_after_refunds': _valueFor(row),
          },
        )
        .where(_hasHourlySales)
        .toList();

    rows.sort((a, b) => _hourFor(a).compareTo(_hourFor(b)));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final activePoints = isHourlyView ? _activeHourlyPoints() : points;
    final hasVisibleData = isHourlyView
        ? activePoints.isNotEmpty
        : activePoints.any((point) => _valueFor(point) > 0);

    if (!hasVisibleData) {
      return _EmptyBlock(
        icon: isHourlyView ? Icons.schedule_rounded : Icons.bar_chart_rounded,
        title: isHourlyView ? 'No hourly sales yet' : 'No sales in this period',
        subtitle: isHourlyView
            ? 'Active sales hours will appear once this day has sales.'
            : 'Choose another range or wait for POS sales to sync.',
      );
    }

    final maxValue = activePoints.fold<double>(
      0,
      (max, point) => math.max(max, _valueFor(point)),
    );
    final withSales =
        activePoints.where((point) => _valueFor(point) > 0).toList(growable: false);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final ticks = <double>[safeMax, safeMax * 0.66, safeMax * 0.33, 0];
    final peakPoint = withSales.isEmpty
        ? null
        : withSales.reduce((a, b) => _valueFor(a) >= _valueFor(b) ? a : b);
    final activeHours = withSales.length;
    final averageActiveHour = activeHours == 0
        ? 0.0
        : withSales.fold<double>(0.0, (sum, point) => sum + _valueFor(point)) /
            activeHours;

    final insightTiles = [
      _TrendInsightData(
        icon: isHourlyView ? Icons.schedule_rounded : Icons.calendar_today_rounded,
        label: isHourlyView ? 'Peak hour' : 'Peak day',
        value: peakPoint == null
            ? '--'
            : isHourlyView
                ? _formatHourLong(_hourFor(peakPoint))
                : _formatDailyLabel(peakPoint),
        tone: _SalesPalette.primary,
      ),
      _TrendInsightData(
        icon: Icons.bolt_rounded,
        label: 'Peak sales',
        value:
            peakPoint == null ? '--' : formatCompactMoney(_valueFor(peakPoint)),
        tone: _SalesPalette.success,
      ),
      _TrendInsightData(
        icon: Icons.timeline_rounded,
        label: isHourlyView ? 'Active hours' : 'Active days',
        value: '$activeHours',
        tone: _SalesPalette.warning,
      ),
      _TrendInsightData(
        icon: Icons.auto_graph_rounded,
        label: 'Average active',
        value: formatCompactMoney(averageActiveHour),
        tone: _SalesPalette.violet,
      ),
    ];

    final chartHeight = isHourlyView ? 198.0 : 170.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrendInsightWrap(items: insightTiles),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3E9F3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _StatusPill(
                    label: 'Net sales',
                    tone: _SalesPalette.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isHourlyView ? 'Active hours only' : 'Swipe for full range',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: chartHeight + 26,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 54,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: ticks
                            .map(
                              (value) => Text(
                                formatCompactMoney(value),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF667085),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TrendChartPlot(
                        points: activePoints,
                        isHourlyView: isHourlyView,
                        chartHeight: chartHeight,
                        safeMax: safeMax,
                        formatMoney: formatMoney,
                        hourFor: _hourFor,
                        valueFor: _valueFor,
                        formatHourLong: _formatHourLong,
                        formatHourShort: _formatHourShort,
                        formatDailyLabel: _formatDailyLabel,
                        shouldShowDailyLabel: _shouldShowDailyLabel,
                        shouldShowHourlyLabel: _shouldShowHourlyLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendInsightData {
  const _TrendInsightData({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;
}

class _TrendInsightWrap extends StatelessWidget {
  const _TrendInsightWrap({
    required this.items,
  });

  final List<_TrendInsightData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 360 ? 1 : 2;
        const spacing = 10.0;
        final tileWidth =
            (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: tileWidth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: item.tone.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: item.tone.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 16, color: item.tone),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF667085),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF172433),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _TrendChartPlot extends StatelessWidget {
  const _TrendChartPlot({
    required this.points,
    required this.isHourlyView,
    required this.chartHeight,
    required this.safeMax,
    required this.formatMoney,
    required this.hourFor,
    required this.valueFor,
    required this.formatHourLong,
    required this.formatHourShort,
    required this.formatDailyLabel,
    required this.shouldShowDailyLabel,
    required this.shouldShowHourlyLabel,
  });

  final List<Map<String, dynamic>> points;
  final bool isHourlyView;
  final double chartHeight;
  final double safeMax;
  final String Function(num value) formatMoney;
  final int Function(Map<String, dynamic> row) hourFor;
  final double Function(Map<String, dynamic> row) valueFor;
  final String Function(int hour) formatHourLong;
  final String Function(int hour) formatHourShort;
  final String Function(Map<String, dynamic> row) formatDailyLabel;
  final bool Function(int index, int total) shouldShowDailyLabel;
  final bool Function(int index, int total) shouldShowHourlyLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final compactWidth = availableWidth < 260;
        final visibleDailyBars = math.max(1, math.min(7, points.length));
        final slotWidth = isHourlyView
            ? 26.0
            : compactWidth
                ? math.max(availableWidth / visibleDailyBars, 30.0)
                : math.max(availableWidth / visibleDailyBars, 34.0);
        final barWidth = isHourlyView
            ? 14.0
            : math.max(10.0, math.min(16.0, slotWidth * 0.4));
        final plotWidth = points.length <= visibleDailyBars
            ? availableWidth
            : math.max(points.length * slotWidth, availableWidth);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: plotWidth,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            4,
                            (_) => Container(
                              height: 1,
                              color: const Color(0xFFDDE5F0),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final point in points)
                              SizedBox(
                                width: slotWidth,
                                child: Builder(
                                  builder: (context) {
                                    final pointLabel = isHourlyView
                                        ? formatHourLong(hourFor(point))
                                        : formatDailyLabel(point);
                                    final pointValue = formatMoney(valueFor(point));
                                    return Tooltip(
                                      richMessage: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '$pointLabel\n',
                                            style: const TextStyle(
                                              color: Color(0xFFCBD8FF),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              height: 1.25,
                                            ),
                                          ),
                                          TextSpan(
                                            text: pointValue,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                      triggerMode: TooltipTriggerMode.longPress,
                                      waitDuration:
                                          const Duration(milliseconds: 160),
                                      showDuration: const Duration(seconds: 3),
                                      preferBelow: false,
                                      verticalOffset: 20,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF1C2E5A),
                                            Color(0xFF111C36),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF5D7FD3)
                                              .withOpacity(0.45),
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x3A0B1226),
                                            blurRadius: 18,
                                            offset: Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          width: barWidth,
                                          height: math.max(
                                            6,
                                            (valueFor(point) / safeMax) *
                                                (chartHeight - 6),
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: valueFor(point) > 0
                                                  ? const [
                                                      Color(0xFF6EA2FF),
                                                      Color(0xFF2F6FE4),
                                                    ]
                                                  : const [
                                                      Color(0xFFD9E3F1),
                                                      Color(0xFFC9D5E6),
                                                    ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            boxShadow: valueFor(point) > 0
                                                ? const [
                                                    BoxShadow(
                                                      color: Color(0x332F6FE4),
                                                      blurRadius: 10,
                                                      offset: Offset(0, 6),
                                                    ),
                                                  ]
                                                : null,
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
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      for (var index = 0; index < points.length; index++)
                        SizedBox(
                          width: slotWidth,
                          child: Text(
                            isHourlyView
                                ? (shouldShowHourlyLabel(index, points.length)
                                    ? formatHourShort(hourFor(points[index]))
                                    : '')
                                : (shouldShowDailyLabel(index, points.length)
                                    ? formatDailyLabel(points[index])
                                    : ''),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaymentReductionCard extends StatelessWidget {
  const _PaymentReductionCard({
    required this.cashSales,
    required this.cardSales,
    required this.discounts,
    required this.refunds,
    required this.grossSales,
    required this.formatMoney,
  });

  final double cashSales;
  final double cardSales;
  final double discounts;
  final double refunds;
  final double grossSales;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final paymentTotal = cashSales + cardSales;
    final hasCashPayments = cashSales > 0.009;
    final hasCardPayments = cardSales > 0.009;
    final useCashOnlyDesign = hasCashPayments && !hasCardPayments;
    final cashPct = paymentTotal > 0 ? (cashSales / paymentTotal) * 100.0 : 0.0;
    final cardPct = paymentTotal > 0 ? (cardSales / paymentTotal) * 100.0 : 0.0;
    final refundPct = grossSales > 0 ? (refunds / grossSales) * 100.0 : 0.0;
    final discountPct =
        grossSales > 0 ? (discounts / grossSales) * 100.0 : 0.0;
    final reductionPct =
        grossSales > 0 ? ((discounts + refunds) / grossSales) * 100.0 : 0.0;
    final hasReductions = refunds > 0.009 || discounts > 0.009;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FBFF), Color(0xFFF4F7FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3EAF4)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;

          final summaryChart = Center(
            child: SizedBox(
              width: compact ? 168 : 186,
              height: compact ? 168 : 186,
              child: CustomPaint(
                painter: _DonutPainter(
                  values: [cashSales, cardSales],
                  colors: const [
                    _SalesPalette.primaryBright,
                    _SalesPalette.successBright,
                  ],
                ),
                child: Center(
                  child: Container(
                    width: compact ? 100 : 112,
                    height: compact ? 100 : 112,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F3D91).withOpacity(0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Collected',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatMoney(paymentTotal),
                              style: TextStyle(
                                fontSize: compact ? 16 : 18,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF172433),
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
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Payment Split',
                      style: TextStyle(
                        color: Color(0xFF172433),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hasReductions
                    ? 'Collected payments with reduction highlights below.'
                    : 'Payment totals for the selected report window.',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              _PaymentLegendTile(
                label: 'Cash sales',
                value: formatMoney(cashSales),
                percent: cashPct,
                color: _SalesPalette.primaryBright,
              ),
              const SizedBox(height: 10),
              _PaymentLegendTile(
                label: 'Card sales',
                value: formatMoney(cardSales),
                percent: cardPct,
                color: _SalesPalette.successBright,
              ),
              if (hasReductions) ...[
                const SizedBox(height: 14),
                if (refunds > 0)
                  _ReductionPill(
                    label: 'Refunds',
                    value:
                        '${formatMoney(refunds)} - ${refundPct.toStringAsFixed(1)}%',
                    color: _SalesPalette.danger,
                    background: const Color(0xFFFEE4E2),
                  ),
                if (refunds > 0 && discounts > 0) const SizedBox(height: 8),
                if (discounts > 0)
                  _ReductionPill(
                    label: 'Discounts',
                    value:
                        '${formatMoney(discounts)} - ${discountPct.toStringAsFixed(1)}%',
                    color: _SalesPalette.warning,
                    background: _SalesPalette.warningSoft,
                  ),
              ],
            ],
          );

          final healthStats = _PaymentHealthStats(
            rows: [
              _PaymentHealthData(
                label: 'Reduction rate',
                value: '${reductionPct.toStringAsFixed(1)}%',
                tone: hasReductions
                    ? _SalesPalette.warning
                    : _SalesPalette.primaryBright,
              ),
              _PaymentHealthData(
                label: 'Total reductions',
                value: formatMoney(discounts + refunds),
                tone: _SalesPalette.violet,
              ),
            ],
          );

          if (useCashOnlyDesign) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PaymentLegendTile(
                  label: 'Cash sales',
                  value: formatMoney(cashSales),
                  percent: null,
                  color: _SalesPalette.primaryBright,
                ),
                if (hasReductions) ...[
                  const SizedBox(height: 14),
                  if (refunds > 0)
                    _ReductionPill(
                      label: 'Refunds',
                      value:
                          '${formatMoney(refunds)} - ${refundPct.toStringAsFixed(1)}%',
                      color: _SalesPalette.danger,
                      background: const Color(0xFFFEE4E2),
                    ),
                  if (refunds > 0 && discounts > 0) const SizedBox(height: 8),
                  if (discounts > 0)
                    _ReductionPill(
                      label: 'Discounts',
                      value:
                          '${formatMoney(discounts)} - ${discountPct.toStringAsFixed(1)}%',
                      color: _SalesPalette.warning,
                      background: _SalesPalette.warningSoft,
                    ),
                ],
                const SizedBox(height: 14),
                healthStats,
              ],
            );
          }

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summaryChart,
                const SizedBox(height: 16),
                details,
                const SizedBox(height: 14),
                healthStats,
              ],
            );
          }

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 190, child: summaryChart),
                  const SizedBox(width: 16),
                  Expanded(child: details),
                ],
              ),
              const SizedBox(height: 14),
              healthStats,
            ],
          );
        },
      ),
    );
  }
}

class _PaymentLegendTile extends StatelessWidget {
  const _PaymentLegendTile({
    required this.label,
    required this.value,
    required this.color,
    this.percent,
  });

  final String label;
  final String value;
  final double? percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF172433),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (percent != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${percent!.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReductionPill extends StatelessWidget {
  const _ReductionPill({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF172433),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentHealthData {
  const _PaymentHealthData({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;
}

class _PaymentHealthStats extends StatelessWidget {
  const _PaymentHealthStats({
    required this.rows,
  });

  final List<_PaymentHealthData> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final desired = compact ? 2 : rows.length;
        final crossAxisCount = math.max(1, math.min(desired, rows.length));
        const spacing = 10.0;
        final tileWidth =
            (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: rows
              .map(
                (row) => SizedBox(
                  width: tileWidth,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE3E9F3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.label,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          row.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: row.tone,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _CashierTile extends StatelessWidget {
  const _CashierTile({
    required this.name,
    required this.transactions,
    required this.refundCount,
    required this.totalSales,
    required this.averageSale,
    required this.formatMoney,
  });

  final String name;
  final int transactions;
  final int refundCount;
  final double totalSales;
  final double averageSale;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final displayName = name.replaceFirst(RegExp(r'\s+\('), '\n(');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: _SalesPalette.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172433),
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Net sales',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(totalSales),
                      style: const TextStyle(
                        color: _SalesPalette.success,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final tiles = <Widget>[
                _CashierMetaTile(
                  label: 'Transactions',
                  value: '$transactions',
                  valueColor: const Color(0xFF172433),
                  background: Colors.white,
                ),
                _CashierMetaTile(
                  label: 'Average sale',
                  value: formatMoney(averageSale),
                  valueColor: _SalesPalette.warning,
                  background: Colors.white,
                ),
                if (refundCount > 0)
                  _CashierMetaTile(
                    label: 'Refund count',
                    value: '$refundCount',
                    valueColor: _SalesPalette.danger,
                    background: Colors.white,
                  ),
              ];

              final compact = constraints.maxWidth < 360;
              final crossAxisCount = compact ? 2 : tiles.length;
              const spacing = 10.0;
              final tileWidth =
                  (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                      crossAxisCount;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: tiles
                    .map(
                      (tile) => SizedBox(
                        width: tileWidth,
                        child: tile,
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CashierMetaTile extends StatelessWidget {
  const _CashierMetaTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.background,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductTile extends StatelessWidget {
  const _TopProductTile({
    required this.rank,
    required this.row,
    required this.formatMoney,
  });

  final int rank;
  final Map<String, dynamic> row;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final sales =
        ((row['net_sales_after_refunds'] ?? row['net_sales']) as num?)
                ?.toDouble() ??
            0.0;
    final soldQty =
        ((row['sold_quantity'] ?? row['quantity_sold']) as num?)?.toInt() ?? 0;
    final refundedQty = (row['refunded_quantity'] as num?)?.toInt() ?? 0;
    final profit =
        ((row['estimated_profit'] ?? row['gross_profit']) as num?)
                ?.toDouble() ??
            0.0;
    final margin = (row['margin_percent'] as num?)?.toDouble() ?? 0.0;
    final productName = (row['product_name'] ?? 'Unknown').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: _SalesPalette.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF172433),
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(sales),
                      style: const TextStyle(
                        color: _SalesPalette.success,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Net sales',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagPill(
                label: 'Sold $soldQty',
                color: const Color(0xFF172433),
                background: Colors.white,
              ),
              if (refundedQty > 0)
                _TagPill(
                  label: 'Refunded $refundedQty',
                  color: _SalesPalette.danger,
                  background: const Color(0xFFFEE4E2),
                ),
              _TagPill(
                label: 'Margin ${margin.toStringAsFixed(1)}%',
                color: _SalesPalette.primary,
                background: const Color(0xFFEAF1FF),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Estimated profit ${formatMoney(profit)}',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlowMoverTile extends StatelessWidget {
  const _SlowMoverTile({
    required this.rank,
    required this.row,
    required this.formatMoney,
  });

  final int rank;
  final Map<String, dynamic> row;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final sold = (row['quantity_sold'] as num?)?.toInt() ?? 0;
    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    final stockValue = (row['stock_value'] as num?)?.toDouble() ?? 0.0;
    final productName = (row['product_name'] ?? 'Unknown').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2DD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: _SalesPalette.warning,
                    fontWeight: FontWeight.w900,
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
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172433),
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(stockValue),
                      style: const TextStyle(
                        color: _SalesPalette.warning,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Stock value',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagPill(
                label: 'Sold $sold',
                color: const Color(0xFF172433),
                background: Colors.white,
              ),
              _TagPill(
                label: 'Stock $stock',
                color: _SalesPalette.warning,
                background: const Color(0xFFFFF8EB),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: background == Colors.white
            ? Border.all(color: const Color(0xFFE3E9F3))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE3E9F3)),
            ),
            child: Icon(icon, size: 28, color: const Color(0xFF98A2B3)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF172433),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.values,
    required this.colors,
  });

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, item) => sum + item);
    final rect = Offset.zero & size;
    final strokeWidth = math.min(size.width, size.height) * 0.16;
    final arcRect = rect.deflate(strokeWidth / 2);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE7ECF3);

    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2,
      false,
      basePaint,
    );

    if (total <= 0) return;

    double startAngle = -math.pi / 2;
    final gap = values.where((value) => value > 0).length > 1 ? 0.05 : 0.0;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value <= 0) continue;
      final sweep = math.max(0.0, (value / total) * math.pi * 2 - gap);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colors[i % colors.length];

      canvas.drawArc(
        arcRect,
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
