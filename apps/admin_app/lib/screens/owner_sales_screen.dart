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
    final window = Map<String, dynamic>.from((report['window'] as Map?) ?? <String, dynamic>{});

    final netSales = (summary['net_after_refunds'] as num?)?.toDouble() ?? (summary['net_sales'] as num?)?.toDouble() ?? 0.0;
    final grossSales = (summary['gross_sales'] as num?)?.toDouble() ?? 0.0;
    final transactions = (summary['transaction_count'] as num?)?.toInt() ?? 0;
    final averageSale = (summary['average_sale'] as num?)?.toDouble() ?? 0.0;
    final grossProfit = (summary['gross_profit'] as num?)?.toDouble() ?? 0.0;
    final marginPercent = (summary['margin_percent'] as num?)?.toDouble() ?? 0.0;
    final discounts = (summary['discounts'] as num?)?.toDouble() ?? 0.0;
    final refunds = (summary['refunds'] as num?)?.toDouble() ?? 0.0;
    final cashSales = (summary['cash_sales'] as num?)?.toDouble() ?? 0.0;
    final cardSales = (summary['card_sales'] as num?)?.toDouble() ?? 0.0;
    final legacyUntypedPaymentSales = (summary['legacy_untyped_payment_sales'] as num?)?.toDouble() ?? 0.0;
    final paymentDataComplete = (summary['payment_data_complete'] as bool?) ?? (legacyUntypedPaymentSales <= 0);
    final itemsSold = (summary['items_sold'] as num?)?.toInt() ?? 0;

    final isLoading = provider.isOwnerSalesLoading && report.isEmpty;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _HeaderCard(),
            const SizedBox(height: 16),
            _RangeBar(
              selectedRange: _selectedRange,
              onRangeSelected: _selectRange,
              onPickDate: _pickSpecificDate,
              onPickRange: _pickDateRange,
            ),
            const SizedBox(height: 10),
            if (window.isNotEmpty)
              Text(
                (window['label'] ?? '').toString(),
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 140),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.42,
                children: [
                  _MetricCard(
                    label: 'Net Sales',
                    value: _formatCompactMoney(netSales),
                    icon: Icons.payments_outlined,
                    color: const Color(0xFF0F3D91),
                  ),
                  _MetricCard(
                    label: 'Transactions',
                    value: '$transactions',
                    icon: Icons.receipt_long,
                    color: const Color(0xFF147A5A),
                  ),
                  _MetricCard(
                    label: 'Average Sale',
                    value: _formatCompactMoney(averageSale),
                    icon: Icons.calculate_outlined,
                    color: const Color(0xFF9C5A00),
                  ),
                  _MetricCard(
                    label: 'Profit',
                    value: _formatCompactMoney(grossProfit),
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF7A1CAC),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Sales Trend',
                subtitle: '${itemsSold < 0 ? 0 : itemsSold} items sold • margin ${marginPercent.toStringAsFixed(1)}%',
                child: trend.isEmpty
                    ? _EmptyBlock(
                        icon: _showHourlyView
                            ? Icons.schedule_rounded
                            : Icons.bar_chart_rounded,
                        title: _showHourlyView
                            ? 'No hourly sales yet'
                            : 'No sales in this period',
                        subtitle: _showHourlyView
                            ? 'Hourly sales will appear once this day has synced transaction timing.'
                            : 'Choose another range or wait for POS sales to sync.',
                      )
                    : _OwnerTrendChart(
                        points: trend,
                        formatMoney: _formatMoney,
                        formatCompactMoney: _formatCompactMoney,
                        isHourlyView: _showHourlyView,
                      ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Payment & Reductions',
                subtitle: 'Cash/card mix, discounts, and refunds',
                child: _PaymentReductionCard(
                  cashSales: cashSales,
                  cardSales: cardSales,
                  discounts: discounts,
                  refunds: refunds,
                  grossSales: grossSales,
                  paymentDataComplete: paymentDataComplete,
                  legacyUntypedPaymentSales: legacyUntypedPaymentSales,
                  formatMoney: _formatMoney,
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Cashier Summary',
                subtitle: 'Performance by cashier for this period',
                child: cashiers.isEmpty
                    ? const _EmptyBlock(
                        icon: Icons.person_outline,
                        title: 'No cashier data yet',
                        subtitle: 'Cashier sales will appear as POS activity syncs.',
                      )
                    : Column(
                        children: cashiers
                            .map<Widget>(
                              (cashier) => _CashierTile(
                                name: (cashier['cashier_name'] ?? 'Unknown').toString(),
                                transactions: (cashier['transaction_count'] as num?)?.toInt() ?? 0,
                                refundCount: (cashier['refund_count'] as num?)?.toInt() ?? 0,
                                totalSales: (cashier['net_after_refunds'] as num?)?.toDouble() ?? (cashier['net_sales'] as num?)?.toDouble() ?? 0.0,
                                averageSale: (cashier['average_sale'] as num?)?.toDouble() ?? 0.0,
                                formatMoney: _formatMoney,
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Top Products',
                subtitle: 'Best sellers for the selected period',
                child: topProducts.isEmpty
                    ? const _EmptyBlock(
                        icon: Icons.inventory_2_outlined,
                        title: 'No top products yet',
                        subtitle: 'Products will appear here once sales sync for the selected range.',
                      )
                    : Column(
                        children: topProducts
                            .asMap()
                            .entries
                            .map(
                              (entry) => _TopProductTile(
                                rank: entry.key + 1,
                                row: entry.value,
                                formatMoney: _formatMoney,
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Slow Movers',
                subtitle: 'Items still in stock but barely moving',
                child: slowMovers.isEmpty
                    ? const _EmptyBlock(
                        icon: Icons.inventory_2_outlined,
                        title: 'No slow movers found',
                        subtitle: 'Slow-moving items will appear once the selected period has enough sales data.',
                      )
                    : Column(
                        children: slowMovers
                            .asMap()
                            .entries
                            .map(
                              (entry) => _SlowMoverTile(
                                rank: entry.key + 1,
                                row: entry.value,
                                formatMoney: _formatMoney,
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3D91), Color(0xFF2F6FE4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sales',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Owner sales reporting for business review.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontWeight: FontWeight.w500,
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
    required this.onRangeSelected,
    required this.onPickDate,
    required this.onPickRange,
  });

  final String selectedRange;
  final Future<void> Function(String value) onRangeSelected;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onPickRange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _RangeChip(
          label: 'Today',
          selected: selectedRange == 'today',
          onTap: () => onRangeSelected('today'),
        ),
        _RangeChip(
          label: '7 Days',
          selected: selectedRange == 'last7',
          onTap: () => onRangeSelected('last7'),
        ),
        _RangeChip(
          label: '30 Days',
          selected: selectedRange == 'last30',
          onTap: () => onRangeSelected('last30'),
        ),
        _RangeChip(
          label: 'Pick Date',
          selected: selectedRange == 'specific',
          onTap: onPickDate,
        ),
        _RangeChip(
          label: 'Date Range',
          selected: selectedRange == 'custom',
          onTap: onPickRange,
        ),
      ],
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F3D91) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF0F3D91) : const Color(0xFFD8E0EA),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF475467),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6B7482),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF182431),
                    ),
                  ),
                ),
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
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172433),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF6B7482),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
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
    if (raw.isEmpty) return '—';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day/$month';
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

    rows.sort(
      (a, b) => _hourFor(a).compareTo(_hourFor(b)),
    );
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
    final withSales = activePoints.where((point) => _valueFor(point) > 0).toList();
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

    Widget insightPill({
      required IconData icon,
      required String label,
      required String value,
      required Color tone,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tone.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone.withOpacity(0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: tone),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7482),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF172433),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final chartHeight = isHourlyView ? 208.0 : 186.0;
    var showInsightSummary = false;
    final showChartHeader = isHourlyView || activePoints.length > 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showInsightSummary) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              insightPill(
                icon: Icons.schedule_rounded,
                label: 'Peak hour',
                value: peakPoint == null
                    ? '—'
                    : _formatHourLong(_hourFor(peakPoint)),
                tone: const Color(0xFF0F3D91),
              ),
              insightPill(
                icon: Icons.bolt_rounded,
                label: 'Peak sales',
                value: peakPoint == null
                    ? '—'
                    : formatCompactMoney(_valueFor(peakPoint)),
                tone: const Color(0xFF147A5A),
              ),
              insightPill(
                icon: Icons.timelapse_rounded,
                label: 'Active hours',
                value: '$activeHours',
                tone: const Color(0xFFF79009),
              ),
              insightPill(
                icon: Icons.auto_graph_rounded,
                label: 'Avg active hour',
                value: formatCompactMoney(averageActiveHour),
                tone: const Color(0xFF7A1CAC),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
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
              if (showChartHeader) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F0FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isHourlyView ? 'Hourly view' : 'Daily view',
                        style: TextStyle(
                          color: Color(0xFF0F3D91),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      isHourlyView
                          ? 'Sales hours only'
                          : 'Swipe for full range',
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: chartHeight + 30,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: ticks
                            .map(
                              (value) => Text(
                                formatCompactMoney(value),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF6B7482),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth = constraints.maxWidth;
                          final visibleDailyBars = math.max(
                            1,
                            math.min(7, activePoints.length),
                          );
                          final slotWidth = isHourlyView
                              ? 24.0
                              : math.max(availableWidth / visibleDailyBars, 34.0);
                          final barWidth = isHourlyView
                              ? 14.0
                              : math.max(
                                  12.0,
                                  math.min(18.0, slotWidth * 0.42),
                                );
                          final plotWidth = isHourlyView
                              ? math.max(activePoints.length * slotWidth, availableWidth)
                              : activePoints.length <= 7
                                  ? availableWidth
                                  : math.max(activePoints.length * slotWidth, availableWidth);

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
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
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
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              for (final point in activePoints)
                                                SizedBox(
                                                  width: slotWidth,
                                                  child: Tooltip(
                                                    message:
                                                        '${isHourlyView ? _formatHourLong(_hourFor(point)) : _formatDailyLabel(point)}\n${formatMoney(_valueFor(point))}',
                                                    child: Align(
                                                      alignment:
                                                          Alignment.bottomCenter,
                                                      child: Container(
                                                        width: barWidth,
                                                        height: math.max(
                                                          6,
                                                          (_valueFor(point) /
                                                                  safeMax) *
                                                              (chartHeight - 6),
                                                        ),
                                                        decoration: BoxDecoration(
                                                          gradient:
                                                              LinearGradient(
                                                            begin:
                                                                Alignment.topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                            colors: _valueFor(point) >
                                                                    0
                                                                ? const [
                                                                    Color(
                                                                      0xFF5D94F7,
                                                                    ),
                                                                    Color(
                                                                      0xFF2F6FE4,
                                                                    ),
                                                                  ]
                                                                : const [
                                                                    Color(
                                                                      0xFFD9E3F1,
                                                                    ),
                                                                    Color(
                                                                      0xFFC9D5E6,
                                                                    ),
                                                                  ],
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                            999,
                                                          ),
                                                          boxShadow:
                                                              _valueFor(point) >
                                                                      0
                                                                  ? const [
                                                                      BoxShadow(
                                                                        color: Color(
                                                                          0x332F6FE4,
                                                                        ),
                                                                        blurRadius: 10,
                                                                        offset: Offset(
                                                                          0,
                                                                          6,
                                                                        ),
                                                                      ),
                                                                    ]
                                                                  : null,
                                                        ),
                                                      ),
                                                    ),
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
                                    height: 20,
                                    child: Row(
                                      children: [
                                        for (var index = 0;
                                            index < activePoints.length;
                                            index++)
                                          SizedBox(
                                            width: slotWidth,
                                            child: Text(
                                              isHourlyView
                                                  ? (_shouldShowHourlyLabel(
                                                          index,
                                                          activePoints.length,
                                                        )
                                                      ? _formatHourShort(
                                                          _hourFor(
                                                            activePoints[index],
                                                          ),
                                                        )
                                                      : '')
                                                  : (_shouldShowDailyLabel(
                                                          index,
                                                          activePoints.length,
                                                        )
                                                      ? _formatDailyLabel(
                                                          activePoints[index],
                                                        )
                                                      : ''),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF6B7482),
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

class _PaymentReductionCard extends StatelessWidget {
  const _PaymentReductionCard({
    required this.cashSales,
    required this.cardSales,
    required this.discounts,
    required this.refunds,
    required this.grossSales,
    required this.paymentDataComplete,
    required this.legacyUntypedPaymentSales,
    required this.formatMoney,
  });

  final double cashSales;
  final double cardSales;
  final double discounts;
  final double refunds;
  final double grossSales;
  final bool paymentDataComplete;
  final double legacyUntypedPaymentSales;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final paymentTotal = cashSales + cardSales;
    final cashPct = paymentTotal > 0 ? (cashSales / paymentTotal) * 100.0 : 0.0;
    final cardPct = paymentTotal > 0 ? (cardSales / paymentTotal) * 100.0 : 0.0;
    final refundPct = grossSales > 0 ? (refunds / grossSales) * 100.0 : 0.0;
    final discountPct = grossSales > 0 ? (discounts / grossSales) * 100.0 : 0.0;

    final hasReductions = refunds > 0.009 || discounts > 0.009;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
              final compact = constraints.maxWidth < 320;

              final summaryChart = Center(
                child: SizedBox(
                  width: compact ? 168 : 186,
                  height: compact ? 168 : 186,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      values: [cashSales, cardSales],
                      colors: const [Color(0xFF2F6FE4), Color(0xFF12B76A)],
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
                                color: Color(0xFF6B7482),
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
                                    color: Color(0xFF172433),
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

              final summaryDetails = Column(
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!paymentDataComplete)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4D6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFF7D58D)),
                          ),
                          child: const Text(
                            'Needs sync',
                            style: TextStyle(
                              color: Color(0xFF9C5A00),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasReductions
                        ? 'Collected payments with reduction highlights below.'
                        : 'Cash and card share for the selected period.',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _PaymentLegendTile(
                    label: 'Cash Sales',
                    value: formatMoney(cashSales),
                    percent: cashPct,
                    color: const Color(0xFF2F6FE4),
                  ),
                  const SizedBox(height: 10),
                  _PaymentLegendTile(
                    label: 'Card Sales',
                    value: formatMoney(cardSales),
                    percent: cardPct,
                    color: const Color(0xFF12B76A),
                  ),
                  if (hasReductions || !paymentDataComplete) ...[
                    const SizedBox(height: 14),
                    if (hasReductions)
                      Column(
                        children: [
                          if (refunds > 0)
                            _PaymentInlineTile(
                              label: 'Refunds',
                              value: formatMoney(refunds),
                              color: const Color(0xFFD92D20),
                              background: const Color(0xFFFEE4E2),
                            ),
                          if (refunds > 0 && discounts > 0) const SizedBox(height: 8),
                          if (discounts > 0)
                            _PaymentInlineTile(
                              label: 'Discounts',
                              value: formatMoney(discounts),
                              color: const Color(0xFFF79009),
                              background: const Color(0xFFFFF4D6),
                            ),
                        ],
                      ),
                    if (!paymentDataComplete && legacyUntypedPaymentSales > 0) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _TagPill(
                          label: 'Legacy cash-assumed ${formatMoney(legacyUntypedPaymentSales)}',
                          color: const Color(0xFF667085),
                          background: const Color(0xFFF2F4F7),
                        ),
                      ),
                    ],
                  ],
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summaryChart,
                    const SizedBox(height: 14),
                    summaryDetails,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 190, child: summaryChart),
                  const SizedBox(width: 16),
                  Expanded(child: summaryDetails),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PaymentLegendTile extends StatelessWidget {
  const _PaymentLegendTile({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
  });

  final String label;
  final String value;
  final double percent;
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FC),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${percent.toStringAsFixed(1)}%',
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

class _PaymentInlineTile extends StatelessWidget {
  const _PaymentInlineTile({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFF0F52BA),
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
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF172433),
                        fontSize: 15,
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
                    'Net Sales',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(totalSales),
                    style: const TextStyle(
                      color: Color(0xFF147A5A),
                      fontWeight: FontWeight.w900,
                      fontSize: 21,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE7ECF3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Sales',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$transactions transactions',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF172433),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: const Color(0xFFE7ECF3),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Avg Sale',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(averageSale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF9C5A00),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
    final sales = ((row['net_sales_after_refunds'] ?? row['net_sales']) as num?)?.toDouble() ?? 0.0;
    final soldQty = ((row['sold_quantity'] ?? row['quantity_sold']) as num?)?.toInt() ?? 0;
    final refundedQty = (row['refunded_quantity'] as num?)?.toInt() ?? 0;
    final profit = ((row['estimated_profit'] ?? row['gross_profit']) as num?)?.toDouble() ?? 0.0;
    final margin = (row['margin_percent'] as num?)?.toDouble() ?? 0.0;
    final productName = (row['product_name'] ?? 'Unknown').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Color(0xFF0F52BA),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
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
                        Text(
                          formatMoney(sales),
                          style: const TextStyle(
                            color: Color(0xFF147A5A),
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Net Sales',
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
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _TopProductInlineStat(
                      label: 'Sold',
                      value: '$soldQty',
                      valueColor: const Color(0xFF172433),
                    ),
                    if (refundedQty > 0)
                      _TopProductInlineStat(
                        label: 'Refunded',
                        value: '$refundedQty',
                        valueColor: const Color(0xFFD92D20),
                      ),
                    _TopProductInlineStat(
                      label: 'Margin',
                      value: '${margin.toStringAsFixed(1)}%',
                      valueColor: const Color(0xFF0F52BA),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Profit ${formatMoney(profit)}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

class _TopProductInlineStat extends StatelessWidget {
  const _TopProductInlineStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFF667085),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2DD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Color(0xFFB54708),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
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
                        Text(
                          formatMoney(stockValue),
                          style: const TextStyle(
                            color: Color(0xFFB54708),
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Stock Value',
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
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _TopProductInlineStat(
                      label: 'Sold',
                      value: '$sold',
                      valueColor: const Color(0xFF172433),
                    ),
                    _TopProductInlineStat(
                      label: 'Stock',
                      value: '$stock',
                      valueColor: const Color(0xFFB54708),
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
          Icon(icon, size: 38, color: const Color(0xFF98A2B3)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
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
