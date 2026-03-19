import 'package:flutter/foundation.dart';

@immutable
class StockReceiptRecord {
  final int id;
  final int? backendReceiptId;
  final String barcode;
  final String productName;
  final int quantity;
  final int supplierId;
  final String supplierName;
  final double cost;
  final String referenceNote;
  final String cashierName;
  final String createdAt;
  final String backendStatus;

  const StockReceiptRecord({
    required this.id,
    required this.backendReceiptId,
    required this.barcode,
    required this.productName,
    required this.quantity,
    required this.supplierId,
    required this.supplierName,
    required this.cost,
    required this.referenceNote,
    required this.cashierName,
    required this.createdAt,
    required this.backendStatus,
  });

  factory StockReceiptRecord.fromMap(Map<dynamic, dynamic> map) {
    return StockReceiptRecord(
      id: (map['id'] as num?)?.toInt() ?? 0,
      backendReceiptId: (map['backend_receipt_id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      cost: ((map['cost'] as num?) ?? 0).toDouble(),
      referenceNote: (map['reference_note'] ?? '').toString(),
      cashierName: (map['cashier_name'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      backendStatus: (map['backend_status'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'backend_receipt_id': backendReceiptId,
      'barcode': barcode,
      'product_name': productName,
      'quantity': quantity,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'cost': cost,
      'reference_note': referenceNote,
      'cashier_name': cashierName,
      'created_at': createdAt,
      'backend_status': backendStatus,
    };
  }
}
