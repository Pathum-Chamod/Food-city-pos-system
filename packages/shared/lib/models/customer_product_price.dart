import 'package:flutter/foundation.dart';

@immutable
class CustomerProductPrice {
  const CustomerProductPrice({
    this.id,
    required this.customerId,
    required this.barcode,
    required this.productNameSnapshot,
    required this.fixedPrice,
    this.isActive = true,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final int? id;
  final int customerId;
  final String barcode;
  final String productNameSnapshot;
  final double fixedPrice;
  final bool isActive;
  final String? note;
  final String createdAt;
  final String updatedAt;
  final int? createdBy;
  final int? updatedBy;

  CustomerProductPrice copyWith({
    int? id,
    int? customerId,
    String? barcode,
    String? productNameSnapshot,
    double? fixedPrice,
    bool? isActive,
    String? note,
    String? createdAt,
    String? updatedAt,
    int? createdBy,
    int? updatedBy,
  }) {
    return CustomerProductPrice(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      barcode: barcode ?? this.barcode,
      productNameSnapshot: productNameSnapshot ?? this.productNameSnapshot,
      fixedPrice: fixedPrice ?? this.fixedPrice,
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
      'customer_id': customerId,
      'barcode': barcode,
      'product_name_snapshot': productNameSnapshot,
      'fixed_price': fixedPrice,
      'is_active': isActive ? 1 : 0,
      'note': note,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  factory CustomerProductPrice.fromMap(Map<dynamic, dynamic> map) {
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

    return CustomerProductPrice(
      id: readNullableInt(map['id']),
      customerId: readNullableInt(map['customer_id']) ?? 0,
      barcode: (map['barcode'] ?? '').toString(),
      productNameSnapshot: (map['product_name_snapshot'] ?? '').toString(),
      fixedPrice: readDouble(map['fixed_price']),
      isActive: readBool(map['is_active'], fallback: true),
      note: readNullableString(map['note']),
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
      createdBy: readNullableInt(map['created_by']),
      updatedBy: readNullableInt(map['updated_by']),
    );
  }
}
