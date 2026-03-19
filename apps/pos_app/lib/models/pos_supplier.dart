import 'package:flutter/foundation.dart';

@immutable
class PosSupplier {
  final int id;
  final String name;
  final String phone;
  final String updatedAt;

  const PosSupplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.updatedAt,
  });

  factory PosSupplier.fromMap(Map<dynamic, dynamic> map) {
    return PosSupplier(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: (map['name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'updated_at': updatedAt,
    };
  }

  PosSupplier copyWith({
    int? id,
    String? name,
    String? phone,
    String? updatedAt,
  }) {
    return PosSupplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
