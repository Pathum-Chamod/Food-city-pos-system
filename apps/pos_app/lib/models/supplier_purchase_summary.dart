import 'package:flutter/foundation.dart';

@immutable
class SupplierPurchaseSummary {
  final int supplierId;
  final String supplierName;
  final String phone;
  final int receiptCount;
  final int poReceiptCount;
  final int productCount;
  final double totalUnits;
  final double totalCost;
  final String lastReceivedAt;

  const SupplierPurchaseSummary({
    required this.supplierId,
    required this.supplierName,
    required this.phone,
    required this.receiptCount,
    required this.poReceiptCount,
    required this.productCount,
    required this.totalUnits,
    required this.totalCost,
    required this.lastReceivedAt,
  });

  factory SupplierPurchaseSummary.fromMap(Map<dynamic, dynamic> map) {
    return SupplierPurchaseSummary(
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      poReceiptCount: (map['po_receipt_count'] as num?)?.toInt() ?? 0,
      productCount: (map['product_count'] as num?)?.toInt() ?? 0,
      totalUnits: ((map['total_units'] as num?) ?? 0).toDouble(),
      totalCost: ((map['total_cost'] as num?) ?? 0).toDouble(),
      lastReceivedAt: (map['last_received_at'] ?? '').toString(),
    );
  }
}
