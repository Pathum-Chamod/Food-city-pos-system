import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image_lib;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'receipt_printer_service.dart';
import 'receipt_text_utils.dart';

class ReceiptPdfResponse {
  final bool isSuccess;
  final String message;
  final String? filePath;

  const ReceiptPdfResponse({
    required this.isSuccess,
    required this.message,
    this.filePath,
  });
}

class ReceiptPdfService {
  ReceiptPdfService._();

  static final ReceiptPdfService instance = ReceiptPdfService._();
  static final PdfPageFormat _receiptPageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    297 * PdfPageFormat.mm,
  );
  Future<pw.Font?>? _unicodeFontFuture;

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final safeValue = value.toDouble().abs() < 0.000001
        ? 0.0
        : value.toDouble();
    return safeValue
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatMoney(num value) =>
      'Rs. ${value.toDouble().toStringAsFixed(2)}';

  String _formatPercent(num value) {
    final number = value.toDouble();
    return number.toStringAsFixed(number % 1 == 0 ? 0 : 2);
  }

  Future<pw.Font?> _loadUnicodeFont() {
    return _unicodeFontFuture ??= _resolveUnicodeFont();
  }

  Future<pw.Font?> _resolveUnicodeFont() async {
    for (final path in const [
      r'C:\Windows\Fonts\Nirmala.ttf',
      r'C:\Windows\Fonts\Iskoola.ttf',
    ]) {
      final file = File(path);
      if (!await file.exists()) continue;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;

      return pw.Font.ttf(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }

    return null;
  }

  String _discountPercentLabel({
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

  Future<ReceiptPdfResponse> saveReceiptPdf({
    required int transactionId,
    required String cashierName,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    String discountType = 'none',
    double discountValue = 0.0,
    required double total,
    double? amountTendered,
    double? changeAmount,
    String storeName = 'FOOD CITY',
    String storeAddress = 'No. 1, Main Street',
    String storePhone = '+94 11 000 0000',
    String? customerName,
    String? customerPhone,
    String? customerCode,
    bool isRefund = false,
    bool isCreditSale = false,
    double? creditPreviousBalance,
    double? creditBillAmount,
    double? creditNewBalance,
    double? creditLimit,
    String? creditApprovedBy,
    int loyaltyPointsEarned = 0,
    int loyaltyPointsRedeemed = 0,
    int? loyaltyTotalPoints,
    double loyaltyRedeemedValue = 0.0,
    double loyaltyEarnBaseAmount = 0.0,
    String? loyaltyNote,
    String? footerNote,
  }) async {
    String? outputPath;
    try {
      if (ReceiptTextUtils.receiptContainsSinhala(
        items: items,
        extraText: [
          storeName,
          storeAddress,
          storePhone,
          cashierName,
          customerName ?? '',
          customerPhone ?? '',
          customerCode ?? '',
          footerNote ?? '',
        ],
      )) {
        return saveReceiptImagePdf(
          transactionId: transactionId,
          cashierName: cashierName,
          paymentMethod: paymentMethod,
          customerName: customerName,
          items: items,
          subtotal: subtotal,
          discountAmount: discountAmount,
          discountType: discountType,
          discountValue: discountValue,
          total: total,
          amountTendered: amountTendered,
          changeAmount: changeAmount,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          isRefund: isRefund,
          isCreditSale: isCreditSale,
          creditPreviousBalance: creditPreviousBalance,
          creditBillAmount: creditBillAmount,
          creditNewBalance: creditNewBalance,
          creditLimit: creditLimit,
          creditApprovedBy: creditApprovedBy,
          loyaltyPointsEarned: loyaltyPointsEarned,
          loyaltyPointsRedeemed: loyaltyPointsRedeemed,
          loyaltyTotalPoints: loyaltyTotalPoints,
          loyaltyRedeemedValue: loyaltyRedeemedValue,
          footerNote: footerNote,
        );
      }
      final now = DateTime.now();
      final fileName =
          'receipt_${transactionId}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';

      final pdf = pw.Document();
      final shouldShowSubtotal =
          (subtotal - total).abs() > 0.000001 || discountAmount > 0;
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/'
          '${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      final cleanCustomerName = (customerName ?? '').trim();
      final hasCustomer = cleanCustomerName.isNotEmpty;
      final markedItemsTotal = items.fold<double>(0, (sum, item) {
        final qty = ((item['qty'] as num?) ?? 0).toDouble().abs();
        final unitPrice = ((item['unitPrice'] as num?) ?? 0).toDouble().abs();
        final markedPrice = ((item['markedPrice'] as num?) ?? unitPrice)
            .toDouble()
            .abs();
        return sum + (markedPrice * qty);
      });
      final totalSavings = markedItemsTotal > total.abs()
          ? markedItemsTotal - total.abs()
          : 0.0;
      final paymentMethodLower = paymentMethod.toLowerCase();
      final isCustomerCredit =
          isCreditSale ||
          paymentMethodLower == 'customer_credit' ||
          paymentMethodLower == 'customer_credit_refund';
      final hasLoyalty =
          loyaltyPointsRedeemed != 0 ||
          loyaltyRedeemedValue.abs() > 0.000001 ||
          loyaltyPointsEarned != 0 ||
          loyaltyTotalPoints != null;
      final unicodeFont =
          ReceiptTextUtils.receiptContainsSinhala(
            items: items,
            extraText: [
              storeName,
              storeAddress,
              storePhone,
              cashierName,
              cleanCustomerName,
              footerNote ?? '',
            ],
          )
          ? await _loadUnicodeFont()
          : null;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: _receiptPageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          build: (context) => [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  storeName.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    fontFallback: unicodeFont == null
                        ? const []
                        : [unicodeFont],
                  ),
                ),
                if (storeAddress.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    storeAddress.trim(),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontFallback: unicodeFont == null
                          ? const []
                          : [unicodeFont],
                    ),
                  ),
                ],
                if (storePhone.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Tel: ${storePhone.trim()}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontFallback: unicodeFont == null
                          ? const []
                          : [unicodeFont],
                    ),
                  ),
                ],
                pw.SizedBox(height: 6),
                pw.Text(
                  isRefund ? '*** REFUND RECEIPT ***' : 'SALES RECEIPT',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                _receiptDivider(),
                _receiptLabelValue('Date', dateStr, unicodeFont: unicodeFont),
                _receiptLabelValue(
                  'Txn',
                  '#$transactionId',
                  unicodeFont: unicodeFont,
                ),
                _receiptLabelValue(
                  'Cashier',
                  cashierName,
                  unicodeFont: unicodeFont,
                ),
                if (hasCustomer)
                  _receiptLabelValue(
                    'Customer',
                    cleanCustomerName,
                    unicodeFont: unicodeFont,
                  ),
                _receiptDivider(),
                _receiptItemHeader(unicodeFont: unicodeFont),
                _receiptThinDivider(),
                pw.SizedBox(height: 3),
                ...items.expand((item) {
                  final name = (item['name'] ?? 'Item').toString();
                  final qty = ((item['qty'] as num?) ?? 0).toDouble();
                  final unitPrice = ((item['unitPrice'] as num?) ?? 0)
                      .toDouble();
                  final markedPrice =
                      ((item['markedPrice'] as num?) ?? unitPrice).toDouble();
                  final baseLineTotal =
                      ((item['baseLineTotal'] as num?) ?? (unitPrice * qty))
                          .toDouble();
                  final itemDiscountAmount =
                      ((item['itemDiscountAmount'] as num?) ?? 0).toDouble();
                  final itemDiscountType = (item['itemDiscountType'] ?? 'none')
                      .toString();
                  final itemDiscountValue =
                      ((item['itemDiscountValue'] as num?) ?? 0).toDouble();
                  final lineTotal = ((item['lineTotal'] as num?) ?? 0)
                      .toDouble();
                  final itemDiscountPercent = _discountPercentLabel(
                    discountAmount: itemDiscountAmount,
                    baseAmount: baseLineTotal,
                    discountType: itemDiscountType,
                    discountValue: itemDiscountValue,
                  );
                  final unitPriceText = itemDiscountAmount > 0
                      ? '${_formatMoney(unitPrice)} (-$itemDiscountPercent%)'
                      : _formatMoney(unitPrice);

                  return [
                    pw.SizedBox(height: 5),
                    _receiptText(
                      name,
                      bold: true,
                      fontSize: 8.4,
                      unicodeFont: unicodeFont,
                    ),
                    pw.SizedBox(height: 2),
                    _receiptItemValueRow(
                      unitPrice: unitPriceText,
                      markedPrice: _formatMoney(markedPrice),
                      quantity: _formatQuantity(qty),
                      total: _formatMoney(lineTotal),
                      unicodeFont: unicodeFont,
                    ),
                    pw.SizedBox(height: 3),
                  ];
                }),
                if (shouldShowSubtotal) ...[
                  _receiptDivider(),
                  _receiptLabelValue(
                    'Subtotal',
                    _formatMoney(subtotal),
                    unicodeFont: unicodeFont,
                  ),
                ],
                if (discountAmount > 0)
                  _receiptLabelValue(
                    'Discount (${_discountPercentLabel(discountAmount: discountAmount, baseAmount: subtotal, discountType: discountType, discountValue: discountValue)}%)',
                    '- ${_formatMoney(discountAmount)}',
                    valueColor: PdfColors.red700,
                    unicodeFont: unicodeFont,
                  ),
                _receiptDivider(char: '='),
                _receiptLabelValue(
                  isRefund ? 'REFUND TOTAL' : 'TOTAL',
                  _formatMoney(total),
                  bold: true,
                  fontSize: 11,
                  unicodeFont: unicodeFont,
                ),
                _receiptDivider(char: '='),
                _receiptLabelValue(
                  'Paid by',
                  isCustomerCredit
                      ? (isRefund
                            ? 'CUSTOMER CREDIT REFUND'
                            : 'CUSTOMER CREDIT')
                      : paymentMethod.toUpperCase(),
                  unicodeFont: unicodeFont,
                ),
                if (isCustomerCredit) ...[
                  if (creditPreviousBalance != null)
                    _receiptLabelValue(
                      'Prev. Balance',
                      _formatMoney(creditPreviousBalance),
                      unicodeFont: unicodeFont,
                    ),
                  _receiptLabelValue(
                    isRefund ? 'This Refund' : 'This Bill',
                    _formatMoney(creditBillAmount ?? total),
                    unicodeFont: unicodeFont,
                  ),
                  if (creditNewBalance != null)
                    _receiptLabelValue(
                      'New Balance',
                      _formatMoney(creditNewBalance),
                      unicodeFont: unicodeFont,
                    ),
                  if (creditLimit != null && creditLimit > 0)
                    _receiptLabelValue(
                      'Credit Limit',
                      _formatMoney(creditLimit),
                      unicodeFont: unicodeFont,
                    ),
                  if ((creditApprovedBy ?? '').trim().isNotEmpty)
                    _receiptLabelValue(
                      'Approved By',
                      creditApprovedBy!.trim(),
                      unicodeFont: unicodeFont,
                    ),
                ],
                if (!isRefund && !isCustomerCredit && amountTendered != null)
                  _receiptLabelValue(
                    'Tendered',
                    _formatMoney(amountTendered),
                    unicodeFont: unicodeFont,
                  ),
                if (!isRefund && !isCustomerCredit && changeAmount != null)
                  _receiptLabelValue(
                    'Change',
                    _formatMoney(changeAmount),
                    unicodeFont: unicodeFont,
                  ),
                if (hasLoyalty) ...[
                  pw.SizedBox(height: 4),
                  if (loyaltyPointsRedeemed != 0 ||
                      loyaltyRedeemedValue.abs() > 0.000001)
                    _receiptLabelValue(
                      'Loyalty redeemed',
                      _formatMoney(loyaltyRedeemedValue.abs()),
                      fontSize: 7,
                      valueColor: PdfColors.grey700,
                      unicodeFont: unicodeFont,
                    ),
                  if (loyaltyPointsEarned != 0)
                    _receiptLabelValue(
                      isRefund
                          ? 'Loyalty points reversed'
                          : 'Loyalty points earned',
                      '${loyaltyPointsEarned.abs()} pts',
                      fontSize: 7,
                      valueColor: PdfColors.grey700,
                      unicodeFont: unicodeFont,
                    ),
                  if (loyaltyTotalPoints != null)
                    _receiptLabelValue(
                      'Total Loyalty points',
                      '${loyaltyTotalPoints.abs()} pts',
                      fontSize: 7,
                      valueColor: PdfColors.grey700,
                      unicodeFont: unicodeFont,
                    ),
                ],
                if (!isRefund && totalSavings > 0.000001) ...[
                  _receiptThinDivider(),
                  pw.Text(
                    'You Save: ${_formatMoney(totalSavings)}!',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
                pw.SizedBox(height: 10),
                pw.Text(
                  footerNote ?? 'Thank you for shopping with us!',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontFallback: unicodeFont == null
                        ? const []
                        : [unicodeFont],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      final pdfBytes = await pdf.save();
      if (pdfBytes.isEmpty) {
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: generated receipt file was empty.',
        );
      }

      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save receipt as PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'PDF save canceled.',
        );
      }

      final file = File(outputPath);
      await file.writeAsBytes(pdfBytes, flush: true);
      final writtenBytes = await file.length();
      if (writtenBytes <= 0) {
        if (await file.exists()) {
          await file.delete();
        }
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: no data was written to the file.',
        );
      }

      return ReceiptPdfResponse(
        isSuccess: true,
        message: 'Receipt PDF saved to $outputPath',
        filePath: outputPath,
      );
    } catch (e) {
      final path = outputPath;
      if (path != null && path.trim().isNotEmpty) {
        final file = File(path);
        if (await file.exists() && await file.length() == 0) {
          await file.delete();
        }
      }
      return ReceiptPdfResponse(
        isSuccess: false,
        message: 'Could not save PDF: $e',
      );
    }
  }

  Future<ReceiptPdfResponse> saveReceiptImagePdf({
    required int transactionId,
    required String cashierName,
    required String paymentMethod,
    String? customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    String discountType = 'none',
    double discountValue = 0.0,
    required double total,
    double? amountTendered,
    double? changeAmount,
    String storeName = 'FOOD CITY',
    String storeAddress = 'No. 1, Main Street',
    String storePhone = '+94 11 000 0000',
    bool isRefund = false,
    bool isCreditSale = false,
    double? creditPreviousBalance,
    double? creditBillAmount,
    double? creditNewBalance,
    double? creditLimit,
    String? creditApprovedBy,
    int loyaltyPointsEarned = 0,
    int loyaltyPointsRedeemed = 0,
    int? loyaltyTotalPoints,
    double loyaltyRedeemedValue = 0.0,
    String? footerNote,
  }) async {
    String? outputPath;
    try {
      final now = DateTime.now();
      final fileName =
          'receipt_${transactionId}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';
      final imageBytes = await ReceiptPrinterService.instance
          .renderReceiptImage(
            transactionId: transactionId,
            cashierName: cashierName,
            paymentMethod: paymentMethod,
            customerName: customerName,
            items: items,
            subtotal: subtotal,
            discountAmount: discountAmount,
            discountType: discountType,
            discountValue: discountValue,
            total: total,
            amountTendered: amountTendered,
            changeAmount: changeAmount,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            isRefund: isRefund,
            isCreditSale: isCreditSale,
            creditPreviousBalance: creditPreviousBalance,
            creditBillAmount: creditBillAmount,
            creditNewBalance: creditNewBalance,
            creditLimit: creditLimit,
            creditApprovedBy: creditApprovedBy,
            loyaltyPointsEarned: loyaltyPointsEarned,
            loyaltyPointsRedeemed: loyaltyPointsRedeemed,
            loyaltyTotalPoints: loyaltyTotalPoints,
            loyaltyRedeemedValue: loyaltyRedeemedValue,
            footerNote: footerNote,
          );
      final decoded = image_lib.decodePng(imageBytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: generated receipt image was invalid.',
        );
      }

      final pageWidth = 80 * PdfPageFormat.mm;
      final imageHeight = pageWidth * decoded.height / decoded.width;
      final minHeight = 297 * PdfPageFormat.mm;
      final pageHeight = imageHeight < minHeight ? minHeight : imageHeight;
      final pdf = pw.Document();
      final receiptImage = pw.MemoryImage(imageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, pageHeight),
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Image(
            receiptImage,
            width: pageWidth,
            height: imageHeight,
            fit: pw.BoxFit.fill,
          ),
        ),
      );

      final pdfBytes = await pdf.save();
      if (pdfBytes.isEmpty) {
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: generated receipt file was empty.',
        );
      }

      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save receipt as PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'PDF save canceled.',
        );
      }

      final file = File(outputPath);
      await file.writeAsBytes(pdfBytes, flush: true);
      final writtenBytes = await file.length();
      if (writtenBytes <= 0) {
        if (await file.exists()) {
          await file.delete();
        }
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: no data was written to the file.',
        );
      }

      return ReceiptPdfResponse(
        isSuccess: true,
        message: 'Receipt PDF saved to $outputPath',
        filePath: outputPath,
      );
    } catch (e) {
      final path = outputPath;
      if (path != null && path.trim().isNotEmpty) {
        final file = File(path);
        if (await file.exists() && await file.length() == 0) {
          await file.delete();
        }
      }
      return ReceiptPdfResponse(
        isSuccess: false,
        message: 'Could not save PDF: $e',
      );
    }
  }

  pw.Widget _receiptDivider({String char = '-'}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      child: pw.Row(
        children: List.generate(
          char == '=' ? 38 : 48,
          (index) => pw.Expanded(
            child: pw.Container(
              height: char == '=' ? 1.1 : 0.8,
              margin: const pw.EdgeInsets.symmetric(horizontal: 0.8),
              color: char == '=' ? PdfColors.grey800 : PdfColors.grey600,
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _receiptThinDivider() {
    return pw.Container(
      height: 0.5,
      margin: const pw.EdgeInsets.only(top: 3, bottom: 6),
      color: PdfColors.grey500,
    );
  }

  pw.Widget _receiptText(
    String value, {
    bool bold = false,
    bool alignRight = false,
    double fontSize = 8,
    PdfColor? color,
    pw.Font? unicodeFont,
  }) {
    return pw.Text(
      value,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
        fontFallback: unicodeFont == null ? const [] : [unicodeFont],
      ),
    );
  }

  pw.Widget _receiptItemHeader({pw.Font? unicodeFont}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 1, bottom: 2),
      child: pw.Row(
        children: [
          _receiptItemCell(
            'Unit price',
            flex: 30,
            bold: true,
            unicodeFont: unicodeFont,
          ),
          _receiptItemCell(
            'Mark price',
            flex: 27,
            bold: true,
            unicodeFont: unicodeFont,
          ),
          _receiptItemCell(
            'Qty',
            flex: 13,
            bold: true,
            alignRight: true,
            unicodeFont: unicodeFont,
          ),
          _receiptItemCell(
            'Total',
            flex: 30,
            bold: true,
            alignRight: true,
            unicodeFont: unicodeFont,
          ),
        ],
      ),
    );
  }

  pw.Widget _receiptItemValueRow({
    required String unitPrice,
    required String markedPrice,
    required String quantity,
    required String total,
    pw.Font? unicodeFont,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _receiptItemCell(unitPrice, flex: 30, unicodeFont: unicodeFont),
          _receiptItemCell(markedPrice, flex: 27, unicodeFont: unicodeFont),
          _receiptItemCell(
            quantity,
            flex: 13,
            alignRight: true,
            unicodeFont: unicodeFont,
          ),
          _receiptItemCell(
            total,
            flex: 30,
            bold: true,
            alignRight: true,
            unicodeFont: unicodeFont,
          ),
        ],
      ),
    );
  }

  pw.Widget _receiptItemCell(
    String value, {
    required int flex,
    bool bold = false,
    bool alignRight = false,
    pw.Font? unicodeFont,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(right: 3),
        child: _receiptText(
          value,
          bold: bold,
          alignRight: alignRight,
          fontSize: bold ? 6.8 : 6.5,
          unicodeFont: unicodeFont,
        ),
      ),
    );
  }

  pw.Widget _receiptLabelValue(
    String label,
    String value, {
    bool bold = false,
    double fontSize = 8,
    PdfColor? valueColor,
    pw.Font? unicodeFont,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _receiptText(
              label,
              bold: bold,
              fontSize: fontSize,
              unicodeFont: unicodeFont,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _receiptText(
              value,
              bold: bold,
              alignRight: true,
              fontSize: fontSize,
              color: valueColor,
              unicodeFont: unicodeFont,
            ),
          ),
        ],
      ),
    );
  }
}
