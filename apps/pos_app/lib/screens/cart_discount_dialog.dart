import 'package:flutter/material.dart';

import '../widgets/premium_dialog.dart';

Future<Map<String, dynamic>?> showCartDiscountDialog(
  BuildContext context, {
  required double subtotal,
  required String currentDiscountType,
  required double currentDiscountValue,
  String title = 'Apply Discount',
  String amountLabel = 'Subtotal',
  String totalLabel = 'Total After Discount',
  String applyLabel = 'Apply',
}) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  const brand = Color(0xFF2FBF9F);
  const danger = Color(0xFFFF6B6B);
  const warning = Color(0xFFF5B942);
  final bg = isDark ? const Color(0xFF081221) : Colors.white;
  final surface = isDark ? const Color(0xFF0F1B2D) : const Color(0xFFF6F9FC);
  final surfaceAlt =
      isDark ? const Color(0xFF14233A) : const Color(0xFFEFF4FB);
  final border = isDark ? const Color(0xFF23344E) : const Color(0xFFD9E3F0);
  final textPrimary = isDark ? Colors.white : const Color(0xFF122033);
  final textSecondary =
      isDark ? const Color(0xFF9FB0C8) : const Color(0xFF607089);

  final valueController = TextEditingController(
    text: currentDiscountType == 'none'
        ? ''
        : currentDiscountValue.toStringAsFixed(
            currentDiscountValue % 1 == 0 ? 0 : 2,
          ),
  );

  String selectedType = currentDiscountType == 'none'
      ? 'percent'
      : currentDiscountType;
  String? errorText;

  double calculateDiscountAmount({
    required double subtotal,
    required String type,
    required double value,
  }) {
    if (subtotal <= 0) return 0.0;

    if (type == 'fixed') {
      final double safe = value < 0 ? 0.0 : value;
      return safe > subtotal ? subtotal : safe;
    }

    if (type == 'percent') {
      final double safe = value < 0 ? 0.0 : value;
      final double capped = safe > 100.0 ? 100.0 : safe;
      return subtotal * (capped / 100.0);
    }

    return 0.0;
  }

  final result = await showPremiumDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final enteredValue =
              double.tryParse(valueController.text.trim()) ?? 0.0;
          final sanitizedPreviewValue = selectedType == 'fixed'
              ? enteredValue.clamp(0.0, subtotal)
              : selectedType == 'percent'
                  ? enteredValue.clamp(0.0, 100.0)
                  : 0.0;
          final discountAmount = calculateDiscountAmount(
            subtotal: subtotal,
            type: selectedType,
            value: sanitizedPreviewValue,
          );
          final total = subtotal - discountAmount;
          final canClear = selectedType != 'none';

          InputDecoration fieldDecoration({
            required String label,
            String? prefixText,
            String? suffixText,
            String? helperText,
            String? errorText,
          }) {
            return InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w700,
              ),
              prefixText: prefixText,
              suffixText: suffixText,
              helperText: helperText,
              helperStyle: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
              errorText: errorText,
              filled: true,
              fillColor: bg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: brand, width: 1.4),
              ),
              errorBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: danger),
              ),
              focusedErrorBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: danger, width: 1.4),
              ),
            );
          }

          Widget buildModeButton({
            required String label,
            required String value,
            required IconData icon,
          }) {
            final selected = selectedType == value;
            final activeColor = value == 'none' ? warning : brand;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    selectedType = value;
                    if (value == 'none') {
                      valueController.clear();
                    }
                    errorText = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? activeColor.withOpacity(isDark ? 0.16 : 0.12)
                        : surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? activeColor : border,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected ? activeColor : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? activeColor : textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget buildSummaryTile({
            required String label,
            required String value,
            required Color valueColor,
          }) {
            return Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      style: TextStyle(
                        color: valueColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 540),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.34 : 0.10),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: brand.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.discount_rounded,
                            color: brand,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Apply a fixed amount or percentage discount.',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: surfaceAlt,
                            foregroundColor: textSecondary,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            amountLabel.toUpperCase(),
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Rs. ${subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: brand,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Discount Type',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        buildModeButton(
                          label: 'None',
                          value: 'none',
                          icon: Icons.block_rounded,
                        ),
                        const SizedBox(width: 10),
                        buildModeButton(
                          label: 'Fixed',
                          value: 'fixed',
                          icon: Icons.sell_outlined,
                        ),
                        const SizedBox(width: 10),
                        buildModeButton(
                          label: 'Percent',
                          value: 'percent',
                          icon: Icons.percent_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: valueController,
                            autofocus: selectedType != 'none',
                            enabled: selectedType != 'none',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: fieldDecoration(
                              label: selectedType == 'percent'
                                  ? 'Discount Percentage'
                                  : 'Discount Amount',
                              prefixText:
                                  selectedType == 'fixed' ? 'Rs. ' : null,
                              suffixText:
                                  selectedType == 'percent' ? '%' : null,
                              helperText: selectedType == 'percent'
                                  ? 'Maximum 100%'
                                  : 'Cannot exceed subtotal',
                              errorText: errorText,
                            ),
                            onChanged: (_) {
                              setState(() {
                                errorText = null;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: (selectedType == 'percent'
                                    ? const <(String, double)>[
                                        ('5%', 5),
                                        ('10%', 10),
                                        ('15%', 15),
                                        ('25%', 25),
                                      ]
                                    : <(String, double)>[
                                        ('Rs. 50', 50),
                                        ('Rs. 100', 100),
                                        ('Rs. 250', 250),
                                        ('Rs. 500', 500),
                                      ])
                                .map((entry) {
                                  final label = entry.$1;
                                  final value = entry.$2;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: selectedType == 'none'
                                        ? null
                                        : () {
                                            valueController.text = value
                                                .toStringAsFixed(
                                                  value % 1 == 0 ? 0 : 2,
                                                );
                                            setState(() {
                                              errorText = null;
                                            });
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: surfaceAlt,
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: border),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: selectedType == 'none'
                                              ? textSecondary.withOpacity(0.55)
                                              : textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        buildSummaryTile(
                          label: 'Discount',
                          value: 'Rs. ${discountAmount.toStringAsFixed(2)}',
                          valueColor: discountAmount > 0 ? danger : textPrimary,
                        ),
                        const SizedBox(width: 10),
                        buildSummaryTile(
                          label: totalLabel,
                          value: 'Rs. ${total.toStringAsFixed(2)}',
                          valueColor: brand,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(color: border),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final rawText = valueController.text.trim();
                              final parsedValue = rawText.isEmpty
                                  ? 0.0
                                  : double.tryParse(rawText);

                              if (selectedType != 'none' && parsedValue == null) {
                                setState(() {
                                  errorText = 'Enter a valid discount value.';
                                });
                                return;
                              }

                              final safeValue = parsedValue ?? 0.0;
                              if (safeValue < 0) {
                                setState(() {
                                  errorText = 'Discount cannot be negative.';
                                });
                                return;
                              }

                              final normalizedValue = selectedType == 'fixed'
                                  ? safeValue.clamp(0.0, subtotal)
                                  : selectedType == 'percent'
                                      ? safeValue.clamp(0.0, 100.0)
                                      : 0.0;

                              Navigator.pop(context, {
                                'discount_type': selectedType,
                                'discount_value': selectedType == 'none'
                                    ? 0.0
                                    : normalizedValue.toDouble(),
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            icon: Icon(
                              canClear
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.auto_awesome_rounded,
                            ),
                            label: Text(
                              applyLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
        },
      );
    },
  );

  valueController.dispose();
  return result;
}
