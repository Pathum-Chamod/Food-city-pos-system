import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

class PricingSchemeRuleDialogResult {
  const PricingSchemeRuleDialogResult({
    required this.applyTo,
    this.category,
    this.product,
    required this.ruleType,
    this.priceType,
    this.discountPercent = 0.0,
    this.fixedPrice,
    this.priority = 100,
    this.isActive = true,
    this.note,
    this.overwriteRuleId,
  });

  final PricingSchemeRuleApplyTo applyTo;
  final String? category;
  final Product? product;
  final PricingSchemeRuleType ruleType;
  final ProductPriceType? priceType;
  final double discountPercent;
  final double? fixedPrice;
  final int priority;
  final bool isActive;
  final String? note;
  final int? overwriteRuleId;
}

Future<PricingSchemeRuleDialogResult?> showPricingSchemeRuleDialog({
  required BuildContext context,
  required List<Product> products,
  required List<String> categories,
  List<PricingSchemeRule> existingRules = const [],
  PricingSchemeRule? rule,
  String titleNoun = 'Scheme Rule',
}) {
  return showPremiumDialog<PricingSchemeRuleDialogResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _PricingSchemeRuleDialog(
      products: products,
      categories: categories,
      existingRules: existingRules,
      rule: rule,
      titleNoun: titleNoun,
    ),
  );
}

class _PricingSchemeRuleDialog extends StatefulWidget {
  const _PricingSchemeRuleDialog({
    required this.products,
    required this.categories,
    required this.existingRules,
    this.rule,
    required this.titleNoun,
  });

  final List<Product> products;
  final List<String> categories;
  final List<PricingSchemeRule> existingRules;
  final PricingSchemeRule? rule;
  final String titleNoun;

  @override
  State<_PricingSchemeRuleDialog> createState() =>
      _PricingSchemeRuleDialogState();
}

class _PricingSchemeRuleDialogState extends State<_PricingSchemeRuleDialog> {
  late final TextEditingController _searchController;
  late final TextEditingController _discountController;
  late final TextEditingController _fixedPriceController;
  late final FocusNode _productSearchFocusNode;
  final LayerLink _productSearchLayerLink = LayerLink();
  final LayerLink _categoryLayerLink = LayerLink();
  final GlobalKey _productSearchFieldKey = GlobalKey();
  final GlobalKey _categoryFieldKey = GlobalKey();
  OverlayEntry? _productSearchOverlay;
  OverlayEntry? _categoryOverlay;
  bool _isSelectingProductFromOverlay = false;

  late PricingSchemeRuleApplyTo _applyTo;
  late PricingSchemeRuleType _ruleType;
  ProductPriceType _priceType = ProductPriceType.wholesale;
  String? _category;
  Product? _product;
  bool _isActive = true;
  late int _priority;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);

  bool get _isEdit => widget.rule != null;
  bool get _isSpecificProductTarget =>
      _applyTo == PricingSchemeRuleApplyTo.product;
  bool get _allowFixedPrice => _isSpecificProductTarget;

  List<PricingSchemeRuleType> get _availableRuleTypes {
    if (_allowFixedPrice) return PricingSchemeRuleType.values;
    return PricingSchemeRuleType.values
        .where((t) => t != PricingSchemeRuleType.fixedPrice)
        .toList();
  }

  String _targetSummary() {
    switch (_applyTo) {
      case PricingSchemeRuleApplyTo.all:
        return 'All Products';
      case PricingSchemeRuleApplyTo.category:
        return _category?.trim().isNotEmpty == true
            ? 'Category: ${_category!.trim()}'
            : 'Category Rule';
      case PricingSchemeRuleApplyTo.product:
        final name = _product?.name.trim();
        final barcode = _product?.barcode.trim();
        if (name != null && name.isNotEmpty) {
          return barcode != null && barcode.isNotEmpty
              ? '$name ($barcode)'
              : name;
        }
        if (barcode != null && barcode.isNotEmpty) return barcode;
        return 'Specific Product';
    }
  }

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _applyTo = rule?.applyTo ?? PricingSchemeRuleApplyTo.all;
    _ruleType = rule?.ruleType ?? PricingSchemeRuleType.priceType;
    _priceType = rule?.priceType ?? ProductPriceType.wholesale;
    _category = rule?.category;
    _product = rule == null ? null : _findProduct(rule.barcode);
    _isActive = rule?.isActive ?? true;
    _searchController = TextEditingController();
    _discountController = TextEditingController(
      text: rule == null || rule.discountPercent == 0
          ? ''
          : rule.discountPercent.toStringAsFixed(2),
    );
    _fixedPriceController = TextEditingController(
      text: rule?.fixedPrice == null
          ? ''
          : rule!.fixedPrice!.toStringAsFixed(2),
    );
    _priority = rule?.priority ?? 100;
    _enforceRuleTypeCompatibility();
    _productSearchFocusNode = FocusNode();
    _productSearchFocusNode.addListener(() {
      if (_productSearchFocusNode.hasFocus) {
        _refreshProductSearchOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          if (_isSelectingProductFromOverlay) return;
          if (!_productSearchFocusNode.hasFocus) {
            _hideProductSearchOverlay();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _fixedPriceController.dispose();
    _productSearchFocusNode.dispose();
    _hideProductSearchOverlay();
    _hideCategoryOverlay();
    super.dispose();
  }

  Product? _findProduct(String? barcode) {
    if (barcode == null || barcode.trim().isEmpty) return null;
    for (final product in widget.products) {
      if (product.barcode == barcode) return product;
    }
    final rule = widget.rule;
    if (rule == null || rule.barcode == null) return null;
    return Product(
      barcode: rule.barcode!,
      name: rule.productNameSnapshot ?? rule.barcode!,
      sellingPrice: rule.fixedPrice ?? 0,
      stock: 0,
      updatedAt: rule.updatedAt,
    );
  }

  void _showMessage(String message, {Color color = _warning}) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _money(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

  List<Product> get _filteredProductSearchResults {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return widget.products
        .where(
          (product) =>
              product.name.toLowerCase().contains(query) ||
              product.barcode.toLowerCase().contains(query) ||
              product.category.toLowerCase().contains(query),
        )
        .take(20)
        .toList();
  }

  double get _productSearchOverlayWidth {
    final box =
        _productSearchFieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 280;
  }

  double get _categoryOverlayWidth {
    final box =
        _categoryFieldKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.width ?? 280;
  }

  void _refreshProductSearchOverlay() {
    final query = _searchController.text.trim();
    if (!mounted || !_productSearchFocusNode.hasFocus || query.isEmpty) {
      _hideProductSearchOverlay();
      return;
    }

    if (_productSearchOverlay == null) {
      _productSearchOverlay = OverlayEntry(
        builder: (context) => _buildProductSearchOverlay(),
      );
      Overlay.of(context, rootOverlay: true).insert(_productSearchOverlay!);
    } else {
      _productSearchOverlay!.markNeedsBuild();
    }
  }

  void _hideProductSearchOverlay() {
    _productSearchOverlay?.remove();
    _productSearchOverlay = null;
  }

  void _toggleCategoryOverlay() {
    if (_categoryOverlay != null) {
      _hideCategoryOverlay();
      return;
    }
    _showCategoryOverlay();
  }

  void _showCategoryOverlay() {
    if (!mounted) return;
    _hideProductSearchOverlay();
    _categoryOverlay = OverlayEntry(
      builder: (context) => _buildCategoryOverlay(),
    );
    Overlay.of(context, rootOverlay: true).insert(_categoryOverlay!);
  }

  void _hideCategoryOverlay() {
    _categoryOverlay?.remove();
    _categoryOverlay = null;
  }

  Widget _buildProductSearchOverlay() {
    final products = _filteredProductSearchResults;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideProductSearchOverlay,
          ),
          CompositedTransformFollower(
            link: _productSearchLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 4),
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _productSearchOverlayWidth,
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF12233A) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2A3A52)
                          : const Color(0xFFD9E3EE),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.30 : 0.12,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: products.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'No matching products found.',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: products.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 2),
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                leading: const Icon(Icons.inventory_2_rounded),
                                title: Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${product.barcode} - ${product.category}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () {
                                  _isSelectingProductFromOverlay = true;
                                  setState(() {
                                    _product = product;
                                    _searchController.clear();
                                  });
                                  _hideProductSearchOverlay();
                                  Future.delayed(
                                    const Duration(milliseconds: 140),
                                    () =>
                                        _isSelectingProductFromOverlay = false,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideCategoryOverlay,
          ),
          CompositedTransformFollower(
            link: _categoryLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 4),
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _categoryOverlayWidth,
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF12233A) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2A3A52)
                          : const Color(0xFFD9E3EE),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.30 : 0.12,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: widget.categories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final category = widget.categories[index];
                        final selected = _category == category;
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          title: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: _brand,
                                  size: 18,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _category = category;
                            });
                            _hideCategoryOverlay();
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _enforceRuleTypeCompatibility() {
    if (!_allowFixedPrice && _ruleType == PricingSchemeRuleType.fixedPrice) {
      _ruleType = PricingSchemeRuleType.priceType;
      _fixedPriceController.clear();
    }
  }

  PricingSchemeRule? get _conflictingSpecificProductRule {
    if (!_isSpecificProductTarget || _product == null) return null;
    final currentId = widget.rule?.id;
    for (final existing in widget.existingRules) {
      if (existing.applyTo != PricingSchemeRuleApplyTo.product) continue;
      if ((existing.barcode ?? '').trim() != _product!.barcode.trim()) continue;
      if (currentId != null && existing.id == currentId) continue;
      return existing;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_applyTo == PricingSchemeRuleApplyTo.category &&
        (_category == null || _category!.trim().isEmpty)) {
      _showMessage('Select a product category.');
      return;
    }
    if (_applyTo == PricingSchemeRuleApplyTo.product && _product == null) {
      _showMessage('Select a product.');
      return;
    }

    final discount = _discountController.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_discountController.text.trim());
    if (_ruleType == PricingSchemeRuleType.percentDiscount &&
        (discount == null || discount < 0 || discount > 100)) {
      _showMessage('Discount must be between 0 and 100.');
      return;
    }

    final fixedPrice = _fixedPriceController.text.trim().isEmpty
        ? null
        : double.tryParse(_fixedPriceController.text.trim());
    if (_ruleType == PricingSchemeRuleType.fixedPrice &&
        (fixedPrice == null || fixedPrice < 0)) {
      _showMessage('Fixed price must be zero or higher.');
      return;
    }

    int? overwriteRuleId;
    final conflictingRule = _conflictingSpecificProductRule;
    if (conflictingRule != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace Existing Product Rule?'),
          content: Text(
            'A rule already exists for ${_product?.name ?? 'this product'}. Saving now will replace that existing rule. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Replace Rule'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
      overwriteRuleId = conflictingRule.id;
    }

    Navigator.of(context).pop(
      PricingSchemeRuleDialogResult(
        applyTo: _applyTo,
        category: _applyTo == PricingSchemeRuleApplyTo.category
            ? _category
            : null,
        product: _applyTo == PricingSchemeRuleApplyTo.product ? _product : null,
        ruleType: _ruleType,
        priceType: _ruleType == PricingSchemeRuleType.priceType
            ? _priceType
            : null,
        discountPercent: _ruleType == PricingSchemeRuleType.percentDiscount
            ? discount ?? 0.0
            : 0.0,
        fixedPrice: _ruleType == PricingSchemeRuleType.fixedPrice
            ? fixedPrice
            : null,
        priority: _priority,
        isActive: _isActive,
        note: widget.rule?.note,
        overwriteRuleId: overwriteRuleId,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelSoft = isDark
        ? const Color(0xFF14243C)
        : const Color(0xFFF8FAFD);
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: panelSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF0F1C31) : Colors.white;
    final panelSoft = isDark
        ? const Color(0xFF14243C)
        : const Color(0xFFF8FAFD);
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
    final textPrimary = isDark
        ? const Color(0xFFF4F8FF)
        : const Color(0xFF14263B);
    final textSecondary = isDark
        ? const Color(0xFF9DB0C8)
        : const Color(0xFF667A92);
    final availableHeight = MediaQuery.of(context).size.height - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1220,
          maxHeight: availableHeight < 520 ? 520 : availableHeight,
        ),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(textPrimary, textSecondary, isDark),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isEdit)
                        _lockedTargetPanel(
                          panelSoft,
                          border,
                          textPrimary,
                          textSecondary,
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 940) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _targetPanel(panelSoft, border),
                                  const SizedBox(height: 12),
                                  _rulePanel(panelSoft, border),
                                ],
                              );
                            }
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _targetPanel(panelSoft, border),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _rulePanel(panelSoft, border),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      if (_isEdit) const SizedBox(height: 12),
                      if (_isEdit) _rulePanel(panelSoft, border),
                      const SizedBox(height: 16),
                      _activeSwitch(
                        panelSoft,
                        border,
                        textPrimary,
                        textSecondary,
                      ),
                      const SizedBox(height: 18),
                      _previewPanel(
                        panelSoft,
                        border,
                        textPrimary,
                        textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_isEdit ? 'Save Rule' : 'Add Rule'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Color textPrimary, Color textSecondary, bool isDark) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _brand.withValues(alpha: 0.24)),
          ),
          child: const Icon(Icons.rule_rounded, color: _brand, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit
                    ? 'Edit ${widget.titleNoun}'
                    : 'Add ${widget.titleNoun}',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Set what this rule applies to and how pricing should behave.',
                style: TextStyle(
                  color: textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _targetPanel(Color panelSoft, Color border) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Applies To',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: PricingSchemeRuleApplyTo.values
                .map(
                  (value) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _applyToChoiceCard(
                        value: value,
                        selected: _applyTo == value,
                        onTap: () => setState(() {
                          _applyTo = value;
                          _hideCategoryOverlay();
                          _hideProductSearchOverlay();
                          _enforceRuleTypeCompatibility();
                        }),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          if (_applyTo == PricingSchemeRuleApplyTo.category)
            _categoryPicker()
          else if (_applyTo == PricingSchemeRuleApplyTo.product)
            _productPicker()
          else
            const Text(
              'This rule applies to all products unless a more specific rule overrides it.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          if (_conflictingSpecificProductRule != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warning.withValues(alpha: 0.30)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: _warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This product already has a rule. Saving will replace it after confirmation.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lockedTargetPanel(
    Color panelSoft,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.30)),
            ),
            child: const Icon(Icons.lock_rounded, color: _brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rule Target (Locked)',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _targetSummary(),
                  style: TextStyle(
                    color: textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyToChoiceCard({
    required PricingSchemeRuleApplyTo value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
    final bg = selected
        ? _brand.withValues(alpha: isDark ? 0.20 : 0.12)
        : Colors.transparent;
    final outline = selected
        ? _brand.withValues(alpha: 0.40)
        : border.withValues(alpha: 0.9);
    final textColor = selected
        ? _brand
        : (isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B));

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productPicker() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final selected = _product;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompositedTransformTarget(
          link: _productSearchLayerLink,
          child: TextField(
            key: _productSearchFieldKey,
            controller: _searchController,
            focusNode: _productSearchFocusNode,
            decoration: _inputDecoration(
              label: 'Search product',
              icon: Icons.search_rounded,
              hint: 'Name, barcode, or category',
            ),
            onChanged: (_) {
              setState(() {});
              _refreshProductSearchOverlay();
            },
            onTap: _refreshProductSearchOverlay,
          ),
        ),
        const SizedBox(height: 8),
        if (selected != null)
          _selectedProductCard(selected)
        else if (!hasQuery)
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _selectedProductCard(Product product) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: const Icon(Icons.inventory_2_rounded, color: _brand),
      title: Text(product.name),
      subtitle: Text('${product.barcode} - ${product.category}'),
      trailing: TextButton(
        onPressed: () {
          setState(() {
            _product = null;
          });
        },
        child: const Text('Change'),
      ),
    );
  }

  Widget _categoryPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final value = (_category == null || _category!.trim().isEmpty)
        ? 'Select category'
        : _category!;
    final textColor = (_category == null || _category!.trim().isEmpty)
        ? (isDark ? const Color(0xFF94A7BE) : const Color(0xFF6C829C))
        : (isDark ? const Color(0xFFEAF1FB) : const Color(0xFF163250));

    return CompositedTransformTarget(
      link: _categoryLayerLink,
      child: InkWell(
        key: _categoryFieldKey,
        borderRadius: BorderRadius.circular(16),
        onTap: _toggleCategoryOverlay,
        child: InputDecorator(
          decoration: _inputDecoration(
            label: 'Product category',
            icon: Icons.category_rounded,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rulePanel(Color panelSoft, Color border) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Price Rule',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<PricingSchemeRuleType>(
            initialValue: _availableRuleTypes.contains(_ruleType)
                ? _ruleType
                : _availableRuleTypes.first,
            decoration: _inputDecoration(
              label: 'Rule type',
              icon: Icons.tune_rounded,
            ),
            items: _availableRuleTypes
                .map(
                  (type) => DropdownMenuItem<PricingSchemeRuleType>(
                    value: type,
                    child: Text(type.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _ruleType = value;
              });
            },
          ),
          const SizedBox(height: 14),
          if (_ruleType == PricingSchemeRuleType.priceType)
            DropdownButtonFormField<ProductPriceType>(
              initialValue: _priceType,
              decoration: _inputDecoration(
                label: 'Price type',
                icon: Icons.sell_rounded,
              ),
              items: ProductPriceType.values
                  .map(
                    (type) => DropdownMenuItem<ProductPriceType>(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _priceType = value;
                });
              },
            )
          else if (_ruleType == PricingSchemeRuleType.percentDiscount)
            TextField(
              controller: _discountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: _inputDecoration(
                label: 'Discount percent',
                icon: Icons.percent_rounded,
                hint: 'Example: 5',
              ),
              onChanged: (_) => setState(() {}),
            )
          else if (_ruleType == PricingSchemeRuleType.fixedPrice)
            TextField(
              controller: _fixedPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: _inputDecoration(
                label: 'Fixed price',
                icon: Icons.price_change_rounded,
              ),
              onChanged: (_) => setState(() {}),
            )
          else
            const Text(
              'No discount keeps the matching item on normal/default pricing and blocks discount rules.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  Widget _previewPanel(
    Color panelSoft,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final product =
        _product ?? (widget.products.isEmpty ? null : widget.products.first);
    final normalPrice = product?.sellingPrice ?? 0.0;
    final newPrice = product == null ? 0.0 : _previewPrice(product);
    final difference = newPrice - normalPrice;
    final hasPreview = product != null;
    final targetSummary = _targetSummary();
    final effectSummary = _ruleEffectDescription();
    final currentRuleDetails = _currentAppliedRuleDetails();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_rounded, color: _blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rule Description',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (hasPreview)
                Text(
                  difference == 0 ? 'No change' : _money(difference.abs()),
                  style: TextStyle(
                    color: difference <= 0 ? _brand : _warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Applies to: $targetSummary',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            effectSummary,
            style: TextStyle(
              color: textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          if (hasPreview) ...[
            const SizedBox(height: 6),
            Text(
              'Preview on ${product.name}: ${_money(normalPrice)} -> ${_money(newPrice)}',
              style: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          if (_isEdit && currentRuleDetails != null) ...[
            const SizedBox(height: 8),
            Text(
              currentRuleDetails,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _ruleEffectDescription() {
    switch (_ruleType) {
      case PricingSchemeRuleType.priceType:
        return 'Matching items use "${_priceType.label}" as the final selling price.';
      case PricingSchemeRuleType.percentDiscount:
        final discount =
            double.tryParse(_discountController.text.trim()) ?? 0.0;
        return 'Matching items get ${discount.toStringAsFixed(2)}% off from their selling price.';
      case PricingSchemeRuleType.fixedPrice:
        final fixed = double.tryParse(_fixedPriceController.text.trim());
        if (fixed == null) {
          return 'Matching item price will be forced to a fixed value once entered.';
        }
        return 'Matching item price is forced to ${_money(fixed)} regardless of normal/sale/wholesale values.';
      case PricingSchemeRuleType.noDiscount:
        return 'Discounting is blocked for matching items, so they remain on default pricing.';
    }
  }

  String? _currentAppliedRuleDetails() {
    final rule = widget.rule;
    if (rule == null) return null;

    String detail =
        'Current saved rule: ${rule.applyTo.label} -> ${rule.ruleType.label}';
    if (rule.ruleType == PricingSchemeRuleType.priceType &&
        rule.priceType != null) {
      detail += ' (${rule.priceType!.label})';
    } else if (rule.ruleType == PricingSchemeRuleType.percentDiscount) {
      detail += ' (${rule.discountPercent.toStringAsFixed(2)}%)';
    } else if (rule.ruleType == PricingSchemeRuleType.fixedPrice &&
        rule.fixedPrice != null) {
      detail += ' (${_money(rule.fixedPrice!)})';
    }
    detail += rule.isActive ? ' [Active]' : ' [Inactive]';
    return detail;
  }

  double _previewPrice(Product product) {
    switch (_ruleType) {
      case PricingSchemeRuleType.priceType:
        return product.resolvePrice(_priceType);
      case PricingSchemeRuleType.percentDiscount:
        final discount =
            double.tryParse(_discountController.text.trim()) ?? 0.0;
        return product.sellingPrice - (product.sellingPrice * (discount / 100));
      case PricingSchemeRuleType.fixedPrice:
        return double.tryParse(_fixedPriceController.text.trim()) ??
            product.sellingPrice;
      case PricingSchemeRuleType.noDiscount:
        return product.sellingPrice;
    }
  }

  Widget _activeSwitch(
    Color panelSoft,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: SwitchListTile(
        value: _isActive,
        contentPadding: EdgeInsets.zero,
        activeThumbColor: _brand,
        title: Text(
          'Active rule',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          _isActive
              ? 'Rule can apply in the scheme.'
              : 'Rule is saved inactive.',
          style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600),
        ),
        onChanged: (value) {
          setState(() {
            _isActive = value;
          });
        },
      ),
    );
  }
}
