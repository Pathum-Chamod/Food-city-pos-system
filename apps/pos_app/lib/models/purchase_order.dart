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
  final int receivedUnits;
  final int receiptCount;
  final double totalCost;
  final String createdBy;
  final String createdAt;
  final String updatedAt;
  final String lastReceivedAt;

  const PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.referenceNote,
    required this.totalLines,
    required this.totalUnits,
    this.receivedUnits = 0,
    this.receiptCount = 0,
    required this.totalCost,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.lastReceivedAt = '',
  });

  int get outstandingUnits {
    final remaining = totalUnits - receivedUnits;
    return remaining < 0 ? 0 : remaining;
  }

  double get receiveProgress {
    if (totalUnits <= 0) return 0;
    final progress = receivedUnits / totalUnits;
    if (progress < 0) return 0;
    if (progress > 1) return 1;
    return progress;
  }

  bool get canReceive =>
      status == 'ordered' || status == 'partially_received';

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
      receivedUnits: (map['received_units'] as num?)?.toInt() ?? 0,
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      totalCost: ((map['total_cost'] as num?) ?? 0).toDouble(),
      createdBy: (map['created_by'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
      lastReceivedAt: (map['last_received_at'] ?? '').toString(),
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
      'received_units': receivedUnits,
      'receipt_count': receiptCount,
      'total_cost': totalCost,
      'created_by': createdBy,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_received_at': lastReceivedAt,
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
    int? receivedUnits,
    int? receiptCount,
    double? totalCost,
    String? createdBy,
    String? createdAt,
    String? updatedAt,
    String? lastReceivedAt,
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
      receivedUnits: receivedUnits ?? this.receivedUnits,
      receiptCount: receiptCount ?? this.receiptCount,
      totalCost: totalCost ?? this.totalCost,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReceivedAt: lastReceivedAt ?? this.lastReceivedAt,
    );
  }
}
