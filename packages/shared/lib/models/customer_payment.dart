import 'package:flutter/foundation.dart';

@immutable
class CustomerPayment {
  const CustomerPayment({
    this.id,
    required this.customerId,
    required this.amount,
    required this.paymentMethod,
    this.referenceNote,
    this.cashierName,
    this.receivedBy,
    required this.createdAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  final int? id;
  final int customerId;
  final double amount;
  final String paymentMethod;
  final String? referenceNote;
  final String? cashierName;
  final String? receivedBy;
  final String createdAt;
  final String? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  bool get isVoided => (voidedAt ?? '').trim().isNotEmpty;

  String get normalizedPaymentMethod {
    final normalized = paymentMethod.trim().toLowerCase();
    if (normalized == 'card') return 'card';
    if (normalized == 'bank_transfer') return 'bank_transfer';
    if (normalized == 'cheque') return 'cheque';
    if (normalized == 'other') return 'other';
    return 'cash';
  }

  String get paymentMethodLabel {
    switch (normalizedPaymentMethod) {
      case 'card':
        return 'Card';
      case 'bank_transfer':
        return 'Bank Transfer';
      case 'cheque':
        return 'Cheque';
      case 'other':
        return 'Other';
      case 'cash':
      default:
        return 'Cash';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'amount': amount,
      'payment_method': normalizedPaymentMethod,
      'reference_note': referenceNote,
      'cashier_name': cashierName,
      'received_by': receivedBy,
      'created_at': createdAt,
      'voided_at': voidedAt,
      'voided_by': voidedBy,
      'void_reason': voidReason,
    };
  }

  factory CustomerPayment.fromMap(Map<dynamic, dynamic> map) {
    int? readNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    int readInt(dynamic value, {int fallback = 0}) {
      return readNullableInt(value) ?? fallback;
    }

    double readDouble(dynamic value, {double fallback = 0.0}) {
      if (value == null) return fallback;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? fallback;
    }

    String? readNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return CustomerPayment(
      id: readNullableInt(map['id']),
      customerId: readInt(map['customer_id']),
      amount: readDouble(map['amount']),
      paymentMethod: (map['payment_method'] ?? 'cash').toString(),
      referenceNote: readNullableString(map['reference_note']),
      cashierName: readNullableString(map['cashier_name']),
      receivedBy: readNullableString(map['received_by']),
      createdAt: (map['created_at'] ?? DateTime.now().toIso8601String())
          .toString(),
      voidedAt: readNullableString(map['voided_at']),
      voidedBy: readNullableString(map['voided_by']),
      voidReason: readNullableString(map['void_reason']),
    );
  }
}
