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
    try {
      final now = DateTime.now();
      final fileName =
          'receipt_${transactionId}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';

      final outputPath = await FilePicker.platform.saveFile(
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
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    storeName,
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (storeAddress.trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text(storeAddress),
                    ),
                  if (storePhone.trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text('Tel: $storePhone'),
                    ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    isRefund ? 'REFUND RECEIPT' : 'SALES RECEIPT',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: isRefund ? PdfColors.red700 : PdfColors.teal700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfLabelValue('Date', dateStr),
                  _pdfLabelValue('Transaction', '#$transactionId'),
                  _pdfLabelValue('Cashier', cashierName),
                  _pdfLabelValue('Payment', paymentMethod.toUpperCase()),
                  if (!isRefund && amountTendered != null)
                    _pdfLabelValue(
                      'Tendered',
                      'Rs. ${amountTendered.toStringAsFixed(2)}',
                    ),
                  if (!isRefund && changeAmount != null)
                    _pdfLabelValue(
                      'Change',
                      'Rs. ${changeAmount.toStringAsFixed(2)}',
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(8),
              headers: const ['Item', 'Qty', 'Unit Price', 'Line Total'],
              data: items.map((item) {
                return [
                  (item['name'] ?? 'Item').toString(),
                  (((item['qty'] as num?) ?? 0).toInt()).toString(),
                  'Rs. ${(((item['unitPrice'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                  'Rs. ${(((item['lineTotal'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Subtotal: Rs. ${subtotal.toStringAsFixed(2)}'),
                  if (discountAmount > 0)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 4),
                      child: pw.Text(
                        'Discount: - Rs. ${discountAmount.toStringAsFixed(2)}',
                        style: const pw.TextStyle(color: PdfColors.red700),
                      ),
                    ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Text(
                      '${isRefund ? 'Refund Total' : 'Total'}: Rs. ${total.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: isRefund ? PdfColors.red700 : PdfColors.teal700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text(
                footerNote ?? 'Thank you for shopping with us!',
                style: const pw.TextStyle(color: PdfColors.grey700),
              ),
            ),
          ],
        ),
      );

      final file = File(outputPath);
      await file.writeAsBytes(await pdf.save(), flush: true);

      return ReceiptPdfResponse(
        isSuccess: true,
        message: 'Receipt PDF saved to $outputPath',
        filePath: outputPath,
      );
    } catch (e) {
      return ReceiptPdfResponse(
        isSuccess: false,
        message: 'Could not save PDF: $e',
      );
    }
  }

  pw.Widget _pdfLabelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(value),
        ],
      ),
    );
  }
}
