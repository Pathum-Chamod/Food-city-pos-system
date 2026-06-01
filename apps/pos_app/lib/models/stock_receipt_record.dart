import 'package:flutter/foundation.dart';

@immutable
class StockReceiptRecord {
  final int id;
  final int? backendReceiptId;
  final String barcode;
  final String productName;
  final String? productNameSi;
  final double quantity;
  final int supplierId;
  final String supplierName;
  final int? purchaseOrderId;
  final String? purchaseOrderNumber;
  final double cost;
  final String referenceNote;
  final String invoiceNumber;
  final String deliveryNoteNumber;
  final String grnReference;
  final int? expiryBatchId;
  final String batchNumber;
  final String expiryDate;
  final String cashierName;
  final String createdAt;
  final String backendStatus;

  const StockReceiptRecord({
    required this.id,
    required this.backendReceiptId,
    required this.barcode,
    required this.productName,
    required this.productNameSi,
    required this.quantity,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseOrderId,
    required this.purchaseOrderNumber,
    required this.cost,
    required this.referenceNote,
    required this.invoiceNumber,
    required this.deliveryNoteNumber,
    required this.grnReference,
    required this.expiryBatchId,
    required this.batchNumber,
    required this.expiryDate,
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
      productNameSi: map['product_name_si']?.toString(),
      quantity: ((map['quantity'] as num?) ?? 0).toDouble(),
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      purchaseOrderId: (map['purchase_order_id'] as num?)?.toInt(),
      purchaseOrderNumber: (map['purchase_order_number'] ?? '').toString(),
      cost: ((map['cost'] as num?) ?? 0).toDouble(),
      referenceNote: (map['reference_note'] ?? '').toString(),
      invoiceNumber: (map['invoice_number'] ?? '').toString(),
      deliveryNoteNumber: (map['delivery_note_number'] ?? '').toString(),
      grnReference: (map['grn_reference'] ?? '').toString(),
      expiryBatchId: (map['expiry_batch_id'] as num?)?.toInt(),
      batchNumber: (map['batch_number'] ?? '').toString(),
      expiryDate: (map['expiry_date'] ?? '').toString(),
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
      'product_name_si': productNameSi,
      'quantity': quantity,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_order_id': purchaseOrderId,
      'purchase_order_number': purchaseOrderNumber,
      'cost': cost,
      'reference_note': referenceNote,
      'invoice_number': invoiceNumber,
      'delivery_note_number': deliveryNoteNumber,
      'grn_reference': grnReference,
      'expiry_batch_id': expiryBatchId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate,
      'cashier_name': cashierName,
      'created_at': createdAt,
      'backend_status': backendStatus,
    };
  }
}
