import 'package:flutter/foundation.dart';

enum LoyaltyExclusionTarget { category, product }

extension LoyaltyExclusionTargetX on LoyaltyExclusionTarget {
  String get label {
    switch (this) {
      case LoyaltyExclusionTarget.category:
        return 'Category';
      case LoyaltyExclusionTarget.product:
        return 'Product';
    }
  }
}

@immutable
class LoyaltyExclusion {
  const LoyaltyExclusion({
    this.id,
    required this.target,
    required this.value,
    this.productNameSnapshot,
    this.excludeEarning = true,
    this.excludeRedemption = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final LoyaltyExclusionTarget target;
  final String value;
  final String? productNameSnapshot;
  final bool excludeEarning;
  final bool excludeRedemption;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  String get displayName {
    if (target == LoyaltyExclusionTarget.product) {
      final productName = (productNameSnapshot ?? '').trim();
      return productName.isEmpty ? value : productName;
    }
    return value;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (target == LoyaltyExclusionTarget.category)
        'category_name': value
      else
        'barcode': value,
      if (target == LoyaltyExclusionTarget.product)
        'product_name_snapshot': productNameSnapshot ?? value,
      'exclude_earning': excludeEarning ? 1 : 0,
      'exclude_redemption': excludeRedemption ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory LoyaltyExclusion.fromCategoryMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return LoyaltyExclusion(
      id: _readNullableInt(map['id']),
      target: LoyaltyExclusionTarget.category,
      value: (map['category_name'] ?? '').toString(),
      excludeEarning: _readBool(map['exclude_earning'], fallback: true),
      excludeRedemption: _readBool(map['exclude_redemption'], fallback: false),
      isActive: _readBool(map['is_active'], fallback: true),
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
    );
  }

  factory LoyaltyExclusion.fromProductMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return LoyaltyExclusion(
      id: _readNullableInt(map['id']),
      target: LoyaltyExclusionTarget.product,
      value: (map['barcode'] ?? '').toString(),
      productNameSnapshot: _readNullableString(map['product_name_snapshot']),
      excludeEarning: _readBool(map['exclude_earning'], fallback: true),
      excludeRedemption: _readBool(map['exclude_redemption'], fallback: false),
      isActive: _readBool(map['is_active'], fallback: true),
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
    );
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _readNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
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
