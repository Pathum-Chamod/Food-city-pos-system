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
}

Future<PricingSchemeRuleDialogResult?> showPricingSchemeRuleDialog({
  required BuildContext context,
  required List<Product> products,
  required List<String> categories,
  PricingSchemeRule? rule,
}) {
  return showPremiumDialog<PricingSchemeRuleDialogResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _PricingSchemeRuleDialog(
      products: products,
      categories: categories,
      rule: rule,
    ),
  );
}

class _PricingSchemeRuleDialog extends StatefulWidget {
  const _PricingSchemeRuleDialog({
    required this.products,
    required this.categories,
    this.rule,
  });

  final List<Product> products;
  final List<String> categories;
  final PricingSchemeRule? rule;

  @override
  State<_PricingSchemeRuleDialog> createState() =>
      _PricingSchemeRuleDialogState();
}

class _PricingSchemeRuleDialogState extends State<_PricingSchemeRuleDialog> {
  late final TextEditingController _searchController;
  late final TextEditingController _discountController;
  late final TextEditingController _fixedPriceController;
  late final TextEditingController _priorityController;
  late final TextEditingController _noteController;

  late PricingSchemeRuleApplyTo _applyTo;
  late PricingSchemeRuleType _ruleType;
  ProductPriceType _priceType = ProductPriceType.wholesale;
  String? _category;
  Product? _product;
  bool _isActive = true;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);

  bool get _isEdit => widget.rule != null;

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
    _priorityController = TextEditingController(
      text: (rule?.priority ?? 100).toString(),
    );
    _noteController = TextEditingController(text: rule?.note ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _fixedPriceController.dispose();
    _priorityController.dispose();
    _noteController.dispose();
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

  String? _cleanOptional(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  void _submit() {
    if (_applyTo == PricingSchemeRuleApplyTo.category &&
        (_category == null || _category!.trim().isEmpty)) {
      _showMessage('Select a product category.');
      return;
    }
    if (_applyTo == PricingSchemeRuleApplyTo.product && _product == null) {
      _showMessage('Select a product.');
      return;
    }

    final priority = int.tryParse(_priorityController.text.trim());
    if (priority == null) {
      _showMessage('Priority must be a whole number.');
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
        priority: priority,
        isActive: _isActive,
        note: _cleanOptional(_noteController.text),
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
          maxWidth: 860,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _targetPanel(panelSoft, border)),
                          const SizedBox(width: 14),
                          Expanded(child: _rulePanel(panelSoft, border)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _previewPanel(
                        panelSoft,
                        border,
                        textPrimary,
                        textSecondary,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _noteController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _inputDecoration(
                          label: 'Note',
                          icon: Icons.note_alt_rounded,
                          hint: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _activeSwitch(
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
                _isEdit ? 'Edit Scheme Rule' : 'Add Scheme Rule',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose what the rule applies to, then choose how price is calculated.',
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PricingSchemeRuleApplyTo>(
            segments: PricingSchemeRuleApplyTo.values
                .map(
                  (value) => ButtonSegment<PricingSchemeRuleApplyTo>(
                    value: value,
                    label: Text(value.label),
                  ),
                )
                .toList(),
            selected: {_applyTo},
            onSelectionChanged: (values) {
              setState(() {
                _applyTo = values.first;
              });
            },
          ),
          const SizedBox(height: 14),
          if (_applyTo == PricingSchemeRuleApplyTo.category)
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: _inputDecoration(
                label: 'Product category',
                icon: Icons.category_rounded,
              ),
              items: widget.categories
                  .map(
                    (category) => DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _category = value;
                });
              },
            )
          else if (_applyTo == PricingSchemeRuleApplyTo.product)
            _productPicker()
          else
            const Text(
              'This rule applies to every product unless a more specific rule wins.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  Widget _productPicker() {
    final query = _searchController.text.trim().toLowerCase();
    final products = query.isEmpty
        ? widget.products.take(12).toList()
        : widget.products
              .where(
                (product) =>
                    product.name.toLowerCase().contains(query) ||
                    product.barcode.toLowerCase().contains(query) ||
                    product.category.toLowerCase().contains(query),
              )
              .take(20)
              .toList();
    final selected = _product;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: _inputDecoration(
            label: 'Search product',
            icon: Icons.search_rounded,
            hint: 'Name, barcode, or category',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (selected != null)
          _selectedProductCard(selected)
        else
          SizedBox(
            height: 210,
            child: products.isEmpty
                ? const Center(child: Text('No matching products found.'))
                : ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: const Icon(Icons.inventory_2_rounded),
                        title: Text(product.name),
                        subtitle: Text(
                          '${product.barcode} - ${product.category}',
                        ),
                        onTap: () {
                          setState(() {
                            _product = product;
                          });
                        },
                      );
                    },
                  ),
          ),
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

  Widget _rulePanel(Color panelSoft, Color border) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<PricingSchemeRuleType>(
            initialValue: _ruleType,
            decoration: _inputDecoration(
              label: 'Rule type',
              icon: Icons.tune_rounded,
            ),
            items: PricingSchemeRuleType.values
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
          const SizedBox(height: 14),
          TextField(
            controller: _priorityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDecoration(
              label: 'Priority',
              icon: Icons.low_priority_rounded,
            ),
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_rounded, color: _blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              product == null
                  ? 'Preview appears after products exist.'
                  : '${product.name}: normal ${_money(normalPrice)} -> rule ${_money(newPrice)}',
              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            difference == 0 ? 'No change' : _money(difference.abs()),
            style: TextStyle(
              color: difference <= 0 ? _brand : _warning,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
