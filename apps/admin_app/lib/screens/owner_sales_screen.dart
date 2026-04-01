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
    final trend = provider.ownerSalesTrendReport;
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
                    ? const _EmptyBlock(
                        icon: Icons.bar_chart_rounded,
                        title: 'No sales in this period',
                        subtitle: 'Choose another range or wait for POS sales to sync.',
                      )
                    : _OwnerTrendChart(
                        points: trend,
                        formatMoney: _formatMoney,
                        formatCompactMoney: _formatCompactMoney,
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
                            .map(
                              (product) => _TopProductTile(
                                row: product,
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
                            .map(
                              (item) => _SlowMoverTile(
                                row: item,
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
  });

  final List<Map<String, dynamic>> points;
  final String Function(num value) formatMoney;
  final String Function(num value) formatCompactMoney;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<double>(
      0,
      (max, point) => math.max(max, (point['net_after_refunds'] as num?)?.toDouble() ?? (point['net_sales'] as num?)?.toDouble() ?? 0.0),
    );
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final ticks = <double>[safeMax, safeMax * 0.66, safeMax * 0.33, 0];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: SizedBox(
        height: 190,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 50,
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
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            4,
                            (_) => Container(
                              height: 1,
                              color: const Color(0xFFDDE5F0),
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final point in points) ...[
                              Expanded(
                                child: Tooltip(
                                  message:
                                      '${(point['label'] ?? '').toString()}\n${formatMoney((point['net_after_refunds'] as num?)?.toDouble() ?? (point['net_sales'] as num?)?.toDouble() ?? 0.0)}',
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: ((((point['net_after_refunds'] as num?)?.toDouble() ?? (point['net_sales'] as num?)?.toDouble() ?? 0.0)) / safeMax)
                                          .clamp(0.0, 1.0),
                                      widthFactor: 0.58,
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2F6FE4),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (point != points.last) const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        for (final point in points) ...[
                          Expanded(
                            child: Text(
                              (point['label'] ?? '').toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7482),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (point != points.last) const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: CustomPaint(
                painter: _DonutPainter(
                  values: [cashSales, cardSales],
                  colors: const [Color(0xFF2F6FE4), Color(0xFF12B76A)],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Payments',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7482),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatMoney(paymentTotal),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                children: [
                  _MetricRow(label: 'Cash Sales', value: formatMoney(cashSales), percent: cashPct, color: const Color(0xFF2F6FE4)),
                  const SizedBox(height: 10),
                  _MetricRow(label: 'Card Sales', value: formatMoney(cardSales), percent: cardPct, color: const Color(0xFF12B76A)),
                  const SizedBox(height: 10),
                  _MetricRow(label: 'Refunds', value: formatMoney(refunds), percent: refundPct, color: const Color(0xFFD92D20)),
                  const SizedBox(height: 10),
                  _MetricRow(label: 'Discounts', value: formatMoney(discounts), percent: discountPct, color: const Color(0xFFF79009)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label • $value',
                style: const TextStyle(
                  color: Color(0xFF475467),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${percent.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 9,
            backgroundColor: const Color(0xFFE6ECF3),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE7F0FF),
            child: Icon(Icons.person_outline, color: Color(0xFF0F3D91)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172433),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _TagPill(
                      label: '$transactions sales',
                      color: const Color(0xFF667085),
                      background: const Color(0xFFF2F4F7),
                    ),
                    if (refundCount > 0)
                      _TagPill(
                        label: '$refundCount refunds',
                        color: const Color(0xFFD92D20),
                        background: const Color(0xFFFEE4E2),
                      ),
                    _TagPill(
                      label: 'Avg ${formatMoney(averageSale)}',
                      color: const Color(0xFF9C5A00),
                      background: const Color(0xFFFFF4D6),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(totalSales),
            style: const TextStyle(
              color: Color(0xFF147A5A),
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
    required this.row,
    required this.formatMoney,
  });

  final Map<String, dynamic> row;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final sales = ((row['net_sales_after_refunds'] ?? row['net_sales']) as num?)?.toDouble() ?? 0.0;
    final soldQty = ((row['sold_quantity'] ?? row['quantity_sold']) as num?)?.toInt() ?? 0;
    final refundedQty = (row['refunded_quantity'] as num?)?.toInt() ?? 0;
    final qty = ((row['net_quantity_sold'] ?? row['quantity_sold']) as num?)?.toInt() ?? 0;
    final profit = ((row['estimated_profit'] ?? row['gross_profit']) as num?)?.toDouble() ?? 0.0;
    final margin = (row['margin_percent'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE7F0FF),
            child: Icon(Icons.star_outline, color: Color(0xFF0F3D91)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row['product_name'] ?? 'Unknown').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF172433)),
                ),
                const SizedBox(height: 4),
                Text(
                  refundedQty > 0
                      ? 'Sold $soldQty • Refunded $refundedQty • Margin ${margin.toStringAsFixed(1)}%'
                      : 'Sold $qty • Margin ${margin.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(sales),
                style: const TextStyle(color: Color(0xFF147A5A), fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Profit ${formatMoney(profit)}',
                style: const TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w600),
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
    required this.row,
    required this.formatMoney,
  });

  final Map<String, dynamic> row;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final sold = (row['quantity_sold'] as num?)?.toInt() ?? 0;
    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    final stockValue = (row['stock_value'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFF4D6),
            child: Icon(Icons.inventory_outlined, color: Color(0xFFF79009)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (row['product_name'] ?? 'Unknown').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF172433)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sold $sold • Stock $stock',
                  style: const TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(stockValue),
            style: const TextStyle(color: Color(0xFF9C5A00), fontWeight: FontWeight.w800),
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
    final strokeWidth = math.min(size.width, size.height) * 0.22;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFE7ECF3);

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
        ..strokeCap = StrokeCap.butt
        ..color = colors[i % colors.length];

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
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
