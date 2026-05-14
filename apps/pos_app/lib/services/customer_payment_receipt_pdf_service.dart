import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared/models/customer_payment_receipt.dart';

import 'receipt_pdf_service.dart';

class CustomerPaymentReceiptPdfService {
  CustomerPaymentReceiptPdfService._();

  static final CustomerPaymentReceiptPdfService instance =
      CustomerPaymentReceiptPdfService._();

  static final PdfPageFormat _tillPageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    297 * PdfPageFormat.mm,
  );

  Future<ReceiptPdfResponse> savePaymentReceiptPdf({
    required CustomerPaymentReceipt receipt,
    String storeName = 'FOOD CITY',
    String storeAddress = 'No. 1, Main Street',
    String storePhone = '+94 11 000 0000',
  }) async {
    String? outputPath;
    try {
      final fileName =
          'customer_payment_${receipt.receiptNo.toLowerCase()}_${_fileStamp(DateTime.now())}.pdf';
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: _tillPageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          build: (context) => [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _centerText(storeName.toUpperCase(), fontSize: 14, bold: true),
                if (storeAddress.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _centerText(storeAddress.trim(), fontSize: 8),
                ],
                if (storePhone.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _centerText('Tel: ${storePhone.trim()}', fontSize: 8),
                ],
                _divider(),
                _centerText(
                  'CUSTOMER PAYMENT RECEIPT',
                  fontSize: 9,
                  bold: true,
                ),
                pw.SizedBox(height: 4),
                _centerText(receipt.receiptNo, fontSize: 8, bold: true),
                if (receipt.isVoided) ...[
                  pw.SizedBox(height: 5),
                  _centerText('*** VOIDED ***', fontSize: 10, bold: true),
                ],
                _divider(),
                _labelValue('Date', _formatDate(receipt.createdAt)),
                _labelValue('Customer', receipt.displayCustomerName),
                _labelValue('Cus. Code', receipt.displayCustomerCode),
                if ((receipt.customerPhone ?? '').trim().isNotEmpty)
                  _labelValue('Phone', receipt.customerPhone!.trim()),
                _divider(),
                _labelValue('Payment', receipt.paymentMethodLabel),
                _labelValue('Received By', _dash(receipt.receivedBy)),
                if ((receipt.referenceNote ?? '').trim().isNotEmpty)
                  _wrappedLabelValue(
                    'Reference',
                    receipt.referenceNote!.trim(),
                  ),
                _divider(char: '='),
                _labelValue(
                  'Prev. Balance',
                  _money(receipt.previousBalance),
                  bold: true,
                ),
                _labelValue(
                  'Amount Paid',
                  _money(receipt.amountPaid),
                  bold: true,
                ),
                _labelValue(
                  'New Balance',
                  _money(receipt.newBalance),
                  bold: true,
                ),
                _divider(char: '='),
                if (receipt.isVoided) ...[
                  _centerText('VOID DETAILS', fontSize: 8, bold: true),
                  pw.SizedBox(height: 3),
                  _wrappedLabelValue('Voided At', _dash(receipt.voidedAt)),
                  _wrappedLabelValue('Voided By', _dash(receipt.voidedBy)),
                  _wrappedLabelValue('Reason', _dash(receipt.voidReason)),
                  _divider(),
                ],
                pw.SizedBox(height: 8),
                _centerText(
                  'Payment recorded against customer credit account.',
                  fontSize: 7.3,
                ),
                pw.SizedBox(height: 8),
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      if (bytes.isEmpty) {
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: generated receipt file was empty.',
        );
      }

      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save customer payment receipt',
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
      await file.writeAsBytes(bytes, flush: true);
      if (await file.length() <= 0) {
        if (await file.exists()) await file.delete();
        return const ReceiptPdfResponse(
          isSuccess: false,
          message: 'Could not save PDF: no data was written to the file.',
        );
      }

      await _openFile(outputPath);
      return ReceiptPdfResponse(
        isSuccess: true,
        message: 'Payment receipt PDF saved to $outputPath',
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
        message: 'Could not save payment receipt PDF: $e',
      );
    }
  }

  pw.Widget _centerText(String text, {double fontSize = 8, bool bold = false}) {
    return pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
  }

  pw.Widget _divider({String char = '-'}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      child: pw.Row(
        children: List.generate(
          char == '=' ? 38 : 48,
          (index) => pw.Expanded(
            child: pw.Text(
              char,
              style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _labelValue(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.6)),
          ),
          pw.Text(': ', style: const pw.TextStyle(fontSize: 7.6)),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: bold ? 8.2 : 7.6,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _wrappedLabelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label:', style: const pw.TextStyle(fontSize: 7.6)),
          pw.SizedBox(height: 1),
          pw.Text(value, style: const pw.TextStyle(fontSize: 7.4)),
        ],
      ),
    );
  }

  String _money(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

  String _dash(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? '-' : text;
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  String _fileStamp(DateTime value) {
    return '${value.year}${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}_'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openFile(String path) async {
    if (!Platform.isWindows) return;
    await Process.start('cmd', ['/c', 'start', '', path], runInShell: true);
  }
}
