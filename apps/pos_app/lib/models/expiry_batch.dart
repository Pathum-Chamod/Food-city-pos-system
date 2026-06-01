import 'package:flutter/foundation.dart';

@immutable
class ExpiryBatch {
  const ExpiryBatch({
    required this.id,
    required this.receiptId,
    required this.barcode,
    required this.productName,
    this.productNameSi,
    required this.batchNumber,
    required this.supplierId,
    required this.supplierName,
    required this.unitLabel,
    required this.receivedQuantity,
    required this.remainingQuantity,
    required this.expiryDate,
    required this.status,
    required this.lastCheckedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.alertDays,
  });

  final int id;
  final int? receiptId;
  final String barcode;
  final String productName;
  final String? productNameSi;
  final String batchNumber;
  final int? supplierId;
  final String supplierName;
  final String unitLabel;
  final double receivedQuantity;
  final double remainingQuantity;
  final DateTime expiryDate;
  final String status;
  final String lastCheckedAt;
  final String createdAt;
  final String updatedAt;
  final int alertDays;

  factory ExpiryBatch.fromMap(Map<dynamic, dynamic> map) {
    final rawExpiry = (map['expiry_date'] ?? '').toString();
    return ExpiryBatch(
      id: (map['id'] as num?)?.toInt() ?? 0,
      receiptId: (map['receipt_id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      productName: (map['product_name'] ?? '').toString(),
      productNameSi: map['product_name_si']?.toString(),
      batchNumber: (map['batch_number'] ?? '').toString(),
      supplierId: (map['supplier_id'] as num?)?.toInt(),
      supplierName: (map['supplier_name'] ?? '').toString(),
      unitLabel: (map['unit_label'] ?? 'pcs').toString(),
      receivedQuantity: ((map['received_quantity'] as num?) ?? 0).toDouble(),
      remainingQuantity: ((map['remaining_quantity'] as num?) ?? 0).toDouble(),
      expiryDate: DateTime.tryParse(rawExpiry) ?? DateTime.now(),
      status: (map['status'] ?? 'active').toString(),
      lastCheckedAt: (map['last_checked_at'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
      alertDays: (map['alert_days'] as num?)?.toInt() ?? 30,
    );
  }

  int daysLeft(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return expiry.difference(today).inDays;
  }

  bool checkedToday(DateTime now) {
    final checked = DateTime.tryParse(lastCheckedAt);
    if (checked == null) return false;
    return checked.year == now.year &&
        checked.month == now.month &&
        checked.day == now.day;
  }
}
