
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/admin_provider.dart';
import 'inventory_history_screen.dart';

class OwnerAlertsScreen extends StatelessWidget {
  const OwnerAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final alerts = provider.ownerAlerts;
    final urgentAlerts = alerts
        .where((alert) => (alert['severity'] ?? '').toString() == 'critical')
        .toList();
    final attentionAlerts = alerts
        .where((alert) => (alert['severity'] ?? '').toString() != 'critical')
        .toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: provider.refreshOwnerDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _HeaderCard(
              title: 'Alerts',
              subtitle: 'Attention-needed items for the owner.',
              urgentCount: urgentAlerts.length,
              attentionCount: attentionAlerts.length,
            ),
            const SizedBox(height: 16),
            if (alerts.isEmpty)
              const _EmptyAlertsState()
            else ...[
              if (urgentAlerts.isNotEmpty) ...[
                const _SectionTitle('Urgent'),
                const SizedBox(height: 10),
                ...urgentAlerts.map(
                  (alert) => _AlertCard(
                    alert: alert,
                    onTap: () => _openAlertTarget(context, provider, alert),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (attentionAlerts.isNotEmpty) ...[
                const _SectionTitle('Needs attention'),
                const SizedBox(height: 10),
                ...attentionAlerts.map(
                  (alert) => _AlertCard(
                    alert: alert,
                    onTap: () => _openAlertTarget(context, provider, alert),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _openAlertTarget(
    BuildContext context,
    AdminProvider provider,
    Map<String, dynamic> alert,
  ) {
    final barcode = (alert['barcode'] ?? '').toString();
    if (barcode.isEmpty) return;

    Product? product;
    for (final item in provider.products) {
      if (item.barcode == barcode) {
        product = item;
        break;
      }
    }

    if (product == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryHistoryScreen(product: product!),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.urgentCount,
    required this.attentionCount,
  });

  final String title;
  final String subtitle;
  final int urgentCount;
  final int attentionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB42318), Color(0xFFF04438)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notification_important_outlined,
            color: Colors.white,
            size: 32,
          ),
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
              color: Colors.white.withOpacity(0.86),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TopPill(label: 'Urgent', value: '$urgentCount'),
              const SizedBox(width: 8),
              _TopPill(label: 'Attention', value: '$attentionCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: Color(0xFF172433),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.onTap,
  });

  final Map<String, dynamic> alert;
  final VoidCallback onTap;

  Color get _accent {
    switch ((alert['severity'] ?? '').toString()) {
      case 'critical':
        return const Color(0xFFD92D20);
      case 'warning':
        return const Color(0xFFF79009);
      default:
        return const Color(0xFF2F6FE4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (alert['title'] ?? '').toString();
    final subtitle = (alert['subtitle'] ?? '').toString();
    final hasTarget = (alert['barcode'] ?? '').toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: hasTarget ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _accent.withOpacity(0.20)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _accent.withOpacity(0.12),
                    child: Icon(
                      hasTarget ? Icons.inventory_2_outlined : Icons.insights_outlined,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF172433),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasTarget)
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF98A2B3),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAlertsState extends StatelessWidget {
  const _EmptyAlertsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 42,
            color: Color(0xFF12B76A),
          ),
          SizedBox(height: 12),
          Text(
            'No active alerts right now',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Low stock, out-of-stock, and weak-sales warnings will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
