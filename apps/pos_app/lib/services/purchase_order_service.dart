import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pos_supplier.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/purchase_order_receipt.dart';
import 'database_helper.dart';
import 'supplier_service.dart';
import 'sync_service.dart';

class PurchaseOrderService {
  PurchaseOrderService();

  final DatabaseHelper _db = DatabaseHelper.instance;
  final SupplierService _supplierService = SupplierService();

  final String apiUrl = 'http://127.0.0.1:8080/api/pos_sync.php';

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

  Future<List<Map<String, dynamic>>> getOutstandingLines(int purchaseOrderId) {
    return _db.getOutstandingPurchaseOrderLines(purchaseOrderId);
  }

  Future<List<PurchaseOrderReceipt>> getReceipts({
    int? purchaseOrderId,
    int limit = 100,
  }) {
    return _db.getPurchaseOrderReceipts(
      purchaseOrderId: purchaseOrderId,
      limit: limit,
    );
  }

  Future<List<PurchaseOrderReceiptLine>> getReceiptLines(int receiptId) {
    return _db.getPurchaseOrderReceiptLines(receiptId);
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

  Future<Map<String, dynamic>> receiveAgainstOrder({
    required PurchaseOrder order,
    required List<PurchaseOrderItem> items,
    required Map<int, int> receiveQuantities,
    required String cashierName,
    String referenceNote = '',
    String invoiceNumber = '',
    String deliveryNoteNumber = '',
    String grnReference = '',
  }) async {
    if (receiveQuantities.isEmpty) {
      return {
        'success': false,
        'applied_lines': 0,
        'failed_lines': 0,
        'message': 'No receive quantities entered.',
      };
    }

    if (!order.canReceive) {
      return {
        'success': false,
        'applied_lines': 0,
        'failed_lines': 0,
        'message': 'Only ordered purchase orders can be received.',
      };
    }

    int appliedLines = 0;
    int failedLines = 0;
    final receivedLines = <Map<String, dynamic>>[];
    final failedMessages = <String>[];

    for (final item in items) {
      final itemId = item.id;
      if (itemId == null) continue;

      final requestedQty = receiveQuantities[itemId] ?? 0;
      if (requestedQty <= 0) continue;

      final outstandingQty = item.quantity - item.receivedQuantity;
      if (outstandingQty <= 0) {
        continue;
      }

      if (requestedQty > outstandingQty) {
        failedLines += 1;
        failedMessages.add(
          '${item.productName}: cannot receive more than outstanding qty ($outstandingQty).',
        );
        continue;
      }

      final totalCost = item.unitCost * requestedQty;

      try {
        final response = await http.post(
          Uri.parse('$apiUrl?action=add_stock'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'barcode': item.barcode,
            'quantity': requestedQty,
            'supplier_id': order.supplierId,
            'cost': totalCost,
          }),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result is Map && result['status'] == 'success') {
            receivedLines.add({
              'purchase_order_item_id': itemId,
              'backend_receipt_id': (result['receipt_id'] as num?)?.toInt(),
              'barcode': item.barcode,
              'product_name': item.productName,
              'quantity': requestedQty,
              'cost': totalCost,
            });
            appliedLines += 1;
          } else {
            failedLines += 1;
            failedMessages.add(
              '${item.productName}: backend did not accept receive.',
            );
          }
        } else {
          failedLines += 1;
          failedMessages.add(
            '${item.productName}: backend responded with ${response.statusCode}.',
          );
        }
      } catch (e) {
        failedLines += 1;
        failedMessages.add('${item.productName}: receive failed.');
        debugPrint('Receive against PO failed for ${item.barcode}: $e');
      }
    }

    if (receivedLines.isNotEmpty) {
      await _db.applyPurchaseOrderReceipt(
        purchaseOrderId: order.id,
        orderNumber: order.orderNumber,
        supplierId: order.supplierId,
        supplierName: order.supplierName,
        cashierName: cashierName,
        referenceNote: referenceNote,
        invoiceNumber: invoiceNumber,
        deliveryNoteNumber: deliveryNoteNumber,
        grnReference: grnReference,
        receivedLines: receivedLines,
      );

      await SyncService().refreshProductsFromBackend();
    }

    final success = receivedLines.isNotEmpty;
    final message = success
        ? failedLines == 0
            ? 'Purchase order received successfully.'
            : 'Received $appliedLines line(s), failed $failedLines.'
        : (failedMessages.isNotEmpty
            ? failedMessages.first
            : 'No lines were received.');

    return {
      'success': success,
      'applied_lines': appliedLines,
      'failed_lines': failedLines,
      'failed_messages': failedMessages,
      'message': message,
    };
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
