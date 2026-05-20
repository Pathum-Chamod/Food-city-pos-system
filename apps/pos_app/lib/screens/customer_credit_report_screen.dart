import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/customer.dart';

import '../navigation/pos_route_names.dart';
import '../navigation/route_search_focus_registry.dart';
import '../providers/auth_provider.dart';
import '../services/customer_credit_service.dart';
import '../widgets/app_snackbar.dart';
import 'customer_detail_screen.dart';
import 'customer_ledger_screen.dart';
import 'customer_payment_dialog.dart';
import 'customer_payment_receipt_dialog.dart';

class CustomerCreditReportScreen extends StatefulWidget {
  const CustomerCreditReportScreen({super.key});

  @override
  State<CustomerCreditReportScreen> createState() =>
      _CustomerCreditReportScreenState();
}

class _CustomerCreditReportScreenState
    extends State<CustomerCreditReportScreen> {
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _resultScrollController = ScrollController();

  List<Map<String, dynamic>> _rows = [];
  bool _isLoading = true;
  bool _includeZeroBalance = false;
  String _query = '';
  String _filter = 'outstanding';
  int? _selectedSearchResultIndex;
  Timer? _searchSelectionTimer;
  final Map<int, GlobalKey> _searchResultKeys = <int, GlobalKey>{};

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);

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

  List<Map<String, dynamic>> get _filteredRows {
    final search = _query.trim().toLowerCase();

    return _rows.where((row) {
      final balance = _readDouble(row['current_credit_balance']);
      final limit = _readDouble(row['credit_limit']);
      final status = (row['credit_status'] ?? 'normal')
          .toString()
          .toLowerCase();
      final creditEnabled = _readBool(row['credit_enabled']);

      if (_filter == 'outstanding' && balance <= 0) return false;
      if (_filter == 'over_limit' && !(limit > 0 && balance > limit)) {
        return false;
      }
      if (_filter == 'blocked' && status != 'blocked') return false;
      if (_filter == 'watchlist' && status != 'watchlist') return false;
      if (_filter == 'enabled' && !creditEnabled) return false;

      if (search.isEmpty) return true;

      final haystack = [
        row['customer_code'],
        row['name'],
        row['phone'],
        row['credit_status'],
        row['credit_note'],
      ].whereType<Object>().join(' ').toLowerCase();

      return haystack.contains(search);
    }).toList();
  }

  double get _totalOutstanding {
    return _filteredRows.fold<double>(0.0, (sum, row) {
      final balance = _readDouble(row['current_credit_balance']);
      return balance > 0 ? sum + balance : sum;
    });
  }

  int get _overLimitCount {
    return _filteredRows.where((row) {
      final balance = _readDouble(row['current_credit_balance']);
      final limit = _readDouble(row['credit_limit']);
      return limit > 0 && balance > limit;
    }).length;
  }

  int get _blockedCount {
    return _filteredRows
        .where((row) => (row['credit_status'] ?? '').toString() == 'blocked')
        .length;
  }

  @override
  void initState() {
    super.initState();
    _searchFocusNode.onKeyEvent = _handleSearchKeyEvent;
    _loadReport();
    RouteSearchFocusRegistry.register(
      PosRouteNames.customerCreditReport,
      _focusSearchField,
    );
    _focusSearchField();
  }

  @override
  void dispose() {
    _searchSelectionTimer?.cancel();
    RouteSearchFocusRegistry.unregister(
      PosRouteNames.customerCreditReport,
      _focusSearchField,
    );
    _resultScrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _searchSelectionTimer?.cancel();
      if (_selectedSearchResultIndex != null) {
        setState(() => _selectedSearchResultIndex = null);
      }
      if (_resultScrollController.hasClients) {
        await _resultScrollController.animateTo(
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
    final rows = _filteredRows;
    if (rows.isEmpty) {
      setState(() => _selectedSearchResultIndex = null);
      return;
    }
    final current = _selectedSearchResultIndex ?? (delta > 0 ? -1 : 0);
    final next = (current + delta).clamp(0, rows.length - 1);
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
    final rows = _filteredRows;
    if (rows.isEmpty) return;
    final index = rows.length == 1
        ? 0
        : (_selectedSearchResultIndex ?? 0).clamp(0, rows.length - 1);
    _showSearchSelection(index, autoClear: false);
    await _openCustomerDetails(rows[index]);
    if (mounted) _showSearchSelection(index);
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final rows = await CustomerCreditService.instance
          .getCreditCustomersReport(includeZeroBalance: _includeZeroBalance);

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load credit report.',
        backgroundColor: _danger,
      );
    }
  }

  bool _readBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  double _readDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  int _readInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
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

  Color _statusColor(String status, double balance, double limit) {
    if (status == 'blocked') return _danger;
    if (status == 'watchlist') return _warning;
    if (limit > 0 && balance > limit) return _danger;
    return _brand;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'blocked':
        return 'Blocked';
      case 'watchlist':
        return 'Watchlist';
      case 'normal':
      default:
        return 'Normal';
    }
  }

  Customer _customerFromRow(Map<String, dynamic> row) {
    final now = DateTime.now().toIso8601String();
    return Customer.fromMap({
      'id': row['id'],
      'customer_code': row['customer_code'],
      'name': row['name'],
      'phone': row['phone'],
      'is_active': row['is_active'],
      'credit_enabled': row['credit_enabled'],
      'credit_limit': row['credit_limit'],
      'current_credit_balance': row['current_credit_balance'],
      'credit_status': row['credit_status'],
      'credit_note': row['credit_note'],
      'created_at': now,
      'updated_at': now,
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

  Future<void> _openLedger(Map<String, dynamic> row) async {
    final customer = _customerFromRow(row);
    if (customer.id == null || customer.id! <= 0) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerLedgerScreen(
          customerId: customer.id!,
          customerName: customer.displayName,
        ),
      ),
    );

    if (!mounted) return;
    await _loadReport();
  }

  Future<void> _receivePayment(Map<String, dynamic> row) async {
    final customer = _customerFromRow(row);
    if (customer.id == null || customer.id! <= 0) return;

    final saved = await showCustomerPaymentDialog(
      context: context,
      customerId: customer.id!,
      customerName: customer.displayName,
      receivedBy:
          context.read<AuthProvider>().currentUser?.name.trim().isNotEmpty ==
              true
          ? context.read<AuthProvider>().currentUser!.name.trim()
          : 'Unknown',
    );

    if (!mounted || saved == null) return;
    AppSnackBar.show(
      context,
      message: 'Payment saved.',
      backgroundColor: _brand,
    );
    if (saved.paymentId != null) {
      await showCustomerPaymentReceiptDialog(
        context: context,
        paymentId: saved.paymentId!,
        paymentJustSaved: true,
      );
    }
    if (!mounted) return;
    await _loadReport();
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
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
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

  Widget _filterBar() {
    final filters = [
      ('outstanding', 'Outstanding'),
      ('all', 'All'),
      ('over_limit', 'Over Limit'),
      ('blocked', 'Blocked'),
      ('watchlist', 'Watchlist'),
      ('enabled', 'Enabled'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((item) {
        final selected = _filter == item.$1;
        return ChoiceChip(
          selected: selected,
          label: Text(item.$2),
          onSelected: (_) {
            setState(() {
              _filter = item.$1;
              _selectedSearchResultIndex = null;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _reportRow(
    Map<String, dynamic> row, {
    bool isKeyboardSelected = false,
  }) {
    final customer = _customerFromRow(row);
    final balance = _readDouble(row['current_credit_balance']);
    final limit = _readDouble(row['credit_limit']);
    final available = limit - balance;
    final status = (row['credit_status'] ?? 'normal').toString().toLowerCase();
    final tone = _statusColor(status, balance, limit);
    final isOverLimit = limit > 0 && balance > limit;
    final isAdvance = balance < 0;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isKeyboardSelected
              ? _brand
              : (isOverLimit ? _danger.withValues(alpha: 0.38) : _border),
          width: isKeyboardSelected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: tone.withValues(alpha: _isDark ? 0.18 : 0.10),
            child: Text(
              customer.displayName.isEmpty
                  ? 'C'
                  : customer.displayName[0].toUpperCase(),
              style: TextStyle(color: tone, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openCustomerDetails(row),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        Text(
                          customer.displayName,
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tone.withValues(
                              alpha: _isDark ? 0.16 : 0.09,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: tone.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            isOverLimit
                                ? 'Over Limit'
                                : isAdvance
                                ? 'Advance'
                                : _statusLabel(status),
                            style: TextStyle(
                              color: tone,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${customer.displayCode} • ${customer.displayPhone}',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Last credit sale: ${_formatDate(row['last_credit_sale_at'])} • Last payment: ${_formatDate(row['last_payment_at'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _amountBlock(
            label: isAdvance ? 'Advance' : 'Balance',
            value: _money(balance.abs()),
            color: isAdvance
                ? _blue
                : balance > 0
                ? _warning
                : _brand,
          ),
          const SizedBox(width: 12),
          _amountBlock(
            label: 'Limit',
            value: _money(limit),
            color: _textPrimary,
          ),
          const SizedBox(width: 12),
          _amountBlock(
            label: available < 0 ? 'Over' : 'Available',
            value: _money(available.abs()),
            color: available < 0 ? _danger : _blue,
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _openLedger(row),
            icon: const Icon(Icons.list_alt_rounded, size: 16),
            label: const Text('Ledger'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _receivePayment(row),
            icon: const Icon(Icons.payments_rounded, size: 16),
            label: const Text('Payment'),
          ),
        ],
      ),
    );
  }

  Widget _amountBlock({
    required String label,
    required String value,
    required Color color,
  }) {
    return SizedBox(
      width: 115,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
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

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Customer Credit Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                children: [
                  _summaryCard(
                    label: 'Outstanding',
                    value: _money(_totalOutstanding),
                    icon: Icons.account_balance_wallet_rounded,
                    color: _warning,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Customers',
                    value: rows.length.toString(),
                    icon: Icons.groups_rounded,
                    color: _brand,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Over Limit',
                    value: _overLimitCount.toString(),
                    icon: Icons.warning_rounded,
                    color: _danger,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Blocked',
                    value: _blockedCount.toString(),
                    icon: Icons.block_rounded,
                    color: _danger,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            focusNode: _searchFocusNode,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Search customer',
                              hintText: 'Name / phone / code',
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: _panelSoft,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(color: _border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(color: _border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(
                                  color: _brand,
                                  width: 1.4,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _query = value;
                                _selectedSearchResultIndex = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: _panelSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Include zero balance',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Switch(
                                value: _includeZeroBalance,
                                activeThumbColor: _brand,
                                onChanged: (value) {
                                  setState(() {
                                    _includeZeroBalance = value;
                                    _selectedSearchResultIndex = null;
                                  });
                                  _loadReport();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: _filterBar()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _border),
                          ),
                          child: Text(
                            'No credit customers found.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: _resultScrollController,
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return KeyedSubtree(
                            key: _searchResultKeys.putIfAbsent(
                              index,
                              GlobalKey.new,
                            ),
                            child: _reportRow(
                              rows[index],
                              isKeyboardSelected:
                                  _selectedSearchResultIndex == index,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
