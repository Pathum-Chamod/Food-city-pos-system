import 'package:flutter/foundation.dart';

import 'pricing_scheme_rule.dart';
import 'product.dart';

@immutable
class CustomerPricingRule {
  const CustomerPricingRule({
    this.id,
    required this.customerId,
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
  final int customerId;
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

  PricingSchemeRule asPricingSchemeRule() {
    return PricingSchemeRule(
      id: id,
      schemeId: customerId,
      applyTo: applyTo,
      category: category,
      barcode: barcode,
      productNameSnapshot: productNameSnapshot,
      ruleType: ruleType,
      priceType: priceType,
      discountPercent: discountPercent,
      fixedPrice: fixedPrice,
      priority: priority,
      isActive: isActive,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy,
    );
  }

  factory CustomerPricingRule.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return CustomerPricingRule(
      id: _readNullableInt(map['id']),
      customerId: _readNullableInt(map['customer_id']) ?? 0,
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
