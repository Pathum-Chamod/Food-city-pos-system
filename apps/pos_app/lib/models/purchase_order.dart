import 'package:flutter/foundation.dart';

@immutable
class PurchaseOrder {
  final int id;
  final String orderNumber;
  final int supplierId;
  final String supplierName;
  final String status;
  final String referenceNote;
  final int totalLines;
  final int totalUnits;
  final double totalCost;
  final String createdBy;
  final String createdAt;
  final String updatedAt;

  const PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.referenceNote,
    required this.totalLines,
    required this.totalUnits,
    required this.totalCost,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseOrder.fromMap(Map<dynamic, dynamic> map) {
    return PurchaseOrder(
      id: (map['id'] as num?)?.toInt() ?? 0,
      orderNumber: (map['order_number'] ?? '').toString(),
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      status: (map['status'] ?? 'draft').toString(),
      referenceNote: (map['reference_note'] ?? '').toString(),
      totalLines: (map['total_lines'] as num?)?.toInt() ?? 0,
      totalUnits: (map['total_units'] as num?)?.toInt() ?? 0,
      totalCost: ((map['total_cost'] as num?) ?? 0).toDouble(),
      createdBy: (map['created_by'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'status': status,
      'reference_note': referenceNote,
      'total_lines': totalLines,
      'total_units': totalUnits,
      'total_cost': totalCost,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  PurchaseOrder copyWith({
    int? id,
    String? orderNumber,
    int? supplierId,
    String? supplierName,
    String? status,
    String? referenceNote,
    int? totalLines,
    int? totalUnits,
    double? totalCost,
    String? createdBy,
    String? createdAt,
    String? updatedAt,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      status: status ?? this.status,
      referenceNote: referenceNote ?? this.referenceNote,
      totalLines: totalLines ?? this.totalLines,
      totalUnits: totalUnits ?? this.totalUnits,
      totalCost: totalCost ?? this.totalCost,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
