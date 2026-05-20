import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/presentation_mode_service.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../widgets/app_snackbar.dart';

class PresentationTransactionHistoryScreen extends StatefulWidget {
  const PresentationTransactionHistoryScreen({super.key});

  @override
  State<PresentationTransactionHistoryScreen> createState() =>
      _PresentationTransactionHistoryScreenState();

  static String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  static String _formatQuantity(num value, {int maxDecimals = 3}) {
    final quantity = value.toDouble().abs();
    if ((quantity - quantity.roundToDouble()).abs() < 0.000001) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _formatPercent(num value) {
    final number = value.toDouble();
    return number.toStringAsFixed(number % 1 == 0 ? 0 : 2);
  }

  static String _discountPercentLabel({
    required double discountAmount,
    required double baseAmount,
    required String discountType,
    required double discountValue,
  }) {
    if (discountAmount <= 0 || baseAmount <= 0) return '0';
    if (discountType == 'percent' && discountValue > 0) {
      return _formatPercent(discountValue);
    }
    return _formatPercent((discountAmount / baseAmount) * 100);
  }

  static String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $h:$min';
    } catch (_) {
      return raw;
    }
  }

  static int _resolveDisplayId({
    required int realSaleId,
    required int? displayId,
  }) {
    final safeDisplayId = displayId ?? realSaleId;
    return safeDisplayId <= 0 ? realSaleId : safeDisplayId;
  }

  static List<Map<String, dynamic>> _buildReceiptItems(
    List<Map<String, dynamic>> items,
    Map<String, dynamic> summary,
  ) {
    final discountType = (summary['discount_type'] ?? 'none').toString();

    return items.map((item) {
      final finalLineTotal = ((item['line_total'] as num?) ?? 0)
          .toDouble()
          .abs();
      final baseLineTotal =
          ((item['base_line_total'] as num?) ?? finalLineTotal)
              .toDouble()
              .abs();
      final storedExplicitItemDiscount =
          ((item['explicit_item_discount_amount'] as num?) ?? 0)
              .toDouble()
              .abs();
      final storedCartDiscount = ((item['cart_discount_amount'] as num?) ?? 0)
          .toDouble()
          .abs();
      final storedCombinedItemDiscount =
          ((item['item_discount_amount'] as num?) ?? 0).toDouble().abs();
      final explicitItemDiscount = storedExplicitItemDiscount > 0
          ? storedExplicitItemDiscount
          : (storedCartDiscount <= 0 && discountType == 'none'
                ? storedCombinedItemDiscount
                : 0.0);

      return {
        'name': (item['product_name'] ?? 'Item').toString(),
        'qty': ((item['quantity'] as num?) ?? 0).toDouble().abs(),
        'unitPrice': ((item['unit_price'] as num?) ?? 0).toDouble(),
        'markedPrice':
            ((item['marked_price'] as num?) ??
                    (item['unit_price'] as num?) ??
                    0)
                .toDouble(),
        'priceType': (item['price_category_used'] ?? 'selling').toString(),
        'baseLineTotal': baseLineTotal,
        'itemDiscountType': (item['item_discount_type'] ?? 'none').toString(),
        'itemDiscountValue': ((item['item_discount_value'] as num?) ?? 0)
            .toDouble()
            .abs(),
        'itemDiscountAmount': explicitItemDiscount,
        'lineTotal': baseLineTotal - explicitItemDiscount,
      };
    }).toList();
  }

  static double _receiptItemDiscountTotal(
    List<Map<String, dynamic>> receiptItems,
  ) {
    return receiptItems.fold<double>(
      0.0,
      (sum, item) =>
          sum + (((item['itemDiscountAmount'] as num?) ?? 0).toDouble()),
    );
  }

  static double _receiptSubtotal(List<Map<String, dynamic>> receiptItems) {
    return receiptItems.fold<double>(
      0.0,
      (sum, item) => sum + (((item['lineTotal'] as num?) ?? 0).toDouble()),
    );
  }

  static Future<bool> printReceiptForTransaction(
    BuildContext context,
    int realSaleId, {
    int? displayId,
  }) async {
    final resolvedDisplayId = _resolveDisplayId(
      realSaleId: realSaleId,
      displayId: displayId,
    );
    final printer = ReceiptPrinterService.instance;

    if (!printer.isConnected) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          message:
              'Receipt printer is not selected. Open Hardware Setup first.',
          backgroundColor: Colors.orange,
        );
      }
      return false;
    }

    final summary = await DatabaseHelper.instance.getTransactionSummary(
      realSaleId,
    );
    final items = await DatabaseHelper.instance.getTransactionItems(realSaleId);

    if (!context.mounted) return false;

    if (summary == null) {
      AppSnackBar.show(
        context,
        message: 'Transaction not found.',
        backgroundColor: Colors.red,
      );
      return false;
    }

    final paymentMethod = (summary['payment_method'] ?? 'cash').toString();
    final cashierName = 'Cashier';
    final discountAmount = ((summary['discount_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final discountType = (summary['discount_type'] ?? 'none').toString();
    final discountValue = ((summary['discount_value'] as num?) ?? 0)
        .toDouble()
        .abs();
    final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
    final amountTendered = ((summary['amount_tendered'] as num?) ?? 0)
        .toDouble();
    final changeAmount = ((summary['change_amount'] as num?) ?? 0).toDouble();
    final isRefund =
        (summary['transaction_type'] ?? 'sale').toString().toLowerCase() ==
        'refund';

    final receiptItems = _buildReceiptItems(items, summary);
    final receiptItemDiscountTotal = _receiptItemDiscountTotal(receiptItems);
    final receiptCartDiscountAmount =
        (discountAmount - receiptItemDiscountTotal)
            .clamp(0.0, discountAmount)
            .toDouble();
    final receiptSubtotal = _receiptSubtotal(receiptItems);

    final response = await printer.printReceipt(
      transactionId: resolvedDisplayId,
      cashierName: cashierName,
      paymentMethod: paymentMethod,
      items: receiptItems,
      subtotal: receiptSubtotal,
      discountAmount: receiptCartDiscountAmount,
      discountType: discountType,
      discountValue: discountValue,
      total: total,
      amountTendered: paymentMethod.toLowerCase() == 'cash'
          ? amountTendered
          : null,
      changeAmount: paymentMethod.toLowerCase() == 'cash' ? changeAmount : null,
      isRefund: isRefund,
    );

    if (!context.mounted) return response.isSuccess;

    AppSnackBar.show(
      context,
      message: response.message,
      backgroundColor: response.isSuccess ? Colors.green : Colors.orange,
    );

    return response.isSuccess;
  }

  static Future<bool> saveReceiptPdfForTransaction(
    BuildContext context,
    int realSaleId, {
    int? displayId,
  }) async {
    final resolvedDisplayId = _resolveDisplayId(
      realSaleId: realSaleId,
      displayId: displayId,
    );
    final summary = await DatabaseHelper.instance.getTransactionSummary(
      realSaleId,
    );
    final items = await DatabaseHelper.instance.getTransactionItems(realSaleId);

    if (!context.mounted) return false;

    if (summary == null) {
      AppSnackBar.show(
        context,
        message: 'Transaction not found.',
        backgroundColor: Colors.red,
      );
      return false;
    }

    final paymentMethod = (summary['payment_method'] ?? 'cash').toString();
    final cashierName = 'Cashier';
    final discountAmount = ((summary['discount_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final discountType = (summary['discount_type'] ?? 'none').toString();
    final discountValue = ((summary['discount_value'] as num?) ?? 0)
        .toDouble()
        .abs();
    final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
    final amountTendered = ((summary['amount_tendered'] as num?) ?? 0)
        .toDouble();
    final changeAmount = ((summary['change_amount'] as num?) ?? 0).toDouble();
    final isRefund =
        (summary['transaction_type'] ?? 'sale').toString().toLowerCase() ==
        'refund';

    final receiptItems = _buildReceiptItems(items, summary);
    final receiptItemDiscountTotal = _receiptItemDiscountTotal(receiptItems);
    final receiptCartDiscountAmount =
        (discountAmount - receiptItemDiscountTotal)
            .clamp(0.0, discountAmount)
            .toDouble();
    final receiptSubtotal = _receiptSubtotal(receiptItems);

    final response = await ReceiptPdfService.instance.saveReceiptPdf(
      transactionId: resolvedDisplayId,
      cashierName: cashierName,
      paymentMethod: paymentMethod,
      items: receiptItems,
      subtotal: receiptSubtotal,
      discountAmount: receiptCartDiscountAmount,
      discountType: discountType,
      discountValue: discountValue,
      total: total,
      amountTendered: paymentMethod.toLowerCase() == 'cash'
          ? amountTendered
          : null,
      changeAmount: paymentMethod.toLowerCase() == 'cash' ? changeAmount : null,
      isRefund: isRefund,
    );

    if (!context.mounted) return response.isSuccess;

    AppSnackBar.show(
      context,
      message: response.message,
      backgroundColor: response.isSuccess ? Colors.green : Colors.orange,
    );

    return response.isSuccess;
  }

  static Future<void> showReceiptDialogForTransaction(
    BuildContext context,
    int realSaleId, {
    int? displayId,
  }) async {
    final resolvedDisplayId = _resolveDisplayId(
      realSaleId: realSaleId,
      displayId: displayId,
    );
    final summary = await DatabaseHelper.instance.getTransactionSummary(
      realSaleId,
    );
    final items = await DatabaseHelper.instance.getTransactionItems(realSaleId);

    if (!context.mounted) return;

    if (summary == null) {
      AppSnackBar.show(
        context,
        message: 'Transaction not found.',
        backgroundColor: Colors.red,
      );
      return;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
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
        const danger = Color(0xFFFF6B7A);

        final type = (summary['transaction_type'] ?? 'sale')
            .toString()
            .toLowerCase();
        final isRefund = type == 'refund';
        final tone = isRefund ? danger : brand;
        final title = isRefund ? 'Refund Receipt' : 'Sale Receipt';
        final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
        final subtotal = ((summary['subtotal_amount'] as num?) ?? total)
            .toDouble()
            .abs();
        final discountAmount = ((summary['discount_amount'] as num?) ?? 0)
            .toDouble()
            .abs();
        final discountType = (summary['discount_type'] ?? 'none').toString();
        final discountValue = ((summary['discount_value'] as num?) ?? 0)
            .toDouble()
            .abs();
        final payment = (summary['payment_method'] ?? 'cash').toString();
        final createdAt = (summary['created_at'] ?? '').toString();
        final amountTendered = ((summary['amount_tendered'] as num?) ?? 0)
            .toDouble();
        final changeAmount = ((summary['change_amount'] as num?) ?? 0)
            .toDouble();
        final receiptItems = _buildReceiptItems(items, summary);
        final discountPercentLabel = discountAmount > 0
            ? _discountPercentLabel(
                discountAmount: discountAmount,
                baseAmount: subtotal,
                discountType: discountType,
                discountValue: discountValue,
              )
            : null;

        Widget headerChip({
          required IconData icon,
          required String label,
          Color? color,
        }) {
          final chipColor = color ?? textSecondary;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: chipColor.withOpacity(isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: chipColor.withOpacity(0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: chipColor),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        Widget detailLine(String label, String value) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        Widget itemCard(int index) {
          final item = items[index];
          final receiptItem = receiptItems[index];
          final name = (item['product_name'] ?? 'Item').toString();
          final barcode = (item['barcode'] ?? '').toString().trim();
          final unitPrice = ((receiptItem['unitPrice'] as num?) ?? 0)
              .toDouble();
          final markedPrice =
              ((receiptItem['markedPrice'] as num?) ?? unitPrice).toDouble();
          final qty = ((receiptItem['qty'] as num?) ?? 0).toDouble();
          final lineTotal = ((receiptItem['lineTotal'] as num?) ?? 0)
              .toDouble();
          final itemDiscountAmount =
              ((receiptItem['itemDiscountAmount'] as num?) ?? 0)
                  .toDouble()
                  .abs();
          final itemDiscountType = (receiptItem['itemDiscountType'] ?? 'none')
              .toString();
          final itemDiscountValue =
              ((receiptItem['itemDiscountValue'] as num?) ?? 0)
                  .toDouble()
                  .abs();
          final baseLineTotal =
              ((receiptItem['baseLineTotal'] as num?) ?? lineTotal)
                  .toDouble()
                  .abs();
          final itemDiscountPercent = itemDiscountAmount > 0
              ? _discountPercentLabel(
                  discountAmount: itemDiscountAmount,
                  baseAmount: baseLineTotal,
                  discountType: itemDiscountType,
                  discountValue: itemDiscountValue,
                )
              : null;

          Widget columnValue(
            String label,
            String value, {
            TextAlign align = TextAlign.left,
            Color? valueColor,
          }) {
            return Expanded(
              child: Column(
                crossAxisAlignment: align == TextAlign.right
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    textAlign: align,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    textAlign: align,
                    style: TextStyle(
                      color: valueColor ?? textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }

          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (barcode.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Barcode: $barcode',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    columnValue(
                      'Unit price',
                      itemDiscountPercent == null
                          ? _formatMoney(unitPrice)
                          : '${_formatMoney(unitPrice)} (-$itemDiscountPercent%)',
                      valueColor: itemDiscountPercent == null ? null : danger,
                    ),
                    const SizedBox(width: 12),
                    columnValue('Mark price', _formatMoney(markedPrice)),
                    const SizedBox(width: 12),
                    columnValue(
                      'Qty',
                      _formatQuantity(qty),
                      align: TextAlign.right,
                    ),
                    const SizedBox(width: 12),
                    columnValue(
                      'Total',
                      _formatMoney(lineTotal),
                      align: TextAlign.right,
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget totalRow(
          String label,
          String value, {
          bool strong = false,
          Color? valueColor,
        }) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$label: ',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: strong ? 20 : 15,
                    fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? textPrimary,
                    fontSize: strong ? 20 : 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        }

        Widget actionButton({
          required String label,
          required IconData icon,
          required VoidCallback onPressed,
          bool filled = false,
        }) {
          final child = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

          if (filled) {
            return Expanded(
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: child,
              ),
            );
          }

          return Expanded(
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: brand,
                side: BorderSide(color: textSecondary.withOpacity(0.7)),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: child,
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
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: MediaQuery.of(dialogContext).size.height - 48,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.32 : 0.12),
                  blurRadius: 34,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tone.withOpacity(isDark ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isRefund
                              ? Icons.undo_rounded
                              : Icons.receipt_long_rounded,
                          color: tone,
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
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Food City POS',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext, 'close'),
                        icon: Icon(Icons.close_rounded, color: textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      headerChip(
                        icon: Icons.receipt_long_rounded,
                        label: 'Transaction #$resolvedDisplayId',
                        color: textSecondary,
                      ),
                      headerChip(
                        icon: isRefund
                            ? Icons.undo_rounded
                            : Icons.point_of_sale_rounded,
                        label: isRefund ? 'Refund' : 'Sale',
                        color: tone,
                      ),
                      headerChip(
                        icon: Icons.access_time_rounded,
                        label: _formatDateTime(createdAt),
                        color: textSecondary,
                      ),
                      headerChip(
                        icon: Icons.payments_rounded,
                        label: payment.isEmpty ? 'N/A' : payment.toUpperCase(),
                        color: textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (payment.toLowerCase() == 'cash') ...[
                    detailLine('Amount Tendered', _formatMoney(amountTendered)),
                    detailLine('Change', _formatMoney(changeAmount)),
                    const SizedBox(height: 8),
                  ],
                  Divider(color: border, height: 28),
                  for (var i = 0; i < items.length; i++) itemCard(i),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          totalRow('Subtotal', _formatMoney(subtotal)),
                          if (discountAmount > 0)
                            totalRow(
                              discountPercentLabel == null
                                  ? 'Discount'
                                  : 'Discount ($discountPercentLabel%)',
                              '-${_formatMoney(discountAmount)}',
                              valueColor: danger,
                            ),
                          totalRow(
                            isRefund ? 'Refund Total' : 'Total',
                            _formatMoney(total),
                            strong: true,
                            valueColor: brand,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      actionButton(
                        label: 'Save PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        onPressed: () => Navigator.pop(dialogContext, 'pdf'),
                      ),
                      const SizedBox(width: 12),
                      actionButton(
                        label: 'Reprint',
                        icon: Icons.print_rounded,
                        onPressed: () => Navigator.pop(dialogContext, 'print'),
                      ),
                      const SizedBox(width: 12),
                      actionButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        filled: true,
                        onPressed: () => Navigator.pop(dialogContext, 'close'),
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

    if (!context.mounted) return;

    if (action == 'print') {
      await printReceiptForTransaction(
        context,
        realSaleId,
        displayId: resolvedDisplayId,
      );
    }

    if (!context.mounted) return;

    if (action == 'pdf') {
      await saveReceiptPdfForTransaction(
        context,
        realSaleId,
        displayId: resolvedDisplayId,
      );
    }
  }

  static Widget _dialogInfoRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor, {
    bool isStrong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: labelColor.withOpacity(0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: isStrong ? FontWeight.w900 : FontWeight.w800,
              fontSize: isStrong ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresentationTransactionHistoryScreenState
    extends State<PresentationTransactionHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isRefreshing = false;
  String _filter = 'all';
  String _dateFilter = 'all';
  String _searchQuery = '';
  DateTime? _selectedDate;
  int _interval = 3;
  List<PresentationVisibleTransaction> _transactions = [];

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _success = Color(0xFF1FCF9A);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _muted =>
      _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _focusSearchField();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      final context = _searchFocusNode.context;
      if (context == null) return;
      final position = Scrollable.maybeOf(context)?.position;
      position?.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  DateTime _normalizedDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _loadTransactions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      final type = _filter == 'all' ? null : _filter;
      final selectedDay = _dateFilter == 'today'
          ? _normalizedDay(DateTime.now())
          : _dateFilter == 'specific'
          ? _selectedDate
          : null;
      final start = selectedDay == null
          ? null
          : DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      final end = selectedDay == null
          ? null
          : DateTime(
              selectedDay.year,
              selectedDay.month,
              selectedDay.day,
              23,
              59,
              59,
              999,
            );

      final service = PresentationModeService.instance;
      final interval = await service.getTransactionInterval();
      final transactions = await service.getVisibleTransactions(
        transactionType: type,
        start: start,
        end: end,
        presentationSessionStartedAt: auth.presentationSessionStartedAt,
      );

      if (!mounted) return;
      setState(() {
        _interval = interval;
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load presentation transactions: $e',
        backgroundColor: _danger,
      );
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      await _loadTransactions();
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  List<PresentationVisibleTransaction> get _visibleTransactions {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _transactions;

    return _transactions.where((tx) {
      final row = tx.row;
      final displayId = tx.displayId.toString();
      final payment = (row['payment_method'] ?? '').toString().toLowerCase();
      final type = (row['transaction_type'] ?? '').toString().toLowerCase();
      final refundReason = (row['refund_reason'] ?? '')
          .toString()
          .toLowerCase();
      final createdAt = (row['created_at'] ?? '').toString().toLowerCase();
      return displayId.contains(q) ||
          payment.contains(q) ||
          type.contains(q) ||
          refundReason.contains(q) ||
          createdAt.contains(q);
    }).toList();
  }

  int get _saleCount => _transactions
      .where(
        (tx) =>
            (tx.row['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'sale',
      )
      .length;

  int get _refundCount => _transactions
      .where(
        (tx) =>
            (tx.row['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'refund',
      )
      .length;

  double get _salesTotal => _transactions
      .where(
        (tx) =>
            (tx.row['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'sale',
      )
      .fold<double>(
        0,
        (sum, tx) =>
            sum + (((tx.row['total_amount'] as num?) ?? 0).toDouble().abs()),
      );

  double get _refundTotal => _transactions
      .where(
        (tx) =>
            (tx.row['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'refund',
      )
      .fold<double>(
        0,
        (sum, tx) =>
            sum + (((tx.row['total_amount'] as num?) ?? 0).toDouble().abs()),
      );

  String _formatMoney(num value) =>
      PresentationTransactionHistoryScreen._formatMoney(value);

  String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDateTime(String raw) =>
      PresentationTransactionHistoryScreen._formatDateTime(raw);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = _normalizedDay(now);
    final selected = _selectedDate;
    final initialDate = selected != null && !selected.isAfter(today)
        ? selected
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: today,
      selectableDayPredicate: (day) => !_normalizedDay(day).isAfter(today),
      helpText: 'Select transaction date',
    );

    if (picked == null || !mounted) return;
    setState(() {
      _dateFilter = 'specific';
      _selectedDate = _normalizedDay(picked);
    });
    await _loadTransactions();
  }

  Future<void> _selectToday() async {
    if (_dateFilter == 'today') return;
    setState(() {
      _dateFilter = 'today';
      _selectedDate = null;
    });
    await _loadTransactions();
  }

  Future<void> _clearDateFilter() async {
    if (_dateFilter == 'all') return;
    setState(() {
      _dateFilter = 'all';
      _selectedDate = null;
    });
    await _loadTransactions();
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
        _loadTransactions();
      },
      selectedColor: _brand.withOpacity(0.14),
      backgroundColor: _panelSoft,
      side: BorderSide(color: selected ? _brand : _border),
      labelStyle: TextStyle(
        color: selected ? _brand : _textSecondary,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _dateChip(String value, String label, VoidCallback onTap) {
    final selected = _dateFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _blue.withOpacity(0.14),
      backgroundColor: _panelSoft,
      side: BorderSide(color: selected ? _blue : _border),
      labelStyle: TextStyle(
        color: selected ? _blue : _textSecondary,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildToolbar() {
    Widget dateActionChip({
      required String label,
      required bool selected,
      required VoidCallback onPressed,
      IconData? icon,
      Color? selectedColor,
    }) {
      final tone = selectedColor ?? _brand;
      return ActionChip(
        avatar: icon == null
            ? null
            : Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : _textPrimary,
              ),
        label: Text(label),
        onPressed: onPressed,
        backgroundColor: selected
            ? tone.withOpacity(_isDark ? 0.22 : 0.16)
            : _panelSoft,
        side: BorderSide(color: selected ? tone.withOpacity(0.45) : _border),
        labelStyle: TextStyle(
          color: selected
              ? (tone == _brand ? _brand : Colors.white)
              : _textPrimary,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText:
                        'Search by transaction, cashier, payment, or type',
                    prefixIcon: const Icon(Icons.search_rounded, color: _brand),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isRefreshing ? null : _refresh,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final typeFilters = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _filterChip('all', 'All'),
                  _filterChip('sale', 'Sales'),
                  _filterChip('refund', 'Refunds'),
                ],
              );

              final pickedDateLabel =
                  _dateFilter == 'specific' && _selectedDate != null
                  ? _formatDate(_selectedDate!)
                  : 'Pick Date';
              final dateFilters = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  dateActionChip(
                    label: 'All Dates',
                    selected: _dateFilter == 'all',
                    onPressed: _clearDateFilter,
                    selectedColor: _brand,
                  ),
                  dateActionChip(
                    label: 'Today',
                    selected: _dateFilter == 'today',
                    onPressed: _selectToday,
                    selectedColor: _blue,
                  ),
                  dateActionChip(
                    label: pickedDateLabel,
                    selected: _dateFilter == 'specific',
                    onPressed: _pickDate,
                    icon: Icons.calendar_month_rounded,
                    selectedColor: _blue,
                  ),
                ],
              );

              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    typeFilters,
                    const SizedBox(height: 10),
                    dateFilters,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: typeFilters),
                  const SizedBox(width: 12),
                  dateFilters,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(PresentationVisibleTransaction tx) {
    final row = tx.row;
    final type = (row['transaction_type'] ?? 'sale').toString().toLowerCase();
    final isRefund = type == 'refund';
    final color = isRefund ? _danger : _brand;
    final total = ((row['total_amount'] as num?) ?? 0).toDouble().abs();
    final itemCount = ((row['item_line_count'] as num?) ?? 0).toInt();
    final payment = (row['payment_method'] ?? 'cash').toString();
    final createdAt = (row['created_at'] ?? '').toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showPresentationReceipt(tx),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(_isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    '#${tx.displayId}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Transaction #${tx.displayId}',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(_isDark ? 0.18 : 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isRefund ? 'Refund' : 'Sale',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatDateTime(createdAt)} • ${payment.isEmpty ? 'N/A' : payment.toUpperCase()} • $itemCount items',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatMoney(total),
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPresentationReceipt(
    PresentationVisibleTransaction tx,
  ) async {
    await PresentationTransactionHistoryScreen.showReceiptDialogForTransaction(
      context,
      tx.realSaleId,
      displayId: tx.displayId,
    );
    if (!mounted) return;
    await _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleTransactions;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(title: const Text('Transaction History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _summaryCard(
                        'Transactions',
                        '${_transactions.length}',
                        Icons.receipt_long_rounded,
                        _blue,
                      ),
                      _summaryCard(
                        'Sales',
                        '$_saleCount',
                        Icons.shopping_cart_rounded,
                        _brand,
                      ),
                      _summaryCard(
                        'Refunds',
                        '$_refundCount',
                        Icons.undo_rounded,
                        _danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildToolbar(),
                  const SizedBox(height: 18),
                  if (visibleRows.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _border),
                      ),
                      child: Text(
                        'No transactions found.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    ...visibleRows.map(
                      (tx) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildTransactionCard(tx),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
