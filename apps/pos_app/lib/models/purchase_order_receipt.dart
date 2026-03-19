import 'package:flutter/foundation.dart';

@immutable
class PurchaseOrderReceipt {
  final int id;
  final int purchaseOrderId;
  final String purchaseOrderNumber;
  final int supplierId;
  final String supplierName;
  final String cashierName;
  final String referenceNote;
  final String invoiceNumber;
  final String deliveryNoteNumber;
  final String grnReference;
  final int totalLines;
  final int totalUnits;
  final double totalCost;
  final String createdAt;

  const PurchaseOrderReceipt({
    required this.id,
    required this.purchaseOrderId,
    required this.purchaseOrderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.cashierName,
    required this.referenceNote,
    required this.invoiceNumber,
    required this.deliveryNoteNumber,
    required this.grnReference,
    required this.totalLines,
    required this.totalUnits,
    required this.totalCost,
    required this.createdAt,
  });

  factory PurchaseOrderReceipt.fromMap(Map<dynamic, dynamic> map) {
    return PurchaseOrderReceipt(
      id: (map['id'] as num?)?.toInt() ?? 0,
      purchaseOrderId: (map['purchase_order_id'] as num?)?.toInt() ?? 0,
      purchaseOrderNumber: (map['purchase_order_number'] ?? '').toString(),
      supplierId: (map['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: (map['supplier_name'] ?? '').toString(),
      cashierName: (map['cashier_name'] ?? '').toString(),
      referenceNote: (map['reference_note'] ?? '').toString(),
      invoiceNumber: (map['invoice_number'] ?? '').toString(),
      deliveryNoteNumber: (map['delivery_note_number'] ?? '').toString(),
      grnReference: (map['grn_reference'] ?? '').toString(),
      totalLines: (map['total_lines'] as num?)?.toInt() ?? 0,
      totalUnits: (map['total_units'] as num?)?.toInt() ?? 0,
      totalCost: ((map['total_cost'] as num?) ?? 0).toDouble(),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }
}

@immutable
class PurchaseOrderReceiptLine {
  final int id;
  final int purchaseOrderReceiptId;
  final int purchaseOrderId;
  final int? purchaseOrderItemId;
  final int? backendReceiptId;
  final String barcode;
  final String productName;
  final int quantity;
  final double unitCost;
  final double lineCost;
  final String createdAt;

  const PurchaseOrderReceiptLine({
    required this.id,
    required this.purchaseOrderReceiptId,
    required this.purchaseOrderId,
    this.purchaseOrderItemId,
    this.backendReceiptId,
    required this.barcode,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.lineCost,
    required this.createdAt,
  });

  factory PurchaseOrderReceiptLine.fromMap(Map<dynamic, dynamic> map) {
    return PurchaseOrderReceiptLine(
      id: (map['id'] as num?)?.toInt() ?? 0,
      purchaseOrderReceiptId:
          (map['purchase_order_receipt_id'] as num?)?.toInt() ?? 0,
      purchaseOrderId: (map['purchase_order_id'] as num?)?.toInt() ?? 0,
      purchaseOrderItemId: (map['purchase_order_item_id'] as num?)?.toInt(),
      backendReceiptId: (map['backend_receipt_id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitCost: ((map['unit_cost'] as num?) ?? 0).toDouble(),
      lineCost: ((map['line_cost'] as num?) ?? 0).toDouble(),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }
}
