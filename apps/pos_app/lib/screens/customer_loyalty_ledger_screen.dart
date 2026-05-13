import 'package:flutter/material.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/loyalty_ledger_entry.dart';
import 'package:shared/models/loyalty_settings.dart';

import '../services/loyalty_service.dart';
import '../widgets/app_snackbar.dart';

class CustomerLoyaltyLedgerScreen extends StatefulWidget {
  const CustomerLoyaltyLedgerScreen({super.key, required this.customer});

  final Customer customer;

  @override
  State<CustomerLoyaltyLedgerScreen> createState() =>
      _CustomerLoyaltyLedgerScreenState();
}

class _CustomerLoyaltyLedgerScreenState
    extends State<CustomerLoyaltyLedgerScreen> {
  LoyaltySettings? _settings;
  List<LoyaltyLedgerEntry> _entries = [];
  bool _isLoading = true;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _success = Color(0xFF1FCF9A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settings = await LoyaltyService.instance.getSettings();
      final entries = await LoyaltyService.instance.getLedgerEntries(
        customerId: widget.customer.id ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load loyalty ledger.',
        backgroundColor: _danger,
      );
    }
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  Color _entryColor(LoyaltyLedgerEntry entry) {
    if (entry.isVoided) return _textSecondary;
    if (entry.pointsDelta > 0) return _success;
    if (entry.entryType == LoyaltyEntryType.redeem) return _warning;
    return _danger;
  }

  IconData _entryIcon(LoyaltyLedgerEntry entry) {
    switch (entry.entryType) {
      case LoyaltyEntryType.earn:
        return Icons.add_circle_rounded;
      case LoyaltyEntryType.redeem:
        return Icons.redeem_rounded;
      case LoyaltyEntryType.refundEarnReversal:
        return Icons.undo_rounded;
      case LoyaltyEntryType.refundRedeemRestore:
        return Icons.restore_rounded;
      case LoyaltyEntryType.manualAdjustment:
        return Icons.tune_rounded;
      case LoyaltyEntryType.voidReversal:
        return Icons.block_rounded;
    }
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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

  Widget _entryRow(LoyaltyLedgerEntry entry) {
    final color = _entryColor(entry);
    final pointsText = entry.pointsDelta > 0
        ? '+${entry.pointsDelta}'
        : entry.pointsDelta.toString();
    final refs = <String>[
      if ((entry.saleId ?? 0) > 0) 'Sale #${entry.saleId}',
      if ((entry.refundSaleId ?? 0) > 0) 'Refund #${entry.refundSaleId}',
      if ((entry.createdBy ?? '').trim().isNotEmpty) entry.createdBy!.trim(),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(_entryIcon(entry), color: color),
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
                        entry.entryType.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (entry.isVoided)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _textSecondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _textSecondary.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          'Voided',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(entry.createdAt),
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if ((entry.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.description!.trim(),
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (refs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    refs.join(' - '),
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pointsText,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Balance ${entry.pointsBalanceAfter}',
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (entry.moneyValue > 0) ...[
                const SizedBox(height: 4),
                Text(
                  _money(entry.moneyValue),
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings ?? LoyaltySettings.defaults();
    final customer = widget.customer;
    final balanceValue =
        customer.loyaltyPointsBalance * settings.safePointValueAmount;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Loyalty Ledger'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadLedger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: _brand.withValues(
                              alpha: _isDark ? 0.18 : 0.12,
                            ),
                            child: Text(
                              customer.displayName.trim().isEmpty
                                  ? 'C'
                                  : customer.displayName
                                        .trim()[0]
                                        .toUpperCase(),
                              style: const TextStyle(
                                color: _brand,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.displayName,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${customer.displayCode} - ${customer.displayPhone}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (settings.isEnabled && customer.loyaltyEnabled
                                          ? _brand
                                          : _textSecondary)
                                      .withValues(alpha: _isDark ? 0.16 : 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              settings.isEnabled && customer.loyaltyEnabled
                                  ? 'Enabled'
                                  : 'Disabled',
                              style: TextStyle(
                                color:
                                    settings.isEnabled &&
                                        customer.loyaltyEnabled
                                    ? _brand
                                    : _textSecondary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _summaryCard(
                          label: 'Points Balance',
                          value: customer.loyaltyPointsBalance.toString(),
                          icon: Icons.stars_rounded,
                          color: _brand,
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          label: 'Redeem Value',
                          value: _money(balanceValue),
                          icon: Icons.payments_rounded,
                          color: _blue,
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          label: 'Lifetime Earned',
                          value: customer.loyaltyLifetimeEarned.toString(),
                          icon: Icons.trending_up_rounded,
                          color: _success,
                        ),
                        const SizedBox(width: 12),
                        _summaryCard(
                          label: 'Lifetime Redeemed',
                          value: customer.loyaltyLifetimeRedeemed.toString(),
                          icon: Icons.redeem_rounded,
                          color: _warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Ledger Entries',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_entries.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _border),
                        ),
                        child: Text(
                          'No loyalty activity yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _entryRow(_entries[index]),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
