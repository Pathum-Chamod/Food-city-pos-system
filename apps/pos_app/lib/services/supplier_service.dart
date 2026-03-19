import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../models/reorder_suggestion.dart';
import '../models/stock_receipt_record.dart';
import '../models/supplier_product_history.dart';
import '../models/supplier_purchase_summary.dart';
import 'database_helper.dart';
import 'sync_service.dart';

class SupplierService {
  SupplierService();

  // POS app is currently desktop-first in local development.
  final String apiUrl = 'http://127.0.0.1:8080/api/pos_sync.php';

  Future<List<PosSupplier>> getSuppliers({bool refreshFromBackend = true}) async {
    if (!refreshFromBackend) {
      return DatabaseHelper.instance.getSuppliers();
    }

    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=get_suppliers'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final now = DateTime.now().toIso8601String();
          final suppliers = decoded
              .map(
                (item) => PosSupplier.fromMap(Map<String, dynamic>.from(item as Map))
                    .copyWith(updatedAt: now),
              )
              .toList();

          await DatabaseHelper.instance.replaceSuppliers(suppliers);
          return suppliers;
        }
      }
    } catch (e) {
      debugPrint('Supplier fetch failed, using local cache: $e');
    }

    return DatabaseHelper.instance.getSuppliers();
  }

  Future<bool> receiveStock({
    required PosSupplier supplier,
    required Product product,
    required int quantity,
    required double cost,
    required String cashierName,
    String referenceNote = '',
  }) async {
    final safeNote = referenceNote.trim();

    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=add_stock'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'barcode': product.barcode,
          'quantity': quantity,
          'supplier_id': supplier.id,
          'cost': cost,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result is Map && result['status'] == 'success') {
          await DatabaseHelper.instance.insertStockReceipt(
            backendReceiptId: (result['receipt_id'] as num?)?.toInt(),
            barcode: product.barcode,
            productName: product.name,
            quantity: quantity,
            supplierId: supplier.id,
            supplierName: supplier.name,
            cost: cost,
            referenceNote: safeNote,
            cashierName: cashierName,
            backendStatus: 'synced',
          );

          await SyncService().refreshProductsFromBackend();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Receive stock failed: $e');
    }

    return false;
  }

  Future<List<StockReceiptRecord>> getReceiveHistory({
    int? supplierId,
    String search = '',
    int limit = 200,
  }) {
    return DatabaseHelper.instance.getStockReceipts(
      supplierId: supplierId,
      search: search,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> getReceiveSummary({int? supplierId}) {
    return DatabaseHelper.instance.getStockReceiptSummary(supplierId: supplierId);
  }


  Future<List<SupplierPurchaseSummary>> getSupplierPurchaseSummaries({
    String search = '',
    int limit = 200,
  }) {
    return DatabaseHelper.instance.getSupplierPurchaseSummaries(
      search: search,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> getSupplierPurchaseOverview(int supplierId) {
    return DatabaseHelper.instance.getSupplierPurchaseOverview(supplierId);
  }

  Future<List<SupplierProductHistory>> getSupplierProductHistory({
    required int supplierId,
    String search = '',
    int limit = 200,
  }) {
    return DatabaseHelper.instance.getSupplierProductHistory(
      supplierId: supplierId,
      search: search,
      limit: limit,
    );
  }

  Future<List<ReorderSuggestion>> getReorderSuggestions({
    String search = '',
    int limit = 200,
    int reorderLevel = 10,
    int defaultTargetStock = 30,
  }) {
    return DatabaseHelper.instance.getReorderSuggestions(
      search: search,
      limit: limit,
      reorderLevel: reorderLevel,
      defaultTargetStock: defaultTargetStock,
    );
  }

  Future<Map<String, dynamic>> getReorderSuggestionSummary({
    String search = '',
    int reorderLevel = 10,
    int defaultTargetStock = 30,
  }) {
    return DatabaseHelper.instance.getReorderSuggestionSummary(
      search: search,
      reorderLevel: reorderLevel,
      defaultTargetStock: defaultTargetStock,
    );
  }

}
