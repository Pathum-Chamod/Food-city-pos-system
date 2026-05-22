import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/customer.dart';

import '../navigation/pos_route_names.dart';
import '../navigation/route_search_focus_registry.dart';
import '../providers/auth_provider.dart';
import '../services/customer_service.dart';
import '../widgets/app_snackbar.dart';
import 'customer_categories_screen.dart';
import 'customer_detail_screen.dart';
import 'customer_form_dialog.dart';
import 'customer_credit_report_screen.dart';
import 'customer_loyalty_report_screen.dart';
import 'loyalty_settings_screen.dart';
import 'pricing_schemes_screen.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  final ScrollController _resultScrollController = ScrollController();
  Timer? _searchDebounce;

  List<Customer> _customers = [];
  bool _isLoading = true;
  String _query = '';
  int? _selectedSearchResultIndex;
  Timer? _searchSelectionTimer;
  final Map<int, GlobalKey> _searchResultKeys = <int, GlobalKey>{};

  static const Color _brand = Color(0xFF2AAA8A);
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
    _loadCustomers();
    RouteSearchFocusRegistry.register(
      PosRouteNames.customerManagement,
      _focusSearchField,
    );
    _focusSearchField();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchSelectionTimer?.cancel();
    RouteSearchFocusRegistry.unregister(
      PosRouteNames.customerManagement,
      _focusSearchField,
    );
    _searchFocusNode.dispose();
    _resultScrollController.dispose();
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
    await _openDetails(_customers[index]);
    if (mounted) _showSearchSelection(index);
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final rows = await CustomerService.instance.getCustomers(
        query: _query,
        activeOnly: false,
        limit: 300,
      );

      if (!mounted) return;
      setState(() {
        _customers = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _customers = [];
        _isLoading = false;
      });
      _showMessage('Could not load customers.', color: _danger);
    }
  }

  void _onSearchChanged(String value) {
    _query = value.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), _loadCustomers);
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  int? get _actorUserId {
    try {
      return context.read<AuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _addCustomer() async {
    final created = await showCustomerFormDialog(
      context: context,
      actorUserId: _actorUserId,
    );

    if (!mounted || created == null) return;
    _showMessage('Customer added: ${created.displayName}', color: _success);
    await _loadCustomers();
  }

  Future<void> _editCustomer(Customer customer) async {
    final updated = await showCustomerFormDialog(
      context: context,
      customer: customer,
      actorUserId: _actorUserId,
    );

    if (!mounted || updated == null) return;
    _showMessage('Customer updated.', color: _success);
    await _loadCustomers();
  }

  Future<void> _toggleActive(Customer customer) async {
    final action = customer.isActive ? 'Deactivate' : 'Reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('$action Customer'),
          content: Text(
            customer.isActive
                ? 'Deactivate ${customer.displayName}? They will be hidden from the normal customer picker, but old sales history will remain.'
                : 'Reactivate ${customer.displayName}? They will be available again in the customer picker.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: customer.isActive ? _danger : _brand,
              ),
              child: Text(action),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      if (customer.isActive) {
        await CustomerService.instance.deactivateCustomer(
          customerId: customer.id ?? 0,
          updatedBy: _actorUserId,
        );
        _showMessage('Customer deactivated.', color: _warning);
      } else {
        await CustomerService.instance.reactivateCustomer(
          customerId: customer.id ?? 0,
          updatedBy: _actorUserId,
        );
        _showMessage('Customer reactivated.', color: _success);
      }
      await _loadCustomers();
    } catch (e) {
      _showMessage('Could not update customer status.', color: _danger);
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final customerId = customer.id ?? 0;
    if (customerId <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Customer'),
          content: Text(
            'Delete ${customer.displayName}? This action is permanent and only works when no linked history exists.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: _danger),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await CustomerService.instance.deleteCustomer(customerId: customerId);
      _showMessage('Customer deleted.', color: _success);
      await _loadCustomers();
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  Future<void> _openCreditReport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerCreditReportScreen()),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  Future<void> _openLoyaltyReport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerLoyaltyReportScreen()),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  Future<void> _openLoyaltySettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoyaltySettingsScreen()),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  Future<void> _openCustomerCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerCategoriesScreen()),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  Future<void> _openPricingSchemes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PricingSchemesScreen()),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  Future<void> _openDetails(Customer customer) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(customerId: customer.id ?? 0),
      ),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
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
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    );
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
                      fontSize: 20,
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

  Widget _customerCard(Customer customer, {bool isKeyboardSelected = false}) {
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isKeyboardSelected
              ? _brand
              : (customer.isActive ? _border : _danger.withValues(alpha: 0.35)),
          width: isKeyboardSelected ? 1.6 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openDetails(customer),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _brand.withValues(
                    alpha: _isDark ? 0.18 : 0.12,
                  ),
                  child: Text(
                    customer.displayName.trim().isEmpty
                        ? 'C'
                        : customer.displayName.trim()[0].toUpperCase(),
                    style: TextStyle(
                      color: _brand,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            customer.displayName,
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          if (!customer.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _danger.withValues(
                                  alpha: _isDark ? 0.18 : 0.10,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _danger.withValues(alpha: 0.24),
                                ),
                              ),
                              child: const Text(
                                'Inactive',
                                style: TextStyle(
                                  color: _danger,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          Text(
                            customer.displayCode,
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            customer.displayPhone,
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (customer.hasAddress)
                            Text(
                              customer.address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  icon: Icon(Icons.more_vert_rounded, color: _textSecondary),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _editCustomer(customer);
                        break;
                      case 'toggle':
                        _toggleActive(customer);
                        break;
                      case 'delete':
                        _deleteCustomer(customer);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.edit_rounded),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'toggle',
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          customer.isActive
                              ? Icons.person_off_rounded
                              : Icons.person_add_alt_rounded,
                          color: customer.isActive ? _danger : _brand,
                        ),
                        title: Text(
                          customer.isActive ? 'Deactivate' : 'Reactivate',
                        ),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
                Icon(Icons.chevron_right_rounded, color: _textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _customers
        .where((customer) => customer.isActive)
        .length;
    final inactiveCount = _customers.length - activeCount;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Customer Management'),
        actions: [
          TextButton.icon(
            onPressed: _openPricingSchemes,
            icon: const Icon(Icons.sell_rounded),
            label: const Text('Pricing Schemes'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openCustomerCategories,
            icon: const Icon(Icons.groups_2_rounded),
            label: const Text('Categories'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openCreditReport,
            icon: const Icon(Icons.account_balance_wallet_rounded),
            label: const Text('Credit Report'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openLoyaltyReport,
            icon: const Icon(Icons.card_giftcard_rounded),
            label: const Text('Loyalty Report'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _openLoyaltySettings,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Loyalty Settings'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadCustomers,
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
                    label: 'Showing',
                    value: _customers.length.toString(),
                    icon: Icons.groups_rounded,
                    color: _brand,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Active',
                    value: activeCount.toString(),
                    icon: Icons.verified_user_rounded,
                    color: _success,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Inactive',
                    value: inactiveCount.toString(),
                    icon: Icons.person_off_rounded,
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
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        autofocus: true,
                        decoration:
                            _inputDecoration(
                              label: 'Search customers',
                              icon: Icons.search_rounded,
                              hint: 'Name / phone / code',
                            ).copyWith(
                              suffixIcon: _searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _query = '';
                                          _selectedSearchResultIndex = null;
                                        });
                                        _loadCustomers();
                                      },
                                      icon: const Icon(Icons.clear_rounded),
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
                    const SizedBox(width: 14),
                    ElevatedButton.icon(
                      onPressed: _addCustomer,
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text('Add Customer'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _customers.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_search_rounded,
                                size: 44,
                                color: _textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No customers found',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add your first customer or try another search term.',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addCustomer,
                                icon: const Icon(Icons.person_add_rounded),
                                label: const Text('Add Customer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: _resultScrollController,
                        itemCount: _customers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return KeyedSubtree(
                            key: _searchResultKeys.putIfAbsent(
                              index,
                              GlobalKey.new,
                            ),
                            child: _customerCard(
                              _customers[index],
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
