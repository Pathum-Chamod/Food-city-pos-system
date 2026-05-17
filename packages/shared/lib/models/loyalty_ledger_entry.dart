import 'package:flutter/foundation.dart';

enum LoyaltyEntryType {
  earn,
  redeem,
  refundEarnReversal,
  refundRedeemRestore,
  manualAdjustment,
  voidReversal,
}

extension LoyaltyEntryTypeX on LoyaltyEntryType {
  String get dbValue {
    switch (this) {
      case LoyaltyEntryType.earn:
        return 'earn';
      case LoyaltyEntryType.redeem:
        return 'redeem';
      case LoyaltyEntryType.refundEarnReversal:
        return 'refund_earn_reversal';
      case LoyaltyEntryType.refundRedeemRestore:
        return 'refund_redeem_restore';
      case LoyaltyEntryType.manualAdjustment:
        return 'manual_adjustment';
      case LoyaltyEntryType.voidReversal:
        return 'void_reversal';
    }
  }

  String get label {
    switch (this) {
      case LoyaltyEntryType.earn:
        return 'Earn';
      case LoyaltyEntryType.redeem:
        return 'Redeem';
      case LoyaltyEntryType.refundEarnReversal:
        return 'Refund Earn Reversal';
      case LoyaltyEntryType.refundRedeemRestore:
        return 'Refund Redeem Restore';
      case LoyaltyEntryType.manualAdjustment:
        return 'Manual Adjustment';
      case LoyaltyEntryType.voidReversal:
        return 'Void Reversal';
    }
  }

  static LoyaltyEntryType fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'redeem':
        return LoyaltyEntryType.redeem;
      case 'refund_earn_reversal':
        return LoyaltyEntryType.refundEarnReversal;
      case 'refund_redeem_restore':
        return LoyaltyEntryType.refundRedeemRestore;
      case 'manual_adjustment':
        return LoyaltyEntryType.manualAdjustment;
      case 'void_reversal':
        return LoyaltyEntryType.voidReversal;
      case 'earn':
      default:
        return LoyaltyEntryType.earn;
    }
  }
}

@immutable
class LoyaltyLedgerEntry {
  const LoyaltyLedgerEntry({
    this.id,
    required this.customerId,
    required this.entryType,
    required this.pointsDelta,
    required this.pointsBalanceAfter,
    this.moneyValue = 0.0,
    this.saleId,
    this.refundSaleId,
    this.description,
    required this.createdAt,
    this.createdBy,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  final int? id;
  final int customerId;
  final LoyaltyEntryType entryType;
  final int pointsDelta;
  final int pointsBalanceAfter;
  final double moneyValue;
  final int? saleId;
  final int? refundSaleId;
  final String? description;
  final String createdAt;
  final String? createdBy;
  final String? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  bool get isVoided => (voidedAt ?? '').trim().isNotEmpty;
  bool get isPositive => pointsDelta > 0;
  bool get isNegative => pointsDelta < 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'entry_type': entryType.dbValue,
      'points_delta': pointsDelta,
      'points_balance_after': pointsBalanceAfter,
      'money_value': moneyValue,
      'sale_id': saleId,
      'refund_sale_id': refundSaleId,
      'description': description,
      'created_at': createdAt,
      'created_by': createdBy,
      'voided_at': voidedAt,
      'voided_by': voidedBy,
      'void_reason': voidReason,
    };
  }

  factory LoyaltyLedgerEntry.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return LoyaltyLedgerEntry(
      id: _readNullableInt(map['id']),
      customerId: _readInt(map['customer_id']),
      entryType: LoyaltyEntryTypeX.fromDb(map['entry_type']?.toString()),
      pointsDelta: _readInt(map['points_delta']),
      pointsBalanceAfter: _readInt(map['points_balance_after']),
      moneyValue: _readDouble(map['money_value']),
      saleId: _readNullableInt(map['sale_id']),
      refundSaleId: _readNullableInt(map['refund_sale_id']),
      description: _readNullableString(map['description']),
      createdAt: (map['created_at'] ?? now).toString(),
      createdBy: _readNullableString(map['created_by']),
      voidedAt: _readNullableString(map['voided_at']),
      voidedBy: _readNullableString(map['voided_by']),
      voidReason: _readNullableString(map['void_reason']),
    );
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static int _readInt(dynamic value, {int fallback = 0}) {
    return _readNullableInt(value) ?? fallback;
  }

  static double _readDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static String? _readNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
