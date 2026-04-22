import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/admin_provider.dart';
import '../widgets/app_snackbar.dart';
import 'inventory_history_screen.dart';

class OwnerAlertsScreen extends StatefulWidget {
  const OwnerAlertsScreen({super.key});

  @override
  State<OwnerAlertsScreen> createState() => _OwnerAlertsScreenState();
}

enum _AlertFilter { all, urgent, stock, sales }

class _OwnerAlertsScreenState extends State<OwnerAlertsScreen> {
  _AlertFilter _selectedFilter = _AlertFilter.all;

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
    final stockAlerts = alerts.where(_isStockAlert).toList();
    final salesAlerts = alerts.where(_isSalesAlert).toList();

    final filteredAlerts = _applyFilter(alerts);
    final filteredUrgent = filteredAlerts
        .where((alert) => (alert['severity'] ?? '').toString() == 'critical')
        .toList();
    final filteredAttention = filteredAlerts
        .where((alert) => (alert['severity'] ?? '').toString() != 'critical')
        .toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: provider.refreshOwnerDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _HeaderCard(),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.50,
              children: [
                _SummaryCard(
                  label: 'Urgent',
                  value: '${urgentAlerts.length}',
                  icon: Icons.priority_high_rounded,
                  color: const Color(0xFFD92D20),
                ),
                _SummaryCard(
                  label: 'Attention',
                  value: '${attentionAlerts.length}',
                  icon: Icons.notification_important_outlined,
                  color: const Color(0xFFF79009),
                ),
                _SummaryCard(
                  label: 'Stock Alerts',
                  value: '${stockAlerts.length}',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF2F6FE4),
                ),
                _SummaryCard(
                  label: 'Sales Alerts',
                  value: '${salesAlerts.length}',
                  icon: Icons.trending_down_rounded,
                  color: const Color(0xFF7A1CAC),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _FilterBar(
              value: _selectedFilter,
              onChanged: (value) {
                setState(() {
                  _selectedFilter = value;
                });
              },
            ),
            const SizedBox(height: 16),
            if (filteredAlerts.isEmpty)
              const _EmptyAlertsState()
            else ...[
              if (filteredUrgent.isNotEmpty) ...[
                const _SectionTitle('Urgent'),
                const SizedBox(height: 10),
                ...filteredUrgent.map(
                  (alert) => _AlertCard(
                    alert: alert,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (filteredAttention.isNotEmpty) ...[
                const _SectionTitle('Needs attention'),
                const SizedBox(height: 10),
                ...filteredAttention.map(
                  (alert) => _AlertCard(
                    alert: alert,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> alerts) {
    switch (_selectedFilter) {
      case _AlertFilter.urgent:
        return alerts
            .where((alert) => (alert['severity'] ?? '').toString() == 'critical')
            .toList();
      case _AlertFilter.stock:
        return alerts.where(_isStockAlert).toList();
      case _AlertFilter.sales:
        return alerts.where(_isSalesAlert).toList();
      case _AlertFilter.all:
        return alerts;
    }
  }

  bool _isStockAlert(Map<String, dynamic> alert) {
    final type = (alert['type'] ?? '').toString();
    return type == 'out_of_stock' ||
        type == 'low_stock' ||
        type == 'best_seller_low_stock';
  }

  bool _isSalesAlert(Map<String, dynamic> alert) {
    final type = (alert['type'] ?? '').toString();
    return type == 'weak_sales';
  }

  Product? _findProduct(AdminProvider provider, String barcode) {
    for (final item in provider.products) {
      if (item.barcode == barcode) {
        return item;
      }
    }
    return null;
  }

  void _openAlertTarget(
    BuildContext context,
    AdminProvider provider,
    Map<String, dynamic> alert,
  ) {
    final barcode = (alert['barcode'] ?? '').toString();
    if (barcode.isEmpty) return;

    final product = _findProduct(provider, barcode);
    if (product == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryHistoryScreen(product: product),
      ),
    );
  }

  Future<void> _showMinStockDialog(
    BuildContext context,
    AdminProvider provider,
    Map<String, dynamic> alert,
  ) async {
    final barcode = (alert['barcode'] ?? '').toString();
    if (barcode.isEmpty) return;

    final product = _findProduct(provider, barcode);
    if (product == null) return;

    final controller = TextEditingController(
      text: '${product.minStockLevel > 0 ? product.minStockLevel : 10}',
    );
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Update Min Stock'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Current stock: ${product.stock}',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    enabled: !isSaving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minimum stock level',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final value = int.tryParse(controller.text.trim());
                          if (value == null || value < 0) {
                            AppSnackBar.show(
                              context,
                              message: 'Enter a valid minimum stock level.',
                              backgroundColor: Colors.red,
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          final success = await provider.updateMinStockLevel(
                            product.barcode,
                            value,
                          );

                          if (!mounted) return;

                          if (success) {
                            Navigator.pop(dialogContext);
                            AppSnackBar.show(
                              context,
                              message: 'Minimum stock updated.',
                              backgroundColor: Colors.green,
                            );
                          } else {
                            setDialogState(() {
                              isSaving = false;
                            });
                            AppSnackBar.show(
                              context,
                              message: 'Failed to update minimum stock.',
                              backgroundColor: Colors.red,
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
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
          colors: [Color(0xFFB42318), Color(0xFFF04438)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(
              Icons.notification_important_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Owner Alerts',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Attention-needed items for the owner.',
                  style: TextStyle(
                    color: Color(0xFFEFEFF4),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7482),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
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
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF182431),
                      height: 1.0,
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.onChanged,
  });

  final _AlertFilter value;
  final ValueChanged<_AlertFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: value == _AlertFilter.all,
            onTap: () => onChanged(_AlertFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Urgent',
            selected: value == _AlertFilter.urgent,
            onTap: () => onChanged(_AlertFilter.urgent),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Stock',
            selected: value == _AlertFilter.stock,
            onTap: () => onChanged(_AlertFilter.stock),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Sales',
            selected: value == _AlertFilter.sales,
            onTap: () => onChanged(_AlertFilter.sales),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF182B6B) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? const Color(0xFF182B6B) : const Color(0xFFD6DEEB),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF667085),
              fontWeight: FontWeight.w700,
            ),
          ),
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
  });

  final Map<String, dynamic> alert;

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

  String get _severityLabel {
    switch ((alert['severity'] ?? '').toString()) {
      case 'critical':
        return 'Urgent';
      case 'warning':
        return 'Attention';
      default:
        return 'Info';
    }
  }

  IconData get _icon {
    switch ((alert['type'] ?? '').toString()) {
      case 'out_of_stock':
        return Icons.remove_shopping_cart_outlined;
      case 'low_stock':
        return Icons.inventory_2_outlined;
      case 'best_seller_low_stock':
        return Icons.local_fire_department_outlined;
      case 'weak_sales':
        return Icons.trending_down_rounded;
      default:
        return Icons.notification_important_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (alert['title'] ?? '').toString();
    final subtitle = (alert['subtitle'] ?? '').toString();
    final supplierName = (alert['supplier_name'] ?? '').toString().trim();
    final supplierPhone = (alert['supplier_phone'] ?? '').toString().trim();
    final hasSupplierDetails = supplierName.isNotEmpty || supplierPhone.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _accent.withOpacity(0.20)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _accent.withOpacity(0.12),
                      child: Icon(_icon, color: _accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF172433),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _severityLabel,
                                  style: TextStyle(
                                    color: _accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (hasSupplierDetails) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _showSupplierInfoSheet(
                                  context,
                                  supplierName: supplierName,
                                  supplierPhone: supplierPhone,
                                ),
                                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                                label: const Text('View Supplier Info'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _accent,
                                  side: BorderSide(color: _accent.withOpacity(0.25)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _callSupplier(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      AppSnackBar.show(
        context,
        message: 'Unable to open the phone dialer.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _showSupplierInfoSheet(
    BuildContext context, {
    required String supplierName,
    required String supplierPhone,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECF3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _accent.withOpacity(0.12),
                    child: Icon(Icons.local_shipping_outlined, color: _accent),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supplier Info',
                          style: TextStyle(
                            color: Color(0xFF172433),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Relevant supplier for this alert item.',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE7ECF3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Supplier Name',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      supplierName.isEmpty ? 'Not available' : supplierName,
                      style: const TextStyle(
                        color: Color(0xFF172433),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Phone Number',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (supplierPhone.isNotEmpty)
                      InkWell(
                        onTap: () => _callSupplier(context, supplierPhone),
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.call_rounded, color: _accent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  supplierPhone,
                                  style: TextStyle(
                                    color: _accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                'Call',
                                style: TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Text(
                        'Not available',
                        style: TextStyle(
                          color: Color(0xFF172433),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
