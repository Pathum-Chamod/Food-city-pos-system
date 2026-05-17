import 'package:flutter/foundation.dart';

import 'product.dart';

enum PricingSchemeRuleApplyTo { all, category, product }

extension PricingSchemeRuleApplyToX on PricingSchemeRuleApplyTo {
  String get dbValue {
    switch (this) {
      case PricingSchemeRuleApplyTo.category:
        return 'category';
      case PricingSchemeRuleApplyTo.product:
        return 'product';
      case PricingSchemeRuleApplyTo.all:
        return 'all';
    }
  }

  String get label {
    switch (this) {
      case PricingSchemeRuleApplyTo.category:
        return 'Product Category';
      case PricingSchemeRuleApplyTo.product:
        return 'Specific Product';
      case PricingSchemeRuleApplyTo.all:
        return 'All Products';
    }
  }

  static PricingSchemeRuleApplyTo fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'category':
        return PricingSchemeRuleApplyTo.category;
      case 'product':
        return PricingSchemeRuleApplyTo.product;
      case 'all':
      default:
        return PricingSchemeRuleApplyTo.all;
    }
  }
}

enum PricingSchemeRuleType {
  priceType,
  percentDiscount,
  fixedPrice,
  noDiscount,
}

extension PricingSchemeRuleTypeX on PricingSchemeRuleType {
  String get dbValue {
    switch (this) {
      case PricingSchemeRuleType.priceType:
        return 'price_type';
      case PricingSchemeRuleType.percentDiscount:
        return 'percent_discount';
      case PricingSchemeRuleType.fixedPrice:
        return 'fixed_price';
      case PricingSchemeRuleType.noDiscount:
        return 'no_discount';
    }
  }

  String get label {
    switch (this) {
      case PricingSchemeRuleType.priceType:
        return 'Use Price Type';
      case PricingSchemeRuleType.percentDiscount:
        return 'Percentage Discount';
      case PricingSchemeRuleType.fixedPrice:
        return 'Fixed Price';
      case PricingSchemeRuleType.noDiscount:
        return 'No Discount';
    }
  }

  static PricingSchemeRuleType fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'percent_discount':
        return PricingSchemeRuleType.percentDiscount;
      case 'fixed_price':
        return PricingSchemeRuleType.fixedPrice;
      case 'no_discount':
        return PricingSchemeRuleType.noDiscount;
      case 'price_type':
      default:
        return PricingSchemeRuleType.priceType;
    }
  }
}

@immutable
class PricingSchemeRule {
  const PricingSchemeRule({
    this.id,
    required this.schemeId,
    this.applyTo = PricingSchemeRuleApplyTo.all,
    this.category,
    this.barcode,
    this.productNameSnapshot,
    this.ruleType = PricingSchemeRuleType.priceType,
    this.priceType,
    this.discountPercent = 0.0,
    this.fixedPrice,
    this.priority = 100,
    this.isActive = true,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final int? id;
  final int schemeId;
  final PricingSchemeRuleApplyTo applyTo;
  final String? category;
  final String? barcode;
  final String? productNameSnapshot;
  final PricingSchemeRuleType ruleType;
  final ProductPriceType? priceType;
  final double discountPercent;
  final double? fixedPrice;
  final int priority;
  final bool isActive;
  final String? note;
  final String createdAt;
  final String updatedAt;
  final int? createdBy;
  final int? updatedBy;

  double get normalizedDiscountPercent {
    if (discountPercent < 0) return 0.0;
    if (discountPercent > 100) return 100.0;
    return discountPercent;
  }

  PricingSchemeRule copyWith({
    int? id,
    int? schemeId,
    PricingSchemeRuleApplyTo? applyTo,
    String? category,
    String? barcode,
    String? productNameSnapshot,
    PricingSchemeRuleType? ruleType,
    ProductPriceType? priceType,
    double? discountPercent,
    double? fixedPrice,
    int? priority,
    bool? isActive,
    String? note,
    String? createdAt,
    String? updatedAt,
    int? createdBy,
    int? updatedBy,
  }) {
    return PricingSchemeRule(
      id: id ?? this.id,
      schemeId: schemeId ?? this.schemeId,
      applyTo: applyTo ?? this.applyTo,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      productNameSnapshot: productNameSnapshot ?? this.productNameSnapshot,
      ruleType: ruleType ?? this.ruleType,
      priceType: priceType ?? this.priceType,
      discountPercent: discountPercent ?? this.discountPercent,
      fixedPrice: fixedPrice ?? this.fixedPrice,
      priority: priority ?? this.priority,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'scheme_id': schemeId,
      'apply_to': applyTo.dbValue,
      'category': _cleanOptional(category),
      'barcode': _cleanOptional(barcode),
      'product_name_snapshot': _cleanOptional(productNameSnapshot),
      'rule_type': ruleType.dbValue,
      'price_type': priceType?.dbValue,
      'discount_percent': normalizedDiscountPercent,
      'fixed_price': fixedPrice,
      'priority': priority,
      'is_active': isActive ? 1 : 0,
      'note': _cleanOptional(note),
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  factory PricingSchemeRule.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return PricingSchemeRule(
      id: _readNullableInt(map['id']),
      schemeId: _readNullableInt(map['scheme_id']) ?? 0,
      applyTo: PricingSchemeRuleApplyToX.fromDb(map['apply_to']?.toString()),
      category: _readNullableString(map['category']),
      barcode: _readNullableString(map['barcode']),
      productNameSnapshot: _readNullableString(map['product_name_snapshot']),
      ruleType: PricingSchemeRuleTypeX.fromDb(map['rule_type']?.toString()),
      priceType: map['price_type'] == null
          ? null
          : ProductPriceTypeX.fromDb(map['price_type']?.toString()),
      discountPercent: _readDouble(map['discount_percent']),
      fixedPrice: _readNullableDouble(map['fixed_price']),
      priority: _readInt(map['priority'], fallback: 100),
      isActive: _readBool(map['is_active'], fallback: true),
      note: _readNullableString(map['note']),
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
      createdBy: _readNullableInt(map['created_by']),
      updatedBy: _readNullableInt(map['updated_by']),
    );
  }

  static String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  static String? _readNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static int _readInt(dynamic value, {required int fallback}) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double _readDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static double? _readNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool _readBool(dynamic value, {bool fallback = true}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return fallback;
  }
}
