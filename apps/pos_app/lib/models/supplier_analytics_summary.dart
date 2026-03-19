class SupplierAnalyticsSummary {
  const SupplierAnalyticsSummary({
    required this.supplierId,
    required this.supplierName,
    required this.totalSpend,
    required this.spend30Days,
    required this.spend90Days,
    required this.mappedProductCount,
    required this.purchaseOrderCount,
    required this.openPurchaseOrderCount,
    required this.reversedReceiptCount,
    required this.averageUnitCost,
    required this.lastReceivedAt,
  });

  final int supplierId;
  final String supplierName;
  final double totalSpend;
  final double spend30Days;
  final double spend90Days;
  final int mappedProductCount;
  final int purchaseOrderCount;
  final int openPurchaseOrderCount;
  final int reversedReceiptCount;
  final double averageUnitCost;
  final String lastReceivedAt;

  factory SupplierAnalyticsSummary.fromMap(Map<String, dynamic> map) {
    return SupplierAnalyticsSummary(
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      totalSpend: (map['total_spend'] as num?)?.toDouble() ?? 0.0,
      spend30Days: (map['spend_30_days'] as num?)?.toDouble() ?? 0.0,
      spend90Days: (map['spend_90_days'] as num?)?.toDouble() ?? 0.0,
      mappedProductCount: (map['mapped_product_count'] as num?)?.toInt() ?? 0,
      purchaseOrderCount: (map['purchase_order_count'] as num?)?.toInt() ?? 0,
      openPurchaseOrderCount:
          (map['open_purchase_order_count'] as num?)?.toInt() ?? 0,
      reversedReceiptCount:
          (map['reversed_receipt_count'] as num?)?.toInt() ?? 0,
      averageUnitCost: (map['average_unit_cost'] as num?)?.toDouble() ?? 0.0,
      lastReceivedAt: (map['last_received_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'total_spend': totalSpend,
      'spend_30_days': spend30Days,
      'spend_90_days': spend90Days,
      'mapped_product_count': mappedProductCount,
      'purchase_order_count': purchaseOrderCount,
      'open_purchase_order_count': openPurchaseOrderCount,
      'reversed_receipt_count': reversedReceiptCount,
      'average_unit_cost': averageUnitCost,
      'last_received_at': lastReceivedAt,
    };
  }
}