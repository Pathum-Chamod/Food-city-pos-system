import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../services/pricing_scheme_service.dart';
import '../widgets/app_snackbar.dart';
import 'customer_category_dialog.dart';

class CustomerCategoriesScreen extends StatefulWidget {
  const CustomerCategoriesScreen({super.key});

  @override
  State<CustomerCategoriesScreen> createState() =>
      _CustomerCategoriesScreenState();
}

class _CustomerCategoriesScreenState extends State<CustomerCategoriesScreen> {
  List<CustomerCategory> _categories = [];
  List<PricingScheme> _schemes = [];
  Map<int, int> _customerCounts = {};
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

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = PricingSchemeService.instance;
      final results = await Future.wait([
        service.getCustomerCategories(activeOnly: !_includeInactive),
        service.getPricingSchemes(activeOnly: false),
        service.getCustomerCountsByCategory(),
      ]);

      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<CustomerCategory>;
        _schemes = results[1] as List<PricingScheme>;
        _customerCounts = results[2] as Map<int, int>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categories = [];
        _schemes = [];
        _customerCounts = {};
        _isLoading = false;
      });
      _showMessage('Could not load customer categories.', color: _danger);
    }
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  Future<void> _addCategory() async {
    final result = await showCustomerCategoryDialog(
      context: context,
      schemes: _schemes,
    );
    if (result == null) return;

    try {
      await PricingSchemeService.instance.createCustomerCategory(
        name: result.name,
        description: result.description,
        defaultPricingSchemeId: result.defaultPricingSchemeId,
      );
      _showMessage('Customer category added.', color: _success);
      await _loadCategories();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _editCategory(CustomerCategory category) async {
    final result = await showCustomerCategoryDialog(
      context: context,
      category: category,
      schemes: _schemes,
    );
    if (result == null) return;

    try {
      await PricingSchemeService.instance.updateCustomerCategory(
        id: category.id ?? 0,
        name: result.name,
        description: result.description,
        defaultPricingSchemeId: result.defaultPricingSchemeId,
        isActive: result.isActive,
      );
      _showMessage('Customer category updated.', color: _success);
      await _loadCategories();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _toggleActive(CustomerCategory category) async {
    final id = category.id;
    if (id == null || id <= 0) return;

    try {
      await PricingSchemeService.instance.setCustomerCategoryActive(
        id: id,
        isActive: !category.isActive,
      );
      _showMessage(
        category.isActive
            ? 'Customer category deactivated.'
            : 'Customer category reactivated.',
        color: category.isActive ? _warning : _success,
      );
      await _loadCategories();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _schemeName(int? schemeId) {
    if (schemeId == null || schemeId <= 0) return 'No default scheme';
    for (final scheme in _schemes) {
      if (scheme.id == schemeId) {
        return scheme.isActive
            ? scheme.displayName
            : '${scheme.displayName} (inactive)';
      }
    }
    return 'Scheme #$schemeId';
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

  Widget _categoryCard(CustomerCategory category) {
    final id = category.id ?? 0;
    final customerCount = _customerCounts[id] ?? 0;
    final tone = category.isActive ? _brand : _textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: category.isActive ? _border : _danger.withValues(alpha: 0.35),
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
              child: Icon(Icons.groups_2_rounded, color: tone),
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
                        category.displayName,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      _chip(
                        category.isActive ? 'Active' : 'Inactive',
                        category.isActive ? _brand : _danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_schemeName(category.defaultPricingSchemeId)} - $customerCount customers',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((category.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      category.description!.trim(),
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
              onPressed: () => _editCategory(category),
              icon: const Icon(Icons.edit_rounded),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: category.isActive ? 'Deactivate' : 'Reactivate',
              onPressed: () => _toggleActive(category),
              icon: Icon(
                category.isActive
                    ? Icons.block_rounded
                    : Icons.check_circle_rounded,
                color: category.isActive ? _danger : _brand,
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
    final activeCount = _categories
        .where((category) => category.isActive)
        .length;
    final assignedCustomers = _customerCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Customer Categories'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadCategories,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCategory,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Category'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                children: [
                  _summaryCard(
                    label: 'Categories',
                    value: _categories.length.toString(),
                    icon: Icons.groups_2_rounded,
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
                    label: 'Assigned Customers',
                    value: assignedCustomers.toString(),
                    icon: Icons.people_alt_rounded,
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
                        'Editable customer categories for Pricing Schemes V1.5',
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
                        _loadCategories();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _categories.isEmpty
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
                                Icons.groups_2_rounded,
                                color: _textSecondary,
                                size: 44,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No categories found',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addCategory,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add Category'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _categoryCard(_categories[index]);
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
