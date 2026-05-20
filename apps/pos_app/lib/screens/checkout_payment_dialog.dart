import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/customer_credit_summary.dart';

import '../services/customer_credit_service.dart';
import '../widgets/premium_dialog.dart';

Future<Map<String, dynamic>?> showCheckoutPaymentDialog(
  BuildContext context, {
  required double totalAmount,
  double? originalTotal,
  Customer? selectedCustomer,
  int loyaltyPointsRedeemed = 0,
  double loyaltyRedeemedValue = 0.0,
}) async {
  const brand = Color(0xFF2AAA8A);
  const danger = Color(0xFFE85D75);
  const warning = Color(0xFFFFB65C);
  const blue = Color(0xFF4B8DFF);

  CustomerCreditSummary? creditSummary;
  String? creditUnavailableReason;
  bool isCreditLoading = false;

  final customerId = selectedCustomer?.id ?? 0;
  if (customerId > 0) {
    isCreditLoading = true;
    try {
      creditSummary = await CustomerCreditService.instance.getCreditSummary(
        customerId,
      );
      final validation = await CustomerCreditService.instance
          .validateCreditSale(customerId: customerId, saleTotal: totalAmount);
      if (!validation.allowed) {
        creditUnavailableReason = validation.message;
      }
    } catch (e) {
      creditUnavailableReason = 'Could not load customer credit details.';
    } finally {
      isCreditLoading = false;
    }
  } else {
    creditUnavailableReason = 'Select a customer to use Customer Credit.';
  }

  if (!context.mounted) return null;

  final amountController = TextEditingController(
    text: totalAmount.toStringAsFixed(2),
  );
  final dialogFocusNode = FocusNode(debugLabel: 'CheckoutPaymentDialog');
  final amountFocusNode = FocusNode(debugLabel: 'CheckoutPaymentAmount');

  String selectedMethod = 'cash';
  double amountTendered = totalAmount;
  double changeAmount = 0.0;
  bool hasConfirmedPayment = false;
  bool replaceAmountOnNextEdit = true;

  double payableTotal() => totalAmount;

  bool canUseCustomerCredit() {
    if (selectedCustomer == null || customerId <= 0) return false;
    if (loyaltyPointsRedeemed > 0) return false;
    if (creditSummary == null) return false;
    if (!creditSummary.creditEnabled) return false;
    if (creditSummary.isBlocked) return false;

    final newBalance = creditSummary.currentBalance + payableTotal();
    if (creditSummary.creditLimit > 0 &&
        newBalance > creditSummary.creditLimit) {
      return false;
    }

    return payableTotal() > 0;
  }

  String customerCreditReason() {
    if (selectedCustomer == null || customerId <= 0) {
      return 'Select a customer to use Customer Credit.';
    }
    if (isCreditLoading) {
      return 'Loading credit account...';
    }
    if (creditSummary == null) {
      return creditUnavailableReason ?? 'Credit account not available.';
    }
    if (!creditSummary.creditEnabled) {
      return 'Credit is not enabled for this customer.';
    }
    if (creditSummary.isBlocked) {
      return 'Customer credit is blocked.';
    }
    if (loyaltyPointsRedeemed > 0) {
      return 'Customer Credit cannot be combined with loyalty redemption.';
    }

    final newBalance = creditSummary.currentBalance + payableTotal();
    if (creditSummary.creditLimit > 0 &&
        newBalance > creditSummary.creditLimit) {
      return 'Credit limit exceeded. Manager approval will be added later.';
    }

    return creditUnavailableReason ?? 'Customer Credit is available.';
  }

  double creditPreviousBalance() => creditSummary?.currentBalance ?? 0.0;

  double creditNewBalance() {
    return double.parse(
      (creditPreviousBalance() + payableTotal()).toStringAsFixed(2),
    );
  }

  void setAmountText(String value, {bool selectForReplacement = true}) {
    amountController.value = TextEditingValue(
      text: value,
      selection: selectForReplacement
          ? TextSelection(baseOffset: 0, extentOffset: value.length)
          : TextSelection.collapsed(offset: value.length),
    );
    replaceAmountOnNextEdit = selectForReplacement;
  }

  setAmountText(payableTotal().toStringAsFixed(2));

  void recalculate() {
    final due = payableTotal();
    if (selectedMethod == 'cash') {
      amountTendered = double.tryParse(amountController.text.trim()) ?? 0.0;
      changeAmount = math.max(0, amountTendered - due);
    } else {
      amountTendered = due;
      changeAmount = 0.0;
    }
  }

  recalculate();

  try {
    final result = await showPremiumDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            recalculate();
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            final bg = isDark
                ? const Color(0xFF091321)
                : const Color(0xFFF3F7FB);
            final surface = isDark ? const Color(0xFF0F1C2E) : Colors.white;
            final surfaceAlt = isDark
                ? const Color(0xFF15263F)
                : const Color(0xFFF7FAFD);
            final inputFill = isDark
                ? const Color(0xFF0C1728)
                : const Color(0xFFF2F6FA);
            final border = isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFFD8E2EC);
            final textPrimary = isDark
                ? const Color(0xFFF3F7FF)
                : const Color(0xFF1B2B44);
            final textSecondary = isDark
                ? const Color(0xFF97AAC6)
                : const Color(0xFF61758F);

            void focusCashAmountOnNextFrame() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!amountFocusNode.canRequestFocus) return;
                amountFocusNode.requestFocus();
                amountController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: amountController.text.length,
                );
              });
            }

            void selectPaymentMethod(String value) {
              if (value == 'customer_credit' && !canUseCustomerCredit()) {
                return;
              }

              setState(() {
                selectedMethod = value;
                setAmountText(payableTotal().toStringAsFixed(2));
              });

              if (value == 'cash') {
                focusCashAmountOnNextFrame();
              } else if (dialogFocusNode.canRequestFocus) {
                dialogFocusNode.requestFocus();
              }
            }

            InputDecoration fieldDecoration({
              required String label,
              String? prefixText,
              String? helperText,
              String? errorText,
            }) {
              return InputDecoration(
                labelText: label,
                prefixText: prefixText,
                helperText: helperText,
                errorText: errorText,
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
              bool enabled = true,
              String? disabledReason,
            }) {
              final selected = selectedMethod == value;
              final tone = value == 'customer_credit' ? warning : brand;

              return Expanded(
                child: Opacity(
                  opacity: enabled ? 1 : 0.52,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: enabled ? () => selectPaymentMethod(value) : null,
                    child: Tooltip(
                      message: enabled ? label : (disabledReason ?? label),
                      waitDuration: const Duration(milliseconds: 450),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? tone.withValues(alpha: isDark ? 0.16 : 0.12)
                              : inputFill,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: selected ? tone : border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 18,
                              color: selected ? tone : textSecondary,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? tone : textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

            final due = payableTotal();
            final canConfirm =
                selectedMethod == 'card' ||
                selectedMethod == 'customer_credit' ||
                amountTendered >= due;

            Future<void> confirmPayment() async {
              if (!canConfirm || hasConfirmedPayment) return;

              hasConfirmedPayment = true;

              Navigator.pop(context, {
                'payment_method': selectedMethod,
                'amount_tendered': selectedMethod == 'cash'
                    ? amountTendered
                    : due,
                'change_amount': selectedMethod == 'cash' ? changeAmount : 0.0,
                'original_total': originalTotal ?? totalAmount,
                'final_total': due,
                'loyalty_points_redeemed': selectedMethod == 'customer_credit'
                    ? 0
                    : loyaltyPointsRedeemed,
                'loyalty_redeemed_value': selectedMethod == 'customer_credit'
                    ? 0.0
                    : loyaltyRedeemedValue,
                'is_credit_sale': selectedMethod == 'customer_credit',
                'credit_previous_balance': selectedMethod == 'customer_credit'
                    ? creditPreviousBalance()
                    : null,
                'credit_new_balance': selectedMethod == 'customer_credit'
                    ? creditNewBalance()
                    : null,
                'credit_approved_by': null,
              });
            }

            final remainingAmount = math.max(0, due - amountTendered);
            final customerCreditEnabled = canUseCustomerCredit();
            final creditReason = customerCreditReason();

            Widget paymentMethodSection() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      const SizedBox(width: 10),
                      buildMethodButton(
                        label: 'Credit',
                        icon: Icons.account_balance_wallet_rounded,
                        value: 'customer_credit',
                        enabled: customerCreditEnabled,
                        disabledReason: creditReason,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: customerCreditEnabled
                          ? warning.withValues(alpha: isDark ? 0.14 : 0.08)
                          : surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: customerCreditEnabled
                            ? warning.withValues(alpha: 0.30)
                            : border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          customerCreditEnabled
                              ? Icons.check_circle_rounded
                              : Icons.info_rounded,
                          color: customerCreditEnabled
                              ? warning
                              : textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            customerCreditEnabled
                                ? '${selectedCustomer!.displayName}: Balance Rs. ${creditPreviousBalance().toStringAsFixed(2)} → Rs. ${creditNewBalance().toStringAsFixed(2)}'
                                : creditReason,
                            style: TextStyle(
                              color: customerCreditEnabled
                                  ? textPrimary
                                  : textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            Widget cardPaymentPanel() {
              return Container(
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
                        color: brand.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: brand.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.credit_score_rounded, color: brand),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                          Text(
                            'Rs. ${due.toStringAsFixed(2)}',
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
              );
            }

            Widget creditPaymentPanel() {
              return Container(
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
                        color: warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: warning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customer Credit Sale',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'This bill will be added to the selected customer ledger.',
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
                    Row(
                      children: [
                        buildInfoTile(
                          label: 'Previous Balance',
                          value:
                              'Rs. ${creditPreviousBalance().toStringAsFixed(2)}',
                          valueColor: textPrimary,
                        ),
                        const SizedBox(width: 10),
                        buildInfoTile(
                          label: 'New Balance',
                          value: 'Rs. ${creditNewBalance().toStringAsFixed(2)}',
                          valueColor: warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        buildInfoTile(
                          label: 'Credit Limit',
                          value:
                              'Rs. ${(creditSummary?.creditLimit ?? 0).toStringAsFixed(2)}',
                          valueColor: brand,
                        ),
                        const SizedBox(width: 10),
                        buildInfoTile(
                          label: 'Available After',
                          value:
                              'Rs. ${((creditSummary?.creditLimit ?? 0) - creditNewBalance()).toStringAsFixed(2)}',
                          valueColor:
                              ((creditSummary?.creditLimit ?? 0) -
                                      creditNewBalance()) <
                                  0
                              ? danger
                              : blue,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Focus(
              focusNode: dialogFocusNode,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.f1) {
                  selectPaymentMethod('cash');
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.f2) {
                  selectPaymentMethod('card');
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.f3) {
                  selectPaymentMethod('customer_credit');
                  return KeyEventResult.handled;
                }

                final isEnterKey =
                    event.logicalKey == LogicalKeyboardKey.enter ||
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
                  constraints: const BoxConstraints(maxWidth: 640),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.34 : 0.10,
                        ),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: SingleChildScrollView(
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
                                  color: brand.withValues(alpha: 0.14),
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
                                  loyaltyRedeemedValue > 0
                                      ? 'PAYABLE TOTAL'
                                      : 'TOTAL DUE',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Rs. ${due.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: brand,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                                if (loyaltyRedeemedValue > 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Before loyalty: Rs. ${(originalTotal ?? totalAmount).toStringAsFixed(2)}   Redeemed: Rs. ${loyaltyRedeemedValue.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          paymentMethodSection(),
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
                                    focusNode: amountFocusNode,
                                    autofocus: true,
                                    textInputAction: TextInputAction.done,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    decoration: fieldDecoration(
                                      label: 'Amount Tendered',
                                      prefixText: 'Rs. ',
                                      helperText:
                                          'Enter the cash received from customer.',
                                    ),
                                    onTap: () {
                                      if (!replaceAmountOnNextEdit) return;
                                      amountController.selection =
                                          TextSelection(
                                            baseOffset: 0,
                                            extentOffset:
                                                amountController.text.length,
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
                                    children:
                                        [
                                          ('Exact', due),
                                          ('+100', due + 100),
                                          ('+500', due + 500),
                                          ('+1000', due + 1000),
                                        ].map((entry) {
                                          final label = entry.$1;
                                          final value = entry.$2;
                                          return InkWell(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            onTap: () {
                                              setAmountText(
                                                value.toStringAsFixed(2),
                                              );
                                              setState(() {});
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 9,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: surfaceAlt,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: border,
                                                ),
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
                                        value:
                                            'Rs. ${amountTendered.toStringAsFixed(2)}',
                                        valueColor: textPrimary,
                                      ),
                                      const SizedBox(width: 10),
                                      buildInfoTile(
                                        label: amountTendered < due
                                            ? 'Remaining'
                                            : 'Change',
                                        value: amountTendered < due
                                            ? 'Rs. ${remainingAmount.toStringAsFixed(2)}'
                                            : 'Rs. ${changeAmount.toStringAsFixed(2)}',
                                        valueColor: amountTendered < due
                                            ? danger
                                            : brand,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ] else if (selectedMethod == 'card') ...[
                            cardPaymentPanel(),
                          ] else ...[
                            creditPaymentPanel(),
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
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
                                    backgroundColor:
                                        selectedMethod == 'customer_credit'
                                        ? warning
                                        : brand,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: Icon(
                                    selectedMethod == 'card'
                                        ? Icons.credit_card_rounded
                                        : selectedMethod == 'customer_credit'
                                        ? Icons.account_balance_wallet_rounded
                                        : Icons.check_circle_outline_rounded,
                                  ),
                                  label: Text(
                                    selectedMethod == 'card'
                                        ? 'Complete Card Sale'
                                        : selectedMethod == 'customer_credit'
                                        ? 'Confirm Credit Sale'
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
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 280));
    return result;
  } finally {
    amountController.dispose();
    dialogFocusNode.dispose();
    amountFocusNode.dispose();
  }
}
