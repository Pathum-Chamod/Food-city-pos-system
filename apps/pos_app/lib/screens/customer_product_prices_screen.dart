import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/auth_provider.dart';
import '../services/customer_pricing_service.dart';
import '../services/database_helper.dart';
import '../services/permission_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/permission_guard.dart';
import 'pricing_scheme_rule_dialog.dart';

class CustomerProductPricesScreen extends StatefulWidget {
  const CustomerProductPricesScreen({super.key, required this.customer});

  final Customer customer;

  @override
  State<CustomerProductPricesScreen> createState() =>
      _CustomerProductPricesScreenState();
}

class _CustomerProductPricesScreenState
    extends State<CustomerProductPricesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<CustomerPricingRule> _rules = [];
  List<Product> _products = [];
  bool _isLoading = true;

  static const Color _brand = Color(0xFF2AAA8A);
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

  int? get _actorUserId {
    try {
      return context.read<AuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? get _actorName {
    try {
      return context.read<AuthProvider>().currentUser?.name;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _focusSearchField();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      final context = _searchFocusNode.context;
      if (context == null) return;
      final position = Scrollable.maybeOf(context)?.position;
      position?.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customerId = widget.customer.id ?? 0;
      final results = await Future.wait([
        CustomerPricingService.instance.getRulesForCustomer(customerId),
        DatabaseHelper.instance.getProducts(),
      ]);

      if (!mounted) return;
      setState(() {
        _rules = results[0] as List<CustomerPricingRule>;
        _products = results[1] as List<Product>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rules = [];
        _products = [];
        _isLoading = false;
      });
      _showMessage('Could not load customer-specific prices.', color: _danger);
    }
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  Future<void> _logPricingUpdate(String description) async {
    await DatabaseHelper.instance.logSensitiveAction(
      actorUserId: _actorUserId,
      actorName: _actorName,
      actionType: 'pricing_update',
      targetUserId: widget.customer.id,
      targetUserName: widget.customer.displayName,
      description: description,
    );
  }

  List<String> get _categories {
    final categories =
        _products
            .map((product) => product.category.trim())
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return categories;
  }

  List<CustomerPricingRule> get _filteredRules {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _rules;

    return _rules.where((rule) {
      return (rule.productNameSnapshot ?? '').toLowerCase().contains(query) ||
          (rule.category ?? '').toLowerCase().contains(query) ||
          (rule.barcode ?? '').toLowerCase().contains(query) ||
          (rule.note ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addRule() async {
    final customerId = widget.customer.id ?? 0;
    if (customerId <= 0) return;

    final result = await showPricingSchemeRuleDialog(
      context: context,
      products: _products,
      categories: _categories,
      titleNoun: 'Customer Rule',
    );
    if (result == null) return;

    try {
      await CustomerPricingService.instance.upsertCustomerRule(
        customerId: customerId,
        applyTo: result.applyTo,
        category: result.category,
        barcode: result.product?.barcode,
        productNameSnapshot: result.product?.name,
        ruleType: result.ruleType,
        priceType: result.priceType,
        discountPercent: result.discountPercent,
        fixedPrice: result.fixedPrice,
        priority: result.priority,
        isActive: result.isActive,
        note: result.note,
      );
      await _logPricingUpdate(
        'Customer-specific pricing rule added for ${widget.customer.displayName}',
      );
      if (!mounted) return;
      _showMessage('Customer-specific rule saved.', color: _success);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  Future<void> _editRule(CustomerPricingRule rule) async {
    final customerId = widget.customer.id ?? 0;
    if (customerId <= 0) return;

    final result = await showPricingSchemeRuleDialog(
      context: context,
      products: _products,
      categories: _categories,
      rule: rule.asPricingSchemeRule(),
      titleNoun: 'Customer Rule',
    );
    if (result == null) return;

    try {
      await CustomerPricingService.instance.upsertCustomerRule(
        id: rule.id,
        customerId: customerId,
        applyTo: result.applyTo,
        category: result.category,
        barcode: result.product?.barcode,
        productNameSnapshot: result.product?.name,
        ruleType: result.ruleType,
        priceType: result.priceType,
        discountPercent: result.discountPercent,
        fixedPrice: result.fixedPrice,
        priority: result.priority,
        isActive: result.isActive,
        note: result.note,
      );
      await _logPricingUpdate(
        'Customer-specific pricing rule updated for ${widget.customer.displayName}',
      );
      if (!mounted) return;
      _showMessage('Customer-specific rule updated.', color: _success);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  Future<void> _toggleActive(CustomerPricingRule rule) async {
    final id = rule.id;
    if (id == null || id <= 0) return;

    try {
      await CustomerPricingService.instance.setCustomerRuleActive(
        id: id,
        isActive: !rule.isActive,
      );
      await _logPricingUpdate(
        'Customer-specific pricing rule for ${widget.customer.displayName} ${rule.isActive ? 'deactivated' : 'reactivated'}',
      );
      if (!mounted) return;
      _showMessage(
        rule.isActive ? 'Rule deactivated.' : 'Rule activated.',
        color: _success,
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      labelText: 'Search customer rules',
      hintText: 'Product, category, barcode, or note',
      prefixIcon: const Icon(Icons.search_rounded),
      filled: true,
      fillColor: _panel,
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

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().can(PosPermission.pricingManage)) {
      return const PermissionGuard(
        permission: PosPermission.pricingManage,
        title: 'Pricing access restricted',
        message: 'Only managers or full-access users can manage pricing.',
        child: SizedBox.shrink(),
      );
    }

    final activeCount = _rules.where((rule) => rule.isActive).length;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Customer Item & Category Rules'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _addRule,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Rule'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(activeCount),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      decoration: _searchDecoration(),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    if (_filteredRules.isEmpty)
                      _emptyState()
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredRules.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _ruleRow(_filteredRules[index]);
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(int activeCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _brand.withValues(alpha: 0.24)),
            ),
            child: const Icon(
              Icons.price_change_rounded,
              color: _brand,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customer.displayName,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.customer.displayCode} - $activeCount active of ${_rules.length} customer rules',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Rule'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Text(
        'No customer-specific item or category rules yet. Add special prices or discounts for this customer.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _ruleRow(CustomerPricingRule rule) {
    final statusColor = rule.isActive ? _brand : _textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: rule.isActive ? _brand.withValues(alpha: 0.22) : _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_targetIcon(rule.applyTo), color: statusColor),
          ),
          const SizedBox(width: 12),
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
                      _targetLabel(rule),
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    _statusPill(rule.isActive),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _ruleActionLabel(rule),
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if ((rule.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    rule.note!.trim(),
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _amountColumn(
            label: 'Priority',
            value: rule.priority.toString(),
            color: _warning,
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _editRule(rule),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: rule.isActive ? 'Deactivate' : 'Activate',
            onPressed: () => _toggleActive(rule),
            icon: Icon(
              rule.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              color: rule.isActive ? _brand : _textSecondary,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool isActive) {
    final color = isActive ? _brand : _textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  IconData _targetIcon(PricingSchemeRuleApplyTo applyTo) {
    switch (applyTo) {
      case PricingSchemeRuleApplyTo.product:
        return Icons.inventory_2_rounded;
      case PricingSchemeRuleApplyTo.category:
        return Icons.category_rounded;
      case PricingSchemeRuleApplyTo.all:
        return Icons.all_inbox_rounded;
    }
  }

  String _targetLabel(CustomerPricingRule rule) {
    switch (rule.applyTo) {
      case PricingSchemeRuleApplyTo.product:
        return rule.productNameSnapshot ?? rule.barcode ?? 'Specific Product';
      case PricingSchemeRuleApplyTo.category:
        return rule.category ?? 'Product Category';
      case PricingSchemeRuleApplyTo.all:
        return 'All Products';
    }
  }

  String _ruleActionLabel(CustomerPricingRule rule) {
    final target = rule.applyTo.label;
    switch (rule.ruleType) {
      case PricingSchemeRuleType.priceType:
        return '$target - Use ${rule.priceType?.label ?? 'Selling Price'}';
      case PricingSchemeRuleType.percentDiscount:
        return '$target - ${rule.normalizedDiscountPercent.toStringAsFixed(2)}% discount';
      case PricingSchemeRuleType.fixedPrice:
        return '$target - Fixed ${_money(rule.fixedPrice ?? 0)}';
      case PricingSchemeRuleType.noDiscount:
        return '$target - No discount';
    }
  }

  Widget _amountColumn({
    required String label,
    required String value,
    required Color color,
  }) {
    return SizedBox(
      width: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.right,
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
}
