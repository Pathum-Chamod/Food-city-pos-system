import 'package:flutter/foundation.dart';

@immutable
class LoyaltySettings {
  const LoyaltySettings({
    this.id = 1,
    this.isEnabled = true,
    this.earnRateAmount = 100.0,
    this.earnRatePoints = 1,
    this.pointValueAmount = 1.0,
    this.minimumRedeemPoints = 100,
    this.maximumRedeemPercent = 20.0,
    this.allowCreditSaleEarn = false,
    this.roundingMode = 'floor',
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final bool isEnabled;
  final double earnRateAmount;
  final int earnRatePoints;
  final double pointValueAmount;
  final int minimumRedeemPoints;
  final double maximumRedeemPercent;
  final bool allowCreditSaleEarn;
  final String roundingMode;
  final String createdAt;
  final String updatedAt;

  String get normalizedRoundingMode {
    final value = roundingMode.trim().toLowerCase();
    if (value == 'ceil' || value == 'round') return value;
    return 'floor';
  }

  double get safeEarnRateAmount => earnRateAmount <= 0 ? 100.0 : earnRateAmount;
  int get safeEarnRatePoints => earnRatePoints <= 0 ? 1 : earnRatePoints;
  double get safePointValueAmount =>
      pointValueAmount <= 0 ? 1.0 : pointValueAmount;
  int get safeMinimumRedeemPoints =>
      minimumRedeemPoints < 0 ? 0 : minimumRedeemPoints;
  double get safeMaximumRedeemPercent {
    if (maximumRedeemPercent < 0) return 0.0;
    if (maximumRedeemPercent > 100) return 100.0;
    return maximumRedeemPercent;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'is_enabled': isEnabled ? 1 : 0,
      'earn_rate_amount': safeEarnRateAmount,
      'earn_rate_points': safeEarnRatePoints,
      'point_value_amount': safePointValueAmount,
      'minimum_redeem_points': safeMinimumRedeemPoints,
      'maximum_redeem_percent': safeMaximumRedeemPercent,
      'allow_credit_sale_earn': allowCreditSaleEarn ? 1 : 0,
      'rounding_mode': normalizedRoundingMode,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory LoyaltySettings.defaults() {
    final now = DateTime.now().toIso8601String();
    return LoyaltySettings(createdAt: now, updatedAt: now);
  }

  factory LoyaltySettings.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return LoyaltySettings(
      id: _readInt(map['id'], fallback: 1),
      isEnabled: _readBool(map['is_enabled'], fallback: true),
      earnRateAmount: _readDouble(map['earn_rate_amount'], fallback: 100.0),
      earnRatePoints: _readInt(map['earn_rate_points'], fallback: 1),
      pointValueAmount: _readDouble(map['point_value_amount'], fallback: 1.0),
      minimumRedeemPoints: _readInt(
        map['minimum_redeem_points'],
        fallback: 100,
      ),
      maximumRedeemPercent: _readDouble(
        map['maximum_redeem_percent'],
        fallback: 20.0,
      ),
      allowCreditSaleEarn: _readBool(
        map['allow_credit_sale_earn'],
        fallback: false,
      ),
      roundingMode: (map['rounding_mode'] ?? 'floor').toString(),
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
    );
  }

  static int _readInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _readDouble(dynamic value, {required double fallback}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static bool _readBool(dynamic value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return fallback;
  }
}
