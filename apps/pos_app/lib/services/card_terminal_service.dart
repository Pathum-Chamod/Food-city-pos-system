import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CardTransactionResult { approved, declined, cancelled, timeout, error }

class CardTransactionResponse {
  final CardTransactionResult result;
  final String? approvalCode;
  final String? authCode;
  final String? cardLast4;
  final String? cardType;
  final String? message;
  final double? amountCharged;

  const CardTransactionResponse({
    required this.result,
    this.approvalCode,
    this.authCode,
    this.cardLast4,
    this.cardType,
    this.message,
    this.amountCharged,
  });
}

class CardTerminalService {
  CardTerminalService._();

  static final CardTerminalService instance = CardTerminalService._();

  static const String _savedPortKey = 'fc_card_terminal_port';
  static const String _savedBaudRateKey = 'fc_card_terminal_baud_rate';

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;
  String? _connectedPortName;
  int _baudRate = 9600;

  bool get isConnected => _port != null;
  String? get connectedPortName => _connectedPortName;
  int get baudRate => _baudRate;

  List<String> getAvailablePorts() {
    try {
      return List<String>.from(SerialPort.availablePorts);
    } catch (e) {
      debugPrint('[CardTerminal] Could not list ports: $e');
      return const [];
    }
  }

  Future<bool> restoreSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getString(_savedPortKey);
    final savedBaud = prefs.getInt(_savedBaudRateKey) ?? 9600;

    if (savedPort == null || savedPort.isEmpty) {
      return false;
    }

    if (!getAvailablePorts().contains(savedPort)) {
      return false;
    }

    return connect(savedPort, baudRate: savedBaud);
  }

  Future<bool> connect(String portName, {int baudRate = 9600}) async {
    await disconnect();

    try {
      final port = SerialPort(portName);
      final didOpen = port.openReadWrite();

      if (!didOpen) {
        debugPrint('[CardTerminal] Could not open $portName');
        return false;
      }

      final config = SerialPortConfig();
      config.baudRate = baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      config.setFlowControl(SerialPortFlowControl.none);
      port.config = config;

      _port = port;
      _connectedPortName = portName;
      _baudRate = baudRate;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedPortKey, portName);
      await prefs.setInt(_savedBaudRateKey, baudRate);

      debugPrint('[CardTerminal] Connected on $portName @ $baudRate');
      return true;
    } catch (e) {
      debugPrint('[CardTerminal] Connection failed: $e');
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect({bool clearSaved = false}) async {
    try {
      await _readerSubscription?.cancel();
    } catch (_) {}
    _readerSubscription = null;

    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;

    try {
      _port?.close();
    } catch (_) {}

    try {
      _port?.dispose();
    } catch (_) {}

    _port = null;
    _connectedPortName = null;

    if (clearSaved) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedPortKey);
      await prefs.remove(_savedBaudRateKey);
    }
  }

  Future<CardTransactionResponse> requestSale(double amount) async {
    if (!isConnected || _port == null) {
      return const CardTransactionResponse(
        result: CardTransactionResult.error,
        message: 'Card terminal not connected',
      );
    }

    final amountCents = (amount * 100).round();
    final amountStr = amountCents.toString().padLeft(12, '0');
    final message = '\x02SALE$amountStr\x03';

    try {
      _port!.write(Uint8List.fromList(message.codeUnits));
      final rawResponse = await _readResponse(
        timeout: const Duration(seconds: 60),
      );

      return _parseResponse(
        rawResponse,
        requestedAmount: amount,
      );
    } catch (e) {
      return CardTransactionResponse(
        result: CardTransactionResult.error,
        message: e.toString(),
        amountCharged: amount,
      );
    }
  }

  Future<CardTransactionResponse> requestVoid(String approvalCode) async {
    if (!isConnected || _port == null) {
      return const CardTransactionResponse(
        result: CardTransactionResult.error,
        message: 'Card terminal not connected',
      );
    }

    try {
      final message = '\x02VOID$approvalCode\x03';
      _port!.write(Uint8List.fromList(message.codeUnits));
      final rawResponse = await _readResponse(
        timeout: const Duration(seconds: 30),
      );
      return _parseResponse(rawResponse);
    } catch (e) {
      return CardTransactionResponse(
        result: CardTransactionResult.error,
        message: e.toString(),
      );
    }
  }

  Future<String> _readResponse({required Duration timeout}) async {
    if (_port == null) {
      throw Exception('Card terminal is not connected');
    }

    final completer = Completer<String>();
    final buffer = StringBuffer();

    _reader = SerialPortReader(_port!);

    late final Timer timer;
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Terminal response timed out'),
        );
      }
    });

    _readerSubscription = _reader!.stream.listen(
      (data) {
        final chunk = String.fromCharCodes(data);
        buffer.write(chunk);

        if (buffer.toString().contains('\x03')) {
          timer.cancel();
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        }
      },
      onError: (error) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      cancelOnError: true,
    );

    try {
      final result = await completer.future;
      return result;
    } finally {
      timer.cancel();
      await _readerSubscription?.cancel();
      _readerSubscription = null;
      try {
        _reader?.close();
      } catch (_) {}
      _reader = null;
    }
  }

  CardTransactionResponse _parseResponse(
    String raw, {
    double? requestedAmount,
  }) {
    final normalized = raw.toUpperCase();

    String? firstMatch(RegExp pattern) {
      return pattern.firstMatch(raw)?.group(1);
    }

    if (normalized.contains('APPROVED') ||
        normalized.contains('|00|') ||
        RegExp(r'\b00\b').hasMatch(normalized)) {
      return CardTransactionResponse(
        result: CardTransactionResult.approved,
        approvalCode: firstMatch(RegExp(r'APPROVAL[:= ]*([A-Z0-9]{4,12})', caseSensitive: false)) ??
            firstMatch(RegExp(r'\b([0-9]{6})\b')),
        authCode: firstMatch(RegExp(r'AUTH[:= ]*([A-Z0-9]{4,12})', caseSensitive: false)),
        cardLast4: firstMatch(RegExp(r'(?:LAST4|CARD)[:= ]*([0-9]{4})', caseSensitive: false)),
        cardType: firstMatch(RegExp(r'(VISA|MASTERCARD|MASTERCARD|AMEX|DISCOVER)', caseSensitive: false)),
        message: 'Payment approved',
        amountCharged: requestedAmount,
      );
    }

    if (normalized.contains('DECLINED') ||
        normalized.contains('REFUSE') ||
        normalized.contains('DENIED')) {
      return const CardTransactionResponse(
        result: CardTransactionResult.declined,
        message: 'Card declined',
      );
    }

    if (normalized.contains('CANCEL') || normalized.contains('USER CANCEL')) {
      return const CardTransactionResponse(
        result: CardTransactionResult.cancelled,
        message: 'Cancelled by customer',
      );
    }

    if (normalized.contains('TIMEOUT')) {
      return const CardTransactionResponse(
        result: CardTransactionResult.timeout,
        message: 'Terminal timed out',
      );
    }

    return CardTransactionResponse(
      result: CardTransactionResult.error,
      message: 'Unknown terminal response: $raw',
      amountCharged: requestedAmount,
    );
  }
}
