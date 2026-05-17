import 'package:flutter/foundation.dart';

import 'product.dart';

@immutable
class Customer {
  const Customer({
    this.id,
    required this.customerCode,
    required this.name,
    this.phone,
    this.phoneNormalized,
    this.email,
    this.address,
    this.customerType = 'regular',
    this.notes,
    this.isActive = true,
    this.creditEnabled = false,
    this.creditLimit = 0.0,
    this.currentCreditBalance = 0.0,
    this.creditStatus = 'normal',
    this.creditNote,
    this.customerCategoryId,
    this.pricingSchemeId,
    this.pricingEnabled = false,
    this.defaultPriceType = ProductPriceType.selling,
    this.defaultDiscountPercent = 0.0,
    this.pricingNote,
    this.loyaltyEnabled = true,
    this.loyaltyPointsBalance = 0,
    this.loyaltyLifetimeEarned = 0,
    this.loyaltyLifetimeRedeemed = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final int? id;
  final String customerCode;
  final String name;
  final String? phone;
  final String? phoneNormalized;
  final String? email;
  final String? address;
  final String customerType;
  final String? notes;
  final bool isActive;

  /// Credit account fields.
  ///
  /// These are optional in Customer Module V1 and become active in
  /// Customer Credit / Ledger implementation.
  final bool creditEnabled;
  final double creditLimit;
  final double currentCreditBalance;
  final String creditStatus; // normal | watchlist | blocked
  final String? creditNote;

  /// Pricing Schemes V1.5 assignment fields.
  ///
  /// The legacy customerType and simple pricing fields remain active for
  /// compatibility and fallback pricing.
  final int? customerCategoryId;
  final int? pricingSchemeId;

  /// Customer-specific pricing fields.
  final bool pricingEnabled;
  final ProductPriceType defaultPriceType;
  final double defaultDiscountPercent;
  final String? pricingNote;

  /// Loyalty Module V1 cached fields.
  ///
  /// The loyalty ledger remains the source of truth. These values are kept on
  /// the customer row for fast display in customer and checkout screens.
  final bool loyaltyEnabled;
  final int loyaltyPointsBalance;
  final int loyaltyLifetimeEarned;
  final int loyaltyLifetimeRedeemed;

  final String createdAt;
  final String updatedAt;
  final int? createdBy;
  final int? updatedBy;

  bool get hasPhone => (phone ?? '').trim().isNotEmpty;
  bool get hasEmail => (email ?? '').trim().isNotEmpty;
  bool get hasAddress => (address ?? '').trim().isNotEmpty;
  bool get hasNotes => (notes ?? '').trim().isNotEmpty;
  bool get hasCreditNote => (creditNote ?? '').trim().isNotEmpty;
  bool get hasPricingNote => (pricingNote ?? '').trim().isNotEmpty;
  bool get hasLoyaltyPoints => loyaltyPointsBalance > 0;

  String get displayCode {
    final trimmed = customerCode.trim();
    return trimmed.isEmpty ? 'CUS-NEW' : trimmed;
  }

  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final phoneText = (phone ?? '').trim();
    return phoneText.isEmpty ? 'Unnamed Customer' : phoneText;
  }

  String get displayPhone {
    final trimmed = (phone ?? '').trim();
    return trimmed.isEmpty ? '-' : trimmed;
  }

  String get normalizedType {
    final normalized = customerType.trim().toLowerCase();
    if (normalized == 'vip') return 'vip';
    if (normalized == 'wholesale') return 'wholesale';
    if (normalized == 'staff') return 'staff';
    return 'regular';
  }

  String get typeLabel {
    switch (normalizedType) {
      case 'vip':
        return 'VIP';
      case 'wholesale':
        return 'Wholesale';
      case 'staff':
        return 'Staff';
      case 'regular':
      default:
        return 'Regular';
    }
  }

  String get normalizedCreditStatus {
    final normalized = creditStatus.trim().toLowerCase();
    if (normalized == 'watchlist') return 'watchlist';
    if (normalized == 'blocked') return 'blocked';
    return 'normal';
  }

  String get creditStatusLabel {
    switch (normalizedCreditStatus) {
      case 'watchlist':
        return 'Watchlist';
      case 'blocked':
        return 'Blocked';
      case 'normal':
      default:
        return 'Normal';
    }
  }

  bool get isCreditBlocked => normalizedCreditStatus == 'blocked';

  double get normalizedDefaultDiscountPercent {
    if (defaultDiscountPercent < 0) return 0.0;
    if (defaultDiscountPercent > 100) return 100.0;
    return defaultDiscountPercent;
  }

  double get availableCredit {
    final available = creditLimit - currentCreditBalance;
    return double.parse(available.toStringAsFixed(2));
  }

  bool get isOverCreditLimit {
    if (!creditEnabled) return false;
    if (creditLimit <= 0) return currentCreditBalance > 0;
    return currentCreditBalance > creditLimit;
  }

  Customer copyWith({
    int? id,
    String? customerCode,
    String? name,
    String? phone,
    String? phoneNormalized,
    String? email,
    String? address,
    String? customerType,
    String? notes,
    bool? isActive,
    bool? creditEnabled,
    double? creditLimit,
    double? currentCreditBalance,
    String? creditStatus,
    String? creditNote,
    int? customerCategoryId,
    int? pricingSchemeId,
    bool? pricingEnabled,
    ProductPriceType? defaultPriceType,
    double? defaultDiscountPercent,
    String? pricingNote,
    bool? loyaltyEnabled,
    int? loyaltyPointsBalance,
    int? loyaltyLifetimeEarned,
    int? loyaltyLifetimeRedeemed,
    String? createdAt,
    String? updatedAt,
    int? createdBy,
    int? updatedBy,
  }) {
    return Customer(
      id: id ?? this.id,
      customerCode: customerCode ?? this.customerCode,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      phoneNormalized: phoneNormalized ?? this.phoneNormalized,
      email: email ?? this.email,
      address: address ?? this.address,
      customerType: customerType ?? this.customerType,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      creditEnabled: creditEnabled ?? this.creditEnabled,
      creditLimit: creditLimit ?? this.creditLimit,
      currentCreditBalance: currentCreditBalance ?? this.currentCreditBalance,
      creditStatus: creditStatus ?? this.creditStatus,
      creditNote: creditNote ?? this.creditNote,
      customerCategoryId: customerCategoryId ?? this.customerCategoryId,
      pricingSchemeId: pricingSchemeId ?? this.pricingSchemeId,
      pricingEnabled: pricingEnabled ?? this.pricingEnabled,
      defaultPriceType: defaultPriceType ?? this.defaultPriceType,
      defaultDiscountPercent:
          defaultDiscountPercent ?? this.defaultDiscountPercent,
      pricingNote: pricingNote ?? this.pricingNote,
      loyaltyEnabled: loyaltyEnabled ?? this.loyaltyEnabled,
      loyaltyPointsBalance: loyaltyPointsBalance ?? this.loyaltyPointsBalance,
      loyaltyLifetimeEarned:
          loyaltyLifetimeEarned ?? this.loyaltyLifetimeEarned,
      loyaltyLifetimeRedeemed:
          loyaltyLifetimeRedeemed ?? this.loyaltyLifetimeRedeemed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_code': customerCode,
      'name': name,
      'phone': phone,
      'phone_normalized': phoneNormalized,
      'email': email,
      'address': address,
      'customer_type': normalizedType,
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'credit_enabled': creditEnabled ? 1 : 0,
      'credit_limit': creditLimit,
      'current_credit_balance': currentCreditBalance,
      'credit_status': normalizedCreditStatus,
      'credit_note': creditNote,
      'customer_category_id': customerCategoryId,
      'pricing_scheme_id': pricingSchemeId,
      'pricing_enabled': pricingEnabled ? 1 : 0,
      'default_price_type': defaultPriceType.dbValue,
      'default_discount_percent': normalizedDefaultDiscountPercent,
      'pricing_note': pricingNote,
      'loyalty_enabled': loyaltyEnabled ? 1 : 0,
      'loyalty_points_balance': loyaltyPointsBalance < 0
          ? 0
          : loyaltyPointsBalance,
      'loyalty_lifetime_earned': loyaltyLifetimeEarned < 0
          ? 0
          : loyaltyLifetimeEarned,
      'loyalty_lifetime_redeemed': loyaltyLifetimeRedeemed < 0
          ? 0
          : loyaltyLifetimeRedeemed,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  factory Customer.fromMap(Map<dynamic, dynamic> map) {
    String? readNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    int? readNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    double readDouble(dynamic value, {double fallback = 0.0}) {
      if (value == null) return fallback;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? fallback;
    }

    bool readBool(dynamic value, {bool fallback = true}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value.toInt() == 1;
      final text = value.toString().trim().toLowerCase();
      if (text == '1' || text == 'true' || text == 'yes') return true;
      if (text == '0' || text == 'false' || text == 'no') return false;
      return fallback;
    }

    final now = DateTime.now().toIso8601String();

    return Customer(
      id: readNullableInt(map['id']),
      customerCode: (map['customer_code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      phone: readNullableString(map['phone']),
      phoneNormalized: readNullableString(map['phone_normalized']),
      email: readNullableString(map['email']),
      address: readNullableString(map['address']),
      customerType: (map['customer_type'] ?? 'regular').toString(),
      notes: readNullableString(map['notes']),
      isActive: readBool(map['is_active'], fallback: true),
      creditEnabled: readBool(map['credit_enabled'], fallback: false),
      creditLimit: readDouble(map['credit_limit']),
      currentCreditBalance: readDouble(map['current_credit_balance']),
      creditStatus: (map['credit_status'] ?? 'normal').toString(),
      creditNote: readNullableString(map['credit_note']),
      customerCategoryId: readNullableInt(map['customer_category_id']),
      pricingSchemeId: readNullableInt(map['pricing_scheme_id']),
      pricingEnabled: readBool(map['pricing_enabled'], fallback: false),
      defaultPriceType: ProductPriceTypeX.fromDb(
        map['default_price_type']?.toString(),
      ),
      defaultDiscountPercent: readDouble(map['default_discount_percent']),
      pricingNote: readNullableString(map['pricing_note']),
      loyaltyEnabled: readBool(map['loyalty_enabled'], fallback: true),
      loyaltyPointsBalance: readNullableInt(map['loyalty_points_balance']) ?? 0,
      loyaltyLifetimeEarned:
          readNullableInt(map['loyalty_lifetime_earned']) ?? 0,
      loyaltyLifetimeRedeemed:
          readNullableInt(map['loyalty_lifetime_redeemed']) ?? 0,
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
      createdBy: readNullableInt(map['created_by']),
      updatedBy: readNullableInt(map['updated_by']),
    );
  }

  static String normalizeSriLankanPhone(String input) {
    var value = input.trim();

    if (value.isEmpty) return '';

    value = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (value.startsWith('+94')) {
      value = '0${value.substring(3)}';
    } else if (value.startsWith('94') && value.length == 11) {
      value = '0${value.substring(2)}';
    }

    value = value.replaceAll(RegExp(r'[^0-9]'), '');
    return value;
  }

  static String generateCustomerCode(int id) {
    return 'CUS-${id.toString().padLeft(6, '0')}';
  }

  static Customer emptyForCreate({
    int? createdBy,
    String customerType = 'regular',
  }) {
    final now = DateTime.now().toIso8601String();
    return Customer(
      customerCode: '',
      name: '',
      customerType: customerType,
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
      updatedBy: createdBy,
    );
  }
}
