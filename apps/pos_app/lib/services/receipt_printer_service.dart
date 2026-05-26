import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usb_esc_printer_windows/usb_esc_printer_windows.dart'
    as usb_esc_printer_windows;

import 'receipt_text_utils.dart';

class ReceiptPrintResponse {
  final bool isSuccess;
  final String message;

  const ReceiptPrintResponse({required this.isSuccess, required this.message});
}

class ReceiptPrinterService {
  ReceiptPrinterService._();

  static final ReceiptPrinterService instance = ReceiptPrinterService._();

  static const String _savedPrinterNameKey = 'fc_receipt_printer_name';
  static const int _lineWidth = 48; // Good default for most 80mm printers
  static const int _imageReceiptWidth = 576; // 80mm thermal width in dots.

  String? _printerName;

  bool get isConnected =>
      _printerName != null && _printerName!.trim().isNotEmpty;
  String? get connectedPrinterName => _printerName;

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final safeValue = value.toDouble().abs() < 0.000001
        ? 0.0
        : value.toDouble();
    return safeValue
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<List<String>> getInstalledPrinters() async {
    if (!Platform.isWindows) return const [];

    final printers = <String>{};

    Future<void> collect(List<String> command) async {
      try {
        final result = await Process.run(command.first, command.sublist(1));
        if (result.exitCode != 0) return;

        final output = (result.stdout ?? '').toString();
        for (final line in output.split(RegExp(r'\r?\n'))) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed.toLowerCase() == 'name') continue;
          printers.add(trimmed);
        }
      } catch (e) {
        debugPrint('[Printer] Could not run ${command.first}: $e');
      }
    }

    await collect([
      'powershell',
      '-NoProfile',
      '-Command',
      'Get-Printer | Select-Object -ExpandProperty Name',
    ]);

    if (printers.isEmpty) {
      await collect(['wmic', 'printer', 'get', 'name']);
    }

    final sorted = printers.toList()..sort();
    return sorted;
  }

  Future<bool> restoreSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_savedPrinterNameKey);

    if (savedName == null || savedName.trim().isEmpty) {
      return false;
    }

    final printers = await getInstalledPrinters();
    if (!printers.contains(savedName)) {
      return false;
    }

    _printerName = savedName;
    return true;
  }

  Future<bool> selectPrinter(String printerName) async {
    final trimmed = printerName.trim();
    if (trimmed.isEmpty) return false;

    final printers = await getInstalledPrinters();
    if (!printers.contains(trimmed)) {
      return false;
    }

    _printerName = trimmed;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedPrinterNameKey, trimmed);
    return true;
  }

  Future<void> disconnect({bool clearSaved = false}) async {
    _printerName = null;

    if (clearSaved) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedPrinterNameKey);
    }
  }

  Future<ReceiptPrintResponse> printTestSlip() async {
    return printReceipt(
      transactionId: 0,
      cashierName: 'Hardware Test',
      paymentMethod: 'cash',
      items: const [
        {
          'name': 'Printer Test Item',
          'qty': 1,
          'unitPrice': 0.0,
          'lineTotal': 0.0,
        },
      ],
      subtotal: 0.0,
      discountAmount: 0.0,
      total: 0.0,
      storeName: 'FOOD CITY',
      storeAddress: 'Windows Printer Test',
      storePhone: '',
      footerNote: 'If you can read this, receipt printing works.',
    );
  }

  Future<ReceiptPrintResponse> printReceipt({
    required int transactionId,
    required String cashierName,
    required String paymentMethod,
    String? customerName,
    String? customerPhone,
    String? customerCode,
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
    double loyaltyEarnBaseAmount = 0.0,
    String? loyaltyNote,
    String? approvalCode,
    String? authCode,
    String? cardLast4,
    String? cardType,
    String? footerNote,
  }) async {
    if (!Platform.isWindows) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message:
            'Receipt printing is only configured for Windows in this build.',
      );
    }

    if (!isConnected || _printerName == null) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message: 'Receipt printer is not selected.',
      );
    }

    final unsafeText = ReceiptTextUtils.firstEscPosUnsafeText(
      items: items,
      extraText: [
        storeName,
        storeAddress,
        storePhone,
        cashierName,
        customerName ?? '',
        footerNote ?? '',
      ],
    );
    if (unsafeText != null) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message:
            'This receipt contains Sinhala/Unicode text. Use PDF receipt output; direct ESC/POS text printing is English-safe only.',
      );
    }

    try {
      final bytes = <int>[];
      final shouldShowSubtotal =
          (subtotal - total).abs() > 0.000001 || discountAmount > 0;
      final customerNameText = (customerName ?? '').trim();
      final hasCustomer = customerNameText.isNotEmpty;
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

      // Reset + basic formatting
      bytes.addAll(_escInit());
      bytes.addAll(_alignCenter());
      bytes.addAll(_boldOn());
      bytes.addAll(_doubleSizeOn());
      bytes.addAll(_text('$storeName\n'));
      bytes.addAll(_doubleSizeOff());
      bytes.addAll(_boldOff());

      if (storeAddress.trim().isNotEmpty) {
        bytes.addAll(_text('${storeAddress.trim()}\n'));
      }
      if (storePhone.trim().isNotEmpty) {
        bytes.addAll(_text('Tel: ${storePhone.trim()}\n'));
      }

      bytes.addAll(_text('${_line('-')}\n'));

      if (isRefund) {
        bytes.addAll(_boldOn());
        bytes.addAll(_text('*** REFUND RECEIPT ***\n'));
        bytes.addAll(_boldOff());
        bytes.addAll(_feed(1));
      }

      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/'
          '${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      bytes.addAll(_alignLeft());
      bytes.addAll(_text('${_labelValue('Date', dateStr)}\n'));
      bytes.addAll(_text('${_labelValue('Txn', '#$transactionId')}\n'));
      bytes.addAll(_text('${_labelValue('Cashier', cashierName)}\n'));
      if (hasCustomer) {
        bytes.addAll(_text('${_labelValue('Customer', customerNameText)}\n'));
      }
      bytes.addAll(_text('${_line('-')}\n'));
      bytes.addAll(_boldOn());
      bytes.addAll(_text('${_itemValueHeader()}\n'));
      bytes.addAll(_boldOff());
      for (final item in items) {
        final name = (item['name'] ?? 'Item').toString().trim();
        final qty = ((item['qty'] as num?) ?? 0).toDouble();
        final unitPrice = ((item['unitPrice'] as num?) ?? 0).toDouble();
        final markedPrice = ((item['markedPrice'] as num?) ?? unitPrice)
            .toDouble();
        final baseLineTotal =
            ((item['baseLineTotal'] as num?) ?? (unitPrice * qty)).toDouble();
        final itemDiscountAmount = ((item['itemDiscountAmount'] as num?) ?? 0)
            .toDouble();
        final itemDiscountType = (item['itemDiscountType'] ?? 'none')
            .toString();
        final itemDiscountValue = ((item['itemDiscountValue'] as num?) ?? 0)
            .toDouble();
        final lineTotal = ((item['lineTotal'] as num?) ?? 0).toDouble();

        for (final line in _wrapText(name, 28)) {
          bytes.addAll(_text('$line\n'));
        }

        var unitPriceText = 'Rs.${unitPrice.toStringAsFixed(2)}';
        if (itemDiscountAmount > 0) {
          final percent = _discountPercentLabel(
            discountAmount: itemDiscountAmount,
            baseAmount: baseLineTotal,
            discountType: itemDiscountType,
            discountValue: itemDiscountValue,
          );
          unitPriceText = '$unitPriceText(-$percent%)';
        }
        bytes.addAll(
          _text(
            '${_itemValueRow(unitPrice: unitPriceText, markedPrice: 'Rs.${markedPrice.toStringAsFixed(2)}', quantity: _formatQuantity(qty), total: 'Rs.${lineTotal.toStringAsFixed(2)}')}\n\n',
          ),
        );
      }

      if (shouldShowSubtotal) {
        bytes.addAll(_text('${_line('-')}\n'));
        bytes.addAll(
          _text(
            '${_labelValue('Subtotal', 'Rs.${subtotal.toStringAsFixed(2)}')}\n',
          ),
        );
      }

      if (discountAmount > 0) {
        final percent = _discountPercentLabel(
          discountAmount: discountAmount,
          baseAmount: subtotal,
          discountType: discountType,
          discountValue: discountValue,
        );
        bytes.addAll(
          _text(
            '${_labelValue('Discount ($percent%)', '- Rs.${discountAmount.toStringAsFixed(2)}')}\n',
          ),
        );
      }

      bytes.addAll(_text('${_line('=')}\n'));
      bytes.addAll(_boldOn());
      bytes.addAll(_doubleSizeOn());
      bytes.addAll(
        _text(
          '${_labelValue(isRefund ? 'REFUND TOTAL' : 'TOTAL', 'Rs.${total.toStringAsFixed(2)}')}\n',
        ),
      );
      bytes.addAll(_doubleSizeOff());
      bytes.addAll(_boldOff());
      bytes.addAll(_text('${_line('=')}\n'));

      bytes.addAll(
        _text(
          '${_labelValue('Paid by', isCustomerCredit ? (isRefund ? 'CUSTOMER CREDIT REFUND' : 'CUSTOMER CREDIT') : paymentMethod.toUpperCase())}\n',
        ),
      );

      if (isCustomerCredit) {
        if (creditPreviousBalance != null) {
          bytes.addAll(
            _text(
              '${_labelValue('Prev. Balance', 'Rs.${creditPreviousBalance.toStringAsFixed(2)}')}\n',
            ),
          );
        }
        bytes.addAll(
          _text(
            '${_labelValue(isRefund ? 'This Refund' : 'This Bill', 'Rs.${(creditBillAmount ?? total).toStringAsFixed(2)}')}\n',
          ),
        );
        if (creditNewBalance != null) {
          bytes.addAll(
            _text(
              '${_labelValue('New Balance', 'Rs.${creditNewBalance.toStringAsFixed(2)}')}\n',
            ),
          );
        }
        if (creditLimit != null && creditLimit > 0) {
          bytes.addAll(
            _text(
              '${_labelValue('Credit Limit', 'Rs.${creditLimit.toStringAsFixed(2)}')}\n',
            ),
          );
        }
        if ((creditApprovedBy ?? '').trim().isNotEmpty) {
          bytes.addAll(
            _text('${_labelValue('Approved By', creditApprovedBy!.trim())}\n'),
          );
        }
      } else if (paymentMethod.toLowerCase() == 'cash') {
        if (amountTendered != null) {
          bytes.addAll(
            _text(
              '${_labelValue('Tendered', 'Rs.${amountTendered.toStringAsFixed(2)}')}\n',
            ),
          );
        }
        if (changeAmount != null) {
          bytes.addAll(
            _text(
              '${_labelValue('Change', 'Rs.${changeAmount.toStringAsFixed(2)}')}\n',
            ),
          );
        }
      } else if (paymentMethod.toLowerCase() == 'card') {
        if ((cardType ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Card', cardType!.trim())}\n'));
        }
        if ((cardLast4 ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Last4', cardLast4!.trim())}\n'));
        }
        if ((approvalCode ?? '').trim().isNotEmpty) {
          bytes.addAll(
            _text('${_labelValue('Approval', approvalCode!.trim())}\n'),
          );
        }
        if ((authCode ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Auth', authCode!.trim())}\n'));
        }
      }

      if (hasLoyalty) {
        bytes.addAll(_feed(1));
        if (loyaltyPointsRedeemed != 0 ||
            loyaltyRedeemedValue.abs() > 0.000001) {
          bytes.addAll(
            _text(
              '${_labelValue('Loyalty redeemed', 'Rs.${loyaltyRedeemedValue.abs().toStringAsFixed(2)}')}\n',
            ),
          );
        }
        if (loyaltyPointsEarned != 0) {
          bytes.addAll(
            _text(
              '${_labelValue(isRefund ? 'Loyalty points reversed' : 'Loyalty points earned', '${loyaltyPointsEarned.abs()} pts')}\n',
            ),
          );
        }
        if (loyaltyTotalPoints != null) {
          bytes.addAll(
            _text(
              '${_labelValue('Total Loyalty points', '${loyaltyTotalPoints.abs()} pts')}\n',
            ),
          );
        }
      }

      if (!isRefund && totalSavings > 0.000001) {
        bytes.addAll(_text('${_line('-')}\n'));
        bytes.addAll(_alignCenter());
        bytes.addAll(_boldOn());
        bytes.addAll(
          _text('You Save: Rs.${totalSavings.toStringAsFixed(2)}!\n'),
        );
        bytes.addAll(_boldOff());
      }

      bytes.addAll(_feed(1));
      bytes.addAll(_alignCenter());
      bytes.addAll(
        _text('${footerNote ?? 'Thank you for shopping with us!'}\n'),
      );
      bytes.addAll(_feed(3));
      bytes.addAll(_cut());

      final result = await usb_esc_printer_windows.sendPrintRequest(
        bytes,
        _printerName!,
      );

      if (result.toString().toLowerCase().contains('success')) {
        return ReceiptPrintResponse(
          isSuccess: true,
          message: 'Receipt printed on $_printerName',
        );
      }

      return ReceiptPrintResponse(
        isSuccess: false,
        message: 'Printer response: $result',
      );
    } catch (e) {
      debugPrint('[Printer] Print error: $e');
      return ReceiptPrintResponse(isSuccess: false, message: 'Print error: $e');
    }
  }

  Future<ReceiptPrintResponse> printReceiptImage({
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
    if (!Platform.isWindows) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message:
            'Receipt image printing is only configured for Windows in this build.',
      );
    }

    if (!isConnected || _printerName == null) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message: 'Receipt printer is not selected.',
      );
    }

    try {
      final imageBytes = await renderReceiptImage(
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
      final decoded = img.decodePng(imageBytes);
      if (decoded == null) {
        return const ReceiptPrintResponse(
          isSuccess: false,
          message: 'Could not render receipt image for printing.',
        );
      }

      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      final bytes = <int>[
        ...generator.reset(),
        ...generator.imageRaster(
          decoded,
          align: PosAlign.center,
          imageFn: PosImageFn.graphics,
        ),
        ...generator.feed(3),
        ...generator.cut(),
      ];
      final result = await usb_esc_printer_windows.sendPrintRequest(
        bytes,
        _printerName!,
      );

      if (result.toString().toLowerCase().contains('success')) {
        return ReceiptPrintResponse(
          isSuccess: true,
          message: 'Sinhala receipt image printed on $_printerName',
        );
      }

      return ReceiptPrintResponse(
        isSuccess: false,
        message: 'Receipt image printer response: $result',
      );
    } catch (e) {
      debugPrint('[Printer] Image print error: $e');
      return ReceiptPrintResponse(
        isSuccess: false,
        message: 'Receipt image print error: $e',
      );
    }
  }

  Future<Uint8List> renderReceiptImage({
    required int transactionId,
    required String cashierName,
    required String paymentMethod,
    String? customerName,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discountAmount,
    required String discountType,
    required double discountValue,
    required double total,
    double? amountTendered,
    double? changeAmount,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required bool isRefund,
    required bool isCreditSale,
    double? creditPreviousBalance,
    double? creditBillAmount,
    double? creditNewBalance,
    double? creditLimit,
    String? creditApprovedBy,
    required int loyaltyPointsEarned,
    required int loyaltyPointsRedeemed,
    int? loyaltyTotalPoints,
    required double loyaltyRedeemedValue,
    String? footerNote,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final paymentMethodLower = paymentMethod.toLowerCase();
    final isCustomerCredit =
        isCreditSale ||
        paymentMethodLower == 'customer_credit' ||
        paymentMethodLower == 'customer_credit_refund';

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), BlendMode.src);

    var y = 26.0;
    const horizontalPadding = 48.0;
    final maxWidth = _imageReceiptWidth - (horizontalPadding * 2);
    final contentRight = _imageReceiptWidth - horizontalPadding;

    double drawText(
      String text, {
      double size = 18,
      bool bold = false,
      TextAlign align = TextAlign.left,
      double before = 0,
      double after = 4,
      double? x,
      double? width,
    }) {
      y += before;
      final painter = _textPainter(
        text,
        size: size,
        bold: bold,
        align: align,
        maxWidth: width ?? maxWidth,
      );
      final paintX =
          x ??
          switch (align) {
            TextAlign.center => (_imageReceiptWidth - painter.width) / 2,
            TextAlign.right => contentRight - painter.width,
            _ => horizontalPadding,
          };
      painter.paint(canvas, Offset(paintX, y));
      y += painter.height + after;
      return painter.height;
    }

    void drawDashedDivider({bool heavy = false}) {
      y += heavy ? 8 : 10;
      final paint = Paint()
        ..color = const ui.Color(0xFF000000)
        ..strokeWidth = heavy ? 3.0 : 1.6;
      var x = horizontalPadding;
      final dashWidth = heavy ? 11.0 : 7.0;
      final gapWidth = heavy ? 4.0 : 5.0;
      while (x < contentRight) {
        final end = (x + dashWidth).clamp(horizontalPadding, contentRight);
        canvas.drawLine(Offset(x, y), Offset(end.toDouble(), y), paint);
        x += dashWidth + gapWidth;
      }
      y += heavy ? 16 : 14;
    }

    void drawThinDivider() {
      y += 4;
      final paint = Paint()
        ..color = const ui.Color(0xFF9E9E9E)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(horizontalPadding, y),
        Offset(contentRight, y),
        paint,
      );
      y += 14;
    }

    void drawPair(
      String label,
      String value, {
      bool bold = false,
      double size = 17,
      double? valueSize,
      double after = 4,
    }) {
      final labelPainter = _textPainter(
        label,
        size: size,
        bold: bold,
        maxWidth: maxWidth * 0.46,
      );
      final valuePainter = _textPainter(
        value,
        size: valueSize ?? size,
        bold: bold,
        align: TextAlign.right,
        maxWidth: maxWidth * 0.52,
      );
      labelPainter.paint(canvas, Offset(horizontalPadding, y));
      valuePainter.paint(canvas, Offset(contentRight - valuePainter.width, y));
      y +=
          (labelPainter.height > valuePainter.height
              ? labelPainter.height
              : valuePainter.height) +
          after;
    }

    void drawTableText(
      String text, {
      required double x,
      required double width,
      double size = 15,
      bool bold = false,
      TextAlign align = TextAlign.left,
    }) {
      final painter = _textPainter(
        text,
        size: size,
        bold: bold,
        align: align,
        maxWidth: width,
      );
      final paintX = switch (align) {
        TextAlign.right => x + width - painter.width,
        TextAlign.center => x + (width - painter.width) / 2,
        _ => x,
      };
      painter.paint(canvas, Offset(paintX, y));
    }

    double tableTextHeight(
      String text, {
      required double width,
      double size = 15,
      bool bold = false,
      TextAlign align = TextAlign.left,
    }) {
      return _textPainter(
        text,
        size: size,
        bold: bold,
        align: align,
        maxWidth: width,
      ).height;
    }

    drawText(
      storeName.toUpperCase(),
      size: 30,
      bold: true,
      align: TextAlign.center,
      after: 3,
    );
    if (storeAddress.trim().isNotEmpty) {
      drawText(
        storeAddress.trim(),
        size: 17,
        align: TextAlign.center,
        after: 2,
      );
    }
    if (storePhone.trim().isNotEmpty) {
      drawText(
        'Tel: ${storePhone.trim()}',
        size: 17,
        align: TextAlign.center,
        after: 8,
      );
    }
    drawText(
      isRefund ? '*** REFUND RECEIPT ***' : 'SALES RECEIPT',
      size: 21,
      bold: true,
      align: TextAlign.center,
      after: 0,
    );
    drawDashedDivider();
    drawPair('Date', dateStr);
    drawPair('Txn', '#$transactionId');
    drawPair('Cashier', cashierName);
    final customer = (customerName ?? '').trim();
    if (customer.isNotEmpty) drawPair('Customer', customer);
    drawDashedDivider();

    final col1X = horizontalPadding;
    final col1W = maxWidth * 0.30;
    final col2X = col1X + col1W;
    final col2W = maxWidth * 0.27;
    final col3X = col2X + col2W;
    final col3W = maxWidth * 0.13;
    final col4X = col3X + col3W;
    final col4W = contentRight - col4X;

    drawTableText('Unit price', x: col1X, width: col1W, bold: true);
    drawTableText('Mark price', x: col2X, width: col2W, bold: true);
    drawTableText(
      'Qty',
      x: col3X,
      width: col3W,
      bold: true,
      align: TextAlign.right,
    );
    drawTableText(
      'Total',
      x: col4X,
      width: col4W,
      bold: true,
      align: TextAlign.right,
    );
    y += 25;
    drawThinDivider();

    for (final item in items) {
      final name = (item['name'] ?? 'Item').toString().trim();
      final qty = ((item['qty'] as num?) ?? 0).toDouble();
      final unitPrice = ((item['unitPrice'] as num?) ?? 0).toDouble();
      final markedPrice = ((item['markedPrice'] as num?) ?? unitPrice)
          .toDouble();
      final baseLineTotal =
          ((item['baseLineTotal'] as num?) ?? (unitPrice * qty)).toDouble();
      final itemDiscountAmount = ((item['itemDiscountAmount'] as num?) ?? 0)
          .toDouble();
      final itemDiscountType = (item['itemDiscountType'] ?? 'none').toString();
      final itemDiscountValue = ((item['itemDiscountValue'] as num?) ?? 0)
          .toDouble();
      final lineTotal = ((item['lineTotal'] as num?) ?? 0).toDouble();
      final discountPercent = _discountPercentLabel(
        discountAmount: itemDiscountAmount,
        baseAmount: baseLineTotal,
        discountType: itemDiscountType,
        discountValue: itemDiscountValue,
      );
      final unitPriceText = itemDiscountAmount > 0
          ? '${_imageMoney(unitPrice)} (-$discountPercent%)'
          : _imageMoney(unitPrice);

      drawText(name.isEmpty ? 'Item' : name, size: 18, bold: true, after: 6);
      drawTableText(unitPriceText, x: col1X, width: col1W, size: 15);
      drawTableText(_imageMoney(markedPrice), x: col2X, width: col2W, size: 15);
      drawTableText(
        _formatQuantity(qty),
        x: col3X,
        width: col3W,
        size: 15,
        align: TextAlign.right,
      );
      drawTableText(
        _imageMoney(lineTotal),
        x: col4X,
        width: col4W,
        size: 15,
        bold: true,
        align: TextAlign.right,
      );
      final rowHeight = [
        tableTextHeight(unitPriceText, width: col1W, size: 15),
        tableTextHeight(_imageMoney(markedPrice), width: col2W, size: 15),
        tableTextHeight(
          _formatQuantity(qty),
          width: col3W,
          size: 15,
          align: TextAlign.right,
        ),
        tableTextHeight(
          _imageMoney(lineTotal),
          width: col4W,
          size: 15,
          bold: true,
          align: TextAlign.right,
        ),
      ].reduce((a, b) => a > b ? a : b);
      y += rowHeight + 13;
    }

    if ((subtotal - total).abs() > 0.000001 || discountAmount > 0) {
      drawDashedDivider();
      drawPair('Subtotal', _imageMoney(subtotal));
    }
    if (discountAmount > 0) {
      final percent = _discountPercentLabel(
        discountAmount: discountAmount,
        baseAmount: subtotal,
        discountType: discountType,
        discountValue: discountValue,
      );
      drawPair('Discount ($percent%)', '- ${_imageMoney(discountAmount)}');
    }
    drawDashedDivider(heavy: true);
    drawPair(
      isRefund ? 'REFUND TOTAL' : 'TOTAL',
      _imageMoney(total),
      bold: true,
      size: 21,
      valueSize: 22,
      after: 2,
    );
    drawDashedDivider(heavy: true);
    drawPair(
      'Paid by',
      isCustomerCredit
          ? (isRefund ? 'CUSTOMER CREDIT REFUND' : 'CUSTOMER CREDIT')
          : paymentMethod.toUpperCase(),
    );

    if (isCustomerCredit) {
      if (creditPreviousBalance != null) {
        drawPair('Prev. Balance', _imageMoney(creditPreviousBalance));
      }
      drawPair(
        isRefund ? 'This Refund' : 'This Bill',
        _imageMoney(creditBillAmount ?? total),
      );
      if (creditNewBalance != null) {
        drawPair('New Balance', _imageMoney(creditNewBalance));
      }
      if (creditLimit != null && creditLimit > 0) {
        drawPair('Credit Limit', _imageMoney(creditLimit));
      }
      if ((creditApprovedBy ?? '').trim().isNotEmpty) {
        drawPair('Approved By', creditApprovedBy!.trim());
      }
    } else if (!isRefund && paymentMethodLower == 'cash') {
      if (amountTendered != null) {
        drawPair('Tendered', _imageMoney(amountTendered));
      }
      if (changeAmount != null) drawPair('Change', _imageMoney(changeAmount));
    }

    if (loyaltyPointsRedeemed != 0 || loyaltyRedeemedValue.abs() > 0.000001) {
      y += 4;
      drawPair(
        'Loyalty redeemed',
        _imageMoney(loyaltyRedeemedValue.abs()),
        size: 15,
      );
    }
    if (loyaltyPointsEarned != 0) {
      drawPair(
        isRefund ? 'Loyalty points reversed' : 'Loyalty points earned',
        '${loyaltyPointsEarned.abs()} pts',
        size: 15,
      );
    }
    if (loyaltyTotalPoints != null) {
      drawPair(
        'Total Loyalty points',
        '${loyaltyTotalPoints.abs()} pts',
        size: 15,
      );
    }

    drawText(
      footerNote ?? 'Thank you for shopping with us!',
      size: 16,
      align: TextAlign.center,
      before: 22,
      after: 0,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(_imageReceiptWidth, y.ceil() + 24);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null || byteData.lengthInBytes == 0) {
      throw Exception('Generated receipt image was empty.');
    }
    return byteData.buffer.asUint8List();
  }

  TextPainter _textPainter(
    String text, {
    required double size,
    bool bold = false,
    TextAlign align = TextAlign.left,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const ui.Color(0xFF000000),
          fontSize: size,
          height: 1.16,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textAlign: align,
      textDirection: ui.TextDirection.ltr,
      locale: const ui.Locale('si', 'LK'),
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  String _imageMoney(num value) => 'Rs. ${value.toDouble().toStringAsFixed(2)}';

  List<int> _escInit() => [27, 64];
  List<int> _alignLeft() => [27, 97, 0];
  List<int> _alignCenter() => [27, 97, 1];
  List<int> _boldOn() => [27, 69, 1];
  List<int> _boldOff() => [27, 69, 0];
  List<int> _doubleSizeOn() => [29, 33, 17];
  List<int> _doubleSizeOff() => [29, 33, 0];
  List<int> _feed(int lines) => [27, 100, lines];
  List<int> _cut() => [29, 86, 66, 0];
  List<int> _text(String value) => latin1.encode(value);

  String _formatPercent(num value) {
    final number = value.toDouble();
    return number.toStringAsFixed(number % 1 == 0 ? 0 : 2);
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

  String _line(String char) => List.filled(_lineWidth, char).join();

  String _labelValue(String label, String value) {
    final safeLabel = label.trim();
    final safeValue = value.trim();

    if (safeLabel.length + safeValue.length + 1 >= _lineWidth) {
      return '$safeLabel: $safeValue';
    }

    final spaces = _lineWidth - safeLabel.length - safeValue.length;
    return '$safeLabel${' ' * spaces}$safeValue';
  }

  String _itemValueHeader() {
    return '${_padRight('Unit price', 15)}'
        '${_padRight('Mark price', 13)}'
        '${_padLeft('Qty', 5)}'
        '${_padLeft('Total', 15)}';
  }

  String _itemValueRow({
    required String unitPrice,
    required String markedPrice,
    required String quantity,
    required String total,
  }) {
    return '${_padRight(unitPrice, 15)}'
        '${_padRight(markedPrice, 13)}'
        '${_padLeft(quantity, 5)}'
        '${_padLeft(total, 15)}';
  }

  String _padLeft(String value, int width) {
    final safe = value.length > width ? value.substring(0, width) : value;
    return safe.padLeft(width);
  }

  String _padRight(String value, int width) {
    final safe = value.length > width ? value.substring(0, width) : value;
    return safe.padRight(width);
  }

  List<String> _wrapText(String text, int maxWidth) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (words.isEmpty) return [''];

    final lines = <String>[];
    var current = '';

    for (final word in words) {
      final next = current.isEmpty ? word : '$current $word';
      if (next.length <= maxWidth) {
        current = next;
      } else {
        if (current.isNotEmpty) {
          lines.add(current);
        }
        if (word.length <= maxWidth) {
          current = word;
        } else {
          for (var i = 0; i < word.length; i += maxWidth) {
            final end = (i + maxWidth < word.length)
                ? i + maxWidth
                : word.length;
            final chunk = word.substring(i, end);
            if (chunk.length == maxWidth || end < word.length) {
              lines.add(chunk);
            } else {
              current = chunk;
            }
          }
        }
      }
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }

    return lines;
  }
}
