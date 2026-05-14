import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_monitor_models.dart';
import '../providers/admin_provider.dart';
import '../services/customer_monitor_service.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({
    super.key,
    required this.customerId,
    required this.initialCustomer,
  });

  final int customerId;
  final CustomerMonitorRow initialCustomer;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  CustomerMonitorProfile? _profile;
  bool _isLoading = true;
  String? _error;

  static const _brand = Color(0xFF0F3D91);
  static const _success = Color(0xFF147A5A);
  static const _warning = Color(0xFFB76E00);
  static const _danger = Color(0xFFB42318);
  static const _purple = Color(0xFF7A1CAC);
  static const _text = Color(0xFF172433);
  static const _muted = Color(0xFF667085);
  static const _border = Color(0xFFE6EBF3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  CustomerMonitorService _service() {
    return CustomerMonitorService(apiUrl: context.read<AdminProvider>().apiUrl);
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await _service().getCustomerProfile(widget.customerId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _money(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

  String _compactMoney(num value) {
    if (value.abs() >= 1000000) {
      return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value.abs() >= 1000) {
      return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    }
    return 'Rs. ${value.toStringAsFixed(0)}';
  }

  String _string(
    Map<String, dynamic> map,
    String key, {
    String fallback = '-',
  }) {
    final text = (map[key] ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _int(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  double _double(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  String _dateText(Object? value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    final y = parsed.year.toString().padLeft(4, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    final h = parsed.hour.toString().padLeft(2, '0');
    final min = parsed.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Color _healthColor(CustomerMonitorRow customer) {
    if (customer.isBlocked || customer.isOverLimit) return _danger;
    if (customer.hasCreditBalance || customer.isWatchlist) return _warning;
    if (customer.loyaltyPoints > 0) return _purple;
    return _success;
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final customer = profile?.customer ?? widget.initialCustomer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadProfile,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: _isLoading && profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (_error != null)
                    _emptyBlock(
                      Icons.cloud_off_rounded,
                      'Could not load profile',
                      _error!,
                    )
                  else ...[
                    _header(customer),
                    const SizedBox(height: 14),
                    _snapshotGrid(profile, customer),
                    const SizedBox(height: 14),
                    _creditSection(profile),
                    const SizedBox(height: 14),
                    _loyaltySection(profile),
                    const SizedBox(height: 14),
                    _pricingSection(profile, customer),
                    const SizedBox(height: 14),
                    _transactionsSection(profile),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _header(CustomerMonitorRow customer) {
    final color = _healthColor(customer);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.74)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.16),
            child: Text(
              customer.displayName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${customer.customerCode} - ${customer.phone.isEmpty ? 'No phone' : customer.phone}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _lightChip(customer.healthLabel),
                    if (customer.category.isNotEmpty)
                      _lightChip(customer.category),
                    if (customer.pricingScheme.isNotEmpty)
                      _lightChip(customer.pricingScheme),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _snapshotGrid(
    CustomerMonitorProfile? profile,
    CustomerMonitorRow customer,
  ) {
    final purchaseSummary =
        profile?.purchaseSummary ?? const <String, dynamic>{};
    final creditSummary = profile?.creditSummary ?? const <String, dynamic>{};
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.42,
      children: [
        _metricCard(
          'Credit Balance',
          _compactMoney(customer.creditBalance),
          Icons.account_balance_wallet_outlined,
          customer.creditBalance > 0 ? _warning : _success,
        ),
        _metricCard(
          'Loyalty Points',
          '${customer.loyaltyPoints}',
          Icons.stars_outlined,
          _purple,
        ),
        _metricCard(
          'Total Purchases',
          _compactMoney(_double(purchaseSummary, 'net_total_spent')),
          Icons.shopping_bag_outlined,
          _brand,
        ),
        _metricCard(
          'Last Payment',
          _dateText(creditSummary['last_payment_at']),
          Icons.payments_outlined,
          _success,
        ),
      ],
    );
  }

  Widget _creditSection(CustomerMonitorProfile? profile) {
    final credit = profile?.creditSummary ?? const <String, dynamic>{};
    final rows = profile?.recentCreditLedger ?? const <Map<String, dynamic>>[];
    return _sectionCard(
      title: 'Credit',
      subtitle:
          '${_string(credit, 'credit_status', fallback: 'normal').toUpperCase()} - Available ${_money(_double(credit, 'available_credit'))}',
      icon: Icons.account_balance_wallet_outlined,
      color: _warning,
      children: [
        _detailRow('Balance', _money(_double(credit, 'credit_balance'))),
        _detailRow('Limit', _money(_double(credit, 'credit_limit'))),
        _detailRow('Last Payment', _dateText(credit['last_payment_at'])),
        const SizedBox(height: 10),
        _subTitle('Recent Credit Ledger'),
        if (rows.isEmpty)
          _mutedText('No credit ledger rows yet.')
        else
          ...rows.map(
            (row) => _movementRow(
              title: _string(row, 'entry_type'),
              subtitle: _dateText(row['created_at']),
              amount: _double(row, 'debit') > 0
                  ? '+${_money(_double(row, 'debit'))}'
                  : '-${_money(_double(row, 'credit'))}',
              color: _double(row, 'debit') > 0 ? _warning : _success,
            ),
          ),
      ],
    );
  }

  Widget _loyaltySection(CustomerMonitorProfile? profile) {
    final loyalty = profile?.loyaltySummary ?? const <String, dynamic>{};
    final rows = profile?.recentLoyaltyLedger ?? const <Map<String, dynamic>>[];
    return _sectionCard(
      title: 'Loyalty',
      subtitle:
          '${_int(loyalty, 'points_balance')} points - ${_money(_double(loyalty, 'redeem_value'))}',
      icon: Icons.stars_outlined,
      color: _purple,
      children: [
        _detailRow(
          'Lifetime Earned',
          '${_int(loyalty, 'lifetime_earned')} pts',
        ),
        _detailRow(
          'Lifetime Redeemed',
          '${_int(loyalty, 'lifetime_redeemed')} pts',
        ),
        const SizedBox(height: 10),
        _subTitle('Recent Loyalty Ledger'),
        if (rows.isEmpty)
          _mutedText('No loyalty ledger rows yet.')
        else
          ...rows.map((row) {
            final points = _int(row, 'points_delta');
            return _movementRow(
              title: _string(row, 'entry_type'),
              subtitle: _dateText(row['created_at']),
              amount: points > 0 ? '+$points pts' : '$points pts',
              color: points >= 0 ? _success : _danger,
            );
          }),
      ],
    );
  }

  Widget _pricingSection(
    CustomerMonitorProfile? profile,
    CustomerMonitorRow customer,
  ) {
    final pricing = profile?.pricingSummary ?? const <String, dynamic>{};
    return _sectionCard(
      title: 'Pricing',
      subtitle: _string(
        pricing,
        'pricing_scheme',
        fallback: 'No pricing scheme',
      ),
      icon: Icons.sell_outlined,
      color: _brand,
      children: [
        _detailRow(
          'Category',
          _string(pricing, 'category', fallback: customer.category),
        ),
        _detailRow(
          'Direct Scheme',
          _string(pricing, 'direct_pricing_scheme', fallback: 'None'),
        ),
        _detailRow(
          'Category Scheme',
          _string(pricing, 'category_pricing_scheme', fallback: 'None'),
        ),
        _detailRow(
          'Product Overrides',
          '${_int(pricing, 'product_override_count')}',
        ),
        _detailRow(
          'Simple Fallback',
          '${_string(pricing, 'default_price_type', fallback: 'selling')} / ${_double(pricing, 'default_discount_percent').toStringAsFixed(2)}%',
        ),
      ],
    );
  }

  Widget _transactionsSection(CustomerMonitorProfile? profile) {
    final purchase = profile?.purchaseSummary ?? const <String, dynamic>{};
    final rows = profile?.recentTransactions ?? const <Map<String, dynamic>>[];
    return _sectionCard(
      title: 'Purchases',
      subtitle:
          '${_int(purchase, 'sale_count')} sales - Avg ${_money(_double(purchase, 'average_sale'))}',
      icon: Icons.receipt_long_outlined,
      color: _success,
      children: [
        _detailRow('Net Total', _money(_double(purchase, 'net_total_spent'))),
        _detailRow('Refunds', '${_int(purchase, 'refund_count')}'),
        _detailRow('Last Purchase', _dateText(purchase['last_purchase_at'])),
        const SizedBox(height: 10),
        _subTitle('Recent Transactions'),
        if (rows.isEmpty)
          _mutedText('No transactions yet.')
        else
          ...rows.map(
            (row) => _movementRow(
              title: '#${row['id'] ?? '-'} ${_string(row, 'payment_method')}',
              subtitle: _dateText(row['created_at']),
              amount: _money(_double(row, 'total_amount')),
              color: _string(row, 'transaction_type') == 'refund'
                  ? _danger
                  : _success,
            ),
          ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _movementRow({
    required String title,
    required String subtitle,
    required String amount,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _lightChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _subTitle(String text) {
    return Text(
      text,
      style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
    );
  }

  Widget _mutedText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _emptyBlock(IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(icon, color: _muted, size: 34),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
