import 'package:flutter/foundation.dart';

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
  final String createdAt;
  final String updatedAt;
  final int? createdBy;
  final int? updatedBy;

  bool get hasPhone => (phone ?? '').trim().isNotEmpty;
  bool get hasEmail => (email ?? '').trim().isNotEmpty;
  bool get hasAddress => (address ?? '').trim().isNotEmpty;
  bool get hasNotes => (notes ?? '').trim().isNotEmpty;

  String get displayCode {
    final trimmed = customerCode.trim();
    return trimmed.isEmpty ? 'CUS-NEW' : trimmed;
  }

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Unnamed Customer' : trimmed;
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
