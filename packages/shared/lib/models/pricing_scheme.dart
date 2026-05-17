import 'package:flutter/foundation.dart';

@immutable
class PricingScheme {
  const PricingScheme({
    this.id,
    required this.name,
    this.description,
    this.isActive = true,
    this.priority = 100,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final int? id;
  final String name;
  final String? description;
  final bool isActive;
  final int priority;
  final String createdAt;
  final String updatedAt;
  final int? createdBy;
  final int? updatedBy;

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Unnamed Scheme' : trimmed;
  }

  PricingScheme copyWith({
    int? id,
    String? name,
    String? description,
    bool? isActive,
    int? priority,
    String? createdAt,
    String? updatedAt,
    int? createdBy,
    int? updatedBy,
  }) {
    return PricingScheme(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name.trim(),
      'description': _cleanOptional(description),
      'is_active': isActive ? 1 : 0,
      'priority': priority,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': createdBy,
      'updated_by': updatedBy,
    };
  }

  factory PricingScheme.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now().toIso8601String();
    return PricingScheme(
      id: _readNullableInt(map['id']),
      name: (map['name'] ?? '').toString(),
      description: _readNullableString(map['description']),
      isActive: _readBool(map['is_active'], fallback: true),
      priority: _readInt(map['priority'], fallback: 100),
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
