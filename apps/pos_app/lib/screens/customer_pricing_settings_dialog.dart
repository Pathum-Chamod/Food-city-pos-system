import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/shared.dart';

import '../services/customer_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

Future<bool> showCustomerPricingSettingsDialog({
  required BuildContext context,
  required Customer customer,
  int? actorUserId,
}) {
  return showPremiumDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CustomerPricingSettingsDialog(
      customer: customer,
      actorUserId: actorUserId,
    ),
  ).then((value) => value ?? false);
}

class _CustomerPricingSettingsDialog extends StatefulWidget {
  const _CustomerPricingSettingsDialog({
    required this.customer,
    this.actorUserId,
  });

  final Customer customer;
  final int? actorUserId;

  @override
  State<_CustomerPricingSettingsDialog> createState() =>
      _CustomerPricingSettingsDialogState();
}

class _CustomerPricingSettingsDialogState
    extends State<_CustomerPricingSettingsDialog> {
  late final TextEditingController _discountController;
  late final TextEditingController _noteController;
  late bool _pricingEnabled;
  late ProductPriceType _defaultPriceType;
  bool _isSaving = false;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _warning = Color(0xFFFFB65C);

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _pricingEnabled = customer.pricingEnabled;
    _defaultPriceType = customer.defaultPriceType;
    _discountController = TextEditingController(
      text: customer.normalizedDefaultDiscountPercent == 0
          ? ''
          : customer.normalizedDefaultDiscountPercent.toStringAsFixed(2),
    );
    _noteController = TextEditingController(text: customer.pricingNote ?? '');
  }

  @override
  void dispose() {
    _discountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {Color color = _warning}) {
    if (!mounted) return;
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final rawDiscount = _discountController.text.trim();
    final discount = rawDiscount.isEmpty ? 0.0 : double.tryParse(rawDiscount);
    if (discount == null || discount < 0 || discount > 100) {
      _showMessage('Discount must be between 0 and 100.');
      return;
    }

    final customerId = widget.customer.id;
    if (customerId == null || customerId <= 0) {
      _showMessage('Customer is not saved yet.', color: _danger);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await CustomerService.instance.updateCustomerPricingSettings(
        customerId: customerId,
        pricingEnabled: _pricingEnabled,
        defaultPriceType: _defaultPriceType.dbValue,
        defaultDiscountPercent: discount,
        pricingNote: _noteController.text.trim(),
        updatedBy: widget.actorUserId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      final message = e.toString().replaceFirst('Exception: ', '');
      _showMessage(message, color: _danger);
    }
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
          maxWidth: 620,
          maxHeight: availableHeight < 420 ? 420 : availableHeight,
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
            mainAxisSize: MainAxisSize.min,
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
                      Icons.local_offer_rounded,
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
                          'Pricing Settings',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.customer.displayCode} - ${widget.customer.displayName}',
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                          value: _pricingEnabled,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Enable customer pricing',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            _pricingEnabled
                                ? 'Customer pricing rules can apply in POS.'
                                : 'POS uses normal selected price mode.',
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          activeThumbColor: _brand,
                          inactiveThumbColor: _danger,
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    _pricingEnabled = value;
                                  });
                                },
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<ProductPriceType>(
                        initialValue: _defaultPriceType,
                        decoration: _inputDecoration(
                          label: 'Default price type',
                          icon: Icons.sell_rounded,
                        ),
                        items: ProductPriceType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _defaultPriceType = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _discountController,
                        enabled: !_isSaving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: _inputDecoration(
                          label: 'Default discount percent',
                          icon: Icons.percent_rounded,
                          hint: '0 to 100',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteController,
                        enabled: !_isSaving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _inputDecoration(
                          label: 'Pricing note',
                          icon: Icons.note_alt_rounded,
                          hint: 'Optional owner note',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
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
}
