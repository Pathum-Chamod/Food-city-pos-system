import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usb_esc_printer_windows/usb_esc_printer_windows.dart'
    as usb_esc_printer_windows;

class ReceiptPrintResponse {
  final bool isSuccess;
  final String message;

  const ReceiptPrintResponse({
    required this.isSuccess,
    required this.message,
  });
}

class ReceiptPrinterService {
  ReceiptPrinterService._();

  static final ReceiptPrinterService instance = ReceiptPrinterService._();

  static const String _savedPrinterNameKey = 'fc_receipt_printer_name';
  static const int _lineWidth = 48; // Good default for most 80mm printers

  String? _printerName;

  bool get isConnected => _printerName != null && _printerName!.trim().isNotEmpty;
  String? get connectedPrinterName => _printerName;

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
    String? approvalCode,
    String? authCode,
    String? cardLast4,
    String? cardType,
    String? footerNote,
  }) async {
    if (!Platform.isWindows) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message: 'Receipt printing is only configured for Windows in this build.',
      );
    }

    if (!isConnected || _printerName == null) {
      return const ReceiptPrintResponse(
        isSuccess: false,
        message: 'Receipt printer is not selected.',
      );
    }

    try {
      final bytes = <int>[];

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
      bytes.addAll(_text('${_line('-')}\n'));
      bytes.addAll(_boldOn());
      bytes.addAll(_text('${_itemHeader()}\n'));
      bytes.addAll(_boldOff());
      bytes.addAll(_text('${_line('-')}\n'));

      for (final item in items) {
        final name = (item['name'] ?? 'Item').toString().trim();
        final qty = ((item['qty'] as num?) ?? 0).toInt();
        final unitPrice = ((item['unitPrice'] as num?) ?? 0).toDouble();
        final lineTotal = ((item['lineTotal'] as num?) ?? 0).toDouble();

        for (final line in _wrapText(name, 28)) {
          bytes.addAll(_text('$line\n'));
        }

        bytes.addAll(
          _text(
            '${_padLeft('$qty', 4)}'
            '${_padLeft('Rs.${unitPrice.toStringAsFixed(2)}', 16)}'
            '${_padLeft('Rs.${lineTotal.toStringAsFixed(2)}', 16)}\n',
          ),
        );
      }

      bytes.addAll(_text('${_line('-')}\n'));
      bytes.addAll(_text('${_labelValue('Subtotal', 'Rs.${subtotal.toStringAsFixed(2)}')}\n'));

      if (discountAmount > 0) {
        bytes.addAll(
          _text('${_labelValue('Discount', '- Rs.${discountAmount.toStringAsFixed(2)}')}\n'),
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

      bytes.addAll(_text('${_labelValue('Paid by', paymentMethod.toUpperCase())}\n'));

      if (paymentMethod.toLowerCase() == 'cash') {
        if (amountTendered != null) {
          bytes.addAll(
            _text('${_labelValue('Tendered', 'Rs.${amountTendered.toStringAsFixed(2)}')}\n'),
          );
        }
        if (changeAmount != null) {
          bytes.addAll(
            _text('${_labelValue('Change', 'Rs.${changeAmount.toStringAsFixed(2)}')}\n'),
          );
        }
      } else {
        if ((cardType ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Card', cardType!.trim())}\n'));
        }
        if ((cardLast4 ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Last4', cardLast4!.trim())}\n'));
        }
        if ((approvalCode ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Approval', approvalCode!.trim())}\n'));
        }
        if ((authCode ?? '').trim().isNotEmpty) {
          bytes.addAll(_text('${_labelValue('Auth', authCode!.trim())}\n'));
        }
      }

      bytes.addAll(_feed(1));
      bytes.addAll(_alignCenter());
      bytes.addAll(_text('${footerNote ?? 'Thank you for shopping with us!'}\n'));
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
      return ReceiptPrintResponse(
        isSuccess: false,
        message: 'Print error: $e',
      );
    }
  }

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

  String _itemHeader() {
    const col1 = 'QTY';
    const col2 = 'UNIT';
    const col3 = 'TOTAL';

    return '${_padLeft(col1, 4)}${_padLeft(col2, 16)}${_padLeft(col3, 16)}';
  }

  String _padLeft(String value, int width) {
    final safe = value.length > width ? value.substring(0, width) : value;
    return safe.padLeft(width);
  }

  List<String> _wrapText(String text, int maxWidth) {
    final words = text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
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
            final end = (i + maxWidth < word.length) ? i + maxWidth : word.length;
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
