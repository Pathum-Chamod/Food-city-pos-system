import 'package:flutter/foundation.dart';

@immutable
class CustomerCategory {
  const CustomerCategory({
    this.id,
    required this.name,
    this.description,
    this.defaultPricingSchemeId,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? description;
  final int? defaultPricingSchemeId;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Unnamed Category' : trimmed;
  }

  CustomerCategory copyWith({
    int? id,
    String? name,
    String? description,
    int? defaultPricingSchemeId,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
  }) {
    return CustomerCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultPricingSchemeId:
          defaultPricingSchemeId ?? this.defaultPricingSchemeId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name.trim(),
      'description': _cleanOptional(description),
      'default_pricing_scheme_id': defaultPricingSchemeId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory CustomerCategory.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return CustomerCategory(
      id: _readNullableInt(map['id']),
      name: (map['name'] ?? '').toString(),
      description: _readNullableString(map['description']),
      defaultPricingSchemeId: _readNullableInt(
        map['default_pricing_scheme_id'],
      ),
      isActive: _readBool(map['is_active'], fallback: true),
      createdAt: (map['created_at'] ?? now).toString(),
      updatedAt: (map['updated_at'] ?? now).toString(),
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
