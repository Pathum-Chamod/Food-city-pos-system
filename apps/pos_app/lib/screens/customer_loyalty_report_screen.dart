import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/loyalty_ledger_entry.dart';

import '../services/loyalty_service.dart';
import '../widgets/app_snackbar.dart';
import 'customer_detail_screen.dart';
import 'customer_loyalty_ledger_screen.dart';

class CustomerLoyaltyReportScreen extends StatefulWidget {
  const CustomerLoyaltyReportScreen({super.key});

  @override
  State<CustomerLoyaltyReportScreen> createState() =>
      _CustomerLoyaltyReportScreenState();
}

class _CustomerLoyaltyReportScreenState
    extends State<CustomerLoyaltyReportScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  final ScrollController _pageScrollController = ScrollController();
  Timer? _searchDebounce;

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _ledgerRows = [];
  bool _isLoading = true;
  bool _includeZeroBalance = true;
  String _query = '';
  String _entryFilter = 'all';
  int? _selectedSearchResultIndex;
  Timer? _searchSelectionTimer;
  final Map<int, GlobalKey> _searchResultKeys = <int, GlobalKey>{};

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _success = Color(0xFF1FCF9A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode(onKeyEvent: _handleSearchKeyEvent);
    _loadReport();
    _focusSearchField();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchSelectionTimer?.cancel();
    _pageScrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _searchSelectionTimer?.cancel();
      if (_selectedSearchResultIndex != null) {
        setState(() => _selectedSearchResultIndex = null);
      }
      if (_pageScrollController.hasClients) {
        await _pageScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSearchSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSearchSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _openSelectedSearchResult();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSearchSelection(int delta) {
    if (_customers.isEmpty) {
      setState(() => _selectedSearchResultIndex = null);
      return;
    }
    final current = _selectedSearchResultIndex ?? (delta > 0 ? -1 : 0);
    final next = (current + delta).clamp(0, _customers.length - 1);
    _showSearchSelection(next, scrollDirection: delta);
  }

  void _showSearchSelection(
    int index, {
    int scrollDirection = 0,
    bool autoClear = true,
  }) {
    _searchSelectionTimer?.cancel();
    setState(() => _selectedSearchResultIndex = index);
    _scrollSearchSelectionIntoView(index, scrollDirection: scrollDirection);
    if (!autoClear) return;
    _searchSelectionTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _selectedSearchResultIndex = null);
    });
  }

  void _scrollSearchSelectionIntoView(
    int index, {
    required int scrollDirection,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _searchResultKeys[index]?.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignmentPolicy: scrollDirection < 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Future<void> _openSelectedSearchResult() async {
    if (_customers.isEmpty) return;
    final index = _customers.length == 1
        ? 0
        : (_selectedSearchResultIndex ?? 0).clamp(0, _customers.length - 1);
    _showSearchSelection(index, autoClear: false);
    await _openCustomerDetails(_customers[index]);
    if (mounted) _showSearchSelection(index);
  }

  Future<void> _loadReport() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final service = LoyaltyService.instance;
      final summary = await service.getLoyaltyReportSummary();
      final customers = await service.getLoyaltyCustomersReport(
        query: _query,
        includeZeroBalance: _includeZeroBalance,
      );
      final ledgerRows = await service.getLoyaltyLedgerReport(
        entryType: _entryFilter,
        limit: 120,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _customers = customers;
        _ledgerRows = ledgerRows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summary = {};
        _customers = [];
        _ledgerRows = [];
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load loyalty report.',
        backgroundColor: _danger,
      );
    }
  }

  void _onSearchChanged(String value) {
    _query = value.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), _loadReport);
  }

  int _readInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  double _readDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  bool _readBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return fallback;
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  Customer _customerFromRow(Map<String, dynamic> row) {
    final now = DateTime.now().toIso8601String();
    return Customer.fromMap({
      ...row,
      'customer_code': row['customer_code'] ?? '',
      'name': row['name'] ?? '',
      'created_at': row['created_at'] ?? now,
      'updated_at': row['updated_at'] ?? now,
    });
  }

  Future<void> _openCustomerDetails(Map<String, dynamic> row) async {
    final customerId = _readInt(row['id']);
    if (customerId <= 0) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customerId: customerId),
      ),
    );
    if (!mounted) return;
    await _loadReport();
  }

  Future<void> _openCustomerLedger(Map<String, dynamic> row) async {
    final customerId = _readInt(row['id']);
    if (customerId <= 0) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CustomerLoyaltyLedgerScreen(customer: _customerFromRow(row)),
      ),
    );
    if (!mounted) return;
    await _loadReport();
  }

  Color _entryColor(String type, int delta) {
    if (type == LoyaltyEntryType.redeem.dbValue) return _warning;
    if (type == LoyaltyEntryType.refundEarnReversal.dbValue) return _danger;
    if (type == LoyaltyEntryType.refundRedeemRestore.dbValue) return _blue;
    return delta >= 0 ? _success : _danger;
  }

  String _entryLabel(String type) {
    return LoyaltyEntryTypeX.fromDb(type).label;
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

  Widget _filterChip(String value, String label) {
    final selected = _entryFilter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) async {
        setState(() {
          _entryFilter = value;
          _selectedSearchResultIndex = null;
        });
        await _loadReport();
      },
    );
  }

  Widget _customerRow(
    Map<String, dynamic> row, {
    bool isKeyboardSelected = false,
  }) {
    final balance = _readInt(row['loyalty_points_balance']);
    final enabled = _readBool(row['loyalty_enabled'], fallback: true);
    final name = (row['name'] ?? '').toString().trim();
    final phone = (row['phone'] ?? '').toString().trim();
    final code = (row['customer_code'] ?? '').toString().trim();
    final displayName = name.isEmpty ? (phone.isEmpty ? code : phone) : name;
    final tone = enabled ? _brand : _textSecondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isKeyboardSelected ? _brand : _border,
          width: isKeyboardSelected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: tone.withValues(alpha: _isDark ? 0.18 : 0.12),
            child: Text(
              displayName.isEmpty ? 'C' : displayName[0].toUpperCase(),
              style: TextStyle(color: tone, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _openCustomerDetails(row),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [code, phone].where((part) => part.isNotEmpty).join('  '),
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _smallMetric('Balance', balance.toString(), _brand),
          const SizedBox(width: 10),
          _smallMetric(
            'Earned',
            _readInt(row['loyalty_lifetime_earned']).toString(),
            _success,
          ),
          const SizedBox(width: 10),
          _smallMetric(
            'Redeemed',
            _readInt(row['loyalty_lifetime_redeemed']).toString(),
            _warning,
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => _openCustomerLedger(row),
            icon: const Icon(Icons.list_alt_rounded, size: 16),
            label: const Text('Ledger'),
          ),
        ],
      ),
    );
  }

  Widget _smallMetric(String label, String value, Color color) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> row) {
    final type = (row['entry_type'] ?? 'earn').toString();
    final delta = _readInt(row['points_delta']);
    final color = _entryColor(type, delta);
    final name = (row['customer_name'] ?? '').toString().trim();
    final phone = (row['customer_phone'] ?? '').toString().trim();
    final customer = name.isEmpty ? phone : name;

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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.stars_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_entryLabel(type)}${customer.isEmpty ? '' : ' - $customer'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(row['created_at']),
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            delta > 0 ? '+$delta' : delta.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _money(_readDouble(row['money_value'])),
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Loyalty Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadReport,
                child: SingleChildScrollView(
                  controller: _pageScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _summaryCard(
                            label: 'Point Balance',
                            value: _readInt(
                              _summary['total_points_balance'],
                            ).toString(),
                            icon: Icons.stars_rounded,
                            color: _brand,
                          ),
                          const SizedBox(width: 12),
                          _summaryCard(
                            label: 'Lifetime Earned',
                            value: _readInt(
                              _summary['total_lifetime_earned'],
                            ).toString(),
                            icon: Icons.trending_up_rounded,
                            color: _success,
                          ),
                          const SizedBox(width: 12),
                          _summaryCard(
                            label: 'Lifetime Redeemed',
                            value: _readInt(
                              _summary['total_lifetime_redeemed'],
                            ).toString(),
                            icon: Icons.redeem_rounded,
                            color: _warning,
                          ),
                          const SizedBox(width: 12),
                          _summaryCard(
                            label: 'Redeemed Value',
                            value: _money(
                              _readDouble(_summary['redeemed_value']),
                            ),
                            icon: Icons.payments_rounded,
                            color: _blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: 'Search customers',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  fillColor: _panelSoft,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: _border),
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedSearchResultIndex = null;
                                  });
                                  _onSearchChanged(value);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilterChip(
                              selected: !_includeZeroBalance,
                              label: const Text('With Balance'),
                              onSelected: (value) async {
                                setState(() {
                                  _includeZeroBalance = !value;
                                  _selectedSearchResultIndex = null;
                                });
                                await _loadReport();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Customer Balances',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_customers.isEmpty)
                        _emptyState('No loyalty customers found.')
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _customers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => KeyedSubtree(
                            key: _searchResultKeys.putIfAbsent(
                              index,
                              GlobalKey.new,
                            ),
                            child: _customerRow(
                              _customers[index],
                              isKeyboardSelected:
                                  _selectedSearchResultIndex == index,
                            ),
                          ),
                        ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Recent Loyalty Activity',
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              _filterChip('all', 'All'),
                              _filterChip('earn', 'Earn'),
                              _filterChip('redeem', 'Redeem'),
                              _filterChip(
                                'refund_earn_reversal',
                                'Earn Reversal',
                              ),
                              _filterChip(
                                'refund_redeem_restore',
                                'Redeem Restore',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_ledgerRows.isEmpty)
                        _emptyState('No loyalty ledger activity found.')
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _ledgerRows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _ledgerRow(_ledgerRows[index]),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
