import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_monitor_models.dart';
import '../providers/admin_provider.dart';
import '../services/customer_monitor_service.dart';
import 'customer_profile_screen.dart';

class CustomerMonitorScreen extends StatefulWidget {
  const CustomerMonitorScreen({super.key});

  @override
  State<CustomerMonitorScreen> createState() => _CustomerMonitorScreenState();
}

class _CustomerMonitorScreenState extends State<CustomerMonitorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  CustomerDashboard? _dashboard;
  List<CustomerMonitorRow> _customers = const [];
  bool _isLoadingDashboard = true;
  bool _isLoadingCustomers = true;
  String _filter = 'all';
  String? _error;
  Timer? _searchDebounce;

  static const _brand = Color(0xFF0F3D91);
  static const _success = Color(0xFF147A5A);
  static const _warning = Color(0xFFB76E00);
  static const _danger = Color(0xFFB42318);
  static const _purple = Color(0xFF7A1CAC);
  static const _text = Color(0xFF172433);
  static const _muted = Color(0xFF667085);
  static const _border = Color(0xFFE6EBF3);

  final List<_MonitorFilter> _filters = const [
    _MonitorFilter('all', 'All', Icons.people_alt_outlined),
    _MonitorFilter(
      'credit_balance',
      'Credit',
      Icons.account_balance_wallet_outlined,
    ),
    _MonitorFilter('over_limit', 'Over Limit', Icons.warning_amber_rounded),
    _MonitorFilter('blocked', 'Blocked', Icons.block_rounded),
    _MonitorFilter('watchlist', 'Watchlist', Icons.visibility_outlined),
    _MonitorFilter('loyalty_members', 'Loyalty', Icons.stars_outlined),
    _MonitorFilter('recently_active', 'Recent', Icons.history_rounded),
    _MonitorFilter('inactive', 'Inactive', Icons.person_off_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  CustomerMonitorService _service() {
    return CustomerMonitorService(apiUrl: context.read<AdminProvider>().apiUrl);
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadDashboard(), _loadCustomers()]);
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoadingDashboard = true;
      _error = null;
    });
    try {
      final dashboard = await _service().getDashboard();
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _isLoadingDashboard = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingDashboard = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoadingCustomers = true;
      _error = null;
    });
    try {
      final customers = await _service().getCustomers(
        query: _searchController.text.trim(),
        filter: _filter,
        limit: 150,
      );
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _isLoadingCustomers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _customers = const [];
        _isLoadingCustomers = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _refresh() async {
    await _loadAll();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadCustomers);
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _loadCustomers();
  }

  String _money(num value) {
    if (value.abs() >= 1000000) {
      return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value.abs() >= 1000) {
      return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    }
    return 'Rs. ${value.toStringAsFixed(0)}';
  }

  String _dateText(String? value) {
    if (value == null || value.trim().isEmpty) return 'No purchases';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final now = DateTime.now();
    final difference = now.difference(parsed);
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 30) return '${difference.inDays} days ago';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  Color _healthColor(CustomerMonitorRow customer) {
    if (customer.isBlocked || customer.isOverLimit) return _danger;
    if (customer.hasCreditBalance || customer.isWatchlist) return _warning;
    if (customer.loyaltyPoints > 0) return _purple;
    return _success;
  }

  Future<void> _openProfile(CustomerMonitorRow customer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerProfileScreen(
          customerId: customer.id,
          initialCustomer: customer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Monitor'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Customers'),
            Tab(text: 'Credit'),
            Tab(text: 'Loyalty'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: TabBarView(
          controller: _tabController,
          children: [
            _overviewTab(dashboard),
            _customersTab(),
            _focusTab(
              title: 'Credit Monitoring',
              subtitle: 'Outstanding and risk customers.',
              rows: dashboard?.topOutstanding ?? const [],
              emptyTitle: 'No outstanding credit',
              icon: Icons.account_balance_wallet_outlined,
            ),
            _focusTab(
              title: 'Loyalty Liability',
              subtitle: 'Customers with highest points balances.',
              rows: dashboard?.highLoyalty ?? const [],
              emptyTitle: 'No loyalty points yet',
              icon: Icons.stars_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab(CustomerDashboard? dashboard) {
    if (_isLoadingDashboard && dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && dashboard == null) {
      return _offlineBlock();
    }

    final summary = dashboard?.summary ?? CustomerMonitorSummary.fromJson(null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _heroCard(summary),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.34,
          children: [
            _metricCard(
              'Customers',
              '${summary.totalCustomers}',
              Icons.people_alt_outlined,
              _brand,
            ),
            _metricCard(
              'Active',
              '${summary.activeCustomers}',
              Icons.trending_up_rounded,
              _success,
            ),
            _metricCard(
              'Outstanding',
              _money(summary.totalOutstanding),
              Icons.account_balance_wallet_outlined,
              _warning,
            ),
            _metricCard(
              'Over Limit',
              '${summary.overLimitCount}',
              Icons.warning_amber_rounded,
              _danger,
            ),
            _metricCard(
              'Loyalty',
              '${summary.loyaltyMembers}',
              Icons.stars_outlined,
              _purple,
            ),
            _metricCard(
              'Liability',
              _money(summary.loyaltyLiability),
              Icons.redeem_rounded,
              _brand,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _section(
          title: 'Needs Attention',
          subtitle:
              'Blocked, over-limit, inactive, or high liability customers.',
          rows: dashboard?.needsAttention ?? const [],
          emptyTitle: 'No customers need attention',
        ),
        const SizedBox(height: 16),
        _section(
          title: 'Top Outstanding',
          subtitle: 'Highest credit balance first.',
          rows: dashboard?.topOutstanding ?? const [],
          emptyTitle: 'No outstanding customers',
        ),
        const SizedBox(height: 16),
        _section(
          title: 'Recently Active',
          subtitle: 'Latest purchase activity.',
          rows: dashboard?.recentCustomers ?? const [],
          emptyTitle: 'No recent customers',
        ),
      ],
    );
  }

  Widget _customersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _loadCustomers(),
          decoration: InputDecoration(
            hintText: 'Search name, phone, or code',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _loadCustomers();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _border),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filters
                .map(
                  (filter) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _filter == filter.id,
                      avatar: Icon(filter.icon, size: 18),
                      label: Text(filter.label),
                      onSelected: (_) => _setFilter(filter.id),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (_isLoadingCustomers)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _offlinePanel()
        else if (_customers.isEmpty)
          const _EmptyBlock(
            icon: Icons.person_search_rounded,
            title: 'No customers found',
            subtitle: 'Try another search or filter.',
          )
        else
          ..._customers.map(_customerCard),
      ],
    );
  }

  Widget _focusTab({
    required String title,
    required String subtitle,
    required List<CustomerMonitorRow> rows,
    required String emptyTitle,
    required IconData icon,
  }) {
    if (_isLoadingDashboard && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _plainHeader(title: title, subtitle: subtitle, icon: icon),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          _EmptyBlock(
            icon: icon,
            title: emptyTitle,
            subtitle: 'This section will update as POS data syncs.',
          )
        else
          ...rows.map(_customerCard),
      ],
    );
  }

  Widget _heroCard(CustomerMonitorSummary summary) {
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
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.manage_accounts_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Customer Monitor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.creditCustomers} with balance - ${summary.loyaltyMembers} loyalty members',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 21),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
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

  Widget _section({
    required String title,
    required String subtitle,
    required List<CustomerMonitorRow> rows,
    required String emptyTitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            _EmptyBlock(
              icon: Icons.check_circle_outline_rounded,
              title: emptyTitle,
              subtitle: 'Nothing to show here right now.',
            )
          else
            ...rows.take(5).map(_customerCard),
        ],
      ),
    );
  }

  Widget _customerCard(CustomerMonitorRow customer) {
    final color = _healthColor(customer);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: customer.isOverLimit
              ? _danger.withValues(alpha: 0.34)
              : _border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            _openProfile(customer);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Text(
                    customer.displayName.substring(0, 1).toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
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
                              customer.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _chip(customer.healthLabel, color),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${customer.customerCode} - ${customer.phone.isEmpty ? 'No phone' : customer.phone}',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _miniInfo(
                            customer.category.isEmpty
                                ? 'No category'
                                : customer.category,
                          ),
                          _miniInfo(
                            customer.pricingScheme.isEmpty
                                ? 'No scheme'
                                : customer.pricingScheme,
                          ),
                          _miniInfo(
                            'Credit ${_money(customer.creditBalance)} / ${_money(customer.creditLimit)}',
                          ),
                          _miniInfo('${customer.loyaltyPoints} pts'),
                          _miniInfo(
                            'Last ${_dateText(customer.lastPurchaseAt)}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _miniInfo(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }

  Widget _plainHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _brand.withValues(alpha: 0.10),
            child: Icon(icon, color: _brand),
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
        ],
      ),
    );
  }

  Widget _offlineBlock() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
      children: [
        _offlinePanel(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _offlinePanel() {
    return _EmptyBlock(
      icon: Icons.cloud_off_rounded,
      title: 'Local server unavailable',
      subtitle: _error ?? 'Start local_server.py and try again.',
    );
  }
}

class _MonitorFilter {
  const _MonitorFilter(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF98A2B3), size: 34),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF172433),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
