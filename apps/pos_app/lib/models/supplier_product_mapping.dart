import 'package:flutter/foundation.dart';

@immutable
class SupplierProductMapping {
  final int? id;
  final String barcode;
  final String productName;
  final int supplierId;
  final String supplierName;
  final bool isPreferred;
  final double defaultUnitCost;
  final int minimumOrderQuantity;
  final int packSize;
  final int leadTimeDays;
  final String note;
  final String updatedAt;

  const SupplierProductMapping({
    this.id,
    required this.barcode,
    required this.productName,
    required this.supplierId,
    required this.supplierName,
    required this.isPreferred,
    required this.defaultUnitCost,
    required this.minimumOrderQuantity,
    required this.packSize,
    required this.leadTimeDays,
    required this.note,
    required this.updatedAt,
  });

  factory SupplierProductMapping.fromMap(Map<dynamic, dynamic> map) {
    return SupplierProductMapping(
      id: (map['id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      isPreferred: ((map['is_preferred'] as num?)?.toInt() ?? 0) == 1,
      defaultUnitCost: ((map['default_unit_cost'] as num?) ?? 0).toDouble(),
      minimumOrderQuantity: (map['minimum_order_quantity'] as num?)?.toInt() ?? 1,
      packSize: (map['pack_size'] as num?)?.toInt() ?? 1,
      leadTimeDays: (map['lead_time_days'] as num?)?.toInt() ?? 0,
      note: (map['note'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'barcode': barcode,
      'product_name': productName,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'is_preferred': isPreferred ? 1 : 0,
      'default_unit_cost': defaultUnitCost,
      'minimum_order_quantity': minimumOrderQuantity,
      'pack_size': packSize,
      'lead_time_days': leadTimeDays,
      'note': note,
      'updated_at': updatedAt,
    };
  }

  SupplierProductMapping copyWith({
    int? id,
    String? barcode,
    String? productName,
    int? supplierId,
    String? supplierName,
    bool? isPreferred,
    double? defaultUnitCost,
    int? minimumOrderQuantity,
    int? packSize,
    int? leadTimeDays,
    String? note,
    String? updatedAt,
  }) {
    return SupplierProductMapping(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      productName: productName ?? this.productName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      isPreferred: isPreferred ?? this.isPreferred,
      defaultUnitCost: defaultUnitCost ?? this.defaultUnitCost,
      minimumOrderQuantity: minimumOrderQuantity ?? this.minimumOrderQuantity,
      packSize: packSize ?? this.packSize,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
