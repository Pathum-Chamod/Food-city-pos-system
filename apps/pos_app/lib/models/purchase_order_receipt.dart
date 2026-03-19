class PurchaseOrderReceiptLine {
  final int id;
  final int receiptId;
  final String barcode;
  final String productName;
  final int orderedQuantity;
  final int receivedQuantity;
  final double unitCost;
  final double lineTotal;

  const PurchaseOrderReceiptLine({
    required this.id,
    required this.receiptId,
    required this.barcode,
    required this.productName,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.unitCost,
    required this.lineTotal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_id': receiptId,
      'barcode': barcode,
      'product_name': productName,
      'ordered_quantity': orderedQuantity,
      'received_quantity': receivedQuantity,
      'unit_cost': unitCost,
      'line_total': lineTotal,
    };
  }

  factory PurchaseOrderReceiptLine.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderReceiptLine(
      id: (map['id'] as num?)?.toInt() ?? 0,
      receiptId: (map['receipt_id'] as num?)?.toInt() ?? 0,
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      orderedQuantity: (map['ordered_quantity'] as num?)?.toInt() ?? 0,
      receivedQuantity: (map['received_quantity'] as num?)?.toInt() ?? 0,
      unitCost: ((map['unit_cost'] as num?) ?? 0).toDouble(),
      lineTotal: ((map['line_total'] as num?) ?? 0).toDouble(),
    );
  }
}

class PurchaseOrderReceipt {
  final int id;
  final int purchaseOrderId;
  final String poNumber;
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
  final String receivedAt;
  final int receiptCountForPo;
  final bool isReversed;
  final String reversedAt;
  final String reversedBy;
  final String reversalReason;
  final String managerApprovedBy;
  final List<PurchaseOrderReceiptLine> lines;

  const PurchaseOrderReceipt({
    required this.id,
    required this.purchaseOrderId,
    required this.poNumber,
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
    required this.receivedAt,
    required this.receiptCountForPo,
    required this.isReversed,
    required this.reversedAt,
    required this.reversedBy,
    required this.reversalReason,
    required this.managerApprovedBy,
    this.lines = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchase_order_id': purchaseOrderId,
      'po_number': poNumber,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'cashier_name': cashierName,
      'reference_note': referenceNote,
      'invoice_number': invoiceNumber,
      'delivery_note_number': deliveryNoteNumber,
      'grn_reference': grnReference,
      'total_lines': totalLines,
      'total_units': totalUnits,
      'total_cost': totalCost,
      'received_at': receivedAt,
      'receipt_count_for_po': receiptCountForPo,
      'is_reversed': isReversed ? 1 : 0,
      'reversed_at': reversedAt,
      'reversed_by': reversedBy,
      'reversal_reason': reversalReason,
      'manager_approved_by': managerApprovedBy,
    };
  }

  factory PurchaseOrderReceipt.fromMap(
    Map<String, dynamic> map, {
    List<PurchaseOrderReceiptLine> lines = const [],
  }) {
    return PurchaseOrderReceipt(
      id: (map['id'] as num?)?.toInt() ?? 0,
      purchaseOrderId: (map['purchase_order_id'] as num?)?.toInt() ?? 0,
      poNumber: (map['po_number'] ?? '').toString(),
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
      receivedAt: (map['received_at'] ?? '').toString(),
      receiptCountForPo: (map['receipt_count_for_po'] as num?)?.toInt() ?? 0,
      isReversed: ((map['is_reversed'] as num?)?.toInt() ?? 0) == 1,
      reversedAt: (map['reversed_at'] ?? '').toString(),
      reversedBy: (map['reversed_by'] ?? '').toString(),
      reversalReason: (map['reversal_reason'] ?? '').toString(),
      managerApprovedBy: (map['manager_approved_by'] ?? '').toString(),
      lines: lines,
    );
  }

  PurchaseOrderReceipt copyWith({
    bool? isReversed,
    String? reversedAt,
    String? reversedBy,
    String? reversalReason,
    String? managerApprovedBy,
    List<PurchaseOrderReceiptLine>? lines,
  }) {
    return PurchaseOrderReceipt(
      id: id,
      purchaseOrderId: purchaseOrderId,
      poNumber: poNumber,
      supplierId: supplierId,
      supplierName: supplierName,
      cashierName: cashierName,
      referenceNote: referenceNote,
      invoiceNumber: invoiceNumber,
      deliveryNoteNumber: deliveryNoteNumber,
      grnReference: grnReference,
      totalLines: totalLines,
      totalUnits: totalUnits,
      totalCost: totalCost,
      receivedAt: receivedAt,
      receiptCountForPo: receiptCountForPo,
      isReversed: isReversed ?? this.isReversed,
      reversedAt: reversedAt ?? this.reversedAt,
      reversedBy: reversedBy ?? this.reversedBy,
      reversalReason: reversalReason ?? this.reversalReason,
      managerApprovedBy: managerApprovedBy ?? this.managerApprovedBy,
      lines: lines ?? this.lines,
    );
  }
}
