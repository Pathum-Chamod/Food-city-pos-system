import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/models/customer_credit_summary.dart';

import '../services/customer_credit_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

Future<bool> showCustomerPaymentDialog({
  required BuildContext context,
  required int customerId,
  required String customerName,
  CustomerCreditSummary? initialSummary,
  String? receivedBy,
}) async {
  final summary =
      initialSummary ??
      await CustomerCreditService.instance.getCreditSummary(customerId);
  if (!context.mounted) return false;

  final amountController = TextEditingController();
  final noteController = TextEditingController();

  var selectedMethod = 'cash';
  var isSaving = false;

  try {
    final saved = await showPremiumDialog<bool>(
      context: context,
      barrierDismissible: !isSaving,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        final panel = isDark ? const Color(0xFF0F1C31) : Colors.white;
        final panelSoft = isDark
            ? const Color(0xFF14243C)
            : const Color(0xFFF8FAFD);
        final border = isDark
            ? const Color(0xFF23344D)
            : const Color(0xFFD9E3EE);
        final textPrimary = isDark
            ? const Color(0xFFF4F8FF)
            : const Color(0xFF14263B);
        final textSecondary = isDark
            ? const Color(0xFF9DB0C8)
            : const Color(0xFF667A92);

        const brand = Color(0xFF2AAA8A);
        const blue = Color(0xFF4B8DFF);
        const warning = Color(0xFFFFB65C);
        const danger = Color(0xFFFF6B7A);
        const success = Color(0xFF1FCF9A);

        String money(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

        InputDecoration inputDecoration({
          required String label,
          required IconData icon,
          String? hint,
        }) {
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
              borderSide: const BorderSide(color: brand, width: 1.4),
            ),
          );
        }

        void showMessage(String message, {Color color = warning}) {
          AppSnackBar.show(
            dialogContext,
            message: message,
            backgroundColor: color,
          );
        }

        Future<void> save(StateSetter setState) async {
          if (isSaving) return;

          final amount = double.tryParse(amountController.text.trim());
          if (amount == null || amount <= 0) {
            showMessage('Enter a valid payment amount.', color: danger);
            return;
          }

          setState(() {
            isSaving = true;
          });

          try {
            final result = await CustomerCreditService.instance.receivePayment(
              customerId: customerId,
              amount: amount,
              paymentMethod: selectedMethod,
              receivedBy: (receivedBy ?? '').trim().isEmpty
                  ? 'Cashier'
                  : receivedBy!.trim(),
              cashierName: receivedBy,
              referenceNote: noteController.text.trim(),
            );

            if (!dialogContext.mounted) return;
            showMessage(
              'Payment saved. New balance ${money(result.newBalance)}.',
              color: success,
            );
            FocusScope.of(dialogContext).unfocus();
            Navigator.of(dialogContext).pop(true);
          } catch (e) {
            if (!dialogContext.mounted) return;
            setState(() {
              isSaving = false;
            });
            final message = e.toString().replaceFirst('Exception: ', '');
            showMessage(message, color: danger);
          }
        }

        Widget balanceInfoCard({
          required String label,
          required String value,
          required IconData icon,
          required Color color,
        }) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panelSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 21),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
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

        return StatefulBuilder(
          builder: (context, setState) {
            final enteredAmount =
                double.tryParse(amountController.text.trim()) ?? 0.0;
            final newBalance = summary.currentBalance - enteredAmount;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 680),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.10,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
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
                              color: brand.withValues(
                                alpha: isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: brand.withValues(alpha: 0.24),
                              ),
                            ),
                            child: const Icon(
                              Icons.payments_rounded,
                              color: brand,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Receive Payment',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: isSaving
                                ? null
                                : () {
                                    FocusScope.of(dialogContext).unfocus();
                                    Navigator.of(dialogContext).pop(false);
                                  },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      Row(
                        children: [
                          balanceInfoCard(
                            label: 'Current Balance',
                            value: money(summary.currentBalance),
                            icon: Icons.account_balance_wallet_rounded,
                            color: summary.currentBalance > 0
                                ? warning
                                : summary.currentBalance < 0
                                ? blue
                                : brand,
                          ),
                          const SizedBox(width: 10),
                          balanceInfoCard(
                            label: 'After Payment',
                            value: money(newBalance),
                            icon: Icons.trending_down_rounded,
                            color: newBalance > 0
                                ? warning
                                : newBalance < 0
                                ? blue
                                : brand,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      TextField(
                        controller: amountController,
                        enabled: !isSaving,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: inputDecoration(
                          label: 'Amount received',
                          icon: Icons.price_check_rounded,
                          hint: 'Example: 5000',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),

                      DropdownButtonFormField<String>(
                        initialValue: selectedMethod,
                        decoration: inputDecoration(
                          label: 'Payment method',
                          icon: Icons.payment_rounded,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'card', child: Text('Card')),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  selectedMethod = value;
                                });
                              },
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: noteController,
                        enabled: !isSaving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: inputDecoration(
                          label: 'Reference note',
                          icon: Icons.note_alt_rounded,
                          hint: 'Optional: old balance payment, bank ref, etc.',
                        ),
                      ),

                      const SizedBox(height: 16),
                      if (newBalance < 0)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: blue.withValues(alpha: isDark ? 0.16 : 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: blue.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_rounded,
                                color: blue,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This payment creates a customer advance / overpayment.',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () {
                                      FocusScope.of(dialogContext).unfocus();
                                      Navigator.of(dialogContext).pop(false);
                                    },
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: isSaving ? null : () => save(setState),
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(
                                isSaving ? 'Saving...' : 'Save Payment',
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

    return saved == true;
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    amountController.dispose();
    noteController.dispose();
  }
}
