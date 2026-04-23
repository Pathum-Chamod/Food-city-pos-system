import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import '../models/pos_supplier.dart';
import '../models/stock_receipt_record.dart';
import '../models/supplier_product_mapping.dart';
import 'database_helper.dart';
import 'sync_service.dart';

class SupplierService {
  SupplierService();

  final String apiUrl = 'http://127.0.0.1:8080/api/pos_sync.php';

  Future<List<PosSupplier>> getSuppliers({
    bool refreshFromBackend = true,
    String search = '',
  }) async {
    final localSuppliers = await DatabaseHelper.instance.getSuppliers();

    if (!refreshFromBackend) {
      return DatabaseHelper.instance.getSuppliers(search: search);
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
          final backendSuppliers = decoded
              .map(
                (item) => PosSupplier.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ).copyWith(updatedAt: now),
              )
              .toList();

          if (localSuppliers.isEmpty) {
            await DatabaseHelper.instance.replaceSuppliers(backendSuppliers);
          } else {
            final localIds = localSuppliers.map((item) => item.id).toSet();
            for (final supplier in backendSuppliers) {
              if (!localIds.contains(supplier.id)) {
                await DatabaseHelper.instance.database.then(
                  (db) => db.insert(
                    'suppliers',
                    {
                      'id': supplier.id,
                      'name': supplier.name,
                      'phone': supplier.phone,
                      'updated_at': supplier.updatedAt,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Supplier fetch failed, using local cache: $e');
    }

    return DatabaseHelper.instance.getSuppliers(search: search);
  }

  Future<PosSupplier> createSupplier({
    required String name,
    String phone = '',
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    final id = await db.insert('suppliers', {
      'name': name.trim(),
      'phone': phone.trim(),
      'updated_at': now,
    });

    return PosSupplier(
      id: id,
      name: name.trim(),
      phone: phone.trim(),
      updatedAt: now,
    );
  }

  Future<void> updateSupplier({
    required int supplierId,
    required String name,
    String phone = '',
  }) async {
    final db = await DatabaseHelper.instance.database;

    await db.update(
      'suppliers',
      {
        'name': name.trim(),
        'phone': phone.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [supplierId],
    );
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
    return DatabaseHelper.instance.getStockReceiptSummary(
      supplierId: supplierId,
    );
  }

  Future<void> saveSupplierProductMapping(SupplierProductMapping mapping) {
    return DatabaseHelper.instance.upsertSupplierProductMapping(mapping);
  }

  Future<void> deleteSupplierProductMapping(int id) {
    return DatabaseHelper.instance.deleteSupplierProductMapping(id);
  }

  Future<List<SupplierProductMapping>> getSupplierProductMappings({
    int? supplierId,
    String search = '',
    int limit = 500,
  }) {
    return DatabaseHelper.instance.getSupplierProductMappings(
      supplierId: supplierId,
      search: search,
      limit: limit,
    );
  }

  Future<List<SupplierProductMapping>> getMappingsForProduct(String barcode) {
    return DatabaseHelper.instance.getMappingsForProduct(barcode);
  }

  Future<SupplierProductMapping?> getPreferredSupplierMapping(String barcode) {
    return DatabaseHelper.instance.getPreferredSupplierMapping(barcode);
  }

  Future<List<PosSupplier>> getMappedSuppliersForProduct(String barcode) {
    return DatabaseHelper.instance.getMappedSuppliersForProduct(barcode);
  }

  Future<void> assignProductToSupplier({
    required PosSupplier supplier,
    required Product product,
    bool isPreferred = true,
    double defaultUnitCost = 0,
    String note = '',
  }) {
    return saveSupplierProductMapping(
      SupplierProductMapping(
        barcode: product.barcode,
        productName: product.name,
        supplierId: supplier.id,
        supplierName: supplier.name,
        isPreferred: isPreferred,
        defaultUnitCost: defaultUnitCost,
        minimumOrderQuantity: 1,
        packSize: 1,
        leadTimeDays: 0,
        note: note.trim(),
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getLinkedProductsForSupplier(
    int supplierId, {
    String search = '',
  }) async {
    final db = await DatabaseHelper.instance.database;
    final trimmed = search.trim().toLowerCase();
    final whereClauses = <String>['m.supplier_id = ?'];
    final whereArgs = <Object?>[supplierId];

    if (trimmed.isNotEmpty) {
      whereClauses.add(
        '(LOWER(m.product_name) LIKE ? OR LOWER(m.barcode) LIKE ? OR LOWER(COALESCE(p.category, "")) LIKE ?)',
      );
      whereArgs
        ..add('%$trimmed%')
        ..add('%$trimmed%')
        ..add('%$trimmed%');
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        m.id,
        m.barcode,
        m.product_name,
        m.is_preferred,
        m.default_unit_cost,
        m.updated_at,
        COALESCE(p.category, '') AS category,
        COALESCE(p.stock, 0) AS stock,
        COALESCE(p.cost_price, 0) AS cost_price,
        COALESCE(p.selling_price, 0) AS selling_price
      FROM supplier_product_mappings m
      LEFT JOIN products p ON p.barcode = m.barcode
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY m.is_preferred DESC, m.product_name COLLATE NOCASE ASC
      ''',
      whereArgs,
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getProductsForAssignment({
    required int supplierId,
    String search = '',
  }) async {
    final products = await DatabaseHelper.instance.getProducts();
    final mappings = await getSupplierProductMappings(supplierId: supplierId, limit: 2000);
    final mappedByBarcode = {
      for (final mapping in mappings) mapping.barcode: mapping,
    };
    final trimmed = search.trim().toLowerCase();

    return products.where((product) {
      if (trimmed.isEmpty) return true;
      return product.name.toLowerCase().contains(trimmed) ||
          product.barcode.toLowerCase().contains(trimmed) ||
          product.category.toLowerCase().contains(trimmed);
    }).map((product) {
      final mapping = mappedByBarcode[product.barcode];
      return {
        'barcode': product.barcode,
        'product_name': product.name,
        'category': product.category,
        'stock': product.stock,
        'cost_price': product.costPrice,
        'mapping_id': mapping?.id,
        'is_assigned': mapping != null,
        'is_preferred': mapping?.isPreferred ?? false,
        'default_unit_cost': mapping?.defaultUnitCost ?? 0.0,
      };
    }).toList();
  }

  Future<Map<int, int>> getLinkedProductCountsBySupplier() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT supplier_id, COUNT(*) AS linked_count
      FROM supplier_product_mappings
      GROUP BY supplier_id
      ''',
    );

    return {
      for (final row in rows)
        ((row['supplier_id'] as num?) ?? 0).toInt():
            ((row['linked_count'] as num?) ?? 0).toInt(),
    };
  }

  Future<bool> receiveStock({
    required PosSupplier supplier,
    required Product product,
    required num quantity,
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
}
