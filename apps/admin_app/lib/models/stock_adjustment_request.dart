class StockAdjustmentRequest {
  final String barcode;
  final String adjustmentType;
  final int quantity;
  final String reason;

  const StockAdjustmentRequest({
    required this.barcode,
    required this.adjustmentType,
    required this.quantity,
    required this.reason,
  });

  Map<String, dynamic> toMap() {
    return {
      'barcode': barcode,
      'adjustment_type': adjustmentType,
      'quantity': quantity,
      'reason': reason,
    };
  }
}