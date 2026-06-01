import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/language_provider.dart';
import '../utils/product_name_helper.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

class CustomerProductPriceDialogResult {
  const CustomerProductPriceDialogResult({
    required this.product,
    required this.fixedPrice,
    required this.isActive,
    this.note,
  });

  final Product product;
  final double fixedPrice;
  final bool isActive;
  final String? note;
}

Future<CustomerProductPriceDialogResult?> showCustomerProductPriceDialog({
  required BuildContext context,
  required List<Product> products,
  CustomerProductPrice? existingPrice,
}) {
  return showPremiumDialog<CustomerProductPriceDialogResult?>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CustomerProductPriceDialog(
      products: products,
      existingPrice: existingPrice,
    ),
  );
}

class _CustomerProductPriceDialog extends StatefulWidget {
  const _CustomerProductPriceDialog({
    required this.products,
    this.existingPrice,
  });

  final List<Product> products;
  final CustomerProductPrice? existingPrice;

  @override
  State<_CustomerProductPriceDialog> createState() =>
      _CustomerProductPriceDialogState();
}

class _CustomerProductPriceDialogState
    extends State<_CustomerProductPriceDialog> {
  late final TextEditingController _searchController;
  late final TextEditingController _priceController;
  late final TextEditingController _noteController;
  Product? _selectedProduct;
  bool _isActive = true;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _warning = Color(0xFFFFB65C);

  bool get _isEdit => widget.existingPrice != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPrice;
    _selectedProduct = existing == null
        ? null
        : _findProduct(existing.barcode) ??
              Product(
                barcode: existing.barcode,
                name: existing.productNameSnapshot,
                sellingPrice: existing.fixedPrice,
                stock: 0,
                updatedAt: existing.updatedAt,
              );
    _isActive = existing?.isActive ?? true;
    _searchController = TextEditingController();
    _priceController = TextEditingController(
      text: existing == null ? '' : existing.fixedPrice.toStringAsFixed(2),
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Product? _findProduct(String barcode) {
    for (final product in widget.products) {
      if (product.barcode == barcode) return product;
    }
    return null;
  }

  void _showMessage(String message, {Color color = _warning}) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  String? _cleanOptional(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  void _submit() {
    final product = _selectedProduct;
    if (product == null) {
      _showMessage('Select a product first.');
      return;
    }

    final rawPrice = _priceController.text.trim();
    final fixedPrice = double.tryParse(rawPrice);
    if (fixedPrice == null || fixedPrice < 0) {
      _showMessage('Enter a valid customer price.');
      return;
    }

    Navigator.of(context).pop(
      CustomerProductPriceDialogResult(
        product: product,
        fixedPrice: fixedPrice,
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
    final query = _searchController.text.trim();
    final queryLower = query.toLowerCase();
    final products = query.isEmpty
        ? widget.products.take(20).toList()
        : widget.products
              .where(
                (product) =>
                    ProductNameHelper.matchesProduct(product, query) ||
                    product.category.toLowerCase().contains(queryLower),
              )
              .take(30)
              .toList();
    final selected = _selectedProduct;
    final enteredPrice = double.tryParse(_priceController.text.trim());
    final difference = selected == null || enteredPrice == null
        ? 0.0
        : enteredPrice - selected.sellingPrice;
    final availableHeight = MediaQuery.of(context).size.height - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: availableHeight < 460 ? 460 : availableHeight,
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
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _brand.withValues(alpha: isDark ? 0.16 : 0.10),
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
                          _isEdit
                              ? 'Edit Specific Product Price'
                              : 'Add Specific Product Price',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isEdit
                              ? 'Update this customer-specific fixed price.'
                              : 'Select a product and set the customer-specific fixed price.',
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
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _searchController,
                            enabled: !_isEdit,
                            decoration: _inputDecoration(
                              label: 'Search product',
                              icon: Icons.search_rounded,
                              hint: 'Name, barcode, or category',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: panelSoft,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                              ),
                              child: _isEdit
                                  ? _selectedProductTile(
                                      selected,
                                      textPrimary,
                                      textSecondary,
                                    )
                                  : products.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No products found.',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: products.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 6),
                                      itemBuilder: (context, index) {
                                        final product = products[index];
                                        final isSelected =
                                            selected?.barcode ==
                                            product.barcode;
                                        return _productTile(
                                          product,
                                          isSelected,
                                          textPrimary,
                                          textSecondary,
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (selected != null)
                              _pricePreview(
                                selected,
                                enteredPrice,
                                difference,
                                panelSoft,
                                border,
                                textPrimary,
                                textSecondary,
                              ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              decoration: _inputDecoration(
                                label: 'Customer-specific fixed price',
                                icon: Icons.sell_rounded,
                                hint: 'Example: 1760.00',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (selected != null &&
                                enteredPrice != null &&
                                enteredPrice > selected.sellingPrice) ...[
                              const SizedBox(height: 10),
                              Text(
                                'This customer price is higher than the normal selling price.',
                                style: TextStyle(
                                  color: _warning,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
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
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: panelSoft,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                              ),
                              child: SwitchListTile(
                                value: _isActive,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Active price',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  _isActive
                                      ? 'This price can apply to new sales.'
                                      : 'This rule is saved but inactive.',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                activeThumbColor: _brand,
                                inactiveThumbColor: _danger,
                                onChanged: (value) {
                                  setState(() {
                                    _isActive = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(
                        _isEdit ? 'Save Price' : 'Add Specific Price',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedProductTile(
    Product? product,
    Color textPrimary,
    Color textSecondary,
  ) {
    if (product == null) {
      return Center(
        child: Text(
          'Product snapshot not available.',
          style: TextStyle(color: textSecondary, fontWeight: FontWeight.w700),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [_productTile(product, true, textPrimary, textSecondary)],
    );
  }

  Widget _productTile(
    Product product,
    bool isSelected,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Material(
      color: isSelected ? _brand.withValues(alpha: 0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isEdit
            ? null
            : () {
                setState(() {
                  _selectedProduct = product;
                  if (_priceController.text.trim().isEmpty) {
                    _priceController.text = product.sellingPrice
                        .toStringAsFixed(2);
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.inventory_2_rounded,
                color: isSelected ? _brand : textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductNameHelper.displayName(
                        product,
                        context.read<LanguageProvider>().language,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${product.barcode} - ${product.category}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _money(product.sellingPrice),
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pricePreview(
    Product product,
    double? enteredPrice,
    double difference,
    Color panelSoft,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final fixed = enteredPrice;
    final savings = fixed == null ? 0.0 : product.sellingPrice - fixed;

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
          _previewLine('Selling', _money(product.sellingPrice), textSecondary),
          const SizedBox(height: 7),
          _previewLine(
            'Wholesale',
            _money(product.resolvePrice(ProductPriceType.wholesale)),
            textSecondary,
          ),
          const SizedBox(height: 7),
          _previewLine(
            'Sale',
            product.hasSalePrice
                ? _money(product.resolvePrice(ProductPriceType.sale))
                : 'Not active',
            textSecondary,
          ),
          const Divider(height: 22),
          _previewLine(
            'Specific price',
            fixed == null ? '-' : _money(fixed),
            textPrimary,
          ),
          const SizedBox(height: 7),
          _previewLine(
            savings >= 0 ? 'Customer saves' : 'Price difference',
            fixed == null ? '-' : _money(savings.abs()),
            savings >= 0 ? _brand : _warning,
          ),
          const SizedBox(height: 7),
          _previewLine(
            'Change vs selling',
            fixed == null ? '-' : _money(difference),
            difference <= 0 ? _brand : _warning,
          ),
        ],
      ),
    );
  }

  Widget _previewLine(String label, String value, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
