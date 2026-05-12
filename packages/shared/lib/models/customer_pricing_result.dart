import 'package:flutter/foundation.dart';

enum CustomerPricingType {
  none,
  customerProductPrice,
  customerDefaultPriceType,
  customerDefaultDiscount,
}

extension CustomerPricingTypeX on CustomerPricingType {
  String get dbValue {
    switch (this) {
      case CustomerPricingType.customerProductPrice:
        return 'customer_product_price';
      case CustomerPricingType.customerDefaultPriceType:
        return 'customer_default_price_type';
      case CustomerPricingType.customerDefaultDiscount:
        return 'customer_default_discount';
      case CustomerPricingType.none:
        return 'none';
    }
  }

  String get label {
    switch (this) {
      case CustomerPricingType.customerProductPrice:
        return 'Customer Price';
      case CustomerPricingType.customerDefaultPriceType:
        return 'Customer Price Type';
      case CustomerPricingType.customerDefaultDiscount:
        return 'Customer Discount';
      case CustomerPricingType.none:
        return 'No Customer Pricing';
    }
  }

  static CustomerPricingType fromDb(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'customer_product_price':
        return CustomerPricingType.customerProductPrice;
      case 'customer_default_price_type':
        return CustomerPricingType.customerDefaultPriceType;
      case 'customer_default_discount':
        return CustomerPricingType.customerDefaultDiscount;
      case 'none':
      default:
        return CustomerPricingType.none;
    }
  }
}

@immutable
class CustomerPricingResult {
  const CustomerPricingResult({
    required this.originalPrice,
    required this.finalPrice,
    this.type = CustomerPricingType.none,
    this.ruleId,
    this.discountAmount = 0.0,
    this.note,
  });

  final double originalPrice;
  final double finalPrice;
  final CustomerPricingType type;
  final int? ruleId;
  final double discountAmount;
  final String? note;

  bool get applied => type != CustomerPricingType.none;

  Map<String, dynamic> toSnapshotMap() {
    return {
      'customer_pricing_applied': applied ? 1 : 0,
      'customer_pricing_type': type.dbValue,
      'customer_pricing_rule_id': ruleId,
      'customer_pricing_original_price': originalPrice,
      'customer_pricing_final_price': finalPrice,
      'customer_pricing_discount_amount': discountAmount,
      'customer_pricing_note': note,
    };
  }
}
