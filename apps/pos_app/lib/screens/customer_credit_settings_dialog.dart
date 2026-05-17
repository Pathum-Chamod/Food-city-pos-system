import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared/models/customer_credit_summary.dart';

import '../services/customer_credit_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

Future<bool> showCustomerCreditSettingsDialog({
  required BuildContext context,
  required int customerId,
  required String customerName,
  CustomerCreditSummary? initialSummary,
  int? actorUserId,
}) async {
  CustomerCreditSummary summary =
      initialSummary ??
      await CustomerCreditService.instance.getCreditSummary(customerId);
  if (!context.mounted) return false;

  final limitController = TextEditingController(
    text: summary.creditLimit <= 0
        ? ''
        : summary.creditLimit.toStringAsFixed(2),
  );
  final noteController = TextEditingController(text: summary.creditNote ?? '');

  var creditEnabled = summary.creditEnabled;
  var selectedStatus = summary.normalizedStatus;
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
        const warning = Color(0xFFFFB65C);
        const danger = Color(0xFFFF6B7A);
        const success = Color(0xFF1FCF9A);

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

        String money(num value) {
          return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
        }

        Color statusColor(String status) {
          switch (status) {
            case 'blocked':
              return danger;
            case 'watchlist':
              return warning;
            case 'normal':
            default:
              return brand;
          }
        }

        Future<void> save(StateSetter setState) async {
          if (isSaving) return;

          final rawLimit = limitController.text.trim();
          final creditLimit = rawLimit.isEmpty
              ? 0.0
              : double.tryParse(rawLimit);

          if (creditLimit == null || creditLimit < 0) {
            showMessage('Enter a valid credit limit.', color: danger);
            return;
          }

          if (creditEnabled && creditLimit <= 0) {
            showMessage(
              'Set a credit limit greater than zero before enabling credit.',
              color: danger,
            );
            return;
          }

          setState(() {
            isSaving = true;
          });

          try {
            await CustomerCreditService.instance.updateCreditSettings(
              customerId: customerId,
              creditEnabled: creditEnabled,
              creditLimit: creditLimit,
              creditStatus: selectedStatus,
              creditNote: noteController.text.trim(),
              updatedBy: actorUserId,
            );

            if (!dialogContext.mounted) return;
            showMessage('Credit settings updated.', color: success);
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

        Widget metricCard({
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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
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
            final statusTone = statusColor(selectedStatus);

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
                              color: brand.withValues(
                                alpha: isDark ? 0.16 : 0.10,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: brand.withValues(alpha: 0.24),
                              ),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
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
                                  'Credit Settings',
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
                                : () => Navigator.of(dialogContext).pop(false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          metricCard(
                            label: 'Current Balance',
                            value: money(summary.currentBalance),
                            icon: Icons.payments_rounded,
                            color: summary.currentBalance > 0
                                ? warning
                                : summary.currentBalance < 0
                                ? const Color(0xFF4B8DFF)
                                : brand,
                          ),
                          const SizedBox(width: 10),
                          metricCard(
                            label: 'Current Limit',
                            value: money(summary.creditLimit),
                            icon: Icons.speed_rounded,
                            color: brand,
                          ),
                          const SizedBox(width: 10),
                          metricCard(
                            label: 'Available',
                            value: money(summary.availableCredit),
                            icon: Icons.trending_up_rounded,
                            color: summary.availableCredit < 0 ? danger : brand,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: panelSoft,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: border),
                        ),
                        child: SwitchListTile(
                          value: creditEnabled,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Enable Customer Credit',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          subtitle: Text(
                            creditEnabled
                                ? 'Customer can use Customer Credit at checkout.'
                                : 'Customer Credit is disabled for this customer.',
                            style: TextStyle(
                              color: textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          activeThumbColor: brand,
                          onChanged: isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    creditEnabled = value;
                                  });
                                },
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: limitController,
                        enabled: !isSaving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: inputDecoration(
                          label: 'Credit limit',
                          icon: Icons.price_check_rounded,
                          hint: 'Example: 10000',
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: inputDecoration(
                          label: 'Credit status',
                          icon: Icons.verified_user_rounded,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal'),
                          ),
                          DropdownMenuItem(
                            value: 'watchlist',
                            child: Text('Watchlist'),
                          ),
                          DropdownMenuItem(
                            value: 'blocked',
                            child: Text('Blocked'),
                          ),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  selectedStatus = value;
                                });
                              },
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusTone.withValues(
                            alpha: isDark ? 0.14 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: statusTone.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_rounded,
                              color: statusTone,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedStatus == 'blocked'
                                    ? 'Blocked customers cannot use credit unless manager override is added later.'
                                    : selectedStatus == 'watchlist'
                                    ? 'Watchlist customers can use credit, but cashier should be careful.'
                                    : 'Normal customers can use credit within their limit.',
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
                      const SizedBox(height: 14),
                      TextField(
                        controller: noteController,
                        enabled: !isSaving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: inputDecoration(
                          label: 'Credit note',
                          icon: Icons.note_alt_rounded,
                          hint:
                              'Example: Pays monthly / Do not allow more credit',
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () =>
                                        Navigator.of(dialogContext).pop(false),
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
                                isSaving ? 'Saving...' : 'Save Settings',
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
    limitController.dispose();
    noteController.dispose();
  }
}
