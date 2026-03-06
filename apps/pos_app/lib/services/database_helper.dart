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
  }

  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('products');
    return maps.map((map) => Product.fromMap(map)).toList();
  }
}
