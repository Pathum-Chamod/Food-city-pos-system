import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/pos_supplier.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../models/stock_receipt_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('food_city_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, filePath);

    debugPrint('POS local DB path: $path');

    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      ),
    );
  }

  double _roundMoney(num value) {
    return double.parse(value.toStringAsFixed(2));
  }

  String _normalizeDiscountType(String? value) {
    if (value == 'fixed') return 'fixed';
    if (value == 'percent') return 'percent';
    return 'none';
  }

  double _calculateDiscountAmount({
    required double subtotal,
    required String discountType,
    required double discountValue,
  }) {
    if (subtotal <= 0) return 0.0;

    if (discountType == 'fixed') {
      final safeValue = discountValue < 0 ? 0.0 : discountValue;
      return _roundMoney(safeValue > subtotal ? subtotal : safeValue);
    }

    if (discountType == 'percent') {
      final safeValue = discountValue < 0 ? 0.0 : discountValue;
      final capped = safeValue > 100 ? 100.0 : safeValue;
      return _roundMoney(subtotal * (capped / 100));
    }

    return 0.0;
  }

  Future<void> _createSupplierTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        backend_receipt_id INTEGER,
        purchase_order_id INTEGER,
        purchase_order_number TEXT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier_name TEXT NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        reference_note TEXT,
        cashier_name TEXT,
        created_at TEXT NOT NULL,
        backend_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');
  }


  Future<void> _createPurchaseOrderTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT UNIQUE NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        reference_note TEXT,
        total_lines INTEGER NOT NULL DEFAULT 0,
        total_units INTEGER NOT NULL DEFAULT 0,
        received_units INTEGER NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        created_by TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_order_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        received_quantity INTEGER NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        stock INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subtotal_amount REAL NOT NULL DEFAULT 0,
        discount_type TEXT NOT NULL DEFAULT 'none',
        discount_value REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL,
        cashier_name TEXT,
        transaction_type TEXT NOT NULL DEFAULT 'sale',
        original_sale_id INTEGER,
        refund_reason TEXT,
        payment_method TEXT,
        amount_tendered REAL,
        change_amount REAL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        base_line_total REAL NOT NULL DEFAULT 0,
        item_discount_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cashier_name TEXT NOT NULL,
        opening_cash REAL NOT NULL,
        expected_cash REAL,
        closing_cash REAL,
        variance REAL,
        status TEXT NOT NULL DEFAULT 'open',
        opened_at TEXT NOT NULL,
        closed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE held_carts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cart_name TEXT NOT NULL,
        cashier_name TEXT NOT NULL,
        is_refund_mode INTEGER NOT NULL DEFAULT 0,
        discount_type TEXT NOT NULL DEFAULT 'none',
        discount_value REAL NOT NULL DEFAULT 0,
        items_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        data TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin TEXT UNIQUE NOT NULL
      )
    ''');

    await _createSupplierTables(db);
    await _createPurchaseOrderTables(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sale_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          unit_price REAL NOT NULL,
          quantity INTEGER NOT NULL,
          line_total REAL NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
        )
      ''');

      await _addColumnIfMissing(db, 'sales', 'cashier_name', 'TEXT');
      await _addColumnIfMissing(
        db,
        'sales',
        'transaction_type',
        "TEXT NOT NULL DEFAULT 'sale'",
      );
    }

    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'sales', 'original_sale_id', 'INTEGER');
      await _addColumnIfMissing(db, 'sales', 'refund_reason', 'TEXT');
    }

    if (oldVersion < 4) {
      await _addColumnIfMissing(db, 'sales', 'payment_method', 'TEXT');
      await _addColumnIfMissing(db, 'sales', 'amount_tendered', 'REAL');
      await _addColumnIfMissing(db, 'sales', 'change_amount', 'REAL');
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shifts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cashier_name TEXT NOT NULL,
          opening_cash REAL NOT NULL,
          expected_cash REAL,
          closing_cash REAL,
          variance REAL,
          status TEXT NOT NULL DEFAULT 'open',
          opened_at TEXT NOT NULL,
          closed_at TEXT
        )
      ''');
    }

    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS held_carts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cart_name TEXT NOT NULL,
          cashier_name TEXT NOT NULL,
          is_refund_mode INTEGER NOT NULL DEFAULT 0,
          items_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 7) {
      await _addColumnIfMissing(
        db,
        'sales',
        'subtotal_amount',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sales',
        'discount_type',
        "TEXT NOT NULL DEFAULT 'none'",
      );
      await _addColumnIfMissing(
        db,
        'sales',
        'discount_value',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sales',
        'discount_amount',
        "REAL NOT NULL DEFAULT 0",
      );

      await _addColumnIfMissing(
        db,
        'sale_items',
        'base_line_total',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'item_discount_amount',
        "REAL NOT NULL DEFAULT 0",
      );

      await _addColumnIfMissing(
        db,
        'held_carts',
        'discount_type',
        "TEXT NOT NULL DEFAULT 'none'",
      );
      await _addColumnIfMissing(
        db,
        'held_carts',
        'discount_value',
        "REAL NOT NULL DEFAULT 0",
      );
    }

    if (oldVersion < 8) {
      await _createSupplierTables(db);
    }

    if (oldVersion < 9) {
      await _createPurchaseOrderTables(db);
    }

    if (oldVersion < 10) {
      await _addColumnIfMissing(db, 'stock_receipts', 'purchase_order_id', 'INTEGER');
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'purchase_order_number',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        'purchase_orders',
        'received_units',
        "INTEGER NOT NULL DEFAULT 0",
      );

      final orderIds = await db.query('purchase_orders', columns: ['id']);
      for (final row in orderIds) {
        final orderId = (row['id'] as num?)?.toInt();
        if (orderId == null) continue;

        final receivedRows = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(received_quantity), 0) AS received_units
          FROM purchase_order_items
          WHERE purchase_order_id = ?
          ''',
          [orderId],
        );

        final receivedUnits =
            (receivedRows.first['received_units'] as num?)?.toInt() ?? 0;

        await db.update(
          'purchase_orders',
          {
            'received_units': receivedUnits,
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
    }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);

    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> insertMockDataIfEmpty() async {
    final db = await database;

    final existingProducts = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products',
    );
    final productCount = existingProducts.first['count'] as int;

    if (productCount == 0) {
      final mockProducts = [
        {
          'barcode': '4791044000123',
          'name': 'Munchee Super Cream Cracker 500g',
          'price': 450.0,
          'stock': 100,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'barcode': '4792011001234',
          'name': 'Anchor Milk Powder 400g',
          'price': 1100.0,
          'stock': 50,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'barcode': '4792022005678',
          'name': 'Saman Halmassa 425g',
          'price': 650.0,
          'stock': 30,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'barcode': '4793033009999',
          'name': 'Kist Strawberry Jam 500g',
          'price': 580.0,
          'stock': 40,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ];

      for (final product in mockProducts) {
        await db.insert('products', product);
      }
    }

    final existingUsers = await db.rawQuery(
      'SELECT COUNT(*) as count FROM users',
    );
    final userCount = existingUsers.first['count'] as int;

    if (userCount == 0) {
      final mockUsers = [
        {'name': 'Pathum (Manager)', 'role': 'manager', 'pin': '1234'},
        {'name': 'Amal (Cashier)', 'role': 'cashier', 'pin': '5555'},
      ];

      for (final user in mockUsers) {
        await db.insert('users', user);
      }
    }

    final existingSuppliers = await db.rawQuery(
      'SELECT COUNT(*) as count FROM suppliers',
    );
    final supplierCount = existingSuppliers.first['count'] as int;

    if (supplierCount == 0) {
      final now = DateTime.now().toIso8601String();
      final mockSuppliers = [
        {
          'id': 1,
          'name': 'Maliban Distributor',
          'phone': '077-1234567',
          'updated_at': now,
        },
        {
          'id': 2,
          'name': 'Fonterra Lanka',
          'phone': '077-9876543',
          'updated_at': now,
        },
      ];

      for (final supplier in mockSuppliers) {
        await db.insert(
          'suppliers',
          supplier,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('products', orderBy: 'name ASC');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<void> replaceProductsFromBackend(List<Product> backendProducts) async {
    final db = await database;

    await db.transaction((txn) async {
      final backendBarcodes = backendProducts.map((p) => p.barcode).toList();

      if (backendBarcodes.isEmpty) {
        await txn.delete('products');
      } else {
        final placeholders = List.filled(backendBarcodes.length, '?').join(',');
        await txn.delete(
          'products',
          where: 'barcode NOT IN ($placeholders)',
          whereArgs: backendBarcodes,
        );
      }

      final batch = txn.batch();

      for (final product in backendProducts) {
        batch.insert('products', {
          'barcode': product.barcode,
          'name': product.name,
          'price': product.price,
          'stock': product.stock,
          'updated_at': product.updatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);

      final pendingItems = await txn.query(
        'sync_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'id ASC',
      );

      for (final pending in pendingItems) {
        final type = (pending['type'] as String?) ?? '';
        final rawData = (pending['data'] as String?) ?? '{}';

        dynamic decodedData;
        try {
          decodedData = jsonDecode(rawData);
        } catch (_) {
          continue;
        }

        if (type == 'SALE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final transactionType = (data['transaction_type'] ?? 'sale')
              .toString()
              .toLowerCase();
          final items = (data['items'] as List?) ?? [];

          for (final rawItem in items) {
            final item = Map<String, dynamic>.from(rawItem as Map);
            final productMap = Map<String, dynamic>.from(
              item['product'] as Map,
            );

            final barcode = productMap['barcode']?.toString() ?? '';
            final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

            if (barcode.isEmpty || quantity <= 0) continue;

            final stockDelta = transactionType == 'refund'
                ? quantity
                : -quantity;

            await txn.rawUpdate(
              '''
              UPDATE products
              SET stock = stock + ?
              WHERE barcode = ?
              ''',
              [stockDelta, barcode],
            );
          }
        } else if (type == 'PRICE_UPDATE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final barcode = data['barcode']?.toString() ?? '';
          final newPrice = (data['new_price'] as num?)?.toDouble();

          if (barcode.isEmpty || newPrice == null) continue;

          await txn.update(
            'products',
            {'price': newPrice, 'updated_at': DateTime.now().toIso8601String()},
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        }
      }
    });
  }

  Future<int> processTransaction({
    required double subtotalAmount,
    required double totalAmount,
    required List<Map<String, dynamic>> cartItems,
    required String cashierName,
    required bool isRefund,
    String? paymentMethod,
    double? amountTendered,
    double? changeAmount,
    String discountType = 'none',
    double discountValue = 0.0,
    double? discountAmount,
  }) async {
    final db = await database;

    if (cartItems.isEmpty) {
      throw Exception('Cart is empty.');
    }

    try {
      late int saleId;

      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final transactionType = isRefund ? 'refund' : 'sale';

        final resolvedSubtotal = _roundMoney(
          isRefund ? totalAmount.abs() : subtotalAmount.abs(),
        );

        final resolvedDiscountType = isRefund
            ? 'none'
            : _normalizeDiscountType(discountType);
        final resolvedDiscountValue = isRefund ? 0.0 : discountValue;
        final resolvedDiscountAmount = isRefund
            ? 0.0
            : _calculateDiscountAmount(
                subtotal: resolvedSubtotal,
                discountType: resolvedDiscountType,
                discountValue: resolvedDiscountValue,
              );

        final resolvedFinalTotal = isRefund
            ? resolvedSubtotal
            : _roundMoney(resolvedSubtotal - resolvedDiscountAmount);

        final signedTotal = isRefund ? -resolvedFinalTotal : resolvedFinalTotal;
        final signedSubtotal = isRefund ? -resolvedSubtotal : resolvedSubtotal;

        String? resolvedPaymentMethod = paymentMethod;
        double? resolvedAmountTendered = amountTendered;
        double resolvedChangeAmount = changeAmount ?? 0.0;

        if (!isRefund) {
          if (resolvedPaymentMethod == null ||
              (resolvedPaymentMethod != 'cash' &&
                  resolvedPaymentMethod != 'card')) {
            throw Exception('Valid payment method is required.');
          }

          if (resolvedPaymentMethod == 'cash') {
            if (resolvedAmountTendered == null ||
                resolvedAmountTendered < resolvedFinalTotal) {
              throw Exception('Cash amount is not enough.');
            }
            resolvedChangeAmount = _roundMoney(
              resolvedAmountTendered - resolvedFinalTotal,
            );
          } else {
            resolvedAmountTendered = resolvedFinalTotal;
            resolvedChangeAmount = 0.0;
          }

          for (final item in cartItems) {
            final productMap = Map<String, dynamic>.from(
              item['product'] as Map,
            );
            final barcode = productMap['barcode']?.toString() ?? '';
            final productName =
                productMap['name']?.toString() ?? 'Unknown product';
            final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

            if (quantity <= 0) {
              throw Exception('Invalid quantity for $productName.');
            }

            final rows = await txn.query(
              'products',
              columns: ['stock'],
              where: 'barcode = ?',
              whereArgs: [barcode],
              limit: 1,
            );

            if (rows.isEmpty) {
              throw Exception(
                '$productName was not found in local POS database.',
              );
            }

            final availableStock = (rows.first['stock'] as num).toInt();

            if (availableStock < quantity) {
              throw Exception(
                'Insufficient stock for $productName. Available: $availableStock, requested: $quantity.',
              );
            }
          }
        } else {
          resolvedPaymentMethod = 'refund';
          resolvedAmountTendered = null;
          resolvedChangeAmount = 0.0;
        }

        saleId = await txn.insert('sales', {
          'subtotal_amount': signedSubtotal,
          'discount_type': resolvedDiscountType,
          'discount_value': resolvedDiscountValue,
          'discount_amount': resolvedDiscountAmount,
          'total_amount': signedTotal,
          'cashier_name': cashierName,
          'transaction_type': transactionType,
          'original_sale_id': null,
          'refund_reason': null,
          'payment_method': resolvedPaymentMethod,
          'amount_tendered': resolvedAmountTendered,
          'change_amount': resolvedChangeAmount,
          'created_at': now,
        });

        final saleItemInputs = <Map<String, dynamic>>[];
        double remainingDiscountToAllocate = resolvedDiscountAmount;

        for (int i = 0; i < cartItems.length; i++) {
          final item = cartItems[i];
          final productMap = Map<String, dynamic>.from(item['product'] as Map);
          final barcode = productMap['barcode']?.toString() ?? '';
          final productName =
              productMap['name']?.toString() ?? 'Unknown product';
          final unitPrice = (productMap['price'] as num).toDouble();
          final quantity = (item['quantity'] as num).toInt();

          final baseLineTotal = _roundMoney(unitPrice * quantity);

          double itemDiscount = 0.0;

          if (!isRefund && resolvedDiscountAmount > 0) {
            if (i == cartItems.length - 1) {
              itemDiscount = remainingDiscountToAllocate;
            } else {
              final share = resolvedSubtotal <= 0
                  ? 0.0
                  : resolvedDiscountAmount * (baseLineTotal / resolvedSubtotal);
              itemDiscount = _roundMoney(share);

              if (itemDiscount > remainingDiscountToAllocate) {
                itemDiscount = remainingDiscountToAllocate;
              }
            }
          }

          itemDiscount = itemDiscount > baseLineTotal
              ? baseLineTotal
              : itemDiscount;
          remainingDiscountToAllocate = _roundMoney(
            remainingDiscountToAllocate - itemDiscount,
          );

          final finalLineTotal = isRefund
              ? -baseLineTotal
              : _roundMoney(baseLineTotal - itemDiscount);

          saleItemInputs.add({
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'quantity': quantity,
            'base_line_total': baseLineTotal,
            'item_discount_amount': isRefund ? 0.0 : itemDiscount,
            'line_total': finalLineTotal,
          });
        }

        for (final item in saleItemInputs) {
          final barcode = item['barcode'] as String;
          final productName = item['product_name'] as String;
          final unitPrice = item['unit_price'] as double;
          final quantity = item['quantity'] as int;
          final baseLineTotal = item['base_line_total'] as double;
          final itemDiscount = item['item_discount_amount'] as double;
          final finalLineTotal = item['line_total'] as double;

          final stockDelta = isRefund ? quantity : -quantity;

          final updatedCount = await txn.rawUpdate(
            '''
            UPDATE products
            SET stock = stock + ?, updated_at = ?
            WHERE barcode = ?
            ''',
            [stockDelta, now, barcode],
          );

          if (updatedCount == 0) {
            throw Exception(
              '$productName was not found in local POS database.',
            );
          }

          await txn.insert('sale_items', {
            'sale_id': saleId,
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'quantity': quantity,
            'base_line_total': baseLineTotal,
            'item_discount_amount': itemDiscount,
            'line_total': finalLineTotal,
            'created_at': now,
          });
        }

        final syncData = jsonEncode({
          'local_sale_id': saleId,
          'subtotal_amount': signedSubtotal,
          'discount_type': resolvedDiscountType,
          'discount_value': resolvedDiscountValue,
          'discount_amount': resolvedDiscountAmount,
          'total_amount': signedTotal,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
          'cashier': cashierName,
          'transaction_type': transactionType,
          'payment_method': resolvedPaymentMethod,
          'amount_tendered': resolvedAmountTendered,
          'change_amount': resolvedChangeAmount,
          'items': cartItems,
        });

        await txn.insert('sync_queue', {
          'type': 'SALE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return saleId;
    } catch (e) {
      debugPrint('Checkout Database Error: $e');
      rethrow;
    }
  }

  Future<int> processRefundFromSale({
    required int originalSaleId,
    required List<Map<String, dynamic>> refundItems,
    required String cashierName,
    required String refundReason,
  }) async {
    final db = await database;

    if (refundItems.isEmpty) {
      throw Exception('No items selected for refund.');
    }

    if (refundReason.trim().isEmpty) {
      throw Exception('Refund reason is required.');
    }

    try {
      late int refundSaleId;

      await db.transaction((txn) async {
        final originalSaleRows = await txn.query(
          'sales',
          where: 'id = ?',
          whereArgs: [originalSaleId],
          limit: 1,
        );

        if (originalSaleRows.isEmpty) {
          throw Exception('Original sale not found.');
        }

        final originalSale = originalSaleRows.first;
        final originalType = (originalSale['transaction_type'] ?? 'sale')
            .toString()
            .toLowerCase();

        if (originalType != 'sale') {
          throw Exception('Only sale transactions can be refunded.');
        }

        final refundableItems = await _getRefundableItemsForSaleExecutor(
          txn,
          originalSaleId,
        );

        final refundableMap = <String, Map<String, dynamic>>{
          for (final item in refundableItems)
            (item['barcode'] ?? '').toString(): item,
        };

        double refundTotal = 0;
        final now = DateTime.now().toIso8601String();

        refundSaleId = await txn.insert('sales', {
          'subtotal_amount': 0.0,
          'discount_type': 'none',
          'discount_value': 0.0,
          'discount_amount': 0.0,
          'total_amount': 0.0,
          'cashier_name': cashierName,
          'transaction_type': 'refund',
          'original_sale_id': originalSaleId,
          'refund_reason': refundReason.trim(),
          'payment_method': 'refund',
          'amount_tendered': null,
          'change_amount': 0.0,
          'created_at': now,
        });

        final syncItems = <Map<String, dynamic>>[];

        for (final rawItem in refundItems) {
          final item = Map<String, dynamic>.from(rawItem);
          final barcode = item['barcode']?.toString() ?? '';
          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

          if (barcode.isEmpty || quantity <= 0) {
            throw Exception('Invalid refund item.');
          }

          final refundableData = refundableMap[barcode];
          if (refundableData == null) {
            throw Exception(
              'Refund item $barcode is not part of the original sale.',
            );
          }

          final refundableQty =
              (refundableData['refundable_quantity'] as num?)?.toInt() ?? 0;
          final remainingRefundableTotal =
              ((refundableData['remaining_refundable_total'] as num?) ?? 0)
                  .toDouble();

          if (quantity > refundableQty) {
            final productName =
                (refundableData['product_name'] ?? 'Unknown product')
                    .toString();
            throw Exception(
              'Cannot refund more than remaining quantity for $productName. Remaining: $refundableQty.',
            );
          }

          final productName =
              (refundableData['product_name'] ?? 'Unknown product').toString();
          final unitPrice = ((refundableData['refund_unit_price'] as num?) ?? 0)
              .toDouble();

          final updatedCount = await txn.rawUpdate(
            '''
            UPDATE products
            SET stock = stock + ?, updated_at = ?
            WHERE barcode = ?
            ''',
            [quantity, now, barcode],
          );

          if (updatedCount == 0) {
            throw Exception(
              '$productName was not found in local POS database.',
            );
          }

          double refundLineTotal;
          if (quantity == refundableQty) {
            refundLineTotal = _roundMoney(remainingRefundableTotal);
          } else {
            refundLineTotal = _roundMoney(
              remainingRefundableTotal * (quantity / refundableQty),
            );
          }

          refundTotal += refundLineTotal;

          await txn.insert('sale_items', {
            'sale_id': refundSaleId,
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'quantity': quantity,
            'base_line_total': refundLineTotal,
            'item_discount_amount': 0.0,
            'line_total': -refundLineTotal,
            'created_at': now,
          });

          syncItems.add({
            'product': {
              'barcode': barcode,
              'name': productName,
              'price': unitPrice,
            },
            'quantity': quantity,
            'line_total': -refundLineTotal,
          });
        }

        refundTotal = _roundMoney(refundTotal);

        await txn.update(
          'sales',
          {'subtotal_amount': -refundTotal, 'total_amount': -refundTotal},
          where: 'id = ?',
          whereArgs: [refundSaleId],
        );

        final syncData = jsonEncode({
          'local_sale_id': refundSaleId,
          'subtotal_amount': -refundTotal,
          'discount_type': 'none',
          'discount_value': 0.0,
          'discount_amount': 0.0,
          'total_amount': -refundTotal,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
          'cashier': cashierName,
          'transaction_type': 'refund',
          'payment_method': 'refund',
          'amount_tendered': null,
          'change_amount': 0.0,
          'original_sale_id': originalSaleId,
          'refund_reason': refundReason.trim(),
          'items': syncItems,
        });

        await txn.insert('sync_queue', {
          'type': 'SALE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return refundSaleId;
    } catch (e) {
      debugPrint('Refund Database Error: $e');
      rethrow;
    }
  }

  Future<bool> updateProductPriceLocal(String barcode, double newPrice) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        await txn.update(
          'products',
          {'price': newPrice, 'updated_at': now},
          where: 'barcode = ?',
          whereArgs: [barcode],
        );

        final syncData = jsonEncode({
          'barcode': barcode,
          'new_price': newPrice,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
        });

        await txn.insert('sync_queue', {
          'type': 'PRICE_UPDATE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error updating price: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> authenticateUser(String pin) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'pin = ?',
      whereArgs: [pin],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first;
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions({
    String? transactionType,
    int limit = 50,
  }) async {
    final db = await database;

    String whereClause = '';
    List<Object?> whereArgs = [];

    if (transactionType != null && transactionType.isNotEmpty) {
      whereClause = 'WHERE s.transaction_type = ?';
      whereArgs = [transactionType];
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        s.id,
        s.subtotal_amount,
        s.discount_type,
        s.discount_value,
        s.discount_amount,
        s.total_amount,
        s.cashier_name,
        s.transaction_type,
        s.original_sale_id,
        s.refund_reason,
        s.payment_method,
        s.amount_tendered,
        s.change_amount,
        s.created_at,
        COUNT(si.id) AS item_line_count,
        COALESCE(SUM(si.quantity), 0) AS item_quantity_total
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id = s.id
      $whereClause
      GROUP BY
        s.id,
        s.subtotal_amount,
        s.discount_type,
        s.discount_value,
        s.discount_amount,
        s.total_amount,
        s.cashier_name,
        s.transaction_type,
        s.original_sale_id,
        s.refund_reason,
        s.payment_method,
        s.amount_tendered,
        s.change_amount,
        s.created_at
      ORDER BY datetime(s.created_at) DESC, s.id DESC
      LIMIT ?
      ''',
      [...whereArgs, limit],
    );

    return rows
        .map(
          (row) => {
            'id': row['id'],
            'subtotal_amount': row['subtotal_amount'],
            'discount_type': row['discount_type'],
            'discount_value': row['discount_value'],
            'discount_amount': row['discount_amount'],
            'total_amount': row['total_amount'],
            'cashier_name': row['cashier_name'],
            'transaction_type': row['transaction_type'],
            'original_sale_id': row['original_sale_id'],
            'refund_reason': row['refund_reason'],
            'payment_method': row['payment_method'],
            'amount_tendered': row['amount_tendered'],
            'change_amount': row['change_amount'],
            'created_at': row['created_at'],
            'item_line_count': row['item_line_count'],
            'item_quantity_total': row['item_quantity_total'],
          },
        )
        .toList();
  }

  Future<Map<String, dynamic>?> getTransactionSummary(int saleId) async {
    final db = await database;

    final rows = await db.rawQuery(
      '''
      SELECT
        s.id,
        s.subtotal_amount,
        s.discount_type,
        s.discount_value,
        s.discount_amount,
        s.total_amount,
        s.cashier_name,
        s.transaction_type,
        s.original_sale_id,
        s.refund_reason,
        s.payment_method,
        s.amount_tendered,
        s.change_amount,
        s.created_at,
        COUNT(si.id) AS item_line_count,
        COALESCE(SUM(si.quantity), 0) AS item_quantity_total
      FROM sales s
      LEFT JOIN sale_items si ON si.sale_id = s.id
      WHERE s.id = ?
      GROUP BY
        s.id,
        s.subtotal_amount,
        s.discount_type,
        s.discount_value,
        s.discount_amount,
        s.total_amount,
        s.cashier_name,
        s.transaction_type,
        s.original_sale_id,
        s.refund_reason,
        s.payment_method,
        s.amount_tendered,
        s.change_amount,
        s.created_at
      LIMIT 1
      ''',
      [saleId],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;

    return {
      'id': row['id'],
      'subtotal_amount': row['subtotal_amount'],
      'discount_type': row['discount_type'],
      'discount_value': row['discount_value'],
      'discount_amount': row['discount_amount'],
      'total_amount': row['total_amount'],
      'cashier_name': row['cashier_name'],
      'transaction_type': row['transaction_type'],
      'original_sale_id': row['original_sale_id'],
      'refund_reason': row['refund_reason'],
      'payment_method': row['payment_method'],
      'amount_tendered': row['amount_tendered'],
      'change_amount': row['change_amount'],
      'created_at': row['created_at'],
      'item_line_count': row['item_line_count'],
      'item_quantity_total': row['item_quantity_total'],
    };
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(int saleId) async {
    final db = await database;

    final rows = await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );

    return rows
        .map(
          (row) => {
            'id': row['id'],
            'sale_id': row['sale_id'],
            'barcode': row['barcode'],
            'product_name': row['product_name'],
            'unit_price': row['unit_price'],
            'quantity': row['quantity'],
            'base_line_total': row['base_line_total'],
            'item_discount_amount': row['item_discount_amount'],
            'line_total': row['line_total'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> getRefundableItemsForSale(
    int saleId,
  ) async {
    final db = await database;
    return _getRefundableItemsForSaleExecutor(db, saleId);
  }

  Future<List<Map<String, dynamic>>> _getRefundableItemsForSaleExecutor(
    DatabaseExecutor executor,
    int saleId,
  ) async {
    final saleRows = await executor.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    if (saleRows.isEmpty) {
      throw Exception('Original sale not found.');
    }

    final saleType = (saleRows.first['transaction_type'] ?? 'sale')
        .toString()
        .toLowerCase();

    if (saleType != 'sale') {
      throw Exception('Only sale transactions can be refunded.');
    }

    final originalItems = await executor.rawQuery(
      '''
      SELECT
        barcode,
        product_name,
        unit_price,
        SUM(quantity) AS original_quantity,
        COALESCE(SUM(ABS(line_total)), 0) AS original_net_total
      FROM sale_items
      WHERE sale_id = ?
      GROUP BY barcode, product_name, unit_price
      ORDER BY product_name ASC
      ''',
      [saleId],
    );

    final refundedItems = await executor.rawQuery(
      '''
      SELECT
        si.barcode,
        COALESCE(SUM(si.quantity), 0) AS refunded_quantity,
        COALESCE(SUM(ABS(si.line_total)), 0) AS refunded_total
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE s.transaction_type = 'refund'
        AND s.original_sale_id = ?
      GROUP BY si.barcode
      ''',
      [saleId],
    );

    final refundedMap = <String, Map<String, dynamic>>{
      for (final row in refundedItems)
        (row['barcode'] ?? '').toString(): {
          'refunded_quantity': (row['refunded_quantity'] as num?)?.toInt() ?? 0,
          'refunded_total': ((row['refunded_total'] as num?) ?? 0).toDouble(),
        },
    };

    return originalItems.map((row) {
      final barcode = (row['barcode'] ?? '').toString();
      final originalQty = (row['original_quantity'] as num?)?.toInt() ?? 0;
      final originalNetTotal = ((row['original_net_total'] as num?) ?? 0)
          .toDouble();

      final refundedQty =
          (refundedMap[barcode]?['refunded_quantity'] as int?) ?? 0;
      final refundedTotal =
          (refundedMap[barcode]?['refunded_total'] as double?) ?? 0.0;

      final refundableQty = originalQty - refundedQty;
      final remainingRefundableTotal = _roundMoney(
        originalNetTotal - refundedTotal,
      );

      final refundUnitPrice = refundableQty > 0
          ? _roundMoney(remainingRefundableTotal / refundableQty)
          : 0.0;

      return {
        'barcode': barcode,
        'product_name': row['product_name'],
        'unit_price': row['unit_price'],
        'original_quantity': originalQty,
        'refunded_quantity': refundedQty,
        'refundable_quantity': refundableQty < 0 ? 0 : refundableQty,
        'remaining_refundable_total': remainingRefundableTotal < 0
            ? 0.0
            : remainingRefundableTotal,
        'refund_unit_price': refundUnitPrice,
      };
    }).toList();
  }

  Future<int> openShift({
    required String cashierName,
    required double openingCash,
  }) async {
    final db = await database;

    if (openingCash < 0) {
      throw Exception('Opening cash cannot be negative.');
    }

    try {
      late int shiftId;

      await db.transaction((txn) async {
        final existingOpenShift = await txn.query(
          'shifts',
          where: 'cashier_name = ? AND status = ?',
          whereArgs: [cashierName, 'open'],
          limit: 1,
        );

        if (existingOpenShift.isNotEmpty) {
          throw Exception('This cashier already has an open shift.');
        }

        final now = DateTime.now().toIso8601String();

        shiftId = await txn.insert('shifts', {
          'cashier_name': cashierName,
          'opening_cash': openingCash,
          'expected_cash': openingCash,
          'closing_cash': null,
          'variance': null,
          'status': 'open',
          'opened_at': now,
          'closed_at': null,
        });
      });

      return shiftId;
    } catch (e) {
      debugPrint('Open Shift Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getOpenShiftForCashier(
    String cashierName,
  ) async {
    final db = await database;

    final rows = await db.query(
      'shifts',
      where: 'cashier_name = ? AND status = ?',
      whereArgs: [cashierName, 'open'],
      orderBy: 'datetime(opened_at) DESC, id DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>?> getOpenShiftSummaryForCashier(
    String cashierName,
  ) async {
    final db = await database;
    return _getOpenShiftSummaryForCashierExecutor(db, cashierName);
  }

  Future<Map<String, dynamic>?> _getOpenShiftSummaryForCashierExecutor(
    DatabaseExecutor executor,
    String cashierName,
  ) async {
    final rows = await executor.query(
      'shifts',
      where: 'cashier_name = ? AND status = ?',
      whereArgs: [cashierName, 'open'],
      orderBy: 'datetime(opened_at) DESC, id DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final shift = Map<String, dynamic>.from(rows.first);
    final stats = await _buildShiftStatsExecutor(
      executor,
      cashierName: cashierName,
      openedAt: (shift['opened_at'] ?? '').toString(),
      openingCash: ((shift['opening_cash'] as num?) ?? 0).toDouble(),
    );

    return {...shift, ...stats};
  }

  Future<Map<String, dynamic>> closeShift({
    required int shiftId,
    required String cashierName,
    required double closingCash,
  }) async {
    final db = await database;

    if (closingCash < 0) {
      throw Exception('Closing cash cannot be negative.');
    }

    try {
      late Map<String, dynamic> result;

      await db.transaction((txn) async {
        final shiftRows = await txn.query(
          'shifts',
          where: 'id = ? AND cashier_name = ? AND status = ?',
          whereArgs: [shiftId, cashierName, 'open'],
          limit: 1,
        );

        if (shiftRows.isEmpty) {
          throw Exception('Open shift not found.');
        }

        final shift = Map<String, dynamic>.from(shiftRows.first);
        final closedAt = DateTime.now().toIso8601String();

        final stats = await _buildShiftStatsExecutor(
          txn,
          cashierName: cashierName,
          openedAt: (shift['opened_at'] ?? '').toString(),
          openingCash: ((shift['opening_cash'] as num?) ?? 0).toDouble(),
          closedAt: closedAt,
        );

        final expectedCash = ((stats['expected_cash'] as num?) ?? 0).toDouble();
        final variance = closingCash - expectedCash;

        await txn.update(
          'shifts',
          {
            'expected_cash': expectedCash,
            'closing_cash': closingCash,
            'variance': variance,
            'closed_at': closedAt,
            'status': 'closed',
          },
          where: 'id = ?',
          whereArgs: [shiftId],
        );

        result = {
          ...shift,
          ...stats,
          'expected_cash': expectedCash,
          'closing_cash': closingCash,
          'variance': variance,
          'closed_at': closedAt,
          'status': 'closed',
        };
      });

      return result;
    } catch (e) {
      debugPrint('Close Shift Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _buildShiftStatsExecutor(
    DatabaseExecutor executor, {
    required String cashierName,
    required String openedAt,
    required double openingCash,
    String? closedAt,
  }) async {
    final endTime = closedAt ?? DateTime.now().toIso8601String();

    final cashSalesRow = (await executor.rawQuery(
      '''
      SELECT
        COALESCE(SUM(total_amount), 0) AS total,
        COUNT(*) AS count
      FROM sales
      WHERE cashier_name = ?
        AND transaction_type = 'sale'
        AND payment_method = 'cash'
        AND datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
      ''',
      [cashierName, openedAt, endTime],
    )).first;

    final cardSalesRow = (await executor.rawQuery(
      '''
      SELECT
        COALESCE(SUM(total_amount), 0) AS total,
        COUNT(*) AS count
      FROM sales
      WHERE cashier_name = ?
        AND transaction_type = 'sale'
        AND payment_method = 'card'
        AND datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
      ''',
      [cashierName, openedAt, endTime],
    )).first;

    final refundCountRow = (await executor.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM sales
      WHERE cashier_name = ?
        AND transaction_type = 'refund'
        AND datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
      ''',
      [cashierName, openedAt, endTime],
    )).first;

    final transactionCountRow = (await executor.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM sales
      WHERE cashier_name = ?
        AND datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
      ''',
      [cashierName, openedAt, endTime],
    )).first;

    final cashRefundRow = (await executor.rawQuery(
      '''
      SELECT
        COALESCE(SUM(ABS(r.total_amount)), 0) AS total
      FROM sales r
      LEFT JOIN sales o ON r.original_sale_id = o.id
      WHERE r.cashier_name = ?
        AND r.transaction_type = 'refund'
        AND o.payment_method = 'cash'
        AND datetime(r.created_at) >= datetime(?)
        AND datetime(r.created_at) <= datetime(?)
      ''',
      [cashierName, openedAt, endTime],
    )).first;

    final cashSalesTotal = ((cashSalesRow['total'] as num?) ?? 0).toDouble();
    final cardSalesTotal = ((cardSalesRow['total'] as num?) ?? 0).toDouble();
    final cashRefundTotal = ((cashRefundRow['total'] as num?) ?? 0).toDouble();

    final expectedCash = openingCash + cashSalesTotal - cashRefundTotal;

    return {
      'cash_sales_total': cashSalesTotal,
      'card_sales_total': cardSalesTotal,
      'cash_refund_total': cashRefundTotal,
      'cash_sale_count': (cashSalesRow['count'] as num?)?.toInt() ?? 0,
      'card_sale_count': (cardSalesRow['count'] as num?)?.toInt() ?? 0,
      'refund_count': (refundCountRow['count'] as num?)?.toInt() ?? 0,
      'transaction_count': (transactionCountRow['count'] as num?)?.toInt() ?? 0,
      'expected_cash': expectedCash,
    };
  }


  Future<Map<String, dynamic>> getCashierSalesSummary({
    String? cashierName,
    DateTime? start,
    DateTime? end,
  }) async {
    final db = await database;

    final startTime = start ?? DateTime.now();
    final endTime = end ?? DateTime.now();

    final conditions = <String>[
      'datetime(s.created_at) >= datetime(?)',
      'datetime(s.created_at) <= datetime(?)',
    ];
    final args = <Object?>[
      startTime.toIso8601String(),
      endTime.toIso8601String(),
    ];

    final trimmedCashier = cashierName?.trim();
    if (trimmedCashier != null && trimmedCashier.isNotEmpty) {
      conditions.add('s.cashier_name = ?');
      args.add(trimmedCashier);
    }

    final whereBase = conditions.join(' AND ');

    final saleRow = (await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS sale_count,
        COALESCE(SUM(ABS(s.subtotal_amount)), 0) AS gross_sales,
        COALESCE(SUM(ABS(s.discount_amount)), 0) AS total_discounts,
        COALESCE(SUM(ABS(s.total_amount)), 0) AS net_sales,
        COALESCE(
          SUM(CASE WHEN s.payment_method = 'cash' THEN ABS(s.total_amount) ELSE 0 END),
          0
        ) AS cash_sales,
        COALESCE(
          SUM(CASE WHEN s.payment_method = 'card' THEN ABS(s.total_amount) ELSE 0 END),
          0
        ) AS card_sales
      FROM sales s
      WHERE s.transaction_type = 'sale'
        AND $whereBase
      ''',
      args,
    )).first;

    final refundRow = (await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS refund_count,
        COALESCE(SUM(ABS(s.total_amount)), 0) AS refund_total
      FROM sales s
      WHERE s.transaction_type = 'refund'
        AND $whereBase
      ''',
      args,
    )).first;

    final itemRow = (await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(si.quantity), 0) AS items_sold,
        COUNT(si.id) AS item_line_count
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE s.transaction_type = 'sale'
        AND $whereBase
      ''',
      args,
    )).first;

    final grossSales = ((saleRow['gross_sales'] as num?) ?? 0).toDouble();
    final totalDiscounts =
        ((saleRow['total_discounts'] as num?) ?? 0).toDouble();
    final netSales = ((saleRow['net_sales'] as num?) ?? 0).toDouble();
    final cashSales = ((saleRow['cash_sales'] as num?) ?? 0).toDouble();
    final cardSales = ((saleRow['card_sales'] as num?) ?? 0).toDouble();
    final refundTotal = ((refundRow['refund_total'] as num?) ?? 0).toDouble();
    final saleCount = (saleRow['sale_count'] as num?)?.toInt() ?? 0;
    final refundCount = (refundRow['refund_count'] as num?)?.toInt() ?? 0;
    final itemsSold = (itemRow['items_sold'] as num?)?.toInt() ?? 0;
    final itemLineCount = (itemRow['item_line_count'] as num?)?.toInt() ?? 0;

    return {
      'start': startTime.toIso8601String(),
      'end': endTime.toIso8601String(),
      'cashier_name': trimmedCashier,
      'sale_count': saleCount,
      'refund_count': refundCount,
      'transaction_count': saleCount + refundCount,
      'gross_sales': _roundMoney(grossSales),
      'total_discounts': _roundMoney(totalDiscounts),
      'net_sales': _roundMoney(netSales),
      'refund_total': _roundMoney(refundTotal),
      'net_after_refunds': _roundMoney(netSales - refundTotal),
      'cash_sales': _roundMoney(cashSales),
      'card_sales': _roundMoney(cardSales),
      'items_sold': itemsSold,
      'item_line_count': itemLineCount,
      'average_sale_value': saleCount <= 0
          ? 0.0
          : _roundMoney(netSales / saleCount),
    };
  }

  Future<List<Map<String, dynamic>>> getTopSellingItemsSummary({
    String? cashierName,
    DateTime? start,
    DateTime? end,
    int limit = 10,
  }) async {
    final db = await database;

    final startTime = start ?? DateTime.now();
    final endTime = end ?? DateTime.now();

    final conditions = <String>[
      "s.transaction_type = 'sale'",
      'datetime(s.created_at) >= datetime(?)',
      'datetime(s.created_at) <= datetime(?)',
    ];
    final args = <Object?>[
      startTime.toIso8601String(),
      endTime.toIso8601String(),
    ];

    final trimmedCashier = cashierName?.trim();
    if (trimmedCashier != null && trimmedCashier.isNotEmpty) {
      conditions.add('s.cashier_name = ?');
      args.add(trimmedCashier);
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        si.barcode,
        si.product_name,
        COALESCE(SUM(si.quantity), 0) AS quantity_sold,
        COALESCE(SUM(ABS(si.base_line_total)), 0) AS gross_sales_amount,
        COALESCE(SUM(ABS(si.item_discount_amount)), 0) AS discount_amount,
        COALESCE(SUM(ABS(si.line_total)), 0) AS net_sales_amount
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE ${conditions.join(' AND ')}
      GROUP BY si.barcode, si.product_name
      ORDER BY quantity_sold DESC, net_sales_amount DESC, si.product_name ASC
      LIMIT ?
      ''',
      [...args, limit],
    );

    return rows
        .map(
          (row) => {
            'barcode': row['barcode'],
            'product_name': row['product_name'],
            'quantity_sold': (row['quantity_sold'] as num?)?.toInt() ?? 0,
            'gross_sales_amount':
                ((row['gross_sales_amount'] as num?) ?? 0).toDouble(),
            'discount_amount':
                ((row['discount_amount'] as num?) ?? 0).toDouble(),
            'net_sales_amount':
                ((row['net_sales_amount'] as num?) ?? 0).toDouble(),
          },
        )
        .toList();
  }


  Future<List<Map<String, dynamic>>> getCashierBreakdownSummary({
    DateTime? start,
    DateTime? end,
    int limit = 20,
  }) async {
    final db = await database;

    final startTime = start ?? DateTime.now();
    final endTime = end ?? DateTime.now();

    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(NULLIF(TRIM(s.cashier_name), ''), 'Unknown') AS cashier_name,
        COALESCE(SUM(CASE WHEN s.transaction_type = 'sale' THEN 1 ELSE 0 END), 0) AS sale_count,
        COALESCE(SUM(CASE WHEN s.transaction_type = 'refund' THEN 1 ELSE 0 END), 0) AS refund_count,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'sale' THEN ABS(s.subtotal_amount) ELSE 0 END),
          0
        ) AS gross_sales,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'sale' THEN ABS(s.discount_amount) ELSE 0 END),
          0
        ) AS total_discounts,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'sale' THEN ABS(s.total_amount) ELSE 0 END),
          0
        ) AS net_sales,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'refund' THEN ABS(s.total_amount) ELSE 0 END),
          0
        ) AS refund_total,
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' AND s.payment_method = 'cash'
                THEN ABS(s.total_amount)
              ELSE 0
            END
          ),
          0
        ) AS cash_sales,
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' AND s.payment_method = 'card'
                THEN ABS(s.total_amount)
              ELSE 0
            END
          ),
          0
        ) AS card_sales
      FROM sales s
      WHERE datetime(s.created_at) >= datetime(?)
        AND datetime(s.created_at) <= datetime(?)
      GROUP BY COALESCE(NULLIF(TRIM(s.cashier_name), ''), 'Unknown')
      ORDER BY net_sales DESC, refund_total ASC, cashier_name ASC
      LIMIT ?
      ''',
      [startTime.toIso8601String(), endTime.toIso8601String(), limit],
    );

    return rows
        .map(
          (row) {
            final netSales = ((row['net_sales'] as num?) ?? 0).toDouble();
            final refundTotal = ((row['refund_total'] as num?) ?? 0).toDouble();

            return {
              'cashier_name': row['cashier_name'],
              'sale_count': (row['sale_count'] as num?)?.toInt() ?? 0,
              'refund_count': (row['refund_count'] as num?)?.toInt() ?? 0,
              'transaction_count':
                  ((row['sale_count'] as num?)?.toInt() ?? 0) +
                  ((row['refund_count'] as num?)?.toInt() ?? 0),
              'gross_sales': ((row['gross_sales'] as num?) ?? 0).toDouble(),
              'total_discounts':
                  ((row['total_discounts'] as num?) ?? 0).toDouble(),
              'net_sales': netSales,
              'refund_total': refundTotal,
              'net_after_refunds': _roundMoney(netSales - refundTotal),
              'cash_sales': ((row['cash_sales'] as num?) ?? 0).toDouble(),
              'card_sales': ((row['card_sales'] as num?) ?? 0).toDouble(),
            };
          },
        )
        .toList();
  }

  Future<int> saveHeldCart({
    required String cartName,
    required String cashierName,
    required bool isRefundMode,
    required String discountType,
    required double discountValue,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await database;

    if (items.isEmpty) {
      throw Exception('Cannot hold an empty cart.');
    }

    final safeName = cartName.trim().isEmpty ? 'Held Cart' : cartName.trim();
    final now = DateTime.now().toIso8601String();

    return db.insert('held_carts', {
      'cart_name': safeName,
      'cashier_name': cashierName,
      'is_refund_mode': isRefundMode ? 1 : 0,
      'discount_type': isRefundMode
          ? 'none'
          : _normalizeDiscountType(discountType),
      'discount_value': isRefundMode ? 0.0 : discountValue,
      'items_json': jsonEncode(items),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getHeldCartsForCashier(
    String cashierName,
  ) async {
    final db = await database;

    final rows = await db.query(
      'held_carts',
      where: 'cashier_name = ?',
      whereArgs: [cashierName],
      orderBy: 'datetime(updated_at) DESC, id DESC',
    );

    return rows.map((row) {
      final itemsJson = (row['items_json'] ?? '[]').toString();
      List<dynamic> decoded;

      try {
        decoded = jsonDecode(itemsJson) as List<dynamic>;
      } catch (_) {
        decoded = [];
      }

      int itemCount = 0;
      double subtotal = 0;

      for (final raw in decoded) {
        final item = Map<String, dynamic>.from(raw as Map);
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final lineTotal = ((item['line_total'] as num?) ?? 0).toDouble();

        itemCount += quantity;
        subtotal += lineTotal.abs();
      }

      final isRefundMode = ((row['is_refund_mode'] as num?) ?? 0).toInt() == 1;
      final discountType = (row['discount_type'] ?? 'none').toString();
      final discountValue = ((row['discount_value'] as num?) ?? 0).toDouble();

      final discountAmount = isRefundMode
          ? 0.0
          : _calculateDiscountAmount(
              subtotal: subtotal,
              discountType: discountType,
              discountValue: discountValue,
            );

      return {
        'id': row['id'],
        'cart_name': row['cart_name'],
        'cashier_name': row['cashier_name'],
        'is_refund_mode': isRefundMode,
        'discount_type': discountType,
        'discount_value': discountValue,
        'item_count': itemCount,
        'total_amount': _roundMoney(subtotal - discountAmount),
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> resumeHeldCart(
    int heldCartId, {
    required String cashierName,
  }) async {
    final db = await database;

    Map<String, dynamic>? result;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'held_carts',
        where: 'id = ? AND cashier_name = ?',
        whereArgs: [heldCartId, cashierName],
        limit: 1,
      );

      if (rows.isEmpty) {
        result = null;
        return;
      }

      final row = Map<String, dynamic>.from(rows.first);
      final itemsJson = (row['items_json'] ?? '[]').toString();

      List<Map<String, dynamic>> decodedItems = [];

      try {
        final decoded = jsonDecode(itemsJson) as List<dynamic>;
        decodedItems = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        decodedItems = [];
      }

      await txn.delete(
        'held_carts',
        where: 'id = ? AND cashier_name = ?',
        whereArgs: [heldCartId, cashierName],
      );

      result = {
        'id': row['id'],
        'cart_name': row['cart_name'],
        'cashier_name': row['cashier_name'],
        'is_refund_mode': ((row['is_refund_mode'] as num?) ?? 0).toInt() == 1,
        'discount_type': (row['discount_type'] ?? 'none').toString(),
        'discount_value': ((row['discount_value'] as num?) ?? 0).toDouble(),
        'items': decodedItems,
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      };
    });

    return result;
  }

  Future<void> deleteHeldCart(
    int heldCartId, {
    required String cashierName,
  }) async {
    final db = await database;

    await db.delete(
      'held_carts',
      where: 'id = ? AND cashier_name = ?',
      whereArgs: [heldCartId, cashierName],
    );
  }


  Future<void> replaceSuppliers(List<PosSupplier> suppliers) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      if (suppliers.isEmpty) {
        await txn.delete('suppliers');
        return;
      }

      final supplierIds = suppliers.map((supplier) => supplier.id).toList();
      final placeholders = List.filled(supplierIds.length, '?').join(',');

      await txn.delete(
        'suppliers',
        where: 'id NOT IN ($placeholders)',
        whereArgs: supplierIds,
      );

      final batch = txn.batch();
      for (final supplier in suppliers) {
        batch.insert(
          'suppliers',
          {
            'id': supplier.id,
            'name': supplier.name,
            'phone': supplier.phone,
            'updated_at': supplier.updatedAt.isEmpty ? now : supplier.updatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PosSupplier>> getSuppliers({String search = ''}) async {
    final db = await database;
    final trimmed = search.trim().toLowerCase();

    final rows = await db.query(
      'suppliers',
      where: trimmed.isEmpty
          ? null
          : '(LOWER(name) LIKE ? OR LOWER(phone) LIKE ? OR CAST(id AS TEXT) LIKE ?)',
      whereArgs: trimmed.isEmpty
          ? null
          : ['%$trimmed%', '%$trimmed%', '%$trimmed%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map((row) => PosSupplier.fromMap(row)).toList();
  }

  Future<int> insertStockReceipt({
    int? backendReceiptId,
    int? purchaseOrderId,
    String? purchaseOrderNumber,
    required String barcode,
    required String productName,
    required int quantity,
    required int supplierId,
    required String supplierName,
    required double cost,
    required String referenceNote,
    required String cashierName,
    String backendStatus = 'synced',
  }) async {
    final db = await database;

    return db.insert('stock_receipts', {
      'backend_receipt_id': backendReceiptId,
      'purchase_order_id': purchaseOrderId,
      'purchase_order_number': purchaseOrderNumber?.trim(),
      'barcode': barcode,
      'product_name': productName,
      'quantity': quantity,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'cost': _roundMoney(cost),
      'reference_note': referenceNote.trim(),
      'cashier_name': cashierName.trim(),
      'created_at': DateTime.now().toIso8601String(),
      'backend_status': backendStatus,
    });
  }

  Future<List<StockReceiptRecord>> getStockReceipts({
    int? supplierId,
    String search = '',
    int limit = 200,
  }) async {
    final db = await database;
    final trimmed = search.trim().toLowerCase();

    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (supplierId != null) {
      whereClauses.add('supplier_id = ?');
      whereArgs.add(supplierId);
    }

    if (trimmed.isNotEmpty) {
      whereClauses.add(
        '(LOWER(product_name) LIKE ? OR LOWER(barcode) LIKE ? OR LOWER(supplier_name) LIKE ?)',
      );
      whereArgs
        ..add('%$trimmed%')
        ..add('%$trimmed%')
        ..add('%$trimmed%');
    }

    final rows = await db.query(
      'stock_receipts',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereClauses.isEmpty ? null : whereArgs,
      orderBy: 'datetime(created_at) DESC, id DESC',
      limit: limit,
    );

    return rows.map((row) => StockReceiptRecord.fromMap(row)).toList();
  }

  Future<Map<String, dynamic>> getStockReceiptSummary({int? supplierId}) async {
    final db = await database;

    final whereClause = supplierId == null ? '' : 'WHERE supplier_id = ?';
    final args = supplierId == null ? <Object?>[] : <Object?>[supplierId];

    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS receipt_count,
        COALESCE(SUM(quantity), 0) AS total_units,
        COALESCE(SUM(cost), 0) AS total_cost
      FROM stock_receipts
      $whereClause
      ''',
      args,
    );

    final row = rows.first;
    return {
      'receipt_count': (row['receipt_count'] as num?)?.toInt() ?? 0,
      'total_units': (row['total_units'] as num?)?.toInt() ?? 0,
      'total_cost': ((row['total_cost'] as num?) ?? 0).toDouble(),
    };
  }



  Future<int> savePurchaseOrder({
    int? purchaseOrderId,
    required String orderNumber,
    required int supplierId,
    required String supplierName,
    required String status,
    required String referenceNote,
    required List<PurchaseOrderItem> items,
    required String createdBy,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final safeStatus = _normalizePurchaseOrderStatus(status);
    final totalLines = items.length;
    final totalUnits = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final totalCost = _roundMoney(
      items.fold<num>(0, (sum, item) => sum + item.lineTotal),
    );
    final receivedUnits = items.fold<int>(
      0,
      (sum, item) => sum + item.receivedQuantity,
    );

    late int resolvedId;

    await db.transaction((txn) async {
      if (purchaseOrderId == null) {
        resolvedId = await txn.insert('purchase_orders', {
          'order_number': orderNumber,
          'supplier_id': supplierId,
          'supplier_name': supplierName,
          'status': safeStatus,
          'reference_note': referenceNote.trim(),
          'total_lines': totalLines,
          'total_units': totalUnits,
          'received_units': receivedUnits,
          'total_cost': totalCost,
          'created_by': createdBy.trim(),
          'created_at': now,
          'updated_at': now,
        });
      } else {
        resolvedId = purchaseOrderId;
        await txn.update(
          'purchase_orders',
          {
            'order_number': orderNumber,
            'supplier_id': supplierId,
            'supplier_name': supplierName,
            'status': safeStatus,
            'reference_note': referenceNote.trim(),
            'total_lines': totalLines,
            'total_units': totalUnits,
            'received_units': receivedUnits,
            'total_cost': totalCost,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [purchaseOrderId],
        );

        await txn.delete(
          'purchase_order_items',
          where: 'purchase_order_id = ?',
          whereArgs: [purchaseOrderId],
        );
      }

      final batch = txn.batch();
      for (final item in items) {
        batch.insert('purchase_order_items', {
          'purchase_order_id': resolvedId,
          'barcode': item.barcode,
          'product_name': item.productName,
          'quantity': item.quantity,
          'received_quantity': item.receivedQuantity,
          'unit_cost': _roundMoney(item.unitCost),
          'created_at': item.createdAt.isEmpty ? now : item.createdAt,
        });
      }
      await batch.commit(noResult: true);
    });

    return resolvedId;
  }

  String _normalizePurchaseOrderStatus(String? value) {
    switch (value) {
      case 'draft':
      case 'ordered':
      case 'partially_received':
      case 'received':
      case 'cancelled':
        return value!;
      default:
        return 'draft';
    }
  }

  Future<List<PurchaseOrder>> getPurchaseOrders({
    int? supplierId,
    String status = 'all',
    String search = '',
    int limit = 200,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    final trimmedSearch = search.trim().toLowerCase();
    final safeStatus = _normalizePurchaseOrderStatus(status);

    if (supplierId != null) {
      whereClauses.add('supplier_id = ?');
      whereArgs.add(supplierId);
    }

    if (status != 'all') {
      whereClauses.add('status = ?');
      whereArgs.add(safeStatus);
    }

    if (trimmedSearch.isNotEmpty) {
      whereClauses.add(
        '(LOWER(order_number) LIKE ? OR LOWER(supplier_name) LIKE ? OR LOWER(reference_note) LIKE ?)',
      );
      whereArgs
        ..add('%$trimmedSearch%')
        ..add('%$trimmedSearch%')
        ..add('%$trimmedSearch%');
    }

    final rows = await db.query(
      'purchase_orders',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereClauses.isEmpty ? null : whereArgs,
      orderBy: 'datetime(updated_at) DESC, id DESC',
      limit: limit,
    );

    return rows.map((row) => PurchaseOrder.fromMap(row)).toList();
  }

  Future<PurchaseOrder?> getPurchaseOrderById(int purchaseOrderId) async {
    final db = await database;
    final rows = await db.query(
      'purchase_orders',
      where: 'id = ?',
      whereArgs: [purchaseOrderId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return PurchaseOrder.fromMap(rows.first);
  }

  Future<List<PurchaseOrderItem>> getPurchaseOrderItems(int purchaseOrderId) async {
    final db = await database;
    final rows = await db.query(
      'purchase_order_items',
      where: 'purchase_order_id = ?',
      whereArgs: [purchaseOrderId],
      orderBy: 'id ASC',
    );

    return rows.map((row) => PurchaseOrderItem.fromMap(row)).toList();
  }

  Future<void> updatePurchaseOrderStatus(int purchaseOrderId, String status) async {
    final db = await database;
    await db.update(
      'purchase_orders',
      {
        'status': _normalizePurchaseOrderStatus(status),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [purchaseOrderId],
    );
  }

  Future<void> deletePurchaseOrder(int purchaseOrderId) async {
    final db = await database;
    await db.delete(
      'purchase_orders',
      where: 'id = ?',
      whereArgs: [purchaseOrderId],
    );
  }

  Future<Map<String, dynamic>> getPurchaseOrderSummary({
    int? supplierId,
    String status = 'all',
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (supplierId != null) {
      whereClauses.add('supplier_id = ?');
      whereArgs.add(supplierId);
    }

    if (status != 'all') {
      whereClauses.add('status = ?');
      whereArgs.add(_normalizePurchaseOrderStatus(status));
    }

    final whereSql = whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS order_count,
        COALESCE(SUM(total_units), 0) AS total_units,
        COALESCE(SUM(received_units), 0) AS received_units,
        COALESCE(SUM(total_cost), 0) AS total_cost
      FROM purchase_orders
      $whereSql
      ''',
      whereArgs,
    );

    final row = rows.first;
    return {
      'order_count': (row['order_count'] as num?)?.toInt() ?? 0,
      'total_units': (row['total_units'] as num?)?.toInt() ?? 0,
      'received_units': (row['received_units'] as num?)?.toInt() ?? 0,
      'total_cost': ((row['total_cost'] as num?) ?? 0).toDouble(),
    };
  }



  Future<void> applyPurchaseOrderReceipt({
    required int purchaseOrderId,
    required String orderNumber,
    required int supplierId,
    required String supplierName,
    required String cashierName,
    required String referenceNote,
    required List<Map<String, dynamic>> receivedLines,
  }) async {
    if (receivedLines.isEmpty) return;

    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final line in receivedLines) {
        final itemId = (line['purchase_order_item_id'] as num?)?.toInt();
        final quantity = (line['quantity'] as num?)?.toInt() ?? 0;
        final cost = ((line['cost'] as num?) ?? 0).toDouble();
        final barcode = (line['barcode'] ?? '').toString();
        final productName = (line['product_name'] ?? '').toString();
        final backendReceiptId = (line['backend_receipt_id'] as num?)?.toInt();

        if (itemId == null || quantity <= 0) continue;

        await txn.insert('stock_receipts', {
          'backend_receipt_id': backendReceiptId,
          'purchase_order_id': purchaseOrderId,
          'purchase_order_number': orderNumber,
          'barcode': barcode,
          'product_name': productName,
          'quantity': quantity,
          'supplier_id': supplierId,
          'supplier_name': supplierName,
          'cost': _roundMoney(cost),
          'reference_note': referenceNote.trim(),
          'cashier_name': cashierName.trim(),
          'created_at': now,
          'backend_status': 'synced',
        });

        await txn.rawUpdate(
          '''
          UPDATE purchase_order_items
          SET received_quantity = received_quantity + ?
          WHERE id = ?
          ''',
          [quantity, itemId],
        );
      }

      final totals = await txn.rawQuery(
        '''
        SELECT
          COALESCE(SUM(quantity), 0) AS total_units,
          COALESCE(SUM(received_quantity), 0) AS received_units
        FROM purchase_order_items
        WHERE purchase_order_id = ?
        ''',
        [purchaseOrderId],
      );

      final row = totals.first;
      final totalUnits = (row['total_units'] as num?)?.toInt() ?? 0;
      final receivedUnits = (row['received_units'] as num?)?.toInt() ?? 0;

      String nextStatus = 'draft';
      if (receivedUnits <= 0) {
        nextStatus = 'ordered';
      } else if (receivedUnits >= totalUnits && totalUnits > 0) {
        nextStatus = 'received';
      } else {
        nextStatus = 'partially_received';
      }

      await txn.update(
        'purchase_orders',
        {
          'received_units': receivedUnits,
          'status': nextStatus,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getOutstandingPurchaseOrderLines(
    int purchaseOrderId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        id,
        purchase_order_id,
        barcode,
        product_name,
        quantity,
        received_quantity,
        unit_cost,
        created_at,
        (quantity - received_quantity) AS outstanding_quantity
      FROM purchase_order_items
      WHERE purchase_order_id = ?
      ORDER BY id ASC
      ''',
      [purchaseOrderId],
    );

    return rows;
  }


}