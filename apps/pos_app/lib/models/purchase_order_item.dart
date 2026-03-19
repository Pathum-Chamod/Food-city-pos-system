import 'package:flutter/foundation.dart';

@immutable
class PurchaseOrderItem {
  final int? id;
  final int? purchaseOrderId;
  final String barcode;
  final String productName;
  final int quantity;
  final int receivedQuantity;
  final double unitCost;
  final String createdAt;

  const PurchaseOrderItem({
    this.id,
    this.purchaseOrderId,
    required this.barcode,
    required this.productName,
    required this.quantity,
    required this.receivedQuantity,
    required this.unitCost,
    required this.createdAt,
  });

  double get lineTotal => quantity * unitCost;

  factory PurchaseOrderItem.fromMap(Map<dynamic, dynamic> map) {
    return PurchaseOrderItem(
      id: (map['id'] as num?)?.toInt(),
      purchaseOrderId: (map['purchase_order_id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      receivedQuantity: (map['received_quantity'] as num?)?.toInt() ?? 0,
      unitCost: ((map['unit_cost'] as num?) ?? 0).toDouble(),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchase_order_id': purchaseOrderId,
      'barcode': barcode,
      'product_name': productName,
      'quantity': quantity,
      'received_quantity': receivedQuantity,
      'unit_cost': unitCost,
      'created_at': createdAt,
    };
  }

  PurchaseOrderItem copyWith({
    int? id,
    int? purchaseOrderId,
    String? barcode,
    String? productName,
    int? quantity,
    int? receivedQuantity,
    double? unitCost,
    String? createdAt,
  }) {
    return PurchaseOrderItem(
      id: id ?? this.id,
      purchaseOrderId: purchaseOrderId ?? this.purchaseOrderId,
      barcode: barcode ?? this.barcode,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
      unitCost: unitCost ?? this.unitCost,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
