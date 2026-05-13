import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/pricing_scheme_service.dart';
import '../widgets/app_snackbar.dart';
import 'pricing_scheme_rule_dialog.dart';

class PricingSchemeRulesScreen extends StatefulWidget {
  const PricingSchemeRulesScreen({super.key, required this.scheme});

  final PricingScheme scheme;

  @override
  State<PricingSchemeRulesScreen> createState() =>
      _PricingSchemeRulesScreenState();
}

class _PricingSchemeRulesScreenState extends State<PricingSchemeRulesScreen> {
  List<PricingSchemeRule> _rules = [];
  List<Product> _products = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _includeInactive = true;

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

  int? get _actorUserId {
    try {
      return context.read<AuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        PricingSchemeService.instance.getRulesForScheme(
          widget.scheme.id ?? 0,
          activeOnly: !_includeInactive,
        ),
        DatabaseHelper.instance.getProducts(),
      ]);

      final products = results[1] as List<Product>;
      final categories =
          products
              .map((product) => product.category.trim())
              .where((category) => category.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _rules = results[0] as List<PricingSchemeRule>;
        _products = products;
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rules = [];
        _products = [];
        _categories = [];
        _isLoading = false;
      });
      _showMessage('Could not load pricing scheme rules.', color: _danger);
    }
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _addRule() async {
    final result = await showPricingSchemeRuleDialog(
      context: context,
      products: _products,
      categories: _categories,
    );
    if (result == null) return;

    await _saveRule(result);
  }

  Future<void> _editRule(PricingSchemeRule rule) async {
    final result = await showPricingSchemeRuleDialog(
      context: context,
      products: _products,
      categories: _categories,
      rule: rule,
    );
    if (result == null) return;

    await _saveRule(result, existingRule: rule);
  }

  Future<void> _saveRule(
    PricingSchemeRuleDialogResult result, {
    PricingSchemeRule? existingRule,
  }) async {
    try {
      await PricingSchemeService.instance.upsertPricingSchemeRule(
        id: existingRule?.id,
        schemeId: widget.scheme.id ?? 0,
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
        userId: _actorUserId,
      );
      _showMessage(
        existingRule == null ? 'Pricing rule added.' : 'Pricing rule updated.',
        color: _success,
      );
      await _loadRules();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _toggleActive(PricingSchemeRule rule) async {
    final id = rule.id;
    if (id == null || id <= 0) return;

    try {
      await PricingSchemeService.instance.setPricingSchemeRuleActive(
        id: id,
        isActive: !rule.isActive,
        updatedBy: _actorUserId,
      );
      _showMessage(
        rule.isActive
            ? 'Pricing rule deactivated.'
            : 'Pricing rule reactivated.',
        color: rule.isActive ? _warning : _success,
      );
      await _loadRules();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  String _targetLabel(PricingSchemeRule rule) {
    switch (rule.applyTo) {
      case PricingSchemeRuleApplyTo.category:
        return rule.category ?? 'Category';
      case PricingSchemeRuleApplyTo.product:
        return rule.productNameSnapshot ?? rule.barcode ?? 'Product';
      case PricingSchemeRuleApplyTo.all:
        return 'All Products';
    }
  }

  String _ruleValue(PricingSchemeRule rule) {
    switch (rule.ruleType) {
      case PricingSchemeRuleType.priceType:
        return rule.priceType?.label ?? 'Selling Price';
      case PricingSchemeRuleType.percentDiscount:
        return '${rule.normalizedDiscountPercent.toStringAsFixed(2)}%';
      case PricingSchemeRuleType.fixedPrice:
        return 'Rs. ${(rule.fixedPrice ?? 0).toStringAsFixed(2)}';
      case PricingSchemeRuleType.noDiscount:
        return 'No Discount';
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

  Widget _ruleCard(PricingSchemeRule rule) {
    final tone = rule.isActive ? _brand : _textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: rule.isActive ? _border : _danger.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: _isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.rule_rounded, color: tone),
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
                        _targetLabel(rule),
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      _chip(rule.applyTo.label, _blue),
                      _chip(rule.ruleType.label, _warning),
                      _chip(
                        rule.isActive ? 'Active' : 'Inactive',
                        rule.isActive ? _brand : _danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_ruleValue(rule)} - Priority ${rule.priority}',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((rule.note ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      rule.note!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Edit',
              onPressed: () => _editRule(rule),
              icon: const Icon(Icons.edit_rounded),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: rule.isActive ? 'Deactivate' : 'Reactivate',
              onPressed: () => _toggleActive(rule),
              icon: Icon(
                rule.isActive
                    ? Icons.block_rounded
                    : Icons.check_circle_rounded,
                color: rule.isActive ? _danger : _brand,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _rules.where((rule) => rule.isActive).length;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: Text('${widget.scheme.displayName} Rules'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadRules,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRule,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Rule'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                children: [
                  _summaryCard(
                    label: 'Rules',
                    value: _rules.length.toString(),
                    icon: Icons.rule_rounded,
                    color: _brand,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Active',
                    value: activeCount.toString(),
                    icon: Icons.verified_rounded,
                    color: _success,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Product Categories',
                    value: _categories.length.toString(),
                    icon: Icons.category_rounded,
                    color: _blue,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Rules are saved for this scheme. Cart pricing uses them in the next integration batch.',
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      'Show inactive',
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Switch(
                      value: _includeInactive,
                      activeThumbColor: _brand,
                      onChanged: (value) {
                        setState(() {
                          _includeInactive = value;
                        });
                        _loadRules();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _rules.isEmpty
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
                                Icons.rule_rounded,
                                color: _textSecondary,
                                size: 44,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No rules found',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addRule,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add Rule'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _rules.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _ruleCard(_rules[index]);
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
