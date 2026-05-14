import 'package:flutter/foundation.dart';

@immutable
class CustomerPaymentReceipt {
  const CustomerPaymentReceipt({
    required this.paymentId,
    required this.receiptNo,
    required this.customerId,
    required this.customerName,
    required this.customerCode,
    this.customerPhone,
    required this.amountPaid,
    required this.previousBalance,
    required this.newBalance,
    required this.paymentMethod,
    this.referenceNote,
    this.receivedBy,
    this.cashierName,
    required this.createdAt,
    required this.isVoided,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  final int paymentId;
  final String receiptNo;
  final int customerId;
  final String customerName;
  final String customerCode;
  final String? customerPhone;
  final double amountPaid;
  final double previousBalance;
  final double newBalance;
  final String paymentMethod;
  final String? referenceNote;
  final String? receivedBy;
  final String? cashierName;
  final String createdAt;
  final bool isVoided;
  final String? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  String get statusLabel => isVoided ? 'VOIDED' : 'NORMAL';

  String get displayCustomerName {
    final trimmed = customerName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final phone = (customerPhone ?? '').trim();
    return phone.isEmpty ? 'Unnamed Customer' : phone;
  }

  String get displayCustomerCode {
    final trimmed = customerCode.trim();
    return trimmed.isEmpty ? 'CUS-UNKNOWN' : trimmed;
  }

  String get paymentMethodLabel {
    switch (paymentMethod.trim().toLowerCase()) {
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
}
