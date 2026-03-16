import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        version: 6,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      ),
    );
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

    final existingProducts =
        await db.rawQuery('SELECT COUNT(*) as count FROM products');
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

    final existingUsers =
        await db.rawQuery('SELECT COUNT(*) as count FROM users');
    final userCount = existingUsers.first['count'] as int;

    if (userCount == 0) {
      final mockUsers = [
        {
          'name': 'Pathum (Manager)',
          'role': 'manager',
          'pin': '1234',
        },
        {
          'name': 'Amal (Cashier)',
          'role': 'cashier',
          'pin': '5555',
        },
      ];

      for (final user in mockUsers) {
        await db.insert('users', user);
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
        batch.insert(
          'products',
          {
            'barcode': product.barcode,
            'name': product.name,
            'price': product.price,
            'stock': product.stock,
            'updated_at': product.updatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
          final transactionType =
              (data['transaction_type'] ?? 'sale').toString().toLowerCase();
          final items = (data['items'] as List?) ?? [];

          for (final rawItem in items) {
            final item = Map<String, dynamic>.from(rawItem as Map);
            final productMap = Map<String, dynamic>.from(item['product'] as Map);

            final barcode = productMap['barcode']?.toString() ?? '';
            final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

            if (barcode.isEmpty || quantity <= 0) continue;

            final stockDelta =
                transactionType == 'refund' ? quantity : -quantity;

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
            {
              'price': newPrice,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        }
      }
    });
  }

  Future<int> processTransaction({
    required double totalAmount,
    required List<Map<String, dynamic>> cartItems,
    required String cashierName,
    required bool isRefund,
    String? paymentMethod,
    double? amountTendered,
    double? changeAmount,
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
        final signedTotal = isRefund ? -totalAmount.abs() : totalAmount.abs();

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
                resolvedAmountTendered < totalAmount) {
              throw Exception('Cash amount is not enough.');
            }
            resolvedChangeAmount = resolvedAmountTendered - totalAmount;
          } else {
            resolvedAmountTendered = totalAmount;
            resolvedChangeAmount = 0.0;
          }

          for (final item in cartItems) {
            final productMap =
                Map<String, dynamic>.from(item['product'] as Map);
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

        for (final item in cartItems) {
          final productMap = Map<String, dynamic>.from(item['product'] as Map);
          final barcode = productMap['barcode']?.toString() ?? '';
          final productName =
              productMap['name']?.toString() ?? 'Unknown product';
          final unitPrice = (productMap['price'] as num).toDouble();
          final quantity = (item['quantity'] as num).toInt();

          if (quantity <= 0) {
            throw Exception('Invalid quantity for $productName.');
          }

          final stockDelta = isRefund ? quantity : -quantity;
          final signedLineTotal = unitPrice * quantity * (isRefund ? -1 : 1);

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
            'line_total': signedLineTotal,
            'created_at': now,
          });
        }

        final syncData = jsonEncode({
          'local_sale_id': saleId,
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
        final originalType =
            (originalSale['transaction_type'] ?? 'sale')
                .toString()
                .toLowerCase();

        if (originalType != 'sale') {
          throw Exception('Only sale transactions can be refunded.');
        }

        final refundableItems =
            await _getRefundableItemsForSaleExecutor(txn, originalSaleId);

        final refundableMap = <String, Map<String, dynamic>>{
          for (final item in refundableItems)
            (item['barcode'] ?? '').toString(): item,
        };

        double refundTotal = 0;
        final now = DateTime.now().toIso8601String();

        refundSaleId = await txn.insert('sales', {
          'total_amount': 0,
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
          final unitPrice =
              ((refundableData['unit_price'] as num?) ?? 0).toDouble();

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

          final lineTotal = -(unitPrice * quantity);
          refundTotal += unitPrice * quantity;

          await txn.insert('sale_items', {
            'sale_id': refundSaleId,
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'quantity': quantity,
            'line_total': lineTotal,
            'created_at': now,
          });

          syncItems.add({
            'product': {
              'barcode': barcode,
              'name': productName,
              'price': unitPrice,
            },
            'quantity': quantity,
            'line_total': lineTotal,
          });
        }

        await txn.update(
          'sales',
          {'total_amount': -refundTotal},
          where: 'id = ?',
          whereArgs: [refundSaleId],
        );

        final syncData = jsonEncode({
          'local_sale_id': refundSaleId,
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
          {
            'price': newPrice,
            'updated_at': now,
          },
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

    final saleType =
        (saleRows.first['transaction_type'] ?? 'sale')
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
        SUM(quantity) AS original_quantity
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
        COALESCE(SUM(si.quantity), 0) AS refunded_quantity
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE s.transaction_type = 'refund'
        AND s.original_sale_id = ?
      GROUP BY si.barcode
      ''',
      [saleId],
    );

    final refundedMap = <String, int>{
      for (final row in refundedItems)
        (row['barcode'] ?? '').toString():
            (row['refunded_quantity'] as num?)?.toInt() ?? 0,
    };

    return originalItems.map((row) {
      final barcode = (row['barcode'] ?? '').toString();
      final originalQty = (row['original_quantity'] as num?)?.toInt() ?? 0;
      final refundedQty = refundedMap[barcode] ?? 0;
      final refundableQty = originalQty - refundedQty;

      return {
        'barcode': barcode,
        'product_name': row['product_name'],
        'unit_price': row['unit_price'],
        'original_quantity': originalQty,
        'refunded_quantity': refundedQty,
        'refundable_quantity': refundableQty < 0 ? 0 : refundableQty,
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

    return {
      ...shift,
      ...stats,
    };
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

        final expectedCash =
            ((stats['expected_cash'] as num?) ?? 0).toDouble();
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
    ))
        .first;

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
    ))
        .first;

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
    ))
        .first;

    final transactionCountRow = (await executor.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM sales
      WHERE cashier_name = ?
        AND datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
      ''',
      [cashierName, openedAt, endTime],
    ))
        .first;

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
    ))
        .first;

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
      'transaction_count':
          (transactionCountRow['count'] as num?)?.toInt() ?? 0,
      'expected_cash': expectedCash,
    };
  }

  Future<int> saveHeldCart({
    required String cartName,
    required String cashierName,
    required bool isRefundMode,
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
      double totalAmount = 0;

      for (final raw in decoded) {
        final item = Map<String, dynamic>.from(raw as Map);
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final lineTotal = ((item['line_total'] as num?) ?? 0).toDouble();

        itemCount += quantity;
        totalAmount += lineTotal.abs();
      }

      return {
        'id': row['id'],
        'cart_name': row['cart_name'],
        'cashier_name': row['cashier_name'],
        'is_refund_mode': ((row['is_refund_mode'] as num?) ?? 0).toInt() == 1,
        'item_count': itemCount,
        'total_amount': totalAmount,
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
}