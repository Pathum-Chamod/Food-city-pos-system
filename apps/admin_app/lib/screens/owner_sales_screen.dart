import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class OwnerSalesScreen extends StatelessWidget {
  const OwnerSalesScreen({super.key});

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
    final summary = provider.ownerDashboardSummary;

    final todaySales =
        (summary['today_sales'] as num?)?.toDouble() ?? provider.todayTotalSales;
    final transactions =
        (summary['transaction_count'] as num?)?.toInt() ?? provider.transactionCount;
    final averageSale =
        (summary['average_sale'] as num?)?.toDouble() ?? provider.averageSale;
    final itemsSold = (summary['items_sold'] as num?)?.toInt() ?? 0;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: provider.refreshOwnerDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _HeaderCard(
              title: 'Sales',
              subtitle:
                  'Phase 1 owner view is live now. Advanced date filters and deeper reports can be connected next.',
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.42,
              children: [
                _MetricCard(
                  label: 'Today Sales',
                  value: _formatCompactMoney(todaySales),
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
                  label: 'Items Sold',
                  value: '$itemsSold',
                  icon: Icons.shopping_bag_outlined,
                  color: const Color(0xFF7A1CAC),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cashier Summary',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'This is the first owner-facing summary layer. Full date-range sales reporting can be connected next.',
                      style: TextStyle(
                        color: Color(0xFF6B7482),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (provider.cashierBreakdown.isEmpty)
                      const _EmptyState()
                    else
                      ...provider.cashierBreakdown.map(
                        (cashier) => _CashierTile(
                          name: (cashier['cashier_name'] ?? 'Unknown').toString(),
                          transactions:
                              int.tryParse('${cashier['transaction_count'] ?? 0}') ?? 0,
                          totalSales:
                              double.tryParse('${cashier['total_sales'] ?? 0}') ?? 0.0,
                          formatMoney: _formatMoney,
                        ),
                      ),
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bar_chart, color: Colors.white, size: 30),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontWeight: FontWeight.w500,
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

class _CashierTile extends StatelessWidget {
  const _CashierTile({
    required this.name,
    required this.transactions,
    required this.totalSales,
    required this.formatMoney,
  });

  final String name;
  final int transactions;
  final double totalSales;
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
            child: Icon(
              Icons.person_outline,
              color: Color(0xFF0F3D91),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF172433),
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
                  color: Color(0xFF147A5A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$transactions transactions',
                style: const TextStyle(
                  color: Color(0xFF667085),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Text(
          'No sales have synced yet.',
          style: TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
