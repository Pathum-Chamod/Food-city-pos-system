import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({super.key});

  String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _formatCompactMoney(num value) {
    if (value.abs() >= 1000000) {
      return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value.abs() >= 1000) {
      return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    }
    return 'Rs. ${value.toStringAsFixed(0)}';
  }

  String _formatToday(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final summary = provider.ownerDashboardSummary;
    final trend = provider.ownerSalesTrend;
    final topAlerts = provider.topAlertsPreview;
    final topProducts = provider.ownerTopProducts.take(3).toList();

    final todaySales =
        (summary['today_sales'] as num?)?.toDouble() ?? provider.todayTotalSales;
    final transactions =
        (summary['transaction_count'] as num?)?.toInt() ?? provider.transactionCount;
    final averageSale =
        (summary['average_sale'] as num?)?.toDouble() ?? provider.averageSale;
    final itemsSold = (summary['items_sold'] as num?)?.toInt() ?? 0;

    final isEmpty = provider.isOwnerShellLoading &&
        summary.isEmpty &&
        provider.products.isEmpty;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: provider.refreshOwnerDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            if (isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _buildHeroCard(
                title: 'Today’s Sales',
                subtitle: 'Live owner snapshot • ${_formatToday(DateTime.now())}',
                value: _formatMoney(todaySales),
                hint:
                    '$transactions transactions • ${itemsSold > 0 ? '$itemsSold items sold' : 'items sold will appear as data grows'}',
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final childAspectRatio = constraints.maxWidth < 380 ? 1.34 : 1.52;
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
                        value: '$transactions',
                        icon: Icons.receipt_long,
                        color: const Color(0xFF0F3D91),
                      ),
                      _MetricCard(
                        label: 'Average Sale',
                        value: _formatCompactMoney(averageSale),
                        icon: Icons.calculate_outlined,
                        color: const Color(0xFF147A5A),
                      ),
                      _MetricCard(
                        label: 'Items Sold',
                        value: '$itemsSold',
                        icon: Icons.shopping_bag_outlined,
                        color: const Color(0xFF9C5A00),
                      ),
                      _MetricCard(
                        label: 'Products',
                        value: '${provider.totalProducts}',
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFF7A1CAC),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Sales Trend',
                subtitle: 'Last 7 days',
                child: trend.isEmpty
                    ? const _EmptyBlock(
                        icon: Icons.bar_chart_rounded,
                        title: 'No trend data yet',
                        subtitle:
                            'As sales sync in, your weekly trend will appear here.',
                      )
                    : _MiniTrendChart(
                        points: trend,
                        formatCompactMoney: _formatCompactMoney,
                        formatMoney: _formatMoney,
                      ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Top 3 Alerts',
                subtitle: 'What needs attention now',
                trailing: _CountBadge(
                  label: '${provider.ownerAlerts.length} alerts',
                ),
                child: topAlerts.isEmpty
                    ? const _EmptyBlock(
                        icon: Icons.check_circle_outline,
                        title: 'No urgent alerts right now',
                        subtitle:
                            'Low-stock and weak-sales warnings will show here.',
                      )
                    : Column(
                        children: topAlerts
                            .map((alert) => _AlertPreviewTile(alert: alert))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Top 3 Products',
                subtitle: 'Today’s best performers',
                child: topProducts.isEmpty
                    ? const _EmptyBlock(
                        icon: Icons.auto_graph_outlined,
                        title: 'No product sales yet',
                        subtitle:
                            'Product leaders will appear after POS sales sync.',
                      )
                    : Column(
                        children: topProducts
                            .map(
                              (product) => _ProductPreviewTile(
                                product: product,
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

  Widget _buildHeader(BuildContext context) {
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
            child: const Icon(
              Icons.storefront_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Owner Dashboard',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quick business view for your store.',
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

  Widget _buildHeroCard({
    required String title,
    required String subtitle,
    required String value,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E7F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: Color(0xFF0F3D91),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F3D91),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF122B45),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF5D6B82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: const TextStyle(
                    color: Color(0xFF7A879B),
                    fontSize: 12,
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color, size: 18),
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF182431),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
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
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F0FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0F3D91),
          fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: const Color(0xFF8491A5)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF263142),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7482),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertPreviewTile extends StatelessWidget {
  const _AlertPreviewTile({required this.alert});

  final Map<String, dynamic> alert;

  Color get _color {
    switch ((alert['severity'] ?? '').toString()) {
      case 'critical':
        return const Color(0xFFD92D20);
      case 'warning':
        return const Color(0xFFF79009);
      default:
        return const Color(0xFF0F3D91);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _color.withOpacity(0.14),
            child: Icon(
              Icons.warning_amber_rounded,
              color: _color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (alert['title'] ?? '').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (alert['subtitle'] ?? '').toString(),
                  style: const TextStyle(
                    color: Color(0xFF6B7482),
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

class _ProductPreviewTile extends StatelessWidget {
  const _ProductPreviewTile({
    required this.product,
    required this.formatMoney,
  });

  final Map<String, dynamic> product;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final productName = (product['product_name'] ?? 'Unknown item').toString();
    final quantity = (product['quantity_sold'] as num?)?.toInt() ?? 0;
    final totalSales = (product['total_sales'] as num?)?.toDouble() ?? 0.0;

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
            child: Icon(
              Icons.shopping_bag_outlined,
              color: Color(0xFF0F3D91),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              productName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(totalSales),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF147A5A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$quantity sold',
                style: const TextStyle(
                  color: Color(0xFF6B7482),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniTrendChart extends StatelessWidget {
  const _MiniTrendChart({
    required this.points,
    required this.formatCompactMoney,
    required this.formatMoney,
  });

  final List<Map<String, dynamic>> points;
  final String Function(num value) formatCompactMoney;
  final String Function(num value) formatMoney;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<double>(
      0,
      (max, point) {
        final value = (point['total_sales'] as num?)?.toDouble() ?? 0.0;
        return math.max(max, value);
      },
    );

    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final tickValues = <double>[
      safeMax,
      safeMax * 0.66,
      safeMax * 0.33,
      0,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E9F3)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFF2F6FE4),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Long-press a bar to see the exact sales amount.',
                    style: TextStyle(
                      color: Color(0xFF263142),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: tickValues
                        .map(
                          (value) => Text(
                            formatCompactMoney(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                          '${(point['label'] ?? '').toString()}\n${formatMoney((point['total_sales'] as num?)?.toDouble() ?? 0.0)}',
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: FractionallySizedBox(
                                          heightFactor: (((point['total_sales']
                                                              as num?)
                                                          ?.toDouble() ??
                                                      0.0) /
                                                  safeMax)
                                              .clamp(0.0, 1.0),
                                          widthFactor: 0.58,
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2F6FE4),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (point != points.last)
                                    const SizedBox(width: 6),
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
                              if (point != points.last)
                                const SizedBox(width: 6),
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
        ],
      ),
    );
  }
}
