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
        version: 2,
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

      // Re-apply local pending changes so local POS state stays correct
      // even if there are unsynced offline actions.
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
            final productMap = Map<String, dynamic>.from(
              item['product'] as Map,
            );

            final barcode = productMap['barcode']?.toString() ?? '';
            final quantity = (item['quantity'] as num?)?.toInt() ?? 0;

            if (barcode.isEmpty || quantity <= 0) continue;

            final stockDelta = transactionType == 'refund' ? quantity : -quantity;

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

  Future<void> processTransaction({
    required double totalAmount,
    required List<Map<String, dynamic>> cartItems,
    required String cashierName,
    required bool isRefund,
  }) async {
    final db = await database;

    if (cartItems.isEmpty) {
      throw Exception('Cart is empty.');
    }

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final transactionType = isRefund ? 'refund' : 'sale';
        final signedTotal = isRefund ? -totalAmount.abs() : totalAmount.abs();

        if (!isRefund) {
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
              throw Exception('$productName was not found in local POS database.');
            }

            final availableStock = (rows.first['stock'] as num).toInt();

            if (availableStock < quantity) {
              throw Exception(
                'Insufficient stock for $productName. Available: $availableStock, requested: $quantity.',
              );
            }
          }
        }

        final saleId = await txn.insert('sales', {
          'total_amount': signedTotal,
          'cashier_name': cashierName,
          'transaction_type': transactionType,
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
          final signedLineTotal =
              unitPrice * quantity * (isRefund ? -1 : 1);

          final updatedCount = await txn.rawUpdate(
            '''
            UPDATE products
            SET stock = stock + ?, updated_at = ?
            WHERE barcode = ?
            ''',
            [stockDelta, now, barcode],
          );

          if (updatedCount == 0) {
            throw Exception('$productName was not found in local POS database.');
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
          'items': cartItems,
        });

        await txn.insert('sync_queue', {
          'type': 'SALE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });
    } catch (e) {
      debugPrint('Checkout Database Error: $e');
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
}