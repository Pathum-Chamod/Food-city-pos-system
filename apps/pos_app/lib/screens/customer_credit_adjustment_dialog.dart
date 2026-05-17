import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/models/customer_credit_summary.dart';

import '../services/customer_credit_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

Future<bool> showCustomerCreditAdjustmentDialog({
  required BuildContext context,
  required int customerId,
  required String customerName,
  CustomerCreditSummary? initialSummary,
  String? performedBy,
}) async {
  final summary =
      initialSummary ??
      await CustomerCreditService.instance.getCreditSummary(customerId);
  if (!context.mounted) return false;

  final amountController = TextEditingController();
  final reasonController = TextEditingController();

  var selectedType = 'debit_adjustment';
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
          final reason = reasonController.text.trim();

          if (amount == null || amount <= 0) {
            showMessage('Enter a valid adjustment amount.', color: danger);
            return;
          }

          if (reason.isEmpty) {
            showMessage('Adjustment reason is required.', color: danger);
            return;
          }

          setState(() {
            isSaving = true;
          });

          try {
            final result = await CustomerCreditService.instance.postAdjustment(
              customerId: customerId,
              amount: amount,
              adjustmentType: selectedType,
              reason: reason,
              performedBy: (performedBy ?? '').trim().isEmpty
                  ? 'Manager'
                  : performedBy!.trim(),
              approvedBy: (performedBy ?? '').trim().isEmpty
                  ? 'Manager'
                  : performedBy!.trim(),
            );

            if (!dialogContext.mounted) return;
            showMessage(
              'Adjustment saved. New balance ${money(result.newBalance)}.',
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

        Widget infoTile({
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

        Widget typeButton({
          required String label,
          required String value,
          required String subtitle,
          required IconData icon,
          required Color color,
          required StateSetter setState,
        }) {
          final selected = selectedType == value;

          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: isSaving
                  ? null
                  : () {
                      setState(() {
                        selectedType = value;
                      });
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: isDark ? 0.16 : 0.10)
                      : panelSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? color.withValues(alpha: 0.42) : border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: selected ? color : textSecondary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: selected ? color : textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setState) {
            final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
            final nextBalance = selectedType == 'debit_adjustment'
                ? summary.currentBalance + amount
                : summary.currentBalance - amount;
            final isDebit = selectedType == 'debit_adjustment';

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
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
                              color: warning.withValues(
                                alpha: isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: warning.withValues(alpha: 0.24),
                              ),
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: warning,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ledger Adjustment',
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
                          infoTile(
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
                          infoTile(
                            label: 'Balance After',
                            value: money(nextBalance),
                            icon: Icons.trending_flat_rounded,
                            color: nextBalance > summary.currentBalance
                                ? danger
                                : blue,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          typeButton(
                            label: 'Debit Adjustment',
                            value: 'debit_adjustment',
                            subtitle: 'Increase customer balance',
                            icon: Icons.north_east_rounded,
                            color: danger,
                            setState: setState,
                          ),
                          const SizedBox(width: 10),
                          typeButton(
                            label: 'Credit Adjustment',
                            value: 'credit_adjustment',
                            subtitle: 'Decrease customer balance',
                            icon: Icons.south_west_rounded,
                            color: blue,
                            setState: setState,
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      TextField(
                        controller: amountController,
                        enabled: !isSaving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: inputDecoration(
                          label: 'Adjustment amount',
                          icon: Icons.price_check_rounded,
                          hint: 'Example: 500',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: 14),
                      TextField(
                        controller: reasonController,
                        enabled: !isSaving,
                        minLines: 3,
                        maxLines: 5,
                        decoration: inputDecoration(
                          label: 'Reason',
                          icon: Icons.note_alt_rounded,
                          hint:
                              'Required: explain why this adjustment is needed',
                        ),
                      ),

                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isDebit ? danger : blue).withValues(
                            alpha: isDark ? 0.14 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (isDebit ? danger : blue).withValues(
                              alpha: 0.24,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_rounded,
                              color: isDebit ? danger : blue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isDebit
                                    ? 'Debit adjustment increases how much the customer owes.'
                                    : 'Credit adjustment decreases how much the customer owes.',
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
                                isSaving ? 'Saving...' : 'Save Adjustment',
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
    reasonController.dispose();
  }
}
