import 'package:flutter/foundation.dart';

@immutable
class SupplierProductHistory {
  final String barcode;
  final String productName;
  final int receiptCount;
  final int linkedPoCount;
  final int totalUnits;
  final double totalCost;
  final String lastReceivedAt;

  const SupplierProductHistory({
    required this.barcode,
    required this.productName,
    required this.receiptCount,
    required this.linkedPoCount,
    required this.totalUnits,
    required this.totalCost,
    required this.lastReceivedAt,
  });

  double get averageUnitCost {
    if (totalUnits <= 0) return 0;
    return totalCost / totalUnits;
  }

  factory SupplierProductHistory.fromMap(Map<dynamic, dynamic> map) {
    return SupplierProductHistory(
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      linkedPoCount: (map['linked_po_count'] as num?)?.toInt() ?? 0,
      totalUnits: (map['total_units'] as num?)?.toInt() ?? 0,
      totalCost: ((map['total_cost'] as num?) ?? 0).toDouble(),
      lastReceivedAt: (map['last_received_at'] ?? '').toString(),
    );
  }
}
