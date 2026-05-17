import 'package:flutter/material.dart';
import 'package:shared/models/customer_payment_receipt.dart';

import '../services/customer_payment_receipt_pdf_service.dart';
import '../services/customer_payment_receipt_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

Future<void> showCustomerPaymentReceiptDialog({
  required BuildContext context,
  required int paymentId,
  bool paymentJustSaved = false,
}) async {
  if (paymentId <= 0) {
    AppSnackBar.show(
      context,
      message: 'Receipt data incomplete: missing payment id.',
      backgroundColor: const Color(0xFFFF6B7A),
    );
    return;
  }

  final receipt = await CustomerPaymentReceiptService.instance
      .getReceiptByPaymentId(paymentId);
  if (!context.mounted) return;

  if (receipt == null) {
    AppSnackBar.show(
      context,
      message: 'Receipt data incomplete. Could not find payment record.',
      backgroundColor: const Color(0xFFFF6B7A),
    );
    return;
  }

  await showPremiumDialog<void>(
    context: context,
    builder: (dialogContext) => _CustomerPaymentReceiptDialog(
      receipt: receipt,
      paymentJustSaved: paymentJustSaved,
    ),
  );
}

class _CustomerPaymentReceiptDialog extends StatefulWidget {
  const _CustomerPaymentReceiptDialog({
    required this.receipt,
    required this.paymentJustSaved,
  });

  final CustomerPaymentReceipt receipt;
  final bool paymentJustSaved;

  @override
  State<_CustomerPaymentReceiptDialog> createState() =>
      _CustomerPaymentReceiptDialogState();
}

class _CustomerPaymentReceiptDialogState
    extends State<_CustomerPaymentReceiptDialog> {
  bool _isSavingPdf = false;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  Future<void> _savePdf() async {
    if (_isSavingPdf) return;
    setState(() {
      _isSavingPdf = true;
    });

    final response = await CustomerPaymentReceiptPdfService.instance
        .savePaymentReceiptPdf(receipt: widget.receipt);

    if (!mounted) return;
    setState(() {
      _isSavingPdf = false;
    });
    AppSnackBar.show(
      context,
      message: response.message,
      backgroundColor: response.isSuccess ? _brand : _danger,
    );
  }

  String _money(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

  String _date(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  String _dash(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? '-' : text;
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final statusColor = receipt.isVoided ? _danger : _brand;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isDark ? 0.28 : 0.10),
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.26),
                      ),
                    ),
                    child: Icon(
                      receipt.isVoided
                          ? Icons.block_rounded
                          : Icons.receipt_long_rounded,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.paymentJustSaved
                              ? 'Payment Saved'
                              : 'Customer Payment Receipt',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${receipt.receiptNo} • ${receipt.statusLabel}',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSavingPdf
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (receipt.isVoided) ...[
                _voidNotice(receipt),
                const SizedBox(height: 14),
              ],
              _infoPanel(
                title: receipt.displayCustomerName,
                subtitle:
                    '${receipt.displayCustomerCode} • ${_dash(receipt.customerPhone)}',
                icon: Icons.person_rounded,
                color: _brand,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _metric(
                    label: 'Previous Balance',
                    value: _money(receipt.previousBalance),
                    color: _warning,
                  ),
                  const SizedBox(width: 10),
                  _metric(
                    label: 'Amount Paid',
                    value: _money(receipt.amountPaid),
                    color: _brand,
                  ),
                  const SizedBox(width: 10),
                  _metric(
                    label: 'New Balance',
                    value: _money(receipt.newBalance),
                    color: receipt.newBalance > 0 ? _warning : _brand,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _detailsGrid(receipt),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSavingPdf
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSavingPdf ? null : _savePdf,
                      icon: _isSavingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      label: Text(_isSavingPdf ? 'Saving...' : 'View PDF'),
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

  Widget _voidNotice(CustomerPaymentReceipt receipt) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: _isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _danger.withValues(alpha: 0.28)),
      ),
      child: Text(
        'Voided ${_dash(receipt.voidedAt)} by ${_dash(receipt.voidedBy)}'
        '\nReason: ${_dash(receipt.voidReason)}',
        style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _infoPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsGrid(CustomerPaymentReceipt receipt) {
    final rows = [
      ('Payment Method', receipt.paymentMethodLabel),
      ('Date / Time', _date(receipt.createdAt)),
      ('Received By', _dash(receipt.receivedBy)),
      ('Reference', _dash(receipt.referenceNote)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    row.$1,
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
