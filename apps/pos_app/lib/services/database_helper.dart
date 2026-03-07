import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:shared/models/product.dart';

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
    // Initialize FFI for macOS/Windows desktop
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    
    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, filePath);

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createDB,
      ),
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Products Table
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

    // 2. Sales Table
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 3. Sync Queue Table (The Offline Buffer)
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        data TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 4. Users Table (Employees)
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin TEXT UNIQUE NOT NULL
      )
    ''');
  }

  Future<void> insertMockDataIfEmpty() async {
    final db = await database;
    final List<Map<String, dynamic>> existing = await db.rawQuery('SELECT COUNT(*) as count FROM products');
    final count = existing.first['count'] as int;
    
    if (count == 0) {
      final mockProducts = [
        {'barcode': '4791044000123', 'name': 'Munchee Super Cream Cracker 500g', 'price': 450.0, 'stock': 100, 'updated_at': DateTime.now().toIso8601String()},
        {'barcode': '4792011001234', 'name': 'Anchor Milk Powder 400g', 'price': 1100.0, 'stock': 50, 'updated_at': DateTime.now().toIso8601String()},
        {'barcode': '4792022005678', 'name': 'Saman Halmassa 425g', 'price': 650.0, 'stock': 30, 'updated_at': DateTime.now().toIso8601String()},
        {'barcode': '4793033009999', 'name': 'Kist Strawberry Jam 500g', 'price': 580.0, 'stock': 40, 'updated_at': DateTime.now().toIso8601String()},
      ];
      for (var p in mockProducts) {
        await db.insert('products', p);
      }
    }

    // Insert Mock Users if none exist
    final List<Map<String, dynamic>> existingUsers = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    final userCount = existingUsers.first['count'] as int;

    if (userCount == 0) {
      final mockUsers = [
        {'name': 'Pathum (Manager)', 'role': 'manager', 'pin': '1234'},
        {'name': 'Amal (Cashier)', 'role': 'cashier', 'pin': '5555'},
      ];
      for (var u in mockUsers) {
        await db.insert('users', u);
      }
    }
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('products');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<bool> processSale(double totalAmount, List<Map<String, dynamic>> cartItems) async {
    final db = await database;
    
    try {
      // Run everything inside a transaction
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        // 1. Record the sale locally
        final saleId = await txn.insert('sales', {
          'total_amount': totalAmount,
          'created_at': now,
        });

        // 2. Deduct local stock so the cashier sees accurate numbers
        for (var item in cartItems) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE barcode = ?',
            [item['quantity'], item['product']['barcode']]
          );
        }

        // 3. Package the payload for the Cloud Sync Worker
        // Adding Alfasoft and Hikkaduwa tags for branch tracking when this scales
        final syncData = jsonEncode({
          'local_sale_id': saleId,
          'total_amount': totalAmount,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
          'items': cartItems,
        });

        // 4. Drop it into the offline buffer
        await txn.insert('sync_queue', {
          'type': 'SALE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });
      return true; // Checkout successful!
    } catch (e) {
      debugPrint("Checkout Database Error: $e");
      return false; // Checkout failed
    }
  }

  Future<bool> updateProductPriceLocal(String barcode, double newPrice) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        // 1. Update the price in the local database
        await txn.update(
          'products',
          {'price': newPrice, 'updated_at': now},
          where: 'barcode = ?',
          whereArgs: [barcode],
        );

        // 2. Queue the update for the cloud (Spaceship API will read this later)
        final syncData = jsonEncode({
          'barcode': barcode,
          'new_price': newPrice,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft'
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
      debugPrint("Error updating price: $e");
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
    return null; // Wrong PIN
  }
}
