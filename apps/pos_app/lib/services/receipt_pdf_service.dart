import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final safeValue = value.toDouble().abs() < 0.000001 ? 0.0 : value.toDouble();
    return safeValue.toStringAsFixed(maxDecimals).replaceFirst(
      RegExp(r'\.?0+$'),
      '',
    );
  }

  String _formatMoney(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

  Future<ReceiptPdfResponse> saveReceiptPdf({
    required int transactionId,
    required String cashierName,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    required double total,
    double? amountTendered,
    double? changeAmount,
    String storeName = 'FOOD CITY',
    String storeAddress = 'No. 1, Main Street',
    String storePhone = '+94 11 000 0000',
    bool isRefund = false,
    String? footerNote,
  }) async {
    String? outputPath;
    try {
      final now = DateTime.now();
      final fileName =
          'receipt_${transactionId}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';

      final pdf = pw.Document();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/'
          '${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: _receiptPageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
                  ),
                ),
                if (storeAddress.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    storeAddress.trim(),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
                if (storePhone.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Tel: ${storePhone.trim()}',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
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
                _receiptLabelValue('Date', dateStr),
                _receiptLabelValue('Txn', '#$transactionId'),
                _receiptLabelValue('Cashier', cashierName),
                _receiptDivider(),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: _receiptText('Item', bold: true),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: _receiptText('Qty', bold: true, alignRight: true),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: _receiptText(
                        'Total',
                        bold: true,
                        alignRight: true,
                      ),
                    ),
                  ],
                ),
                _receiptDivider(),
                ...items.expand((item) {
                  final name = (item['name'] ?? 'Item').toString();
                  final qty = ((item['qty'] as num?) ?? 0).toDouble();
                  final unitPrice =
                      ((item['unitPrice'] as num?) ?? 0).toDouble();
                  final lineTotal =
                      ((item['lineTotal'] as num?) ?? 0).toDouble();

                  return [
                    _receiptText(name, bold: true),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: _receiptText(
                            '${_formatQuantity(qty)} x ${_formatMoney(unitPrice)}',
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        _receiptText(
                          _formatMoney(lineTotal),
                          bold: true,
                          alignRight: true,
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                  ];
                }),
                _receiptDivider(),
                _receiptLabelValue('Subtotal', _formatMoney(subtotal)),
                if (discountAmount > 0)
                  _receiptLabelValue(
                    'Discount',
                    '- ${_formatMoney(discountAmount)}',
                    valueColor: PdfColors.red700,
                  ),
                _receiptDivider(char: '='),
                _receiptLabelValue(
                  isRefund ? 'REFUND TOTAL' : 'TOTAL',
                  _formatMoney(total),
                  bold: true,
                  fontSize: 11,
                ),
                _receiptDivider(char: '='),
                _receiptLabelValue('Paid by', paymentMethod.toUpperCase()),
                if (!isRefund && amountTendered != null)
                  _receiptLabelValue('Tendered', _formatMoney(amountTendered)),
                if (!isRefund && changeAmount != null)
                  _receiptLabelValue('Change', _formatMoney(changeAmount)),
                pw.SizedBox(height: 10),
                pw.Text(
                  footerNote ?? 'Thank you for shopping with us!',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
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

  pw.Widget _receiptDivider({String char = '-'}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Text(
        List.filled(32, char).join(),
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  pw.Widget _receiptText(
    String value, {
    bool bold = false,
    bool alignRight = false,
    double fontSize = 8,
    PdfColor? color,
  }) {
    return pw.Text(
      value,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    );
  }

  pw.Widget _receiptLabelValue(
    String label,
    String value, {
    bool bold = false,
    double fontSize = 8,
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _receiptText(label, bold: bold, fontSize: fontSize),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _receiptText(
              value,
              bold: bold,
              alignRight: true,
              fontSize: fontSize,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
