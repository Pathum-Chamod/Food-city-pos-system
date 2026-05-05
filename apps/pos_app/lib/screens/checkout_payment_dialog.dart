import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/premium_dialog.dart';

Future<Map<String, dynamic>?> showCheckoutPaymentDialog(
  BuildContext context, {
  required double totalAmount,
}) async {
  const brand = Color(0xFF2AAA8A);
  const danger = Color(0xFFE85D75);

  final amountController = TextEditingController(
    text: totalAmount.toStringAsFixed(2),
  );

  String selectedMethod = 'cash';
  double amountTendered = totalAmount;
  double changeAmount = 0.0;
  bool hasConfirmedPayment = false;
  bool replaceAmountOnNextEdit = true;

  void setAmountText(String value, {bool selectForReplacement = true}) {
    amountController.value = TextEditingValue(
      text: value,
      selection: selectForReplacement
          ? TextSelection(baseOffset: 0, extentOffset: value.length)
          : TextSelection.collapsed(offset: value.length),
    );
    replaceAmountOnNextEdit = selectForReplacement;
  }

  setAmountText(totalAmount.toStringAsFixed(2));

  void recalculate() {
    if (selectedMethod == 'cash') {
      amountTendered = double.tryParse(amountController.text.trim()) ?? 0.0;
      changeAmount = math.max(0, amountTendered - totalAmount);
    } else {
      amountTendered = totalAmount;
      changeAmount = 0.0;
    }
  }

  recalculate();

  final result = await showPremiumDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.26),
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          recalculate();
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          final bg = isDark ? const Color(0xFF091321) : const Color(0xFFF3F7FB);
          final surface = isDark ? const Color(0xFF0F1C2E) : Colors.white;
          final surfaceAlt =
              isDark ? const Color(0xFF15263F) : const Color(0xFFF7FAFD);
          final inputFill =
              isDark ? const Color(0xFF0C1728) : const Color(0xFFF2F6FA);
          final border = isDark
              ? Colors.white.withOpacity(0.08)
              : const Color(0xFFD8E2EC);
          final textPrimary =
              isDark ? const Color(0xFFF3F7FF) : const Color(0xFF1B2B44);
          final textSecondary =
              isDark ? const Color(0xFF97AAC6) : const Color(0xFF61758F);

          InputDecoration fieldDecoration({
            required String label,
            String? prefixText,
            String? helperText,
          }) {
            return InputDecoration(
              labelText: label,
              prefixText: prefixText,
              helperText: helperText,
              filled: true,
              fillColor: inputFill,
              labelStyle: TextStyle(color: textSecondary),
              helperStyle: TextStyle(color: textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: brand, width: 1.4),
              ),
            );
          }

          Widget buildMethodButton({
            required String label,
            required IconData icon,
            required String value,
          }) {
            final selected = selectedMethod == value;

            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    selectedMethod = value;
                    setAmountText(totalAmount.toStringAsFixed(2));
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? brand.withOpacity(isDark ? 0.16 : 0.12)
                        : inputFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? brand : border,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected ? brand : textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? brand : textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget buildInfoTile({
            required String label,
            required String value,
            required Color valueColor,
          }) {
            return Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: TextStyle(
                        color: valueColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final canConfirm =
              selectedMethod == 'card' || amountTendered >= totalAmount;

          Future<void> confirmPayment() async {
            if (!canConfirm || hasConfirmedPayment) return;

            hasConfirmedPayment = true;
            Navigator.pop(context, {
              'payment_method': selectedMethod,
              'amount_tendered':
                  selectedMethod == 'card' ? totalAmount : amountTendered,
              'change_amount': selectedMethod == 'card' ? 0.0 : changeAmount,
            });
          }

          final remainingAmount = math.max(0, totalAmount - amountTendered);

          return Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;

              final isEnterKey = event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;
              if (isEnterKey) {
                unawaited(confirmPayment());
                return KeyEventResult.handled;
              }

              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.pop(context);
                return KeyEventResult.handled;
              }

              return KeyEventResult.ignored;
            },
            child: Dialog(
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
                            Icons.point_of_sale_rounded,
                            color: brand,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Checkout Payment',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Complete the payment for this bill.',
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
                            'TOTAL DUE',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Rs. ${totalAmount.toStringAsFixed(2)}',
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
                      'Payment Method',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        buildMethodButton(
                          label: 'Cash',
                          icon: Icons.payments_outlined,
                          value: 'cash',
                        ),
                        const SizedBox(width: 10),
                        buildMethodButton(
                          label: 'Card',
                          icon: Icons.credit_card_rounded,
                          value: 'card',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (selectedMethod == 'cash') ...[
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
                              controller: amountController,
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: fieldDecoration(
                                label: 'Amount Tendered',
                                prefixText: 'Rs. ',
                                helperText: 'Enter the cash received from customer.',
                              ),
                              onTap: () {
                                if (!replaceAmountOnNextEdit) return;
                                amountController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: amountController.text.length,
                                );
                              },
                              onChanged: (_) {
                                replaceAmountOnNextEdit = false;
                                setState(() {});
                              },
                              onSubmitted: (_) {
                                unawaited(confirmPayment());
                              },
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ('Exact', totalAmount),
                                ('+100', totalAmount + 100),
                                ('+500', totalAmount + 500),
                                ('+1000', totalAmount + 1000),
                              ].map((entry) {
                                final label = entry.$1;
                                final value = entry.$2;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () {
                                    setAmountText(value.toStringAsFixed(2));
                                    setState(() {});
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
                                        color: textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                buildInfoTile(
                                  label: 'Tendered',
                                  value: 'Rs. ${amountTendered.toStringAsFixed(2)}',
                                  valueColor: textPrimary,
                                ),
                                const SizedBox(width: 10),
                                buildInfoTile(
                                  label: amountTendered < totalAmount
                                      ? 'Remaining'
                                      : 'Change',
                                  value: amountTendered < totalAmount
                                      ? 'Rs. ${remainingAmount.toStringAsFixed(2)}'
                                      : 'Rs. ${changeAmount.toStringAsFixed(2)}',
                                  valueColor: amountTendered < totalAmount
                                      ? danger
                                      : brand,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
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
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: brand.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: brand.withOpacity(0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.credit_score_rounded,
                                    color: brand,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Manual card payment',
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Enter the amount on the bank card machine, then confirm here after approval.',
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surfaceAlt,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Card charge amount',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    '',
                                    style: TextStyle(fontSize: 1),
                                  ),
                                  Text(
                                    'Rs. ${totalAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: brand,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                            onPressed: canConfirm
                                ? () {
                                    unawaited(confirmPayment());
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brand,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  isDark ? Colors.white10 : Colors.black12,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            icon: Icon(
                              selectedMethod == 'card'
                                  ? Icons.credit_card_rounded
                                  : Icons.check_circle_outline_rounded,
                            ),
                            label: Text(
                              selectedMethod == 'card'
                                  ? 'Complete Card Sale'
                                  : 'Confirm Payment',
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
            ),
          );
        },
      );
    },
  );

  await Future<void>.delayed(const Duration(milliseconds: 280));
  amountController.dispose();
  return result;
}
