import 'package:flutter/foundation.dart';

@immutable
class CustomerCreditSummary {
  const CustomerCreditSummary({
    required this.customerId,
    required this.creditEnabled,
    required this.creditLimit,
    required this.currentBalance,
    required this.creditStatus,
    this.creditNote,
  });

  final int customerId;
  final bool creditEnabled;
  final double creditLimit;
  final double currentBalance;
  final String creditStatus;
  final String? creditNote;

  double get availableCredit {
    return double.parse((creditLimit - currentBalance).toStringAsFixed(2));
  }

  bool get isBlocked => normalizedStatus == 'blocked';

  bool get isWatchlist => normalizedStatus == 'watchlist';

  bool get isOverLimit {
    if (!creditEnabled) return false;
    if (creditLimit <= 0) return currentBalance > 0;
    return currentBalance > creditLimit;
  }

  String get normalizedStatus {
    final normalized = creditStatus.trim().toLowerCase();
    if (normalized == 'blocked') return 'blocked';
    if (normalized == 'watchlist') return 'watchlist';
    return 'normal';
  }

  String get statusLabel {
    switch (normalizedStatus) {
      case 'blocked':
        return 'Blocked';
      case 'watchlist':
        return 'Watchlist';
      case 'normal':
      default:
        return 'Normal';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'customer_id': customerId,
      'credit_enabled': creditEnabled ? 1 : 0,
      'credit_limit': creditLimit,
      'current_balance': currentBalance,
      'available_credit': availableCredit,
      'credit_status': normalizedStatus,
      'credit_note': creditNote,
      'is_over_limit': isOverLimit ? 1 : 0,
      'is_blocked': isBlocked ? 1 : 0,
    };
  }

  factory CustomerCreditSummary.empty(int customerId) {
    return CustomerCreditSummary(
      customerId: customerId,
      creditEnabled: false,
      creditLimit: 0,
      currentBalance: 0,
      creditStatus: 'normal',
    );
  }

  factory CustomerCreditSummary.fromMap(Map<dynamic, dynamic> map) {
    bool readBool(dynamic value, {bool fallback = false}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value.toInt() == 1;
      final text = value.toString().trim().toLowerCase();
      if (text == '1' || text == 'true' || text == 'yes') return true;
      if (text == '0' || text == 'false' || text == 'no') return false;
      return fallback;
    }

    double readDouble(dynamic value, {double fallback = 0.0}) {
      if (value == null) return fallback;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? fallback;
    }

    int readInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString()) ?? fallback;
    }

    String? readNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return CustomerCreditSummary(
      customerId: readInt(map['customer_id'] ?? map['id']),
      creditEnabled: readBool(map['credit_enabled']),
      creditLimit: readDouble(map['credit_limit']),
      currentBalance: readDouble(
        map['current_balance'] ?? map['current_credit_balance'],
      ),
      creditStatus: (map['credit_status'] ?? 'normal').toString(),
      creditNote: readNullableString(map['credit_note']),
    );
  }
}
