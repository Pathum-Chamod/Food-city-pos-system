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

class PurchaseOrderReceiveLineInput {
  final String barcode;
  final String productName;
  final int orderedQuantity;
  final int alreadyReceivedQuantity;
  final int quantityToReceive;
  final double unitCost;

  const PurchaseOrderReceiveLineInput({
    required this.barcode,
    required this.productName,
    required this.orderedQuantity,
    required this.alreadyReceivedQuantity,
    required this.quantityToReceive,
    required this.unitCost,
  });

  int get remainingQuantity => orderedQuantity - alreadyReceivedQuantity;
}

class ReversePurchaseOrderReceiptRequest {
  final int receiptId;
  final int purchaseOrderId;
  final String reason;
  final String cashierName;
  final String managerName;

  const ReversePurchaseOrderReceiptRequest({
    required this.receiptId,
    required this.purchaseOrderId,
    required this.reason,
    required this.cashierName,
    required this.managerName,
  });
}

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

  Future<PurchaseOrderReceipt?> getReceiptById(int receiptId) {
    return _db.getPurchaseOrderReceiptById(receiptId);
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

  String? validateReceiveAttempt({
    required PurchaseOrder order,
    required List<PurchaseOrderReceiveLineInput> lines,
  }) {
    if (order.status == 'draft') {
      return 'Draft purchase orders cannot be received yet. Mark it as Ordered first.';
    }
    if (order.status == 'cancelled') {
      return 'Cancelled purchase orders cannot be received.';
    }
    if (order.status == 'received') {
      return 'This purchase order is already fully received.';
    }

    final selected = lines.where((e) => e.quantityToReceive > 0).toList();
    if (selected.isEmpty) {
      return 'Enter at least one receive quantity.';
    }

    for (final line in selected) {
      if (line.quantityToReceive < 0) {
        return 'Receive quantity cannot be negative for ${line.productName}.';
      }
      if (line.quantityToReceive > line.remainingQuantity) {
        return 'Cannot receive more than remaining quantity for ${line.productName}.';
      }
      if (line.unitCost < 0) {
        return 'Unit cost cannot be negative for ${line.productName}.';
      }
    }

    return null;
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

    final validationError = validateReceiveAttempt(
      order: order,
      lines: items
          .where((item) => item.id != null)
          .map(
            (item) => PurchaseOrderReceiveLineInput(
              barcode: item.barcode,
              productName: item.productName,
              orderedQuantity: item.quantity,
              alreadyReceivedQuantity: item.receivedQuantity,
              quantityToReceive: receiveQuantities[item.id!] ?? 0,
              unitCost: item.unitCost,
            ),
          )
          .toList(),
    );

    if (validationError != null) {
      return {
        'success': false,
        'applied_lines': 0,
        'failed_lines': 0,
        'message': validationError,
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
        failedLines += 1;
        failedMessages.add(
          '${item.productName}: no remaining quantity left to receive.',
        );
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

  Future<void> reverseReceiptBatch(
    ReversePurchaseOrderReceiptRequest request,
  ) async {
    final receipt = await _db.getPurchaseOrderReceiptById(request.receiptId);
    if (receipt == null) {
      throw Exception('Receipt batch not found.');
    }
    if (receipt.isReversed) {
      throw Exception('This receipt batch was already reversed.');
    }
    if (request.reason.trim().isEmpty) {
      throw Exception('Reversal reason is required.');
    }
    if (request.cashierName.trim().isEmpty) {
      throw Exception('Reversed by is required.');
    }
    if (request.managerName.trim().isEmpty) {
      throw Exception('Manager approval is required.');
    }

    final lines = receipt.lines.isNotEmpty
        ? receipt.lines
        : await _db.getPurchaseOrderReceiptLines(receipt.id);

    if (lines.isEmpty) {
      throw Exception('Receipt batch has no lines to reverse.');
    }

    await SyncService().refreshProductsFromBackend();

    for (final line in lines) {
      final qty = line.receivedQuantity;
      if (qty <= 0) continue;

      final currentStock = await _db.getLocalProductStock(line.barcode);
      if (currentStock == null) {
        throw Exception('Product not found locally for ${line.productName}. Refresh products and try again.');
      }
      if (currentStock < qty) {
        throw Exception(
          'Cannot reverse ${line.productName}. Current stock is $currentStock but reversal needs $qty. Sell-down or manual adjustment happened after receipt.',
        );
      }
    }

    final failures = <String>[];
    for (final line in lines) {
      final qty = line.receivedQuantity;
      if (qty <= 0) continue;

      try {
        final response = await http.post(
          Uri.parse('$apiUrl?action=adjust_stock'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'barcode': line.barcode,
            'adjustment_type': 'decrease',
            'quantity': qty,
            'reason':
                'PO receipt reversal • ${receipt.poNumber} • ${request.reason.trim()}',
          }),
        );

        if (response.statusCode != 200) {
          failures.add('${line.productName}: backend responded with ${response.statusCode}.');
          break;
        }

        final result = jsonDecode(response.body);
        if (result is! Map || result['status'] != 'success') {
          final message = result is Map
              ? (result['message']?.toString() ?? 'backend rejected reversal')
              : 'backend rejected reversal';
          failures.add('${line.productName}: $message');
          break;
        }
      } catch (e) {
        failures.add('${line.productName}: failed to reverse backend stock.');
        debugPrint('Reverse receipt batch backend failure for ${line.barcode}: $e');
        break;
      }
    }

    await SyncService().refreshProductsFromBackend();

    if (failures.isNotEmpty) {
      throw Exception(
        'Receipt reversal did not complete safely. ${failures.first} Products were refreshed from backend. Review stock before retrying.',
      );
    }

    await _db.markReceiptReversed(
      receiptId: receipt.id,
      purchaseOrderId: receipt.purchaseOrderId,
      poNumber: receipt.poNumber,
      reason: request.reason.trim(),
      reversedBy: request.cashierName,
      managerApprovedBy: request.managerName,
      totalUnits: receipt.totalUnits,
      totalCost: receipt.totalCost,
    );
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
