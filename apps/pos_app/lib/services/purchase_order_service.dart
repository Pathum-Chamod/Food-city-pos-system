import 'package:flutter/foundation.dart';

import '../models/pos_supplier.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import 'database_helper.dart';
import 'supplier_service.dart';

class PurchaseOrderService {
  PurchaseOrderService();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final SupplierService _supplierService = SupplierService();

  Future<List<PosSupplier>> getSuppliers({bool refreshFromBackend = false}) {
    return _supplierService.getSuppliers(refreshFromBackend: refreshFromBackend);
  }

  Future<List<PurchaseOrder>> getOrders({
    int? supplierId,
    String status = 'all',
    String search = '',
    int limit = 200,
  }) {
    return _db.getPurchaseOrders(
      supplierId: supplierId,
      status: status,
      search: search,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> getSummary({
    int? supplierId,
    String status = 'all',
  }) {
    return _db.getPurchaseOrderSummary(
      supplierId: supplierId,
      status: status,
    );
  }

  Future<PurchaseOrder?> getOrder(int purchaseOrderId) {
    return _db.getPurchaseOrderById(purchaseOrderId);
  }

  Future<List<PurchaseOrderItem>> getOrderItems(int purchaseOrderId) {
    return _db.getPurchaseOrderItems(purchaseOrderId);
  }

  String generateOrderNumber() {
    final now = DateTime.now();
    final datePart =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePart =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'PO-$datePart-$timePart';
  }

  Future<int> saveOrder({
    int? purchaseOrderId,
    required String orderNumber,
    required PosSupplier supplier,
    required String status,
    required String referenceNote,
    required List<PurchaseOrderItem> items,
    required String createdBy,
  }) {
    return _db.savePurchaseOrder(
      purchaseOrderId: purchaseOrderId,
      orderNumber: orderNumber,
      supplierId: supplier.id,
      supplierName: supplier.name,
      status: status,
      referenceNote: referenceNote,
      items: items,
      createdBy: createdBy,
    );
  }

  Future<void> updateStatus(int purchaseOrderId, String status) {
    return _db.updatePurchaseOrderStatus(purchaseOrderId, status);
  }

  Future<void> deleteOrder(int purchaseOrderId) {
    return _db.deletePurchaseOrder(purchaseOrderId);
  }

  @visibleForTesting
  static List<String> statuses = const [
    'draft',
    'ordered',
    'partially_received',
    'received',
    'cancelled',
  ];
}
