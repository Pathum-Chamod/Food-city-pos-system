import 'package:flutter/foundation.dart';

@immutable
class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    this.id,
    required this.customerId,
    required this.entryType,
    required this.debit,
    required this.credit,
    required this.balanceAfter,
    this.referenceType,
    this.referenceId,
    this.saleId,
    this.paymentId,
    this.description,
    this.paymentMethod,
    this.performedBy,
    this.approvedBy,
    required this.createdAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  final int? id;
  final int customerId;
  final String entryType;
  final double debit;
  final double credit;
  final double balanceAfter;
  final String? referenceType;
  final int? referenceId;
  final int? saleId;
  final int? paymentId;
  final String? description;
  final String? paymentMethod;
  final String? performedBy;
  final String? approvedBy;
  final String createdAt;
  final String? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  bool get isVoided => (voidedAt ?? '').trim().isNotEmpty;

  double get movementAmount {
    return double.parse((debit - credit).toStringAsFixed(2));
  }

  String get normalizedType {
    return entryType.trim().toLowerCase();
  }

  String get typeLabel {
    switch (normalizedType) {
      case 'credit_sale':
        return 'Credit Sale';
      case 'payment':
        return 'Payment';
      case 'refund':
        return 'Refund';
      case 'debit_adjustment':
        return 'Debit Adjustment';
      case 'credit_adjustment':
        return 'Credit Adjustment';
      case 'opening_balance':
        return 'Opening Balance';
      case 'void_reversal':
        return 'Void Reversal';
      default:
        return entryType;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'entry_type': normalizedType,
      'debit': debit,
      'credit': credit,
      'balance_after': balanceAfter,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'sale_id': saleId,
      'payment_id': paymentId,
      'description': description,
      'payment_method': paymentMethod,
      'performed_by': performedBy,
      'approved_by': approvedBy,
      'created_at': createdAt,
      'voided_at': voidedAt,
      'voided_by': voidedBy,
      'void_reason': voidReason,
    };
  }

  factory CustomerLedgerEntry.fromMap(Map<dynamic, dynamic> map) {
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

    return CustomerLedgerEntry(
      id: readNullableInt(map['id']),
      customerId: readInt(map['customer_id']),
      entryType: (map['entry_type'] ?? '').toString(),
      debit: readDouble(map['debit']),
      credit: readDouble(map['credit']),
      balanceAfter: readDouble(map['balance_after']),
      referenceType: readNullableString(map['reference_type']),
      referenceId: readNullableInt(map['reference_id']),
      saleId: readNullableInt(map['sale_id']),
      paymentId: readNullableInt(map['payment_id']),
      description: readNullableString(map['description']),
      paymentMethod: readNullableString(map['payment_method']),
      performedBy: readNullableString(map['performed_by']),
      approvedBy: readNullableString(map['approved_by']),
      createdAt: (map['created_at'] ?? DateTime.now().toIso8601String())
          .toString(),
      voidedAt: readNullableString(map['voided_at']),
      voidedBy: readNullableString(map['voided_by']),
      voidReason: readNullableString(map['void_reason']),
    );
  }
}
