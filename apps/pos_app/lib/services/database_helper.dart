import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/pos_supplier.dart';
import '../models/expiry_batch.dart';
import '../models/supplier_product_mapping.dart';
import '../models/stock_receipt_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static const double _quantityEpsilon = 0.000001;
  static const int _maxActiveLabelPricesPerProduct = 2;
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

    final legacyPath = await _resolveLegacyDbPath(databaseFactory, filePath);
    final stablePath = await _resolveStableDbPath(filePath);
    await _migrateLegacyDbIfNeeded(
      legacyPath: legacyPath,
      stablePath: stablePath,
    );

    debugPrint('POS local DB legacy path: $legacyPath');
    debugPrint('POS local DB stable path: $stablePath');

    return databaseFactory.openDatabase(
      stablePath,
      options: OpenDatabaseOptions(
        version: 25,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      ),
    );
  }

  Future<String> _resolveLegacyDbPath(
    DatabaseFactory databaseFactory,
    String filePath,
  ) async {
    final dbPath = await databaseFactory.getDatabasesPath();
    return join(dbPath, filePath);
  }

  Future<String> _resolveStableDbPath(String filePath) async {
    final env = Platform.environment;
    final localAppData = (env['LOCALAPPDATA'] ?? env['APPDATA'] ?? '').trim();

    final baseDir = localAppData.isNotEmpty
        ? join(localAppData, 'Food City POS', 'data')
        : join(Directory.current.path, 'food_city_pos_data');

    await Directory(baseDir).create(recursive: true);
    return join(baseDir, filePath);
  }

  Future<void> _migrateLegacyDbIfNeeded({
    required String legacyPath,
    required String stablePath,
  }) async {
    if (legacyPath == stablePath) return;

    final stableFile = File(stablePath);
    if (await stableFile.exists()) {
      return;
    }

    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      return;
    }

    await stableFile.parent.create(recursive: true);
    await legacyFile.copy(stablePath);
    await _copySidecarDbFileIfExists('$legacyPath-wal', '$stablePath-wal');
    await _copySidecarDbFileIfExists('$legacyPath-shm', '$stablePath-shm');

    debugPrint('Migrated POS DB from legacy path to stable path.');
  }

  Future<void> _copySidecarDbFileIfExists(
    String sourcePath,
    String targetPath,
  ) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    await sourceFile.copy(targetPath);
  }

  double _roundMoney(num value) {
    return double.parse(value.toStringAsFixed(2));
  }

  double _roundQuantity(num value) {
    return double.parse(value.toStringAsFixed(3));
  }

  double _parseQuantity(dynamic value, {double fallback = 0.0}) {
    return _roundQuantity(_parseDouble(value, fallback: fallback));
  }

  bool _isPositiveQuantity(num value) {
    return value.toDouble() > _quantityEpsilon;
  }

  bool _quantityExceeds(num requested, num available) {
    return requested.toDouble() - available.toDouble() > _quantityEpsilon;
  }

  String _formatQuantityValue(num value) {
    final safeValue = value.toDouble().abs() < _quantityEpsilon
        ? 0.0
        : value.toDouble();
    return safeValue.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatDateOnly(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.toIso8601String().split('T').first;
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

  Future<void> _createProductPriceHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        price_type TEXT NOT NULL DEFAULT 'selling',
        label_price REAL NOT NULL,
        old_price REAL NOT NULL DEFAULT 0,
        new_price REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_by TEXT,
        reason TEXT,
        effective_from TEXT NOT NULL,
        effective_to TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_price_history_barcode ON product_price_history(barcode, price_type, is_active)',
    );
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
      CREATE TABLE IF NOT EXISTS supplier_product_mappings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier_name TEXT NOT NULL,
        is_preferred INTEGER NOT NULL DEFAULT 1,
        default_unit_cost REAL NOT NULL DEFAULT 0,
        minimum_order_quantity INTEGER NOT NULL DEFAULT 1,
        pack_size INTEGER NOT NULL DEFAULT 1,
        lead_time_days INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        updated_at TEXT NOT NULL,
        UNIQUE(barcode, supplier_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        backend_receipt_id INTEGER,
        purchase_order_id INTEGER,
        purchase_order_number TEXT,
        purchase_order_receipt_id INTEGER,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier_name TEXT NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        reference_note TEXT,
        invoice_number TEXT,
        delivery_note_number TEXT,
        grn_reference TEXT,
        expiry_batch_id INTEGER,
        batch_number TEXT NOT NULL DEFAULT '',
        expiry_date TEXT,
        cashier_name TEXT,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        reversed_at TEXT NOT NULL DEFAULT '',
        reversal_reason TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        backend_status TEXT NOT NULL DEFAULT 'synced'
      )
    ''');
  }

  Future<void> _createExpiryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expiry_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        batch_number TEXT NOT NULL DEFAULT '',
        supplier_id INTEGER,
        supplier_name TEXT NOT NULL DEFAULT '',
        received_quantity REAL NOT NULL,
        remaining_quantity REAL NOT NULL,
        expiry_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        last_checked_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS expiry_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        action_type TEXT NOT NULL,
        quantity REAL,
        note TEXT NOT NULL DEFAULT '',
        performed_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (batch_id) REFERENCES expiry_batches(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expiry_batches_barcode ON expiry_batches(barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expiry_batches_expiry_date ON expiry_batches(expiry_date)',
    );
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_order_id INTEGER NOT NULL,
        purchase_order_number TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier_name TEXT NOT NULL,
        cashier_name TEXT,
        reference_note TEXT,
        invoice_number TEXT,
        delivery_note_number TEXT,
        grn_reference TEXT,
        total_lines INTEGER NOT NULL DEFAULT 0,
        total_units INTEGER NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        reversed_at TEXT NOT NULL DEFAULT '',
        reversed_by TEXT NOT NULL DEFAULT '',
        reversal_reason TEXT NOT NULL DEFAULT '',
        manager_approved_by TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_receipt_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_order_receipt_id INTEGER NOT NULL,
        purchase_order_id INTEGER NOT NULL,
        purchase_order_item_id INTEGER,
        backend_receipt_id INTEGER,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL DEFAULT 0,
        line_cost REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (purchase_order_receipt_id) REFERENCES purchase_order_receipts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_receipt_reversal_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        purchase_order_id INTEGER NOT NULL,
        po_number TEXT NOT NULL,
        reason TEXT NOT NULL,
        manager_name TEXT NOT NULL,
        reversed_by TEXT NOT NULL,
        reversed_at TEXT NOT NULL,
        total_units INTEGER NOT NULL DEFAULT 0,
        total_cost REAL NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'General',
        quantity_type TEXT NOT NULL DEFAULT 'unit',
        unit_label TEXT NOT NULL DEFAULT 'pcs',
        price REAL NOT NULL,
        cost_price REAL NOT NULL DEFAULT 0,
        selling_price REAL NOT NULL DEFAULT 0,
        wholesale_price REAL NOT NULL DEFAULT 0,
        sale_price REAL,
        sale_enabled INTEGER NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL,
        min_stock_level INTEGER NOT NULL DEFAULT 0,
        track_expiry INTEGER NOT NULL DEFAULT 0,
        expiry_alert_days INTEGER NOT NULL DEFAULT 30,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        last_price_updated_at TEXT
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
        marked_price REAL NOT NULL DEFAULT 0,
        price_category_used TEXT NOT NULL DEFAULT 'selling',
        system_unit_price REAL NOT NULL DEFAULT 0,
        price_override_type TEXT NOT NULL DEFAULT 'none',
        price_override_reason TEXT NOT NULL DEFAULT '',
        price_override_original_price REAL NOT NULL DEFAULT 0,
        price_override_difference REAL NOT NULL DEFAULT 0,
        price_history_id INTEGER,
        price_override_approved_by TEXT,
        customer_pricing_applied INTEGER NOT NULL DEFAULT 0,
        customer_pricing_type TEXT NOT NULL DEFAULT 'none',
        customer_pricing_rule_id INTEGER,
        customer_pricing_original_price REAL NOT NULL DEFAULT 0,
        customer_pricing_final_price REAL NOT NULL DEFAULT 0,
        customer_pricing_discount_amount REAL NOT NULL DEFAULT 0,
        customer_pricing_note TEXT,
        cost_price_snapshot REAL NOT NULL DEFAULT 0,
        quantity INTEGER NOT NULL,
        base_line_total REAL NOT NULL DEFAULT 0,
        item_discount_type TEXT NOT NULL DEFAULT 'none',
        item_discount_value REAL NOT NULL DEFAULT 0,
        explicit_item_discount_amount REAL NOT NULL DEFAULT 0,
        cart_discount_amount REAL NOT NULL DEFAULT 0,
        item_discount_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');

    await _createProductPriceHistoryTable(db);

    await db.execute('''
      CREATE TABLE inventory_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        action_type TEXT NOT NULL,
        quantity_change INTEGER,
        stock_before INTEGER,
        stock_after INTEGER,
        old_price REAL,
        new_price REAL,
        price_type TEXT,
        reason TEXT,
        reference_id INTEGER,
        reference_type TEXT,
        performed_by TEXT,
        supplier_id INTEGER,
        supplier_name TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_take_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        total_products INTEGER NOT NULL DEFAULT 0,
        counted_items INTEGER NOT NULL DEFAULT 0,
        discrepancy_items INTEGER NOT NULL DEFAULT 0,
        applied_items INTEGER NOT NULL DEFAULT 0,
        started_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_take_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        system_stock INTEGER NOT NULL,
        counted_stock INTEGER NOT NULL,
        difference_qty INTEGER NOT NULL,
        applied INTEGER NOT NULL DEFAULT 0,
        applied_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(session_id, barcode),
        FOREIGN KEY (session_id) REFERENCES stock_take_sessions(id) ON DELETE CASCADE
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
        selected_price_type TEXT NOT NULL DEFAULT 'selling',
        discount_type TEXT NOT NULL DEFAULT 'none',
        discount_value REAL NOT NULL DEFAULT 0,
        customer_id INTEGER,
        customer_name_snapshot TEXT,
        customer_phone_snapshot TEXT,
        customer_code_snapshot TEXT,
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

    await _createCustomersTable(db);
    await _ensureCustomerPricingSchema(db);

    await _createUserTables(db);

    await _createSupplierTables(db);
    await _createPurchaseOrderTables(db);
    await _createExpiryTables(db);
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
          price_category_used TEXT NOT NULL DEFAULT 'selling',
          cost_price_snapshot REAL NOT NULL DEFAULT 0,
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
          selected_price_type TEXT NOT NULL DEFAULT 'selling',
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

    if (oldVersion < 22) {
      await _addColumnIfMissing(
        db,
        'sale_items',
        'marked_price',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'item_discount_type',
        "TEXT NOT NULL DEFAULT 'none'",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'item_discount_value',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'explicit_item_discount_amount',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'cart_discount_amount',
        "REAL NOT NULL DEFAULT 0",
      );
    }

    if (oldVersion < 9) {
      await _createPurchaseOrderTables(db);
    }

    if (oldVersion < 10) {
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'purchase_order_id',
        'INTEGER',
      );
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
          {'received_units': receivedUnits},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
    }

    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_order_receipts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_order_id INTEGER NOT NULL,
          purchase_order_number TEXT NOT NULL,
          supplier_id INTEGER NOT NULL,
          supplier_name TEXT NOT NULL,
          cashier_name TEXT,
          reference_note TEXT,
          total_lines INTEGER NOT NULL DEFAULT 0,
          total_units INTEGER NOT NULL DEFAULT 0,
          total_cost REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_order_receipt_lines (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_order_receipt_id INTEGER NOT NULL,
          purchase_order_id INTEGER NOT NULL,
          purchase_order_item_id INTEGER,
          backend_receipt_id INTEGER,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_cost REAL NOT NULL DEFAULT 0,
          line_cost REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY (purchase_order_receipt_id) REFERENCES purchase_order_receipts(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 12) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS supplier_product_mappings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          supplier_id INTEGER NOT NULL,
          supplier_name TEXT NOT NULL,
          is_preferred INTEGER NOT NULL DEFAULT 1,
          default_unit_cost REAL NOT NULL DEFAULT 0,
          minimum_order_quantity INTEGER NOT NULL DEFAULT 1,
          pack_size INTEGER NOT NULL DEFAULT 1,
          lead_time_days INTEGER NOT NULL DEFAULT 0,
          note TEXT,
          updated_at TEXT NOT NULL,
          UNIQUE(barcode, supplier_id)
        )
      ''');

      await _addColumnIfMissing(db, 'stock_receipts', 'invoice_number', 'TEXT');
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'delivery_note_number',
        'TEXT',
      );
      await _addColumnIfMissing(db, 'stock_receipts', 'grn_reference', 'TEXT');
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'invoice_number',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'delivery_note_number',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'grn_reference',
        'TEXT',
      );
    }

    if (oldVersion < 13) {
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'is_reversed',
        "INTEGER NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'reversed_at',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'reversed_by',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'reversal_reason',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        'purchase_order_receipts',
        'manager_approved_by',
        "TEXT NOT NULL DEFAULT ''",
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_order_receipt_reversal_audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          receipt_id INTEGER NOT NULL,
          purchase_order_id INTEGER NOT NULL,
          po_number TEXT NOT NULL,
          reason TEXT NOT NULL,
          manager_name TEXT NOT NULL,
          reversed_by TEXT NOT NULL,
          reversed_at TEXT NOT NULL,
          total_units INTEGER NOT NULL DEFAULT 0,
          total_cost REAL NOT NULL DEFAULT 0
        )
      ''');
    }

    if (oldVersion < 14) {
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'purchase_order_receipt_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'is_reversed',
        "INTEGER NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'reversed_at',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'reversal_reason',
        "TEXT NOT NULL DEFAULT ''",
      );
    }

    if (oldVersion < 15) {
      await _addColumnIfMissing(
        db,
        'products',
        'category',
        "TEXT NOT NULL DEFAULT 'General'",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'quantity_type',
        "TEXT NOT NULL DEFAULT 'unit'",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'unit_label',
        "TEXT NOT NULL DEFAULT 'pcs'",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'cost_price',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'selling_price',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'wholesale_price',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(db, 'products', 'sale_price', 'REAL');
      await _addColumnIfMissing(
        db,
        'products',
        'sale_enabled',
        "INTEGER NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'min_stock_level',
        "INTEGER NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'is_active',
        "INTEGER NOT NULL DEFAULT 1",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'last_price_updated_at',
        'TEXT',
      );

      await db.execute('''
        UPDATE products
        SET
          quantity_type = CASE
            WHEN LOWER(COALESCE(quantity_type, '')) = 'weight' THEN 'weight'
            ELSE 'unit'
          END,
          unit_label = CASE
            WHEN TRIM(COALESCE(unit_label, '')) != '' THEN TRIM(unit_label)
            WHEN LOWER(COALESCE(quantity_type, 'unit')) = 'weight' THEN 'kg'
            ELSE 'pcs'
          END,
          selling_price = CASE
            WHEN COALESCE(selling_price, 0) <= 0 THEN COALESCE(price, 0)
            ELSE selling_price
          END,
          wholesale_price = CASE
            WHEN COALESCE(wholesale_price, 0) <= 0 THEN COALESCE(price, 0)
            ELSE wholesale_price
          END,
          price = CASE
            WHEN COALESCE(price, 0) <= 0 THEN COALESCE(selling_price, 0)
            ELSE price
          END
      ''');

      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_category_used',
        "TEXT NOT NULL DEFAULT 'selling'",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'cost_price_snapshot',
        "REAL NOT NULL DEFAULT 0",
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          action_type TEXT NOT NULL,
          quantity_change INTEGER,
          stock_before INTEGER,
          stock_after INTEGER,
          old_price REAL,
          new_price REAL,
          price_type TEXT,
          reason TEXT,
          reference_id INTEGER,
          reference_type TEXT,
          performed_by TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      await _addColumnIfMissing(
        db,
        'held_carts',
        'selected_price_type',
        "TEXT NOT NULL DEFAULT 'selling'",
      );
    }

    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_take_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_name TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'open',
          total_products INTEGER NOT NULL DEFAULT 0,
          counted_items INTEGER NOT NULL DEFAULT 0,
          discrepancy_items INTEGER NOT NULL DEFAULT 0,
          applied_items INTEGER NOT NULL DEFAULT 0,
          started_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          completed_at TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_take_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          barcode TEXT NOT NULL,
          product_name TEXT NOT NULL,
          system_stock INTEGER NOT NULL,
          counted_stock INTEGER NOT NULL,
          difference_qty INTEGER NOT NULL,
          applied INTEGER NOT NULL DEFAULT 0,
          applied_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          UNIQUE(session_id, barcode),
          FOREIGN KEY (session_id) REFERENCES stock_take_sessions(id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 19) {
      await _addColumnIfMissing(
        db,
        'sync_queue',
        'status',
        "TEXT NOT NULL DEFAULT 'pending'",
      );
    }

    if (oldVersion < 20) {
      await _addColumnIfMissing(
        db,
        'inventory_movements',
        'supplier_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        'inventory_movements',
        'supplier_name',
        'TEXT',
      );
    }

    if (oldVersion < 21) {
      await _addColumnIfMissing(
        db,
        'products',
        'quantity_type',
        "TEXT NOT NULL DEFAULT 'unit'",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'unit_label',
        "TEXT NOT NULL DEFAULT 'pcs'",
      );

      await db.execute('''
        UPDATE products
        SET
          quantity_type = CASE
            WHEN LOWER(COALESCE(quantity_type, '')) = 'weight' THEN 'weight'
            ELSE 'unit'
          END,
          unit_label = CASE
            WHEN TRIM(COALESCE(unit_label, '')) != '' THEN TRIM(unit_label)
            WHEN LOWER(COALESCE(quantity_type, 'unit')) = 'weight' THEN 'kg'
            ELSE 'pcs'
          END
      ''');
    }

    if (oldVersion < 17) {
      await _createUserTables(db);

      await _addColumnIfMissing(
        db,
        'users',
        'is_active',
        "INTEGER NOT NULL DEFAULT 1",
      );
      await _addColumnIfMissing(db, 'users', 'created_at', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'updated_at', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'last_login_at', 'TEXT');
      await _addColumnIfMissing(db, 'users', 'created_by', 'INTEGER');
      await _addColumnIfMissing(db, 'users', 'updated_by', 'INTEGER');

      final now = DateTime.now().toIso8601String();
      await db.execute(
        '''
        UPDATE users
        SET
          is_active = COALESCE(is_active, 1),
          created_at = COALESCE(NULLIF(created_at, ''), ?),
          updated_at = COALESCE(NULLIF(updated_at, ''), ?)
        ''',
        [now, now],
      );
    }

    if (oldVersion < 18) {
      await _addColumnIfMissing(
        db,
        'users',
        'has_full_access',
        "INTEGER NOT NULL DEFAULT 0",
      );

      await db.execute('''
        UPDATE users
        SET has_full_access = COALESCE(has_full_access, 0)
        ''');
    }

    if (oldVersion < 23) {
      await _addColumnIfMissing(
        db,
        'products',
        'track_expiry',
        "INTEGER NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'products',
        'expiry_alert_days',
        "INTEGER NOT NULL DEFAULT 30",
      );
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'expiry_batch_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        'stock_receipts',
        'batch_number',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(db, 'stock_receipts', 'expiry_date', 'TEXT');
      await _createExpiryTables(db);
    }

    if (oldVersion < 24) {
      await _createProductPriceHistoryTable(db);

      await _addColumnIfMissing(
        db,
        'sale_items',
        'system_unit_price',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_override_type',
        "TEXT NOT NULL DEFAULT 'none'",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_override_reason',
        "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_override_original_price',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_override_difference',
        "REAL NOT NULL DEFAULT 0",
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_history_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        'sale_items',
        'price_override_approved_by',
        'TEXT',
      );

      await db.execute('''
        UPDATE sale_items
        SET system_unit_price = CASE
              WHEN COALESCE(system_unit_price, 0) <= 0 THEN COALESCE(unit_price, 0)
              ELSE system_unit_price
            END,
            price_override_original_price = CASE
              WHEN COALESCE(price_override_original_price, 0) <= 0
              THEN COALESCE(unit_price, 0)
              ELSE price_override_original_price
            END,
            price_override_type = COALESCE(NULLIF(price_override_type, ''), 'none'),
            price_override_reason = COALESCE(price_override_reason, ''),
            price_override_difference = COALESCE(unit_price, 0) - COALESCE(system_unit_price, COALESCE(unit_price, 0))
      ''');
    }

    if (oldVersion < 25) {
      await _createCustomersTable(db);
      await _ensureCustomerPricingSchema(db);
      await _ensureHeldCartCustomerSchema(db);
    }
  }

  Future<void> _createCustomersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_code TEXT UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        phone_normalized TEXT,
        email TEXT,
        address TEXT,
        customer_type TEXT NOT NULL DEFAULT 'regular',
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        credit_enabled INTEGER NOT NULL DEFAULT 0,
        credit_limit REAL NOT NULL DEFAULT 0,
        current_credit_balance REAL NOT NULL DEFAULT 0,
        credit_status TEXT NOT NULL DEFAULT 'normal',
        credit_note TEXT,
        pricing_enabled INTEGER NOT NULL DEFAULT 0,
        default_price_type TEXT NOT NULL DEFAULT 'selling',
        default_discount_percent REAL NOT NULL DEFAULT 0,
        pricing_note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by INTEGER,
        updated_by INTEGER
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone_normalized)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_code ON customers(customer_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active)',
    );
  }

  Future<void> _ensureCustomerPricingSchema(Database db) async {
    await _addColumnIfMissing(
      db,
      'customers',
      'pricing_enabled',
      "INTEGER NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(
      db,
      'customers',
      'default_price_type',
      "TEXT NOT NULL DEFAULT 'selling'",
    );
    await _addColumnIfMissing(
      db,
      'customers',
      'default_discount_percent',
      "REAL NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(db, 'customers', 'pricing_note', 'TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_product_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        product_name_snapshot TEXT NOT NULL,
        fixed_price REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by INTEGER,
        updated_by INTEGER,
        UNIQUE(customer_id, barcode),
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_product_prices_customer
      ON customer_product_prices(customer_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_product_prices_barcode
      ON customer_product_prices(barcode)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_product_prices_active
      ON customer_product_prices(is_active)
    ''');

    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_applied',
      "INTEGER NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_type',
      "TEXT NOT NULL DEFAULT 'none'",
    );
    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_rule_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_original_price',
      "REAL NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_final_price',
      "REAL NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_discount_amount',
      "REAL NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(
      db,
      'sale_items',
      'customer_pricing_note',
      'TEXT',
    );
  }

  Future<void> _ensureHeldCartCustomerSchema(Database db) async {
    await _addColumnIfMissing(db, 'held_carts', 'customer_id', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'held_carts',
      'customer_name_snapshot',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'held_carts',
      'customer_phone_snapshot',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'held_carts',
      'customer_code_snapshot',
      'TEXT',
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (tableRows.isEmpty) return;

    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);

    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  double _parseDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  int? _parseOptionalInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _normalizePriceOverrideType(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized == 'old_label') return 'old_label';
    if (normalized == 'manual') return 'manual';
    return 'none';
  }

  String _normalizeCustomerPricingType(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'customer_product_price':
      case 'customer_default_price_type':
      case 'customer_default_discount':
        return normalized;
      default:
        return 'none';
    }
  }

  String _normalizeProductQuantityType(dynamic value) {
    return ProductQuantityTypeX.fromDb(value?.toString()).dbValue;
  }

  String _normalizeProductUnitLabel({
    required String quantityType,
    String? unitLabel,
  }) {
    final trimmed = (unitLabel ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    return ProductQuantityTypeX.fromDb(quantityType).defaultUnitLabel;
  }

  String _normalizePriceType(String? value) {
    if (value == 'wholesale') return 'wholesale';
    if (value == 'sale') return 'sale';
    return 'selling';
  }

  String _normalizeUserRole(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized == 'manager') return 'manager';
    return 'cashier';
  }

  List<Map<String, dynamic>> _decodeHeldCartItemsJson(String itemsJson) {
    try {
      final decoded = jsonDecode(itemsJson);
      if (decoded is! List) return const <Map<String, dynamic>>[];

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['product'] is Map)
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic>? _tryCastMap(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> _decodePendingSaleItems(dynamic rawItems) {
    if (rawItems is! List) return const <Map<String, dynamic>>[];

    return rawItems
        .whereType<Map>()
        .map((rawItem) => Map<String, dynamic>.from(rawItem))
        .where((item) => _tryCastMap(item['product']) != null)
        .toList(growable: false);
  }

  Map<String, dynamic> _requireCartItemProductMap(
    Map<String, dynamic> item, {
    String fallbackName = 'This cart item',
  }) {
    final productMap = _tryCastMap(item['product']);
    if (productMap == null) {
      throw Exception('$fallbackName is missing valid product data.');
    }

    final barcode = productMap['barcode']?.toString().trim() ?? '';
    final productName = productMap['name']?.toString().trim() ?? '';
    if (barcode.isEmpty || productName.isEmpty) {
      throw Exception('$fallbackName is missing required product details.');
    }

    return productMap;
  }

  String _normalizeUserStatusFilter(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized == 'active') return 'active';
    if (normalized == 'inactive') return 'inactive';
    return 'all';
  }

  String _normalizeUserLogActionType(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();

    switch (normalized) {
      case 'login_success':
      case 'login_failed':
      case 'logout':
      case 'user_created':
      case 'user_updated':
      case 'pin_reset':
      case 'user_deactivated':
      case 'user_reactivated':
      case 'role_changed':
      case 'manager_approval':
      case 'full_access_granted':
      case 'full_access_revoked':
        return normalized;
      default:
        return normalized.isEmpty ? 'user_updated' : normalized;
    }
  }

  Future<void> _createUserTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin TEXT UNIQUE NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        has_full_access INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_login_at TEXT,
        created_by INTEGER,
        updated_by INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor_user_id INTEGER,
        actor_name TEXT NOT NULL,
        action_type TEXT NOT NULL,
        target_user_id INTEGER,
        target_user_name TEXT,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _insertUserLog(
    DatabaseExecutor executor, {
    int? actorUserId,
    String? actorName,
    required String actionType,
    int? targetUserId,
    String? targetUserName,
    required String description,
    String? createdAt,
  }) async {
    await executor.insert('user_logs', {
      'actor_user_id': actorUserId,
      'actor_name': (actorName == null || actorName.trim().isEmpty)
          ? 'System'
          : actorName.trim(),
      'action_type': _normalizeUserLogActionType(actionType),
      'target_user_id': targetUserId,
      'target_user_name': targetUserName?.trim(),
      'description': description.trim(),
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
    });
  }

  String _formatUserRoleLabel(String? value) {
    return _normalizeUserRole(value) == 'manager' ? 'Manager' : 'Cashier';
  }

  String _buildUserActionDescription(
    String actionType, {
    required String targetUserName,
    String? targetRole,
  }) {
    final roleLabel = targetRole == null || targetRole.trim().isEmpty
        ? ''
        : ' (${_formatUserRoleLabel(targetRole)})';

    switch (_normalizeUserLogActionType(actionType)) {
      case 'user_created':
        return 'Created user $targetUserName$roleLabel';
      case 'user_updated':
        return 'Updated user $targetUserName$roleLabel details';
      case 'pin_reset':
        return 'Reset PIN for $targetUserName';
      case 'user_deactivated':
        return 'Deactivated user $targetUserName';
      case 'user_reactivated':
        return 'Reactivated user $targetUserName';
      case 'role_changed':
        return 'Changed role for $targetUserName$roleLabel';
      case 'full_access_granted':
        return 'Granted full access to $targetUserName';
      case 'full_access_revoked':
        return 'Removed full access from $targetUserName';
      case 'login_success':
        return '$targetUserName logged in';
      case 'login_failed':
        return 'Failed login attempt';
      case 'logout':
        return '$targetUserName logged out';
      case 'manager_approval':
        return 'Manager approval recorded for $targetUserName';
      default:
        return 'User activity recorded for $targetUserName';
    }
  }

  Future<int> _getActiveManagerCountExecutor(
    DatabaseExecutor executor, {
    int? excludingUserId,
  }) async {
    final hasExclusion = excludingUserId != null && excludingUserId > 0;
    final rows = await executor.rawQuery('''
      SELECT COUNT(*) AS count
      FROM users
      WHERE role = 'manager'
        AND is_active = 1
        ${hasExclusion ? 'AND id != ?' : ''}
      ''', hasExclusion ? [excludingUserId] : const <Object?>[]);

    return _parseInt(rows.first['count']);
  }

  double _resolveCartItemUnitPrice(Map<String, dynamic> item) {
    final explicitUnitPrice = item['unit_price_used'];
    if (explicitUnitPrice != null) {
      return _parseDouble(explicitUnitPrice);
    }

    final fallbackName = item['product_name']?.toString().trim();
    final productMap = _requireCartItemProductMap(
      item,
      fallbackName: fallbackName == null || fallbackName.isEmpty
          ? 'This cart item'
          : fallbackName,
    );
    final priceType = _normalizePriceType(item['price_type_used']?.toString());

    final sellingPrice = _parseDouble(
      productMap['selling_price'] ?? productMap['price'],
    );
    final wholesalePrice = _parseDouble(
      productMap['wholesale_price'],
      fallback: sellingPrice,
    );
    final salePrice = productMap['sale_price'] == null
        ? null
        : _parseDouble(productMap['sale_price']);
    final saleEnabledRaw = productMap['sale_enabled'];
    final saleEnabled = saleEnabledRaw == null
        ? salePrice != null
        : _parseInt(saleEnabledRaw) == 1 || saleEnabledRaw == true;

    switch (priceType) {
      case 'wholesale':
        return wholesalePrice > 0 ? wholesalePrice : sellingPrice;
      case 'sale':
        if (saleEnabled && salePrice != null && salePrice > 0) {
          return salePrice;
        }
        return sellingPrice;
      case 'selling':
      default:
        return sellingPrice;
    }
  }

  String _resolveCartItemPriceType(Map<String, dynamic> item) {
    return _normalizePriceType(item['price_type_used']?.toString());
  }

  String _mapPriceActionType(String priceType) {
    switch (priceType) {
      case 'cost':
        return 'price_change_cost';
      case 'wholesale':
        return 'price_change_wholesale';
      case 'sale':
        return 'price_change_sale';
      case 'selling':
      default:
        return 'price_change_selling';
    }
  }

  Future<void> _insertInventoryMovement(
    DatabaseExecutor executor, {
    required String barcode,
    required String productName,
    required String actionType,
    num? quantityChange,
    num? stockBefore,
    num? stockAfter,
    double? oldPrice,
    double? newPrice,
    String? priceType,
    String? reason,
    int? referenceId,
    String? referenceType,
    String? performedBy,
    int? supplierId,
    String? supplierName,
    String? createdAt,
  }) async {
    await executor.insert('inventory_movements', {
      'barcode': barcode,
      'product_name': productName,
      'action_type': actionType,
      'quantity_change': quantityChange,
      'stock_before': stockBefore,
      'stock_after': stockAfter,
      'old_price': oldPrice,
      'new_price': newPrice,
      'price_type': priceType,
      'reason': reason,
      'reference_id': referenceId,
      'reference_type': referenceType,
      'performed_by': performedBy,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
    });
  }

  Future<void> insertMockDataIfEmpty() async {
    final db = await database;

    final existingProducts = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products',
    );
    final productCount = existingProducts.first['count'] as int;

    if (productCount == 0) {
      final now = DateTime.now().toIso8601String();
      final mockProducts = [
        {
          'barcode': '4791044000123',
          'name': 'Munchee Super Cream Cracker 500g',
          'category': 'Biscuits',
          'price': 450.0,
          'selling_price': 450.0,
          'cost_price': 390.0,
          'wholesale_price': 430.0,
          'sale_price': null,
          'sale_enabled': 0,
          'stock': 100,
          'min_stock_level': 10,
          'is_active': 1,
          'updated_at': now,
          'last_price_updated_at': now,
        },
        {
          'barcode': '4792011001234',
          'name': 'Anchor Milk Powder 400g',
          'category': 'Dairy',
          'price': 1100.0,
          'selling_price': 1100.0,
          'cost_price': 980.0,
          'wholesale_price': 1050.0,
          'sale_price': null,
          'sale_enabled': 0,
          'stock': 50,
          'min_stock_level': 8,
          'is_active': 1,
          'updated_at': now,
          'last_price_updated_at': now,
        },
        {
          'barcode': '4792022005678',
          'name': 'Saman Halmassa 425g',
          'category': 'Canned Food',
          'price': 650.0,
          'selling_price': 650.0,
          'cost_price': 560.0,
          'wholesale_price': 620.0,
          'sale_price': 625.0,
          'sale_enabled': 0,
          'stock': 30,
          'min_stock_level': 6,
          'is_active': 1,
          'updated_at': now,
          'last_price_updated_at': now,
        },
        {
          'barcode': '4793033009999',
          'name': 'Kist Strawberry Jam 500g',
          'category': 'Groceries',
          'price': 580.0,
          'selling_price': 580.0,
          'cost_price': 505.0,
          'wholesale_price': 555.0,
          'sale_price': 549.0,
          'sale_enabled': 0,
          'stock': 40,
          'min_stock_level': 8,
          'is_active': 1,
          'updated_at': now,
          'last_price_updated_at': now,
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
      final now = DateTime.now().toIso8601String();
      final mockUsers = [
        {
          'name': 'Pathum (Manager)',
          'role': 'manager',
          'pin': '1234',
          'is_active': 1,
          'has_full_access': 0,
          'created_at': now,
          'updated_at': now,
          'last_login_at': null,
          'created_by': null,
          'updated_by': null,
        },
        {
          'name': 'Amal (Cashier)',
          'role': 'cashier',
          'pin': '5555',
          'is_active': 1,
          'has_full_access': 0,
          'created_at': now,
          'updated_at': now,
          'last_login_at': null,
          'created_by': null,
          'updated_by': null,
        },
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
          'category': product.category,
          'quantity_type': product.quantityType.dbValue,
          'unit_label': product.unitLabel,
          'price': product.sellingPrice,
          'cost_price': product.costPrice,
          'selling_price': product.sellingPrice,
          'wholesale_price': product.wholesalePrice,
          'sale_price': product.salePrice,
          'sale_enabled': product.saleEnabled ? 1 : 0,
          'stock': product.stock,
          'min_stock_level': product.minStockLevel,
          'track_expiry': product.trackExpiry ? 1 : 0,
          'expiry_alert_days': product.expiryAlertDays,
          'is_active': product.isActive ? 1 : 0,
          'updated_at': product.updatedAt,
          'last_price_updated_at':
              product.lastPriceUpdatedAt ?? product.updatedAt,
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
          if (decodedData is! Map) {
            continue;
          }
          final data = Map<String, dynamic>.from(decodedData);
          final transactionType = (data['transaction_type'] ?? 'sale')
              .toString()
              .toLowerCase();
          final items = _decodePendingSaleItems(data['items']);

          for (final item in items) {
            final productMap = _tryCastMap(item['product']);
            if (productMap == null) continue;

            final barcode = productMap['barcode']?.toString() ?? '';
            final quantity = _parseQuantity(item['quantity']);

            if (barcode.isEmpty || !_isPositiveQuantity(quantity)) continue;

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
          final newPrice = _parseDouble(data['new_price'], fallback: -1);
          final priceType = (data['price_type'] ?? 'selling').toString();
          final saleEnabledRaw = data['sale_enabled'];
          final now = DateTime.now().toIso8601String();

          if (barcode.isEmpty || newPrice < 0) continue;

          final normalizedPriceType = priceType == 'cost'
              ? 'cost'
              : _normalizePriceType(priceType);

          final updates = <String, Object?>{
            'updated_at': now,
            'last_price_updated_at': now,
          };

          switch (normalizedPriceType) {
            case 'cost':
              updates['cost_price'] = newPrice;
              break;
            case 'wholesale':
              updates['wholesale_price'] = newPrice;
              break;
            case 'sale':
              updates['sale_price'] = newPrice;
              if (saleEnabledRaw != null) {
                updates['sale_enabled'] =
                    _parseInt(saleEnabledRaw) == 1 || saleEnabledRaw == true
                    ? 1
                    : 0;
              } else {
                updates['sale_enabled'] = 1;
              }
              break;
            case 'selling':
            default:
              updates['selling_price'] = newPrice;
              updates['price'] = newPrice;
              break;
          }

          await txn.update(
            'products',
            updates,
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        } else if (type == 'STOCK_RECEIVE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final barcode = data['barcode']?.toString() ?? '';
          final quantity = _parseInt(data['quantity']);
          final unitCostRaw = data['unit_cost'];

          if (barcode.isEmpty || quantity <= 0) continue;

          final rows = await txn.query(
            'products',
            columns: ['stock'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          if (rows.isEmpty) continue;

          final currentStock = _parseInt(rows.first['stock']);
          final updates = <String, Object?>{
            'stock': currentStock + quantity,
            'updated_at': DateTime.now().toIso8601String(),
          };

          if (unitCostRaw != null) {
            updates['cost_price'] = _roundMoney(_parseDouble(unitCostRaw));
            updates['last_price_updated_at'] = DateTime.now().toIso8601String();
          }

          await txn.update(
            'products',
            updates,
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        } else if (type == 'STOCK_ADJUST') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final barcode = data['barcode']?.toString() ?? '';
          final adjustmentType = (data['adjustment_type'] ?? '').toString();
          final quantity = _parseInt(data['quantity']);

          if (barcode.isEmpty) continue;

          final rows = await txn.query(
            'products',
            columns: ['stock'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          if (rows.isEmpty) continue;

          final currentStock = _parseInt(rows.first['stock']);
          int nextStock = currentStock;

          switch (adjustmentType) {
            case 'add':
            case 'increase':
              if (quantity <= 0) continue;
              nextStock = currentStock + quantity;
              break;
            case 'remove':
            case 'decrease':
              if (quantity <= 0) continue;
              nextStock = currentStock - quantity;
              if (nextStock < 0) nextStock = 0;
              break;
            case 'set':
            case 'set_exact':
              if (quantity < 0) continue;
              nextStock = quantity;
              break;
            default:
              continue;
          }

          await txn.update(
            'products',
            {
              'stock': nextStock,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        } else if (type == 'MIN_STOCK_UPDATE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final barcode = data['barcode']?.toString() ?? '';
          final minStockLevel = _parseInt(
            data['min_stock_level'],
            fallback: -1,
          );

          if (barcode.isEmpty || minStockLevel < 0) continue;

          await txn.update(
            'products',
            {
              'min_stock_level': minStockLevel,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        } else if (type == 'BULK_PRODUCT_IMPORT') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final rows = (data['rows'] as List?) ?? const [];
          final now = DateTime.now().toIso8601String();

          for (final rawRow in rows) {
            final row = Map<String, dynamic>.from(rawRow as Map);
            final barcode = row['barcode']?.toString().trim() ?? '';
            final name = row['name']?.toString().trim() ?? '';
            if (barcode.isEmpty || name.isEmpty) continue;

            final sellingPrice = _roundMoney(
              _parseDouble(row['selling_price'] ?? row['price']),
            );
            final wholesalePrice = _roundMoney(
              _parseDouble(row['wholesale_price'], fallback: sellingPrice),
            );
            final salePriceRaw = row['sale_price'];
            final salePrice = salePriceRaw == null
                ? null
                : _roundMoney(_parseDouble(salePriceRaw));
            final saleEnabled = row['sale_enabled'] == null
                ? (salePrice != null ? 1 : 0)
                : ((_parseInt(row['sale_enabled']) == 1 ||
                          row['sale_enabled'] == true)
                      ? 1
                      : 0);
            final stock = _parseInt(row['stock'] ?? row['opening_stock']);

            await txn.insert('products', {
              'barcode': barcode,
              'name': name,
              'category': (row['category'] ?? 'General').toString(),
              'price': sellingPrice,
              'cost_price': _roundMoney(_parseDouble(row['cost_price'])),
              'selling_price': sellingPrice,
              'wholesale_price': wholesalePrice,
              'sale_price': salePrice,
              'sale_enabled': saleEnabled,
              'stock': stock,
              'min_stock_level': _parseInt(row['min_stock_level']),
              'is_active': 1,
              'updated_at': now,
              'last_price_updated_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        } else if (type == 'PRODUCT_CREATE' || type == 'PRODUCT_UPDATE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final barcode = data['barcode']?.toString().trim() ?? '';
          final name = data['name']?.toString().trim() ?? '';
          if (barcode.isEmpty || name.isEmpty) continue;

          final now = DateTime.now().toIso8601String();
          final sellingPrice = _roundMoney(
            _parseDouble(data['selling_price'] ?? data['price']),
          );
          final wholesalePrice = _roundMoney(
            _parseDouble(data['wholesale_price'], fallback: sellingPrice),
          );
          final salePriceRaw = data['sale_price'];
          final salePrice = salePriceRaw == null
              ? null
              : _roundMoney(_parseDouble(salePriceRaw));
          final saleEnabled = data['sale_enabled'] == null
              ? (salePrice != null ? 1 : 0)
              : ((_parseInt(data['sale_enabled']) == 1 ||
                        data['sale_enabled'] == true)
                    ? 1
                    : 0);

          await txn.insert('products', {
            'barcode': barcode,
            'name': name,
            'category': (data['category'] ?? 'General').toString(),
            'price': sellingPrice,
            'cost_price': _roundMoney(_parseDouble(data['cost_price'])),
            'selling_price': sellingPrice,
            'wholesale_price': wholesalePrice,
            'sale_price': salePrice,
            'sale_enabled': saleEnabled,
            'stock': _parseInt(data['opening_stock'] ?? data['stock']),
            'min_stock_level': _parseInt(data['min_stock_level']),
            'is_active': 1,
            'updated_at': now,
            'last_price_updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else if (type == 'PRODUCT_DELETE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final barcode = data['barcode']?.toString().trim() ?? '';
          if (barcode.isEmpty) continue;

          await txn.delete(
            'supplier_product_mappings',
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
          await txn.delete(
            'products',
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        } else if (type == 'BULK_PRODUCT_DELETE') {
          final data = Map<String, dynamic>.from(decodedData as Map);
          final rows = (data['barcodes'] as List?) ?? const [];
          for (final rawBarcode in rows) {
            final barcode = rawBarcode?.toString().trim() ?? '';
            if (barcode.isEmpty) continue;

            await txn.delete(
              'supplier_product_mappings',
              where: 'barcode = ?',
              whereArgs: [barcode],
            );
            await txn.delete(
              'products',
              where: 'barcode = ?',
              whereArgs: [barcode],
            );
          }
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
        final preliminaryLineInputs = <Map<String, dynamic>>[];
        double explicitItemDiscountTotal = 0.0;

        for (final item in cartItems) {
          final productMap = _requireCartItemProductMap(item);
          final barcode = productMap['barcode']?.toString() ?? '';
          final productName =
              productMap['name']?.toString() ?? 'Unknown product';
          final unitPrice = _resolveCartItemUnitPrice(item);
          final systemUnitPrice = _parseDouble(
            item['system_unit_price'],
            fallback: unitPrice,
          );
          final priceOverrideType = _normalizePriceOverrideType(
            item['price_override_type']?.toString(),
          );
          final priceOverrideReason = (item['price_override_reason'] ?? '')
              .toString()
              .trim();
          final priceOverrideOriginalPrice = _parseDouble(
            item['price_override_original_price'],
            fallback: systemUnitPrice,
          );
          final priceOverrideDifference = _roundMoney(
            unitPrice - systemUnitPrice,
          );
          final priceHistoryId = _parseOptionalInt(item['price_history_id']);
          final priceOverrideApprovedBy = item['price_override_approved_by']
              ?.toString()
              .trim();
          final customerPricingType = _normalizeCustomerPricingType(
            item['customer_pricing_type']?.toString(),
          );
          final customerPricingEffective =
              priceOverrideType == 'none' &&
              customerPricingType != 'none' &&
              _parseInt(item['customer_pricing_applied']) == 1;
          final customerPricingOriginalPrice = customerPricingEffective
              ? _parseDouble(
                  item['customer_pricing_original_price'],
                  fallback: systemUnitPrice,
                )
              : 0.0;
          final customerPricingFinalPrice = customerPricingEffective
              ? _parseDouble(
                  item['customer_pricing_final_price'],
                  fallback: unitPrice,
                )
              : 0.0;
          final customerPricingDiscountAmount = customerPricingEffective
              ? _roundMoney(
                  _parseDouble(item['customer_pricing_discount_amount']),
                )
              : 0.0;
          final customerPricingNote = customerPricingEffective
              ? item['customer_pricing_note']?.toString().trim()
              : null;
          final priceTypeUsed = _resolveCartItemPriceType(item);
          final markedPrice = _parseDouble(productMap['selling_price']) > 0
              ? _parseDouble(productMap['selling_price'])
              : unitPrice;
          final costPriceSnapshot = _parseDouble(productMap['cost_price']);
          final quantity = _parseQuantity(item['quantity']);
          final computedBaseLineTotal = _roundMoney(unitPrice * quantity);
          final baseLineTotal = _roundMoney(
            ((item['base_line_total'] as num?) ?? computedBaseLineTotal)
                .toDouble(),
          );
          final providedItemDiscount =
              ((item['item_discount_amount'] as num?) ?? 0).toDouble();
          final itemDiscountType = _normalizeDiscountType(
            item['item_discount_type']?.toString() ?? 'none',
          );
          final itemDiscountValue = ((item['item_discount_value'] as num?) ?? 0)
              .toDouble();
          final providedLineTotal =
              ((item['line_total'] as num?) ??
                      (baseLineTotal - providedItemDiscount))
                  .toDouble();

          final safeItemDiscount = providedItemDiscount < 0
              ? 0.0
              : (providedItemDiscount > baseLineTotal
                    ? baseLineTotal
                    : _roundMoney(providedItemDiscount));
          final netLineTotal = _roundMoney(
            providedLineTotal < 0
                ? 0.0
                : (providedLineTotal > baseLineTotal
                      ? baseLineTotal
                      : providedLineTotal),
          );

          explicitItemDiscountTotal = _roundMoney(
            explicitItemDiscountTotal + safeItemDiscount,
          );

          preliminaryLineInputs.add({
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'system_unit_price': systemUnitPrice,
            'price_override_type': priceOverrideType,
            'price_override_reason': priceOverrideReason,
            'price_override_original_price': priceOverrideOriginalPrice,
            'price_override_difference': priceOverrideDifference,
            'price_history_id': priceHistoryId,
            'price_override_approved_by': priceOverrideApprovedBy,
            'customer_pricing_applied': customerPricingEffective ? 1 : 0,
            'customer_pricing_type': customerPricingEffective
                ? customerPricingType
                : 'none',
            'customer_pricing_rule_id': customerPricingEffective
                ? _parseOptionalInt(item['customer_pricing_rule_id'])
                : null,
            'customer_pricing_original_price': customerPricingOriginalPrice,
            'customer_pricing_final_price': customerPricingFinalPrice,
            'customer_pricing_discount_amount': customerPricingDiscountAmount,
            'customer_pricing_note':
                customerPricingNote == null || customerPricingNote.isEmpty
                ? null
                : customerPricingNote,
            'marked_price': markedPrice,
            'price_category_used': priceTypeUsed,
            'cost_price_snapshot': costPriceSnapshot,
            'quantity': quantity,
            'base_line_total': baseLineTotal,
            'item_discount_type': itemDiscountType,
            'item_discount_value': itemDiscountValue < 0
                ? 0.0
                : itemDiscountValue,
            'explicit_item_discount_amount': safeItemDiscount,
            'net_line_total_before_cart_discount': netLineTotal,
          });
        }

        final fallbackDiscountAmount = isRefund
            ? 0.0
            : _calculateDiscountAmount(
                subtotal: _roundMoney(
                  resolvedSubtotal - explicitItemDiscountTotal,
                ),
                discountType: resolvedDiscountType,
                discountValue: resolvedDiscountValue,
              );
        final resolvedDiscountAmount = isRefund
            ? 0.0
            : _roundMoney(
                (discountAmount ??
                        (explicitItemDiscountTotal + fallbackDiscountAmount))
                    .abs(),
              );
        final resolvedFinalTotal = isRefund
            ? resolvedSubtotal
            : _roundMoney(totalAmount.abs());

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
            final productMap = _requireCartItemProductMap(item);
            final barcode = productMap['barcode']?.toString() ?? '';
            final productName =
                productMap['name']?.toString() ?? 'Unknown product';
            final quantity = _parseQuantity(item['quantity']);

            if (!_isPositiveQuantity(quantity)) {
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

            final availableStock = _parseQuantity(rows.first['stock']);

            if (_quantityExceeds(quantity, availableStock)) {
              throw Exception(
                'Insufficient stock for $productName. Available: ${_formatQuantityValue(availableStock)}, requested: ${_formatQuantityValue(quantity)}.',
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
        double remainingCartDiscountToAllocate = _roundMoney(
          resolvedDiscountAmount - explicitItemDiscountTotal,
        );
        if (remainingCartDiscountToAllocate < 0) {
          remainingCartDiscountToAllocate = 0.0;
        }

        for (int i = 0; i < preliminaryLineInputs.length; i++) {
          final item = preliminaryLineInputs[i];
          final barcode = item['barcode'] as String;
          final productName = item['product_name'] as String;
          final unitPrice = item['unit_price'] as double;
          final systemUnitPrice =
              (item['system_unit_price'] as num?)?.toDouble() ?? unitPrice;
          final priceOverrideType = (item['price_override_type'] ?? 'none')
              .toString();
          final priceOverrideReason = (item['price_override_reason'] ?? '')
              .toString();
          final priceOverrideOriginalPrice =
              (item['price_override_original_price'] as num?)?.toDouble() ??
              systemUnitPrice;
          final priceOverrideDifference =
              (item['price_override_difference'] as num?)?.toDouble() ??
              (unitPrice - systemUnitPrice);
          final priceHistoryId = item['price_history_id'] as int?;
          final priceOverrideApprovedBy = item['price_override_approved_by']
              ?.toString();
          final customerPricingApplied =
              ((item['customer_pricing_applied'] as num?)?.toInt() ?? 0) == 1;
          final customerPricingType = (item['customer_pricing_type'] ?? 'none')
              .toString();
          final customerPricingRuleId =
              item['customer_pricing_rule_id'] as int?;
          final customerPricingOriginalPrice =
              (item['customer_pricing_original_price'] as num?)?.toDouble() ??
              0.0;
          final customerPricingFinalPrice =
              (item['customer_pricing_final_price'] as num?)?.toDouble() ?? 0.0;
          final customerPricingDiscountAmount =
              (item['customer_pricing_discount_amount'] as num?)?.toDouble() ??
              0.0;
          final customerPricingNote = item['customer_pricing_note']?.toString();
          final markedPrice = item['marked_price'] as double;
          final priceTypeUsed = (item['price_category_used'] ?? 'selling')
              .toString();
          final costPriceSnapshot =
              (item['cost_price_snapshot'] as num?)?.toDouble() ?? 0.0;
          final quantity = (item['quantity'] as num).toDouble();
          final baseLineTotal = item['base_line_total'] as double;
          final itemDiscountType = (item['item_discount_type'] ?? 'none')
              .toString();
          final itemDiscountValue =
              (item['item_discount_value'] as num?)?.toDouble() ?? 0.0;
          final explicitItemDiscount =
              (item['explicit_item_discount_amount'] as num).toDouble();
          final netLineTotalBeforeCartDiscount =
              (item['net_line_total_before_cart_discount'] as num).toDouble();

          double cartLevelItemDiscount = 0.0;

          if (!isRefund && remainingCartDiscountToAllocate > 0) {
            if (i == preliminaryLineInputs.length - 1) {
              cartLevelItemDiscount = remainingCartDiscountToAllocate;
            } else {
              final totalNetBeforeCartDiscount = _roundMoney(
                preliminaryLineInputs.fold<double>(
                  0.0,
                  (sum, current) =>
                      sum +
                      ((current['net_line_total_before_cart_discount']
                                  as num?) ??
                              0)
                          .toDouble(),
                ),
              );
              final share = totalNetBeforeCartDiscount <= 0
                  ? 0.0
                  : remainingCartDiscountToAllocate *
                        (netLineTotalBeforeCartDiscount /
                            totalNetBeforeCartDiscount);
              cartLevelItemDiscount = _roundMoney(share);

              if (cartLevelItemDiscount > remainingCartDiscountToAllocate) {
                cartLevelItemDiscount = remainingCartDiscountToAllocate;
              }
            }
          }

          final itemDiscount = _roundMoney(
            explicitItemDiscount + cartLevelItemDiscount,
          );
          final maxDiscount = baseLineTotal;
          final safeItemDiscount = itemDiscount > maxDiscount
              ? maxDiscount
              : itemDiscount;
          remainingCartDiscountToAllocate = _roundMoney(
            remainingCartDiscountToAllocate - cartLevelItemDiscount,
          );

          final finalLineTotal = isRefund
              ? -baseLineTotal
              : _roundMoney(baseLineTotal - safeItemDiscount);

          saleItemInputs.add({
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'system_unit_price': systemUnitPrice,
            'price_override_type': priceOverrideType,
            'price_override_reason': priceOverrideReason,
            'price_override_original_price': priceOverrideOriginalPrice,
            'price_override_difference': priceOverrideDifference,
            'price_history_id': priceHistoryId,
            'price_override_approved_by': priceOverrideApprovedBy,
            'customer_pricing_applied': customerPricingApplied ? 1 : 0,
            'customer_pricing_type': customerPricingType,
            'customer_pricing_rule_id': customerPricingRuleId,
            'customer_pricing_original_price': customerPricingOriginalPrice,
            'customer_pricing_final_price': customerPricingFinalPrice,
            'customer_pricing_discount_amount': customerPricingDiscountAmount,
            'customer_pricing_note': customerPricingNote,
            'marked_price': markedPrice,
            'price_category_used': priceTypeUsed,
            'cost_price_snapshot': costPriceSnapshot,
            'quantity': quantity,
            'base_line_total': baseLineTotal,
            'item_discount_type': itemDiscountType,
            'item_discount_value': itemDiscountValue,
            'explicit_item_discount_amount': isRefund
                ? 0.0
                : explicitItemDiscount,
            'cart_discount_amount': isRefund ? 0.0 : cartLevelItemDiscount,
            'item_discount_amount': isRefund ? 0.0 : safeItemDiscount,
            'line_total': finalLineTotal,
          });
        }

        for (final item in saleItemInputs) {
          final barcode = item['barcode'] as String;
          final productName = item['product_name'] as String;
          final unitPrice = item['unit_price'] as double;
          final systemUnitPrice =
              (item['system_unit_price'] as num?)?.toDouble() ?? unitPrice;
          final priceOverrideType = (item['price_override_type'] ?? 'none')
              .toString();
          final priceOverrideReason = (item['price_override_reason'] ?? '')
              .toString();
          final priceOverrideOriginalPrice =
              (item['price_override_original_price'] as num?)?.toDouble() ??
              systemUnitPrice;
          final priceOverrideDifference =
              (item['price_override_difference'] as num?)?.toDouble() ??
              (unitPrice - systemUnitPrice);
          final priceHistoryId = item['price_history_id'] as int?;
          final priceOverrideApprovedBy = item['price_override_approved_by']
              ?.toString();
          final customerPricingApplied =
              ((item['customer_pricing_applied'] as num?)?.toInt() ?? 0) == 1;
          final customerPricingType = (item['customer_pricing_type'] ?? 'none')
              .toString();
          final customerPricingRuleId =
              item['customer_pricing_rule_id'] as int?;
          final customerPricingOriginalPrice =
              (item['customer_pricing_original_price'] as num?)?.toDouble() ??
              0.0;
          final customerPricingFinalPrice =
              (item['customer_pricing_final_price'] as num?)?.toDouble() ?? 0.0;
          final customerPricingDiscountAmount =
              (item['customer_pricing_discount_amount'] as num?)?.toDouble() ??
              0.0;
          final customerPricingNote = item['customer_pricing_note']?.toString();
          final markedPrice =
              (item['marked_price'] as num?)?.toDouble() ?? unitPrice;
          final priceCategoryUsed = (item['price_category_used'] ?? 'selling')
              .toString();
          final costPriceSnapshot =
              (item['cost_price_snapshot'] as num?)?.toDouble() ?? 0.0;
          final quantity = (item['quantity'] as num).toDouble();
          final baseLineTotal = item['base_line_total'] as double;
          final itemDiscountType = (item['item_discount_type'] ?? 'none')
              .toString();
          final itemDiscountValue =
              (item['item_discount_value'] as num?)?.toDouble() ?? 0.0;
          final explicitItemDiscount =
              (item['explicit_item_discount_amount'] as num?)?.toDouble() ??
              0.0;
          final cartDiscount =
              (item['cart_discount_amount'] as num?)?.toDouble() ?? 0.0;
          final itemDiscount = item['item_discount_amount'] as double;
          final finalLineTotal = item['line_total'] as double;

          final stockDelta = isRefund ? quantity : -quantity;

          final stockRows = await txn.query(
            'products',
            columns: ['stock'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          final stockBefore = stockRows.isEmpty
              ? 0.0
              : _parseQuantity(stockRows.first['stock']);

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

          if (!isRefund) {
            await _deductExpiryBatchesForSale(
              txn,
              barcode: barcode,
              quantity: quantity,
              updatedAt: now,
            );
          }

          await txn.insert('sale_items', {
            'sale_id': saleId,
            'barcode': barcode,
            'product_name': productName,
            'unit_price': unitPrice,
            'system_unit_price': systemUnitPrice,
            'price_override_type': priceOverrideType,
            'price_override_reason': priceOverrideReason,
            'price_override_original_price': priceOverrideOriginalPrice,
            'price_override_difference': priceOverrideDifference,
            'price_history_id': priceHistoryId,
            'price_override_approved_by': priceOverrideApprovedBy,
            'customer_pricing_applied': customerPricingApplied ? 1 : 0,
            'customer_pricing_type': customerPricingType,
            'customer_pricing_rule_id': customerPricingRuleId,
            'customer_pricing_original_price': customerPricingOriginalPrice,
            'customer_pricing_final_price': customerPricingFinalPrice,
            'customer_pricing_discount_amount': customerPricingDiscountAmount,
            'customer_pricing_note': customerPricingNote,
            'marked_price': markedPrice,
            'price_category_used': priceCategoryUsed,
            'cost_price_snapshot': costPriceSnapshot,
            'quantity': quantity,
            'base_line_total': baseLineTotal,
            'item_discount_type': itemDiscountType,
            'item_discount_value': itemDiscountValue,
            'explicit_item_discount_amount': explicitItemDiscount,
            'cart_discount_amount': cartDiscount,
            'item_discount_amount': itemDiscount,
            'line_total': finalLineTotal,
            'created_at': now,
          });

          await _insertInventoryMovement(
            txn,
            barcode: barcode,
            productName: productName,
            actionType: isRefund ? 'refund' : 'sale',
            quantityChange: stockDelta,
            stockBefore: stockBefore,
            stockAfter: stockBefore + stockDelta,
            priceType: priceCategoryUsed,
            referenceId: saleId,
            referenceType: 'sale',
            performedBy: cashierName,
            createdAt: now,
          );
        }

        final syncItems = saleItemInputs
            .map((item) {
              final barcode = item['barcode'] as String;
              final productName = item['product_name'] as String;
              final unitPrice = (item['unit_price'] as num).toDouble();
              final systemUnitPrice =
                  (item['system_unit_price'] as num?)?.toDouble() ?? unitPrice;
              final priceOverrideType = (item['price_override_type'] ?? 'none')
                  .toString();
              final priceOverrideReason = (item['price_override_reason'] ?? '')
                  .toString();
              final priceOverrideOriginalPrice =
                  (item['price_override_original_price'] as num?)?.toDouble() ??
                  systemUnitPrice;
              final priceOverrideDifference =
                  (item['price_override_difference'] as num?)?.toDouble() ??
                  (unitPrice - systemUnitPrice);
              final priceHistoryId = item['price_history_id'];
              final priceOverrideApprovedBy = item['price_override_approved_by']
                  ?.toString();
              final customerPricingApplied =
                  ((item['customer_pricing_applied'] as num?)?.toInt() ?? 0) ==
                  1;
              final customerPricingType =
                  (item['customer_pricing_type'] ?? 'none').toString();
              final customerPricingRuleId = item['customer_pricing_rule_id'];
              final customerPricingOriginalPrice =
                  (item['customer_pricing_original_price'] as num?)
                      ?.toDouble() ??
                  0.0;
              final customerPricingFinalPrice =
                  (item['customer_pricing_final_price'] as num?)?.toDouble() ??
                  0.0;
              final customerPricingDiscountAmount =
                  (item['customer_pricing_discount_amount'] as num?)
                      ?.toDouble() ??
                  0.0;
              final customerPricingNote = item['customer_pricing_note']
                  ?.toString();
              final priceCategoryUsed =
                  (item['price_category_used'] ?? 'selling').toString();
              final costPriceSnapshot =
                  (item['cost_price_snapshot'] as num?)?.toDouble() ?? 0.0;
              final quantity = (item['quantity'] as num).toDouble();
              final baseLineTotal = (item['base_line_total'] as num).toDouble();
              final itemDiscount =
                  (item['item_discount_amount'] as num?)?.toDouble() ?? 0.0;
              final finalLineTotal = (item['line_total'] as num).toDouble();

              return {
                'product': {
                  'barcode': barcode,
                  'name': productName,
                  'price': unitPrice,
                  'selling_price': unitPrice,
                  'cost_price': costPriceSnapshot,
                },
                'quantity': quantity,
                'unit_price_used': unitPrice,
                'system_unit_price': systemUnitPrice,
                'price_override_type': priceOverrideType,
                'price_override_reason': priceOverrideReason,
                'price_override_original_price': priceOverrideOriginalPrice,
                'price_override_difference': priceOverrideDifference,
                'price_history_id': priceHistoryId,
                'price_override_approved_by': priceOverrideApprovedBy,
                'customer_pricing_applied': customerPricingApplied ? 1 : 0,
                'customer_pricing_type': customerPricingType,
                'customer_pricing_rule_id': customerPricingRuleId,
                'customer_pricing_original_price': customerPricingOriginalPrice,
                'customer_pricing_final_price': customerPricingFinalPrice,
                'customer_pricing_discount_amount':
                    customerPricingDiscountAmount,
                'customer_pricing_note': customerPricingNote,
                'price_type_used': priceCategoryUsed,
                'cost_price_snapshot': costPriceSnapshot,
                'base_line_total': baseLineTotal,
                'item_discount_amount': itemDiscount,
                'line_total': finalLineTotal,
              };
            })
            .toList(growable: false);

        final syncData = jsonEncode({
          'local_sale_id': saleId,
          'created_at': now,
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
          'items': syncItems,
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
          final quantity = _parseQuantity(item['quantity']);

          if (barcode.isEmpty || !_isPositiveQuantity(quantity)) {
            throw Exception('Invalid refund item.');
          }

          final refundableData = refundableMap[barcode];
          if (refundableData == null) {
            throw Exception(
              'Refund item $barcode is not part of the original sale.',
            );
          }

          final refundableQty = _parseQuantity(
            refundableData['refundable_quantity'],
          );
          final remainingRefundableTotal =
              ((refundableData['remaining_refundable_total'] as num?) ?? 0)
                  .toDouble();

          if (_quantityExceeds(quantity, refundableQty)) {
            final productName =
                (refundableData['product_name'] ?? 'Unknown product')
                    .toString();
            throw Exception(
              'Cannot refund more than remaining quantity for $productName. Remaining: ${_formatQuantityValue(refundableQty)}.',
            );
          }

          final productName =
              (refundableData['product_name'] ?? 'Unknown product').toString();
          final unitPrice = ((refundableData['refund_unit_price'] as num?) ?? 0)
              .toDouble();
          final originalPriceCategory =
              (refundableData['price_category_used'] ?? 'selling').toString();
          final costPriceSnapshot =
              ((refundableData['cost_price_snapshot'] as num?) ?? 0).toDouble();
          final customerPricingApplied =
              ((refundableData['customer_pricing_applied'] as num?)?.toInt() ??
                  0) ==
              1;
          final customerPricingType = _normalizeCustomerPricingType(
            refundableData['customer_pricing_type']?.toString(),
          );
          final customerPricingRuleId = _parseOptionalInt(
            refundableData['customer_pricing_rule_id'],
          );
          final customerPricingOriginalPrice = _parseDouble(
            refundableData['customer_pricing_original_price'],
          );
          final customerPricingFinalPrice = _parseDouble(
            refundableData['customer_pricing_final_price'],
          );
          final customerPricingDiscountAmount = _parseDouble(
            refundableData['customer_pricing_discount_amount'],
          );
          final customerPricingNote = refundableData['customer_pricing_note']
              ?.toString();

          final stockRows = await txn.query(
            'products',
            columns: ['stock'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          final stockBefore = stockRows.isEmpty
              ? 0.0
              : _parseQuantity(stockRows.first['stock']);

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
          if ((quantity - refundableQty).abs() < _quantityEpsilon) {
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
            'marked_price': unitPrice,
            'price_category_used': originalPriceCategory,
            'cost_price_snapshot': costPriceSnapshot,
            'customer_pricing_applied': customerPricingApplied ? 1 : 0,
            'customer_pricing_type': customerPricingApplied
                ? customerPricingType
                : 'none',
            'customer_pricing_rule_id': customerPricingApplied
                ? customerPricingRuleId
                : null,
            'customer_pricing_original_price': customerPricingApplied
                ? customerPricingOriginalPrice
                : 0.0,
            'customer_pricing_final_price': customerPricingApplied
                ? customerPricingFinalPrice
                : 0.0,
            'customer_pricing_discount_amount': customerPricingApplied
                ? customerPricingDiscountAmount
                : 0.0,
            'customer_pricing_note': customerPricingApplied
                ? customerPricingNote
                : null,
            'quantity': quantity,
            'base_line_total': refundLineTotal,
            'item_discount_type': 'none',
            'item_discount_value': 0.0,
            'explicit_item_discount_amount': 0.0,
            'cart_discount_amount': 0.0,
            'item_discount_amount': 0.0,
            'line_total': -refundLineTotal,
            'created_at': now,
          });

          await _insertInventoryMovement(
            txn,
            barcode: barcode,
            productName: productName,
            actionType: 'refund',
            quantityChange: quantity,
            stockBefore: stockBefore,
            stockAfter: stockBefore + quantity,
            priceType: originalPriceCategory,
            referenceId: refundSaleId,
            referenceType: 'refund',
            reason: refundReason.trim(),
            performedBy: cashierName,
            createdAt: now,
          );

          syncItems.add({
            'product': {
              'barcode': barcode,
              'name': productName,
              'price': unitPrice,
              'cost_price': costPriceSnapshot,
            },
            'quantity': quantity,
            'unit_price_used': unitPrice,
            'price_type_used': originalPriceCategory,
            'customer_pricing_applied': customerPricingApplied ? 1 : 0,
            'customer_pricing_type': customerPricingApplied
                ? customerPricingType
                : 'none',
            'customer_pricing_rule_id': customerPricingApplied
                ? customerPricingRuleId
                : null,
            'customer_pricing_original_price': customerPricingApplied
                ? customerPricingOriginalPrice
                : 0.0,
            'customer_pricing_final_price': customerPricingApplied
                ? customerPricingFinalPrice
                : 0.0,
            'customer_pricing_discount_amount': customerPricingApplied
                ? customerPricingDiscountAmount
                : 0.0,
            'customer_pricing_note': customerPricingApplied
                ? customerPricingNote
                : null,
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
          'created_at': now,
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

  Future<bool> updateProductPriceLocal(
    String barcode,
    double newPrice, {
    String priceType = 'selling',
    String? changedBy,
    String? reason,
    bool? saleEnabled,
  }) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        final rows = await txn.query(
          'products',
          columns: [
            'name',
            'price',
            'cost_price',
            'selling_price',
            'wholesale_price',
            'sale_price',
            'sale_enabled',
          ],
          where: 'barcode = ?',
          whereArgs: [barcode],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception('Product not found for barcode $barcode.');
        }

        final row = rows.first;
        final productName = (row['name'] ?? 'Unknown product').toString();
        final normalizedPriceType = priceType == 'cost'
            ? 'cost'
            : _normalizePriceType(priceType);

        final oldPrice = normalizedPriceType == 'cost'
            ? _parseDouble(row['cost_price'])
            : normalizedPriceType == 'wholesale'
            ? _parseDouble(row['wholesale_price'])
            : normalizedPriceType == 'sale'
            ? _parseDouble(row['sale_price'])
            : _parseDouble(row['selling_price'] ?? row['price']);

        final updates = <String, Object?>{
          'updated_at': now,
          'last_price_updated_at': now,
        };

        switch (normalizedPriceType) {
          case 'cost':
            updates['cost_price'] = newPrice;
            break;
          case 'wholesale':
            updates['wholesale_price'] = newPrice;
            break;
          case 'sale':
            updates['sale_price'] = newPrice;
            updates['sale_enabled'] = saleEnabled == null
                ? 1
                : (saleEnabled ? 1 : 0);
            break;
          case 'selling':
          default:
            updates['selling_price'] = newPrice;
            updates['price'] = newPrice;
            break;
        }

        await txn.update(
          'products',
          updates,
          where: 'barcode = ?',
          whereArgs: [barcode],
        );

        await _insertInventoryMovement(
          txn,
          barcode: barcode,
          productName: productName,
          actionType: _mapPriceActionType(normalizedPriceType),
          oldPrice: oldPrice,
          newPrice: newPrice,
          priceType: normalizedPriceType,
          reason: reason,
          performedBy: changedBy,
          createdAt: now,
        );

        if (normalizedPriceType == 'selling' &&
            oldPrice > 0 &&
            (oldPrice - newPrice).abs() > 0.000001) {
          await _upsertProductLabelPriceHistory(
            txn,
            barcode: barcode,
            productName: productName,
            labelPrice: oldPrice,
            oldPrice: oldPrice,
            newPrice: newPrice,
            priceType: normalizedPriceType,
            changedBy: changedBy,
            reason: reason,
            createdAt: now,
          );
        }

        final syncData = jsonEncode({
          'barcode': barcode,
          'new_price': newPrice,
          'price_type': normalizedPriceType,
          'sale_enabled': saleEnabled,
          'reason': reason,
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

  Future<void> _upsertProductLabelPriceHistory(
    DatabaseExecutor executor, {
    required String barcode,
    required String productName,
    required double labelPrice,
    required double oldPrice,
    required double newPrice,
    required String priceType,
    String? changedBy,
    String? reason,
    required String createdAt,
  }) async {
    final normalizedPriceType = _normalizePriceType(priceType);
    final roundedLabelPrice = _roundMoney(labelPrice);
    final existing = await executor.query(
      'product_price_history',
      columns: ['id'],
      where:
          'barcode = ? AND price_type = ? AND ABS(label_price - ?) < 0.000001 AND is_active = 1',
      whereArgs: [barcode, normalizedPriceType, roundedLabelPrice],
      limit: 1,
    );

    final row = {
      'barcode': barcode,
      'product_name': productName,
      'price_type': normalizedPriceType,
      'label_price': roundedLabelPrice,
      'old_price': _roundMoney(oldPrice),
      'new_price': _roundMoney(newPrice),
      'is_active': 1,
      'created_by': changedBy?.trim(),
      'reason': reason?.trim(),
      'effective_from': createdAt,
      'updated_at': createdAt,
    };

    if (existing.isEmpty) {
      await executor.insert('product_price_history', {
        ...row,
        'created_at': createdAt,
      });
    } else {
      await executor.update(
        'product_price_history',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }

    await _limitActiveProductLabelPrices(
      executor,
      barcode: barcode,
      priceType: normalizedPriceType,
    );
  }

  Future<void> _limitActiveProductLabelPrices(
    DatabaseExecutor executor, {
    required String barcode,
    required String priceType,
    int keepLatest = _maxActiveLabelPricesPerProduct,
  }) async {
    final safeLimit = keepLatest < 0 ? 0 : keepLatest;
    final normalizedPriceType = _normalizePriceType(priceType);
    final activeRows = await executor.query(
      'product_price_history',
      columns: ['id'],
      where: 'barcode = ? AND price_type = ? AND is_active = 1',
      whereArgs: [barcode, normalizedPriceType],
      orderBy: 'datetime(updated_at) DESC, datetime(created_at) DESC, id DESC',
    );

    if (activeRows.length <= safeLimit) return;

    final idsToDeactivate = <int>[];
    for (final row in activeRows.skip(safeLimit)) {
      final id = (row['id'] as num?)?.toInt();
      if (id != null) {
        idsToDeactivate.add(id);
      }
    }

    if (idsToDeactivate.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(idsToDeactivate.length, '?').join(',');

    await executor.update(
      'product_price_history',
      {'is_active': 0, 'effective_to': now, 'updated_at': now},
      where: 'id IN ($placeholders)',
      whereArgs: idsToDeactivate,
    );
  }

  Future<List<Map<String, dynamic>>> getActiveLabelPricesForProduct(
    String barcode, {
    String priceType = 'selling',
    int limit = _maxActiveLabelPricesPerProduct,
  }) async {
    final db = await database;
    final normalizedPriceType = _normalizePriceType(priceType);
    final safeLimit = limit < 0 ? 0 : limit;

    final rows = await db.query(
      'product_price_history',
      where: 'barcode = ? AND price_type = ? AND is_active = 1',
      whereArgs: [barcode, normalizedPriceType],
      orderBy: 'datetime(updated_at) DESC, datetime(created_at) DESC, id DESC',
      limit: safeLimit == 0 ? null : safeLimit,
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<bool> deactivateLabelPrice(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final updated = await db.update(
      'product_price_history',
      {'is_active': 0, 'effective_to': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    return updated > 0;
  }

  Future<Map<String, dynamic>?> findUserByPin(String pin) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'pin = ?',
      whereArgs: [pin],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first);
    }

    return null;
  }

  Future<Map<String, dynamic>?> authenticateUser(String pin) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'pin = ? AND is_active = 1',
      whereArgs: [pin],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first);
    }

    return null;
  }

  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final db = await database;

    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first);
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> getUsers({
    String search = '',
    String role = 'all',
    String status = 'all',
  }) async {
    final db = await database;
    final trimmedSearch = search.trim().toLowerCase();
    final normalizedRole = role.trim().toLowerCase();
    final normalizedStatus = _normalizeUserStatusFilter(status);

    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (normalizedRole == 'manager' || normalizedRole == 'cashier') {
      whereClauses.add('role = ?');
      whereArgs.add(normalizedRole);
    }

    if (normalizedStatus == 'active') {
      whereClauses.add('is_active = 1');
    } else if (normalizedStatus == 'inactive') {
      whereClauses.add('is_active = 0');
    }

    if (trimmedSearch.isNotEmpty) {
      whereClauses.add(
        '(LOWER(name) LIKE ? OR LOWER(role) LIKE ? OR pin LIKE ?)',
      );
      final pattern = '%$trimmedSearch%';
      whereArgs
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    final rows = await db.query(
      'users',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy:
          'is_active DESC, role ASC, has_full_access DESC, name COLLATE NOCASE ASC',
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> getUserSummaryCounts() async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS total_users,
        COALESCE(SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END), 0) AS active_users,
        COALESCE(SUM(CASE WHEN role = 'manager' THEN 1 ELSE 0 END), 0) AS managers,
        COALESCE(SUM(CASE WHEN role = 'cashier' THEN 1 ELSE 0 END), 0) AS cashiers
      FROM users
      ''');

    final row = rows.first;
    return {
      'total_users': (row['total_users'] as num?)?.toInt() ?? 0,
      'active_users': (row['active_users'] as num?)?.toInt() ?? 0,
      'managers': (row['managers'] as num?)?.toInt() ?? 0,
      'cashiers': (row['cashiers'] as num?)?.toInt() ?? 0,
    };
  }

  Future<int> createUser({
    required String name,
    required String role,
    required String pin,
    int? actorUserId,
    String? actorName,
  }) async {
    final db = await database;
    final trimmedName = name.trim();
    final trimmedPin = pin.trim();
    final normalizedRole = _normalizeUserRole(role);

    if (trimmedName.isEmpty) {
      throw Exception('User name is required.');
    }

    if (!RegExp(r'^\d{4}$').hasMatch(trimmedPin)) {
      throw Exception('PIN must be exactly 4 digits.');
    }

    late int userId;

    await db.transaction((txn) async {
      final existingPin = await txn.query(
        'users',
        columns: ['id'],
        where: 'pin = ?',
        whereArgs: [trimmedPin],
        limit: 1,
      );

      if (existingPin.isNotEmpty) {
        throw Exception('PIN is already used by another user.');
      }

      final now = DateTime.now().toIso8601String();

      userId = await txn.insert('users', {
        'name': trimmedName,
        'role': normalizedRole,
        'pin': trimmedPin,
        'is_active': 1,
        'has_full_access': 0,
        'created_at': now,
        'updated_at': now,
        'last_login_at': null,
        'created_by': actorUserId,
        'updated_by': actorUserId,
      });

      await _insertUserLog(
        txn,
        actorUserId: actorUserId,
        actorName: actorName,
        actionType: 'user_created',
        targetUserId: userId,
        targetUserName: trimmedName,
        description: _buildUserActionDescription(
          'user_created',
          targetUserName: trimmedName,
          targetRole: normalizedRole,
        ),
        createdAt: now,
      );
    });

    return userId;
  }

  Future<bool> updateUserProfile({
    required int userId,
    required String name,
    required String role,
    int? actorUserId,
    String? actorName,
  }) async {
    final db = await database;
    final trimmedName = name.trim();
    final normalizedRole = _normalizeUserRole(role);

    if (trimmedName.isEmpty) {
      throw Exception('User name is required.');
    }

    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'users',
          columns: ['id', 'name', 'role', 'is_active'],
          where: 'id = ?',
          whereArgs: [userId],
          limit: 1,
        );

        if (existing.isEmpty) {
          throw Exception('User not found.');
        }

        final current = Map<String, dynamic>.from(existing.first);
        final oldRole = _normalizeUserRole(current['role']?.toString());
        final oldName = (current['name'] ?? '').toString().trim();
        final isActive = _parseInt(current['is_active'], fallback: 1) == 1;
        final now = DateTime.now().toIso8601String();

        final roleChanged = oldRole != normalizedRole;

        if (roleChanged &&
            oldRole == 'manager' &&
            normalizedRole != 'manager' &&
            isActive) {
          final activeManagerCount = await _getActiveManagerCountExecutor(txn);
          if (activeManagerCount <= 1) {
            throw Exception(
              'You cannot change the last active manager to cashier.',
            );
          }
        }

        await txn.update(
          'users',
          {
            'name': trimmedName,
            'role': normalizedRole,
            if (normalizedRole == 'manager') 'has_full_access': 0,
            'updated_at': now,
            'updated_by': actorUserId,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );

        await _insertUserLog(
          txn,
          actorUserId: actorUserId,
          actorName: actorName,
          actionType: roleChanged ? 'role_changed' : 'user_updated',
          targetUserId: userId,
          targetUserName: trimmedName,
          description: roleChanged
              ? 'Changed role for $trimmedName from ${_formatUserRoleLabel(oldRole)} to ${_formatUserRoleLabel(normalizedRole)}'
              : oldName == trimmedName
              ? 'Updated user $trimmedName (${_formatUserRoleLabel(normalizedRole)}) details'
              : 'Renamed user $oldName to $trimmedName',
          createdAt: now,
        );
      });

      return true;
    } catch (e) {
      debugPrint('Error updating user profile: $e');
      rethrow;
    }
  }

  Future<bool> resetUserPin({
    required int userId,
    required String newPin,
    int? actorUserId,
    String? actorName,
  }) async {
    final db = await database;
    final trimmedPin = newPin.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(trimmedPin)) {
      throw Exception('PIN must be exactly 4 digits.');
    }

    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'users',
          columns: ['id', 'name'],
          where: 'id = ?',
          whereArgs: [userId],
          limit: 1,
        );

        if (existing.isEmpty) {
          throw Exception('User not found.');
        }

        final duplicatePin = await txn.query(
          'users',
          columns: ['id'],
          where: 'pin = ? AND id != ?',
          whereArgs: [trimmedPin, userId],
          limit: 1,
        );

        if (duplicatePin.isNotEmpty) {
          throw Exception('PIN is already used by another user.');
        }

        final targetName = (existing.first['name'] ?? 'User').toString();
        final now = DateTime.now().toIso8601String();

        await txn.update(
          'users',
          {'pin': trimmedPin, 'updated_at': now, 'updated_by': actorUserId},
          where: 'id = ?',
          whereArgs: [userId],
        );

        await _insertUserLog(
          txn,
          actorUserId: actorUserId,
          actorName: actorName,
          actionType: 'pin_reset',
          targetUserId: userId,
          targetUserName: targetName,
          description: _buildUserActionDescription(
            'pin_reset',
            targetUserName: targetName,
          ),
          createdAt: now,
        );
      });

      return true;
    } catch (e) {
      debugPrint('Error resetting user PIN: $e');
      rethrow;
    }
  }

  Future<bool> setUserActiveStatus({
    required int userId,
    required bool isActive,
    int? actorUserId,
    String? actorName,
  }) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'users',
          columns: ['id', 'name', 'role', 'is_active'],
          where: 'id = ?',
          whereArgs: [userId],
          limit: 1,
        );

        if (existing.isEmpty) {
          throw Exception('User not found.');
        }

        final current = Map<String, dynamic>.from(existing.first);
        final targetName = (current['name'] ?? 'User').toString().trim();
        final currentActive = _parseInt(current['is_active'], fallback: 1) == 1;
        final currentRole = _normalizeUserRole(current['role']?.toString());

        if (currentActive == isActive) {
          return;
        }

        if (!isActive && actorUserId != null && actorUserId == userId) {
          throw Exception(
            'You cannot deactivate your own account while logged in.',
          );
        }

        if (!isActive && currentActive && currentRole == 'manager') {
          final activeManagerCount = await _getActiveManagerCountExecutor(txn);
          if (activeManagerCount <= 1) {
            throw Exception('You cannot deactivate the last active manager.');
          }
        }

        final now = DateTime.now().toIso8601String();

        await txn.update(
          'users',
          {
            'is_active': isActive ? 1 : 0,
            'updated_at': now,
            'updated_by': actorUserId,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );

        await _insertUserLog(
          txn,
          actorUserId: actorUserId,
          actorName: actorName,
          actionType: isActive ? 'user_reactivated' : 'user_deactivated',
          targetUserId: userId,
          targetUserName: targetName,
          description: _buildUserActionDescription(
            isActive ? 'user_reactivated' : 'user_deactivated',
            targetUserName: targetName,
          ),
          createdAt: now,
        );
      });

      return true;
    } catch (e) {
      debugPrint('Error updating user active status: $e');
      rethrow;
    }
  }

  Future<bool> setUserFullAccess({
    required int userId,
    required bool hasFullAccess,
    int? actorUserId,
    String? actorName,
  }) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'users',
          columns: ['id', 'name', 'role', 'has_full_access'],
          where: 'id = ?',
          whereArgs: [userId],
          limit: 1,
        );

        if (existing.isEmpty) {
          throw Exception('User not found.');
        }

        final current = Map<String, dynamic>.from(existing.first);
        final targetName = (current['name'] ?? 'User').toString().trim();
        final currentRole = _normalizeUserRole(current['role']?.toString());
        final currentFullAccess =
            _parseInt(current['has_full_access'], fallback: 0) == 1;

        if (currentRole == 'manager') {
          throw Exception('Managers already have full access by role.');
        }

        if (currentFullAccess == hasFullAccess) {
          return;
        }

        final now = DateTime.now().toIso8601String();

        await txn.update(
          'users',
          {
            'has_full_access': hasFullAccess ? 1 : 0,
            'updated_at': now,
            'updated_by': actorUserId,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );

        await _insertUserLog(
          txn,
          actorUserId: actorUserId,
          actorName: actorName,
          actionType: hasFullAccess
              ? 'full_access_granted'
              : 'full_access_revoked',
          targetUserId: userId,
          targetUserName: targetName,
          description: _buildUserActionDescription(
            hasFullAccess ? 'full_access_granted' : 'full_access_revoked',
            targetUserName: targetName,
          ),
          createdAt: now,
        );
      });

      return true;
    } catch (e) {
      debugPrint('Error updating full access: $e');
      rethrow;
    }
  }

  Future<void> updateUserLastLogin(int userId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'users',
      {'last_login_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> logLoginSuccess({
    required int userId,
    required String userName,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'users',
        {'last_login_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [userId],
      );

      await _insertUserLog(
        txn,
        actorUserId: userId,
        actorName: userName,
        actionType: 'login_success',
        targetUserId: userId,
        targetUserName: userName,
        description: _buildUserActionDescription(
          'login_success',
          targetUserName: userName,
        ),
        createdAt: now,
      );
    });
  }

  Future<void> logLoginFailed({
    String? attemptedPin,
    String? description,
  }) async {
    final db = await database;
    final pinHint = (attemptedPin ?? '').trim();
    final resolvedDescription = description?.trim().isNotEmpty == true
        ? description!.trim()
        : pinHint.isEmpty
        ? 'Failed login attempt'
        : 'Failed login attempt for PIN $pinHint';

    await _insertUserLog(
      db,
      actorUserId: null,
      actorName: 'Unknown',
      actionType: 'login_failed',
      targetUserId: null,
      targetUserName: null,
      description: resolvedDescription,
    );
  }

  Future<void> logLogout({
    required int userId,
    required String userName,
  }) async {
    final db = await database;

    await _insertUserLog(
      db,
      actorUserId: userId,
      actorName: userName,
      actionType: 'logout',
      targetUserId: userId,
      targetUserName: userName,
      description: _buildUserActionDescription(
        'logout',
        targetUserName: userName,
      ),
    );
  }

  Future<void> logManagerApproval({
    required int actorUserId,
    required String actorName,
    int? targetUserId,
    String? targetUserName,
    required String description,
  }) async {
    final db = await database;

    await _insertUserLog(
      db,
      actorUserId: actorUserId,
      actorName: actorName,
      actionType: 'manager_approval',
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      description: description,
    );
  }

  Future<List<Map<String, dynamic>>> getUserLogs({
    String search = '',
    String actionFilter = 'all',
    int? relatedUserId,
    int limit = 200,
  }) async {
    final db = await database;
    final trimmedSearch = search.trim().toLowerCase();
    final normalizedFilter = actionFilter.trim().toLowerCase();

    final whereClauses = <String>[];
    final whereArgs = <Object?>[];

    if (relatedUserId != null && relatedUserId > 0) {
      whereClauses.add('(actor_user_id = ? OR target_user_id = ?)');
      whereArgs
        ..add(relatedUserId)
        ..add(relatedUserId);
    }

    if (normalizedFilter != 'all' && normalizedFilter.isNotEmpty) {
      if (normalizedFilter == 'logins') {
        whereClauses.add(
          "(action_type = 'login_success' OR action_type = 'login_failed' OR action_type = 'logout')",
        );
      } else if (normalizedFilter == 'user_changes') {
        whereClauses.add(
          "(action_type = 'user_created' OR action_type = 'user_updated' OR action_type = 'user_deactivated' OR action_type = 'user_reactivated' OR action_type = 'role_changed' OR action_type = 'full_access_granted' OR action_type = 'full_access_revoked')",
        );
      } else if (normalizedFilter == 'pin_changes') {
        whereClauses.add("action_type = 'pin_reset'");
      } else if (normalizedFilter == 'approvals') {
        whereClauses.add("action_type = 'manager_approval'");
      } else {
        whereClauses.add('action_type = ?');
        whereArgs.add(normalizedFilter);
      }
    }

    if (trimmedSearch.isNotEmpty) {
      whereClauses.add(
        '(LOWER(actor_name) LIKE ? OR LOWER(COALESCE(target_user_name, \'\')) LIKE ? OR LOWER(description) LIKE ?)',
      );
      final pattern = '%$trimmedSearch%';
      whereArgs
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    final rows = await db.query(
      'user_logs',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'datetime(created_at) DESC, id DESC',
      limit: limit,
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> addUserLog({
    int? actorUserId,
    String? actorName,
    required String actionType,
    int? targetUserId,
    String? targetUserName,
    required String description,
  }) async {
    final db = await database;
    await _insertUserLog(
      db,
      actorUserId: actorUserId,
      actorName: actorName,
      actionType: actionType,
      targetUserId: targetUserId,
      targetUserName: targetUserName,
      description: description,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions({
    String? transactionType,
    DateTime? start,
    DateTime? end,
    int? limit = 50,
  }) async {
    final db = await database;

    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    if (transactionType != null && transactionType.isNotEmpty) {
      whereParts.add('s.transaction_type = ?');
      whereArgs.add(transactionType);
    }

    if (start != null) {
      whereParts.add('datetime(s.created_at) >= datetime(?)');
      whereArgs.add(start.toIso8601String());
    }

    if (end != null) {
      whereParts.add('datetime(s.created_at) <= datetime(?)');
      whereArgs.add(end.toIso8601String());
    }

    final whereClause = whereParts.isEmpty
        ? ''
        : 'WHERE ${whereParts.join(' AND ')}';
    final limitClause = limit == null ? '' : 'LIMIT ?';
    final queryArgs = <Object?>[...whereArgs, if (limit != null) limit];

    final rows = await db.rawQuery('''
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
      $limitClause
      ''', queryArgs);

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

    final rows = await db.rawQuery(
      '''
      SELECT
        si.id,
        si.sale_id,
        si.barcode,
        si.product_name,
        si.unit_price,
        si.system_unit_price,
        si.price_override_type,
        si.price_override_reason,
        si.price_override_original_price,
        si.price_override_difference,
        si.price_history_id,
        si.price_override_approved_by,
        si.customer_pricing_applied,
        si.customer_pricing_type,
        si.customer_pricing_rule_id,
        si.customer_pricing_original_price,
        si.customer_pricing_final_price,
        si.customer_pricing_discount_amount,
        si.customer_pricing_note,
        CASE
          WHEN COALESCE(si.marked_price, 0) > 0 THEN si.marked_price
          WHEN COALESCE(p.selling_price, 0) > 0 THEN p.selling_price
          ELSE si.unit_price
        END AS marked_price,
        si.price_category_used,
        si.cost_price_snapshot,
        si.quantity,
        si.base_line_total,
        si.item_discount_type,
        si.item_discount_value,
        si.explicit_item_discount_amount,
        si.cart_discount_amount,
        si.item_discount_amount,
        si.line_total,
        si.created_at
      FROM sale_items si
      LEFT JOIN products p ON p.barcode = si.barcode
      WHERE si.sale_id = ?
      ORDER BY si.id ASC
      ''',
      [saleId],
    );

    return rows
        .map(
          (row) => {
            'id': row['id'],
            'sale_id': row['sale_id'],
            'barcode': row['barcode'],
            'product_name': row['product_name'],
            'unit_price': row['unit_price'],
            'system_unit_price': row['system_unit_price'],
            'price_override_type': row['price_override_type'],
            'price_override_reason': row['price_override_reason'],
            'price_override_original_price':
                row['price_override_original_price'],
            'price_override_difference': row['price_override_difference'],
            'price_history_id': row['price_history_id'],
            'price_override_approved_by': row['price_override_approved_by'],
            'customer_pricing_applied': row['customer_pricing_applied'],
            'customer_pricing_type': row['customer_pricing_type'],
            'customer_pricing_rule_id': row['customer_pricing_rule_id'],
            'customer_pricing_original_price':
                row['customer_pricing_original_price'],
            'customer_pricing_final_price': row['customer_pricing_final_price'],
            'customer_pricing_discount_amount':
                row['customer_pricing_discount_amount'],
            'customer_pricing_note': row['customer_pricing_note'],
            'marked_price': row['marked_price'],
            'price_category_used': row['price_category_used'],
            'cost_price_snapshot': row['cost_price_snapshot'],
            'quantity': row['quantity'],
            'base_line_total': row['base_line_total'],
            'item_discount_type': row['item_discount_type'],
            'item_discount_value': row['item_discount_value'],
            'explicit_item_discount_amount':
                row['explicit_item_discount_amount'],
            'cart_discount_amount': row['cart_discount_amount'],
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
        si.barcode,
        si.product_name,
        si.unit_price,
        si.price_category_used,
        si.cost_price_snapshot,
        si.customer_pricing_applied,
        si.customer_pricing_type,
        si.customer_pricing_rule_id,
        si.customer_pricing_original_price,
        si.customer_pricing_final_price,
        si.customer_pricing_discount_amount,
        si.customer_pricing_note,
        CASE
          WHEN LOWER(COALESCE(MAX(p.quantity_type), '')) = 'weight' THEN 'weight'
          ELSE 'unit'
        END AS quantity_type,
        COALESCE(
          NULLIF(TRIM(MAX(p.unit_label)), ''),
          CASE
            WHEN LOWER(COALESCE(MAX(p.quantity_type), '')) = 'weight' THEN 'kg'
            ELSE 'pcs'
          END
        ) AS unit_label,
        SUM(si.quantity) AS original_quantity,
        COALESCE(SUM(ABS(line_total)), 0) AS original_net_total
      FROM sale_items si
      LEFT JOIN products p ON p.barcode = si.barcode
      WHERE si.sale_id = ?
      GROUP BY
        si.barcode,
        si.product_name,
        si.unit_price,
        si.price_category_used,
        si.cost_price_snapshot,
        si.customer_pricing_applied,
        si.customer_pricing_type,
        si.customer_pricing_rule_id,
        si.customer_pricing_original_price,
        si.customer_pricing_final_price,
        si.customer_pricing_discount_amount,
        si.customer_pricing_note
      ORDER BY si.product_name ASC
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
          'refunded_quantity': _parseQuantity(row['refunded_quantity']),
          'refunded_total': ((row['refunded_total'] as num?) ?? 0).toDouble(),
        },
    };

    return originalItems.map((row) {
      final barcode = (row['barcode'] ?? '').toString();
      final originalQty = _parseQuantity(row['original_quantity']);
      final originalNetTotal = ((row['original_net_total'] as num?) ?? 0)
          .toDouble();

      final refundedQty =
          (refundedMap[barcode]?['refunded_quantity'] as num?)?.toDouble() ??
          0.0;
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
        'price_category_used': row['price_category_used'],
        'cost_price_snapshot': row['cost_price_snapshot'],
        'customer_pricing_applied': row['customer_pricing_applied'],
        'customer_pricing_type': row['customer_pricing_type'],
        'customer_pricing_rule_id': row['customer_pricing_rule_id'],
        'customer_pricing_original_price':
            row['customer_pricing_original_price'],
        'customer_pricing_final_price': row['customer_pricing_final_price'],
        'customer_pricing_discount_amount':
            row['customer_pricing_discount_amount'],
        'customer_pricing_note': row['customer_pricing_note'],
        'quantity_type': row['quantity_type'],
        'unit_label': row['unit_label'],
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

    final saleRow = (await db.rawQuery('''
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
      ''', args)).first;

    final refundRow = (await db.rawQuery('''
      SELECT
        COUNT(*) AS refund_count,
        COALESCE(SUM(ABS(s.total_amount)), 0) AS refund_total
      FROM sales s
      WHERE s.transaction_type = 'refund'
        AND $whereBase
      ''', args)).first;

    final itemRow = (await db.rawQuery('''
      SELECT
        COALESCE(SUM(si.quantity), 0) AS items_sold,
        COUNT(si.id) AS item_line_count
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE s.transaction_type = 'sale'
        AND $whereBase
      ''', args)).first;

    final costRow = (await db.rawQuery('''
      SELECT
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' THEN (si.cost_price_snapshot * si.quantity)
              ELSE -(si.cost_price_snapshot * si.quantity)
            END
          ),
          0
        ) AS net_cost_amount
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE s.transaction_type IN ('sale', 'refund')
        AND $whereBase
      ''', args)).first;

    final grossSales = ((saleRow['gross_sales'] as num?) ?? 0).toDouble();
    final totalDiscounts = ((saleRow['total_discounts'] as num?) ?? 0)
        .toDouble();
    final netSales = ((saleRow['net_sales'] as num?) ?? 0).toDouble();
    final cashSales = ((saleRow['cash_sales'] as num?) ?? 0).toDouble();
    final cardSales = ((saleRow['card_sales'] as num?) ?? 0).toDouble();
    final refundTotal = ((refundRow['refund_total'] as num?) ?? 0).toDouble();
    final saleCount = (saleRow['sale_count'] as num?)?.toInt() ?? 0;
    final refundCount = (refundRow['refund_count'] as num?)?.toInt() ?? 0;
    final itemsSold = (itemRow['items_sold'] as num?)?.toInt() ?? 0;
    final itemLineCount = (itemRow['item_line_count'] as num?)?.toInt() ?? 0;
    final netCostAmount = ((costRow['net_cost_amount'] as num?) ?? 0)
        .toDouble();
    final netAfterRefunds = netSales - refundTotal;
    final estimatedProfit = _roundMoney(netAfterRefunds - netCostAmount);
    final marginPercent = netAfterRefunds <= 0
        ? 0.0
        : _roundMoney((estimatedProfit / netAfterRefunds) * 100);

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
      'net_after_refunds': _roundMoney(netAfterRefunds),
      'cash_sales': _roundMoney(cashSales),
      'card_sales': _roundMoney(cardSales),
      'items_sold': itemsSold,
      'item_line_count': itemLineCount,
      'net_cost_amount': _roundMoney(netCostAmount),
      'estimated_profit': estimatedProfit,
      'margin_percent': marginPercent,
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
        COALESCE(MAX(p.name), MAX(si.product_name)) AS product_name,
        CASE
          WHEN LOWER(COALESCE(MAX(p.quantity_type), '')) = 'weight' THEN 'weight'
          ELSE 'unit'
        END AS quantity_type,
        COALESCE(
          NULLIF(TRIM(MAX(p.unit_label)), ''),
          CASE
            WHEN LOWER(COALESCE(MAX(p.quantity_type), '')) = 'weight' THEN 'kg'
            ELSE 'pcs'
          END
        ) AS unit_label,
        COALESCE(SUM(si.quantity), 0) AS quantity_sold,
        COALESCE(SUM(ABS(si.base_line_total)), 0) AS gross_sales_amount,
        COALESCE(SUM(ABS(si.item_discount_amount)), 0) AS discount_amount,
        COALESCE(SUM(ABS(si.line_total)), 0) AS net_sales_amount
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN products p ON p.barcode = si.barcode
      WHERE ${conditions.join(' AND ')}
      GROUP BY si.barcode
      ORDER BY quantity_sold DESC, net_sales_amount DESC, product_name ASC
      LIMIT ?
      ''',
      [...args, limit],
    );

    return rows
        .map(
          (row) => {
            'barcode': row['barcode'],
            'product_name': row['product_name'],
            'quantity_type': row['quantity_type'],
            'unit_label': row['unit_label'],
            'quantity_sold': ((row['quantity_sold'] as num?) ?? 0).toDouble(),
            'gross_sales_amount': ((row['gross_sales_amount'] as num?) ?? 0)
                .toDouble(),
            'discount_amount': ((row['discount_amount'] as num?) ?? 0)
                .toDouble(),
            'net_sales_amount': ((row['net_sales_amount'] as num?) ?? 0)
                .toDouble(),
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

    return rows.map((row) {
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
        'total_discounts': ((row['total_discounts'] as num?) ?? 0).toDouble(),
        'net_sales': netSales,
        'refund_total': refundTotal,
        'net_after_refunds': _roundMoney(netSales - refundTotal),
        'cash_sales': ((row['cash_sales'] as num?) ?? 0).toDouble(),
        'card_sales': ((row['card_sales'] as num?) ?? 0).toDouble(),
      };
    }).toList();
  }

  Future<int> saveHeldCart({
    required String cartName,
    required String cashierName,
    required bool isRefundMode,
    required String discountType,
    required double discountValue,
    required List<Map<String, dynamic>> items,
    String selectedPriceType = 'selling',
    Customer? selectedCustomer,
  }) async {
    final db = await database;
    await _ensureHeldCartCustomerSchema(db);

    if (items.isEmpty) {
      throw Exception('Cannot hold an empty cart.');
    }

    final safeName = cartName.trim().isEmpty ? 'Held Cart' : cartName.trim();
    final now = DateTime.now().toIso8601String();

    return db.insert('held_carts', {
      'cart_name': safeName,
      'cashier_name': cashierName,
      'is_refund_mode': isRefundMode ? 1 : 0,
      'selected_price_type': isRefundMode
          ? 'selling'
          : _normalizePriceType(selectedPriceType),
      'discount_type': isRefundMode
          ? 'none'
          : _normalizeDiscountType(discountType),
      'discount_value': isRefundMode ? 0.0 : discountValue,
      'customer_id': selectedCustomer?.id,
      'customer_name_snapshot': selectedCustomer?.displayName,
      'customer_phone_snapshot': selectedCustomer?.hasPhone == true
          ? selectedCustomer?.phone?.trim()
          : null,
      'customer_code_snapshot': selectedCustomer?.displayCode,
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
      final decoded = _decodeHeldCartItemsJson(itemsJson);

      double itemCount = 0.0;
      double subtotal = 0;

      for (final raw in decoded) {
        final item = Map<String, dynamic>.from(raw);
        final quantity = _parseQuantity(item['quantity']);
        final lineTotal = ((item['line_total'] as num?) ?? 0).toDouble();

        itemCount = _roundQuantity(itemCount + quantity);
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
        'selected_price_type': (row['selected_price_type'] ?? 'selling')
            .toString(),
        'discount_type': discountType,
        'discount_value': discountValue,
        'customer_id': row['customer_id'],
        'customer_name_snapshot': row['customer_name_snapshot'],
        'customer_phone_snapshot': row['customer_phone_snapshot'],
        'customer_code_snapshot': row['customer_code_snapshot'],
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
      final decodedItems = _decodeHeldCartItemsJson(itemsJson);
      final hadStoredItems =
          itemsJson.trim().isNotEmpty && itemsJson.trim() != '[]';

      if (hadStoredItems && decodedItems.isEmpty) {
        result = {
          'resume_error': 'This held cart contains invalid saved item data.',
        };
        return;
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
        'selected_price_type': (row['selected_price_type'] ?? 'selling')
            .toString(),
        'discount_type': (row['discount_type'] ?? 'none').toString(),
        'discount_value': ((row['discount_value'] as num?) ?? 0).toDouble(),
        'customer_id': row['customer_id'],
        'customer_name_snapshot': row['customer_name_snapshot'],
        'customer_phone_snapshot': row['customer_phone_snapshot'],
        'customer_code_snapshot': row['customer_code_snapshot'],
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
        batch.insert('suppliers', {
          'id': supplier.id,
          'name': supplier.name,
          'phone': supplier.phone,
          'updated_at': supplier.updatedAt.isEmpty ? now : supplier.updatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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

    return rows
        .map((row) => PosSupplier.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<PosSupplier>> getMappedSuppliersForProduct(String barcode) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        m.supplier_id AS id,
        COALESCE(NULLIF(TRIM(s.name), ''), m.supplier_name) AS name,
        COALESCE(s.phone, '') AS phone,
        COALESCE(s.updated_at, m.updated_at) AS updated_at,
        m.is_preferred
      FROM supplier_product_mappings m
      LEFT JOIN suppliers s ON s.id = m.supplier_id
      WHERE m.barcode = ?
      ORDER BY m.is_preferred DESC, LOWER(COALESCE(NULLIF(TRIM(s.name), ''), m.supplier_name)) ASC
      ''',
      [barcode],
    );

    return rows
        .map((row) => PosSupplier.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<int> insertStockReceipt({
    int? backendReceiptId,
    int? purchaseOrderId,
    String? purchaseOrderNumber,
    required String barcode,
    required String productName,
    required num quantity,
    required int supplierId,
    required String supplierName,
    required double cost,
    required String referenceNote,
    String invoiceNumber = '',
    String deliveryNoteNumber = '',
    String grnReference = '',
    String batchNumber = '',
    DateTime? expiryDate,
    required String cashierName,
    String backendStatus = 'synced',
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final safeQuantity = _roundQuantity(quantity);
      final safeExpiryDate = expiryDate == null
          ? null
          : _formatDateOnly(expiryDate);
      final receiptId = await txn.insert('stock_receipts', {
        'backend_receipt_id': backendReceiptId,
        'purchase_order_id': purchaseOrderId,
        'purchase_order_number': purchaseOrderNumber?.trim(),
        'purchase_order_receipt_id': null,
        'barcode': barcode,
        'product_name': productName,
        'quantity': safeQuantity,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'cost': _roundMoney(cost),
        'reference_note': referenceNote.trim(),
        'invoice_number': invoiceNumber.trim(),
        'delivery_note_number': deliveryNoteNumber.trim(),
        'grn_reference': grnReference.trim(),
        'expiry_batch_id': null,
        'batch_number': batchNumber.trim(),
        'expiry_date': safeExpiryDate,
        'cashier_name': cashierName.trim(),
        'is_reversed': 0,
        'reversed_at': '',
        'reversal_reason': '',
        'created_at': now,
        'backend_status': backendStatus,
      });

      if (safeExpiryDate != null && _isPositiveQuantity(safeQuantity)) {
        final batchId = await txn.insert('expiry_batches', {
          'receipt_id': receiptId,
          'barcode': barcode.trim(),
          'product_name': productName.trim(),
          'batch_number': batchNumber.trim(),
          'supplier_id': supplierId,
          'supplier_name': supplierName.trim(),
          'received_quantity': safeQuantity,
          'remaining_quantity': safeQuantity,
          'expiry_date': safeExpiryDate,
          'status': 'active',
          'last_checked_at': '',
          'created_at': now,
          'updated_at': now,
        });

        await txn.update(
          'stock_receipts',
          {'expiry_batch_id': batchId},
          where: 'id = ?',
          whereArgs: [receiptId],
        );
      }

      return receiptId;
    });
  }

  Future<void> upsertSupplierProductMapping(
    SupplierProductMapping mapping,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      if (mapping.isPreferred) {
        await txn.update(
          'supplier_product_mappings',
          {'is_preferred': 0},
          where: 'barcode = ?',
          whereArgs: [mapping.barcode],
        );
      }

      await txn.insert(
        'supplier_product_mappings',
        mapping.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteSupplierProductMapping(int id) async {
    final db = await database;
    await db.delete(
      'supplier_product_mappings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<SupplierProductMapping>> getSupplierProductMappings({
    int? supplierId,
    String search = '',
    int limit = 500,
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
      'supplier_product_mappings',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereClauses.isEmpty ? null : whereArgs,
      orderBy:
          'is_preferred DESC, supplier_name COLLATE NOCASE ASC, product_name COLLATE NOCASE ASC',
      limit: limit,
    );

    return rows
        .map(
          (row) =>
              SupplierProductMapping.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<SupplierProductMapping>> getMappingsForProduct(
    String barcode,
  ) async {
    final db = await database;
    final rows = await db.query(
      'supplier_product_mappings',
      where: 'barcode = ?',
      whereArgs: [barcode],
      orderBy: 'is_preferred DESC, supplier_name COLLATE NOCASE ASC',
    );
    return rows
        .map(
          (row) =>
              SupplierProductMapping.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<SupplierProductMapping?> getPreferredSupplierMapping(
    String barcode,
  ) async {
    final db = await database;
    final rows = await db.query(
      'supplier_product_mappings',
      where: 'barcode = ? AND is_preferred = 1',
      whereArgs: [barcode],
      orderBy: 'updated_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return SupplierProductMapping.fromMap(
      Map<String, dynamic>.from(rows.first),
    );
  }

  Future<Map<String, dynamic>> getSupplierProductMappingSummary({
    int? supplierId,
  }) async {
    final db = await database;
    final whereClause = supplierId == null ? '' : 'WHERE supplier_id = ?';
    final args = supplierId == null ? <Object?>[] : <Object?>[supplierId];

    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS mapping_count,
        COALESCE(SUM(CASE WHEN is_preferred = 1 THEN 1 ELSE 0 END), 0) AS preferred_count,
        COALESCE(AVG(default_unit_cost), 0) AS avg_cost
      FROM supplier_product_mappings
      $whereClause
      ''', args);

    final row = rows.first;
    return {
      'mapping_count': (row['mapping_count'] as num?)?.toInt() ?? 0,
      'preferred_count': (row['preferred_count'] as num?)?.toInt() ?? 0,
      'avg_cost': ((row['avg_cost'] as num?) ?? 0).toDouble(),
    };
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
        '(LOWER(product_name) LIKE ? OR LOWER(barcode) LIKE ? OR LOWER(supplier_name) LIKE ? OR LOWER(COALESCE(batch_number, "")) LIKE ? OR COALESCE(expiry_date, "") LIKE ?)',
      );
      whereArgs
        ..add('%$trimmed%')
        ..add('%$trimmed%')
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

    return rows
        .map(
          (row) => StockReceiptRecord.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getStockReceiptSummary({int? supplierId}) async {
    final db = await database;

    final whereClause = supplierId == null ? '' : 'WHERE supplier_id = ?';
    final args = supplierId == null ? <Object?>[] : <Object?>[supplierId];

    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS receipt_count,
        COALESCE(SUM(quantity), 0) AS total_units,
        COALESCE(SUM(cost), 0) AS total_cost
      FROM stock_receipts
      $whereClause
      ''', args);

    final row = rows.first;
    return {
      'receipt_count': (row['receipt_count'] as num?)?.toInt() ?? 0,
      'total_units': _roundQuantity((row['total_units'] as num?) ?? 0),
      'total_cost': ((row['total_cost'] as num?) ?? 0).toDouble(),
    };
  }

  Future<List<Map<String, dynamic>>> getInventoryMovements({
    int limit = 50,
    String? barcode,
    List<String>? actionTypes,
    String searchQuery = '',
    DateTime? onDate,
    bool hydrateSuppliers = true,
  }) async {
    final db = await database;

    final clauses = <String>[];
    final args = <Object?>[];

    if (barcode != null && barcode.trim().isNotEmpty) {
      clauses.add('barcode = ?');
      args.add(barcode.trim());
    }

    if (actionTypes != null && actionTypes.isNotEmpty) {
      final placeholders = List.filled(actionTypes.length, '?').join(',');
      clauses.add('action_type IN ($placeholders)');
      args.addAll(actionTypes);
    }

    final trimmedSearch = searchQuery.trim();
    if (trimmedSearch.isNotEmpty) {
      clauses.add(
        "(product_name LIKE ? OR barcode LIKE ? OR COALESCE(reason, '') LIKE ? OR COALESCE(supplier_name, '') LIKE ?)",
      );
      final pattern = '%$trimmedSearch%';
      args
        ..add(pattern)
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    if (onDate != null) {
      final start = DateTime(onDate.year, onDate.month, onDate.day);
      final end = start.add(const Duration(days: 1));
      clauses.add('created_at >= ? AND created_at < ?');
      args
        ..add(start.toIso8601String())
        ..add(end.toIso8601String());
    }

    final rows = await db.query(
      'inventory_movements',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );

    final movements = rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (hydrateSuppliers) {
      for (final movement in movements) {
        await hydrateInventoryMovementSupplierData(movement, db: db);
      }
    }

    return movements;
  }

  Future<Map<String, dynamic>> hydrateInventoryMovementSupplierData(
    Map<String, dynamic> movement, {
    Database? db,
  }) async {
    final actionType = (movement['action_type'] ?? '').toString();
    final existingSupplier = (movement['supplier_name'] ?? '')
        .toString()
        .trim();
    if (actionType != 'stock_receive') {
      return movement;
    }

    final targetDb = db ?? await database;
    final movementBarcode = (movement['barcode'] ?? '').toString().trim();
    final quantity = _parseQuantity(movement['quantity_change']).abs();
    final createdAt = (movement['created_at'] ?? '').toString();
    if (movementBarcode.isEmpty || quantity <= 0) {
      return movement;
    }

    List<Map<String, dynamic>> receiptRows = [];
    try {
      final raw = await targetDb.rawQuery(
        """
          SELECT
            supplier_id,
            supplier_name,
            cost,
            reference_note,
            batch_number,
            expiry_date,
            created_at
          FROM stock_receipts
          WHERE barcode = ?
            AND quantity = ?
            AND COALESCE(is_reversed, 0) = 0
          ORDER BY ABS(julianday(created_at) - julianday(?)) ASC, id DESC
          LIMIT 1
          """,
        [movementBarcode, quantity, createdAt],
      );
      receiptRows = raw.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      final raw = await targetDb.query(
        'stock_receipts',
        columns: [
          'supplier_id',
          'supplier_name',
          'cost',
          'reference_note',
          'batch_number',
          'expiry_date',
          'created_at',
        ],
        where: 'barcode = ? AND quantity = ? AND COALESCE(is_reversed, 0) = 0',
        whereArgs: [movementBarcode, quantity],
        orderBy: 'created_at DESC, id DESC',
        limit: 1,
      );
      receiptRows = raw.map((row) => Map<String, dynamic>.from(row)).toList();
    }

    if (receiptRows.isEmpty) {
      return movement;
    }

    final receipt = receiptRows.first;
    movement['supplier_id'] = receipt['supplier_id'];
    final receiptSupplier = (receipt['supplier_name'] ?? '').toString();
    movement['supplier_name'] = existingSupplier.isNotEmpty
        ? existingSupplier
        : receiptSupplier;
    movement['supplier_cost'] = receipt['cost'];
    movement['batch_number'] = (receipt['batch_number'] ?? '').toString();
    movement['expiry_date'] = (receipt['expiry_date'] ?? '').toString();
    if ((movement['reason'] ?? '').toString().trim().isEmpty) {
      final note = (receipt['reference_note'] ?? '').toString().trim();
      if (note.isNotEmpty) {
        movement['reason'] = note;
      }
    }

    return movement;
  }

  Future<bool> receiveStockLocal(
    String barcode,
    num quantity, {
    double? unitCost,
    String? performedBy,
    String? reason,
    int? supplierId,
    String? supplierName,
  }) async {
    final safeQuantity = _roundQuantity(quantity);
    if (barcode.trim().isEmpty || !_isPositiveQuantity(safeQuantity))
      return false;

    final db = await database;

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final rows = await txn.query(
          'products',
          columns: ['name', 'stock', 'cost_price'],
          where: 'barcode = ?',
          whereArgs: [barcode.trim()],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception('Product not found for barcode $barcode');
        }

        final row = rows.first;
        final productName = (row['name'] ?? 'Unknown product').toString();
        final stockBefore = _parseQuantity(row['stock']);
        final stockAfter = _roundQuantity(stockBefore + safeQuantity);

        final updates = <String, Object?>{
          'stock': stockAfter,
          'updated_at': now,
        };

        if (unitCost != null && unitCost >= 0) {
          updates['cost_price'] = _roundMoney(unitCost);
          updates['last_price_updated_at'] = now;
        }

        await txn.update(
          'products',
          updates,
          where: 'barcode = ?',
          whereArgs: [barcode.trim()],
        );

        await _insertInventoryMovement(
          txn,
          barcode: barcode.trim(),
          productName: productName,
          actionType: 'stock_receive',
          quantityChange: safeQuantity,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: reason,
          performedBy: performedBy,
          supplierId: supplierId,
          supplierName: supplierName?.trim().isEmpty == true
              ? null
              : supplierName?.trim(),
          createdAt: now,
        );

        final syncData = jsonEncode({
          'barcode': barcode.trim(),
          'quantity': safeQuantity,
          'unit_cost': unitCost,
          'reason': reason,
          'performed_by': performedBy,
          'supplier_id': supplierId,
          'supplier_name': supplierName,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
        });

        await txn.insert('sync_queue', {
          'type': 'STOCK_RECEIVE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error receiving stock: $e');
      return false;
    }
  }

  Future<bool> adjustStockLocal(
    String barcode, {
    required String adjustmentType,
    required num quantity,
    String? performedBy,
    String? reason,
  }) async {
    final safeQuantity = _roundQuantity(quantity);
    if (barcode.trim().isEmpty) return false;
    if (adjustmentType != 'add' &&
        adjustmentType != 'remove' &&
        adjustmentType != 'set') {
      return false;
    }
    if (safeQuantity < 0) return false;
    if (adjustmentType != 'set' && !_isPositiveQuantity(safeQuantity))
      return false;

    final db = await database;

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final rows = await txn.query(
          'products',
          columns: ['name', 'stock'],
          where: 'barcode = ?',
          whereArgs: [barcode.trim()],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception('Product not found for barcode $barcode');
        }

        final row = rows.first;
        final productName = (row['name'] ?? 'Unknown product').toString();
        final stockBefore = _parseQuantity(row['stock']);

        late final double stockAfter;
        late final double quantityChange;
        late final String actionType;

        switch (adjustmentType) {
          case 'add':
            stockAfter = _roundQuantity(stockBefore + safeQuantity);
            quantityChange = safeQuantity;
            actionType = 'stock_adjust_add';
            break;
          case 'remove':
            if (_quantityExceeds(safeQuantity, stockBefore)) {
              throw Exception('Cannot remove more than available stock.');
            }
            stockAfter = _roundQuantity(stockBefore - safeQuantity);
            quantityChange = _roundQuantity(-safeQuantity);
            actionType = 'stock_adjust_remove';
            break;
          case 'set':
            stockAfter = safeQuantity;
            quantityChange = _roundQuantity(safeQuantity - stockBefore);
            actionType = 'stock_adjust_set';
            break;
          default:
            throw Exception('Unsupported adjustment type.');
        }

        if (quantityChange.abs() < _quantityEpsilon) {
          throw Exception('No stock change detected.');
        }

        await txn.update(
          'products',
          {'stock': stockAfter, 'updated_at': now},
          where: 'barcode = ?',
          whereArgs: [barcode.trim()],
        );

        await _insertInventoryMovement(
          txn,
          barcode: barcode.trim(),
          productName: productName,
          actionType: actionType,
          quantityChange: quantityChange,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: reason,
          performedBy: performedBy,
          createdAt: now,
        );

        final backendAdjustmentType = adjustmentType == 'add'
            ? 'increase'
            : adjustmentType == 'remove'
            ? 'decrease'
            : 'set_exact';

        final syncData = jsonEncode({
          'barcode': barcode.trim(),
          'adjustment_type': backendAdjustmentType,
          'quantity': safeQuantity,
          'reason': reason,
          'performed_by': performedBy,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
        });

        await txn.insert('sync_queue', {
          'type': 'STOCK_ADJUST',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error adjusting stock: $e');
      return false;
    }
  }

  Future<bool> updateProductMinStockLevelLocal(
    String barcode,
    int minStockLevel, {
    String? changedBy,
  }) async {
    if (barcode.trim().isEmpty || minStockLevel < 0) return false;

    final db = await database;

    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final rows = await txn.query(
          'products',
          columns: ['name', 'min_stock_level'],
          where: 'barcode = ?',
          whereArgs: [barcode.trim()],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception('Product not found for barcode $barcode');
        }

        final row = rows.first;
        final productName = (row['name'] ?? 'Unknown product').toString();
        final beforeLevel = _parseInt(row['min_stock_level']);

        await txn.update(
          'products',
          {'min_stock_level': minStockLevel, 'updated_at': now},
          where: 'barcode = ?',
          whereArgs: [barcode.trim()],
        );

        await _insertInventoryMovement(
          txn,
          barcode: barcode.trim(),
          productName: productName,
          actionType: 'min_stock_change',
          quantityChange: minStockLevel - beforeLevel,
          stockBefore: beforeLevel,
          stockAfter: minStockLevel,
          performedBy: changedBy,
          createdAt: now,
        );

        final syncData = jsonEncode({
          'barcode': barcode.trim(),
          'min_stock_level': minStockLevel,
          'reason': 'Minimum stock level updated',
          'performed_by': changedBy,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
        });

        await txn.insert('sync_queue', {
          'type': 'MIN_STOCK_UPDATE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error updating minimum stock: $e');
      return false;
    }
  }

  Future<bool> createProductLocal({
    required String barcode,
    required String name,
    required String category,
    required double costPrice,
    required double sellingPrice,
    ProductQuantityType quantityType = ProductQuantityType.unit,
    String? unitLabel,
    double? wholesalePrice,
    double? salePrice,
    required bool saleEnabled,
    required int openingStock,
    required int minStockLevel,
    bool trackExpiry = false,
    int expiryAlertDays = 30,
    String? changedBy,
  }) async {
    final trimmedBarcode = barcode.trim();
    final trimmedName = name.trim();
    final trimmedCategory = category.trim().isEmpty
        ? 'General'
        : category.trim();

    if (trimmedBarcode.isEmpty || trimmedName.isEmpty) return false;
    if (sellingPrice <= 0 ||
        costPrice < 0 ||
        openingStock < 0 ||
        minStockLevel < 0 ||
        expiryAlertDays < 1) {
      return false;
    }
    if (saleEnabled && (salePrice == null || salePrice <= 0)) {
      return false;
    }

    final db = await database;

    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'products',
          columns: ['id'],
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
          limit: 1,
        );

        if (existing.isNotEmpty) {
          throw Exception(
            'Product with barcode $trimmedBarcode already exists.',
          );
        }

        final now = DateTime.now().toIso8601String();
        final resolvedWholesale = _roundMoney(
          (wholesalePrice == null || wholesalePrice <= 0)
              ? sellingPrice
              : wholesalePrice,
        );
        final resolvedSalePrice = salePrice == null
            ? null
            : _roundMoney(salePrice);
        final resolvedQuantityType = quantityType.dbValue;
        final resolvedUnitLabel = _normalizeProductUnitLabel(
          quantityType: resolvedQuantityType,
          unitLabel: unitLabel,
        );

        await txn.insert('products', {
          'barcode': trimmedBarcode,
          'name': trimmedName,
          'category': trimmedCategory,
          'quantity_type': resolvedQuantityType,
          'unit_label': resolvedUnitLabel,
          'price': _roundMoney(sellingPrice),
          'cost_price': _roundMoney(costPrice),
          'selling_price': _roundMoney(sellingPrice),
          'wholesale_price': resolvedWholesale,
          'sale_price': resolvedSalePrice,
          'sale_enabled': saleEnabled ? 1 : 0,
          'stock': openingStock,
          'min_stock_level': minStockLevel,
          'track_expiry': trackExpiry ? 1 : 0,
          'expiry_alert_days': expiryAlertDays,
          'is_active': 1,
          'updated_at': now,
          'last_price_updated_at': now,
        });

        await _insertInventoryMovement(
          txn,
          barcode: trimmedBarcode,
          productName: trimmedName,
          actionType: 'product_created',
          reason: 'Product added to inventory',
          performedBy: changedBy,
          createdAt: now,
        );

        if (openingStock > 0) {
          await _insertInventoryMovement(
            txn,
            barcode: trimmedBarcode,
            productName: trimmedName,
            actionType: 'stock_receive',
            quantityChange: openingStock,
            stockBefore: 0,
            stockAfter: openingStock,
            reason: 'Opening stock added during product creation',
            performedBy: changedBy,
            createdAt: now,
          );
        }

        final syncData = jsonEncode({
          'barcode': trimmedBarcode,
          'name': trimmedName,
          'category': trimmedCategory,
          'quantity_type': resolvedQuantityType,
          'unit_label': resolvedUnitLabel,
          'cost_price': _roundMoney(costPrice),
          'selling_price': _roundMoney(sellingPrice),
          'price': _roundMoney(sellingPrice),
          'wholesale_price': resolvedWholesale,
          'sale_price': resolvedSalePrice,
          'sale_enabled': saleEnabled,
          'opening_stock': openingStock,
          'stock': openingStock,
          'min_stock_level': minStockLevel,
          'track_expiry': trackExpiry,
          'expiry_alert_days': expiryAlertDays,
          'performed_by': changedBy,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
        });

        await txn.insert('sync_queue', {
          'type': 'PRODUCT_CREATE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error creating product: $e');
      return false;
    }
  }

  Future<bool> updateProductDetailsLocal({
    required String barcode,
    required String name,
    required String category,
    required double costPrice,
    required double sellingPrice,
    ProductQuantityType quantityType = ProductQuantityType.unit,
    String? unitLabel,
    double? wholesalePrice,
    double? salePrice,
    required bool saleEnabled,
    required int minStockLevel,
    required bool trackExpiry,
    required int expiryAlertDays,
    String? changedBy,
  }) async {
    final trimmedBarcode = barcode.trim();
    final trimmedName = name.trim();
    final trimmedCategory = category.trim().isEmpty
        ? 'General'
        : category.trim();

    if (trimmedBarcode.isEmpty || trimmedName.isEmpty) return false;
    if (sellingPrice <= 0 ||
        costPrice < 0 ||
        minStockLevel < 0 ||
        expiryAlertDays < 1) {
      return false;
    }
    if (saleEnabled && (salePrice == null || salePrice <= 0)) {
      return false;
    }

    final db = await database;

    try {
      await db.transaction((txn) async {
        final rows = await txn.query(
          'products',
          columns: [
            'name',
            'category',
            'quantity_type',
            'unit_label',
            'cost_price',
            'selling_price',
            'wholesale_price',
            'sale_price',
            'sale_enabled',
            'min_stock_level',
            'track_expiry',
            'expiry_alert_days',
            'stock',
          ],
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception('Product not found for barcode $trimmedBarcode.');
        }

        final row = rows.first;
        final now = DateTime.now().toIso8601String();
        final resolvedWholesale = _roundMoney(
          (wholesalePrice == null || wholesalePrice <= 0)
              ? sellingPrice
              : wholesalePrice,
        );
        final resolvedSalePrice = salePrice == null
            ? null
            : _roundMoney(salePrice);
        final resolvedQuantityType = quantityType.dbValue;
        final resolvedUnitLabel = _normalizeProductUnitLabel(
          quantityType: resolvedQuantityType,
          unitLabel: unitLabel,
        );

        final oldName = (row['name'] ?? '').toString();
        final oldCategory = (row['category'] ?? 'General').toString();
        final oldQuantityType = _normalizeProductQuantityType(
          row['quantity_type'],
        );
        final oldUnitLabel = _normalizeProductUnitLabel(
          quantityType: oldQuantityType,
          unitLabel: row['unit_label']?.toString(),
        );
        final oldCostPrice = _parseDouble(row['cost_price']);
        final oldSellingPrice = _parseDouble(row['selling_price']);
        final oldWholesalePrice = _parseDouble(row['wholesale_price']);
        final oldSalePrice = row['sale_price'] == null
            ? null
            : _parseDouble(row['sale_price']);
        final oldSaleEnabled = _parseInt(row['sale_enabled']) == 1;
        final oldMinStockLevel = _parseInt(row['min_stock_level']);
        final oldTrackExpiry = _parseInt(row['track_expiry']) == 1;
        final oldExpiryAlertDays = _parseInt(row['expiry_alert_days']);
        final currentStock = _parseQuantity(row['stock']);

        await txn.update(
          'products',
          {
            'name': trimmedName,
            'category': trimmedCategory,
            'quantity_type': resolvedQuantityType,
            'unit_label': resolvedUnitLabel,
            'price': _roundMoney(sellingPrice),
            'cost_price': _roundMoney(costPrice),
            'selling_price': _roundMoney(sellingPrice),
            'wholesale_price': resolvedWholesale,
            'sale_price': resolvedSalePrice,
            'sale_enabled': saleEnabled ? 1 : 0,
            'min_stock_level': minStockLevel,
            'track_expiry': trackExpiry ? 1 : 0,
            'expiry_alert_days': expiryAlertDays,
            'updated_at': now,
            'last_price_updated_at': now,
          },
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
        );

        final changes = <String>[];
        if (oldName != trimmedName) changes.add('name');
        if (oldCategory != trimmedCategory) changes.add('category');
        if (oldQuantityType != resolvedQuantityType ||
            oldUnitLabel != resolvedUnitLabel) {
          changes.add('measurement');
        }
        if (oldCostPrice != _roundMoney(costPrice)) changes.add('cost');
        if (oldSellingPrice != _roundMoney(sellingPrice))
          changes.add('selling');
        if (oldWholesalePrice != resolvedWholesale) changes.add('wholesale');
        if (oldSalePrice != resolvedSalePrice ||
            oldSaleEnabled != saleEnabled) {
          changes.add('sale');
        }
        if (oldMinStockLevel != minStockLevel) changes.add('min stock');
        if (oldTrackExpiry != trackExpiry ||
            oldExpiryAlertDays != expiryAlertDays) {
          changes.add('expiry tracking');
        }

        await _insertInventoryMovement(
          txn,
          barcode: trimmedBarcode,
          productName: trimmedName,
          actionType: 'product_updated',
          stockBefore: currentStock,
          stockAfter: currentStock,
          reason: changes.isEmpty
              ? 'Product details updated'
              : 'Updated ${changes.join(', ')}',
          performedBy: changedBy,
          createdAt: now,
        );

        final syncData = jsonEncode({
          'barcode': trimmedBarcode,
          'name': trimmedName,
          'category': trimmedCategory,
          'quantity_type': resolvedQuantityType,
          'unit_label': resolvedUnitLabel,
          'cost_price': _roundMoney(costPrice),
          'selling_price': _roundMoney(sellingPrice),
          'price': _roundMoney(sellingPrice),
          'wholesale_price': resolvedWholesale,
          'sale_price': resolvedSalePrice,
          'sale_enabled': saleEnabled,
          'stock': currentStock,
          'opening_stock': currentStock,
          'min_stock_level': minStockLevel,
          'track_expiry': trackExpiry,
          'expiry_alert_days': expiryAlertDays,
          'performed_by': changedBy,
          'updated_at': now,
          'branch': 'Hikkaduwa',
          'vendor': 'Alfasoft',
        });

        await txn.insert('sync_queue', {
          'type': 'PRODUCT_UPDATE',
          'data': syncData,
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error updating product details: $e');
      return false;
    }
  }

  Future<bool> deleteProductLocal(String barcode, {String? changedBy}) async {
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) return false;

    final db = await database;

    try {
      await db.transaction((txn) async {
        final rows = await txn.query(
          'products',
          columns: ['name'],
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw Exception('Product not found for barcode $trimmedBarcode.');
        }

        final productName = (rows.first['name'] ?? 'Unknown product')
            .toString();
        final now = DateTime.now().toIso8601String();

        await txn.delete(
          'supplier_product_mappings',
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
        );

        await txn.delete(
          'expiry_batches',
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
        );

        await txn.delete(
          'products',
          where: 'barcode = ?',
          whereArgs: [trimmedBarcode],
        );

        await _insertInventoryMovement(
          txn,
          barcode: trimmedBarcode,
          productName: productName,
          actionType: 'product_deleted',
          reason: 'Product removed from inventory',
          performedBy: changedBy,
          createdAt: now,
        );

        await txn.insert('sync_queue', {
          'type': 'PRODUCT_DELETE',
          'data': jsonEncode({
            'barcode': trimmedBarcode,
            'name': productName,
            'performed_by': changedBy,
            'updated_at': now,
            'branch': 'Hikkaduwa',
            'vendor': 'Alfasoft',
          }),
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error deleting product: $e');
      return false;
    }
  }

  Future<int> bulkDeleteProductsLocal(
    List<String> barcodes, {
    String? changedBy,
  }) async {
    final normalizedBarcodes = barcodes
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();

    if (normalizedBarcodes.isEmpty) return 0;

    final db = await database;

    try {
      var deletedCount = 0;
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final deletedBarcodes = <String>[];

        for (final barcode in normalizedBarcodes) {
          final rows = await txn.query(
            'products',
            columns: ['name'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          if (rows.isEmpty) continue;

          final productName = (rows.first['name'] ?? 'Unknown product')
              .toString();

          await txn.delete(
            'supplier_product_mappings',
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
          await txn.delete(
            'expiry_batches',
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
          await txn.delete(
            'products',
            where: 'barcode = ?',
            whereArgs: [barcode],
          );

          await _insertInventoryMovement(
            txn,
            barcode: barcode,
            productName: productName,
            actionType: 'product_deleted',
            reason: 'Product removed by bulk delete',
            performedBy: changedBy,
            createdAt: now,
          );

          deletedBarcodes.add(barcode);
          deletedCount += 1;
        }

        if (deletedBarcodes.isNotEmpty) {
          await txn.insert('sync_queue', {
            'type': 'BULK_PRODUCT_DELETE',
            'data': jsonEncode({
              'barcodes': deletedBarcodes,
              'performed_by': changedBy,
              'updated_at': now,
              'branch': 'Hikkaduwa',
              'vendor': 'Alfasoft',
            }),
            'status': 'pending',
            'created_at': now,
          });
        }
      });

      return deletedCount;
    } catch (e) {
      debugPrint('Error bulk deleting products: $e');
      return 0;
    }
  }

  Future<Map<String, int>> bulkUpsertProductsLocal({
    required List<Map<String, dynamic>> rows,
    String? changedBy,
  }) async {
    if (rows.isEmpty) {
      return {'created': 0, 'updated': 0};
    }

    final db = await database;

    try {
      var createdCount = 0;
      var updatedCount = 0;

      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final syncRows = <Map<String, dynamic>>[];

        for (final raw in rows) {
          final barcode = (raw['barcode'] ?? '').toString().trim();
          final name = (raw['name'] ?? '').toString().trim();
          final category =
              (raw['category'] ?? 'General').toString().trim().isEmpty
              ? 'General'
              : (raw['category'] ?? 'General').toString().trim();
          final quantityType = _normalizeProductQuantityType(
            raw['quantity_type'],
          );
          final unitLabel = _normalizeProductUnitLabel(
            quantityType: quantityType,
            unitLabel: raw['unit_label']?.toString(),
          );
          final sellingPrice = _roundMoney(
            _parseDouble(raw['selling_price'] ?? raw['price']),
          );
          final costPrice = _roundMoney(_parseDouble(raw['cost_price']));
          final wholesalePrice = _roundMoney(
            _parseDouble(raw['wholesale_price'], fallback: sellingPrice),
          );
          final salePriceRaw = raw['sale_price'];
          final salePrice = salePriceRaw == null
              ? null
              : _roundMoney(_parseDouble(salePriceRaw));
          final saleEnabled = raw['sale_enabled'] == null
              ? (salePrice != null)
              : (_parseInt(raw['sale_enabled']) == 1 ||
                    raw['sale_enabled'] == true);
          final stock = _parseQuantity(raw['stock'] ?? raw['opening_stock']);
          final minStockLevel = _parseInt(raw['min_stock_level']);

          if (barcode.isEmpty ||
              name.isEmpty ||
              sellingPrice <= 0 ||
              costPrice < 0 ||
              stock < 0 ||
              minStockLevel < 0) {
            continue;
          }
          if (saleEnabled && (salePrice == null || salePrice <= 0)) {
            continue;
          }

          final existing = await txn.query(
            'products',
            columns: ['id', 'stock'],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );

          if (existing.isEmpty) {
            await txn.insert('products', {
              'barcode': barcode,
              'name': name,
              'category': category,
              'quantity_type': quantityType,
              'unit_label': unitLabel,
              'price': sellingPrice,
              'cost_price': costPrice,
              'selling_price': sellingPrice,
              'wholesale_price': wholesalePrice,
              'sale_price': salePrice,
              'sale_enabled': saleEnabled ? 1 : 0,
              'stock': stock,
              'min_stock_level': minStockLevel,
              'is_active': 1,
              'updated_at': now,
              'last_price_updated_at': now,
            });
            createdCount += 1;

            await _insertInventoryMovement(
              txn,
              barcode: barcode,
              productName: name,
              actionType: 'product_created',
              reason: 'Product created by bulk upload',
              performedBy: changedBy,
              createdAt: now,
            );

            if (stock > 0) {
              await _insertInventoryMovement(
                txn,
                barcode: barcode,
                productName: name,
                actionType: 'stock_receive',
                quantityChange: stock,
                stockBefore: 0,
                stockAfter: stock,
                reason: 'Opening stock added during bulk upload',
                performedBy: changedBy,
                createdAt: now,
              );
            }
          } else {
            final stockBefore = _parseQuantity(existing.first['stock']);
            await txn.update(
              'products',
              {
                'name': name,
                'category': category,
                'quantity_type': quantityType,
                'unit_label': unitLabel,
                'price': sellingPrice,
                'cost_price': costPrice,
                'selling_price': sellingPrice,
                'wholesale_price': wholesalePrice,
                'sale_price': salePrice,
                'sale_enabled': saleEnabled ? 1 : 0,
                'stock': stock,
                'min_stock_level': minStockLevel,
                'is_active': 1,
                'updated_at': now,
                'last_price_updated_at': now,
              },
              where: 'barcode = ?',
              whereArgs: [barcode],
            );
            updatedCount += 1;

            await _insertInventoryMovement(
              txn,
              barcode: barcode,
              productName: name,
              actionType: 'product_updated',
              quantityChange: stock - stockBefore,
              stockBefore: stockBefore,
              stockAfter: stock,
              reason: 'Product updated by bulk upload',
              performedBy: changedBy,
              createdAt: now,
            );
          }

          syncRows.add({
            'barcode': barcode,
            'name': name,
            'category': category,
            'quantity_type': quantityType,
            'unit_label': unitLabel,
            'cost_price': costPrice,
            'selling_price': sellingPrice,
            'price': sellingPrice,
            'wholesale_price': wholesalePrice,
            'sale_price': salePrice,
            'sale_enabled': saleEnabled,
            'opening_stock': stock,
            'stock': stock,
            'min_stock_level': minStockLevel,
          });
        }

        if (syncRows.isNotEmpty) {
          await txn.insert('sync_queue', {
            'type': 'BULK_PRODUCT_IMPORT',
            'data': jsonEncode({
              'rows': syncRows,
              'performed_by': changedBy,
              'updated_at': now,
              'branch': 'Hikkaduwa',
              'vendor': 'Alfasoft',
            }),
            'status': 'pending',
            'created_at': now,
          });
        }
      });

      return {'created': createdCount, 'updated': updatedCount};
    } catch (e) {
      debugPrint('Error importing products: $e');
      rethrow;
    }
  }

  Future<List<ExpiryBatch>> getExpiryAlertBatches({
    String search = '',
    bool onlyAlerting = true,
    int limit = 1000,
  }) async {
    final db = await database;
    final today = _formatDateOnly(DateTime.now());
    final trimmed = search.trim().toLowerCase();
    final whereClauses = <String>[
      "b.status = 'active'",
      'b.remaining_quantity > ?',
    ];
    final whereArgs = <Object?>[_quantityEpsilon];

    if (onlyAlerting) {
      whereClauses.add(
        "date(b.expiry_date) <= date(?, '+' || COALESCE(p.expiry_alert_days, 30) || ' days')",
      );
      whereArgs.add(today);
    }

    if (trimmed.isNotEmpty) {
      whereClauses.add(
        '(LOWER(b.product_name) LIKE ? OR LOWER(b.barcode) LIKE ? OR LOWER(b.batch_number) LIKE ? OR LOWER(b.supplier_name) LIKE ?)',
      );
      whereArgs
        ..add('%$trimmed%')
        ..add('%$trimmed%')
        ..add('%$trimmed%')
        ..add('%$trimmed%');
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        b.*,
        COALESCE(p.unit_label, 'pcs') AS unit_label,
        COALESCE(p.expiry_alert_days, 30) AS alert_days
      FROM expiry_batches b
      LEFT JOIN products p ON p.barcode = b.barcode
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY date(b.expiry_date) ASC, LOWER(b.product_name) ASC
      LIMIT ?
      ''',
      [...whereArgs, limit],
    );

    return rows.map((row) => ExpiryBatch.fromMap(row)).toList();
  }

  Future<Map<String, int>> getExpiryAlertSummary() async {
    final batches = await getExpiryAlertBatches(onlyAlerting: false);
    final now = DateTime.now();
    var expired = 0;
    var today = 0;
    var critical = 0;
    var warning = 0;
    var checkedToday = 0;

    for (final batch in batches) {
      final days = batch.daysLeft(now);
      if (days < 0) {
        expired += 1;
      } else if (days == 0) {
        today += 1;
      } else if (days <= 7) {
        critical += 1;
      } else {
        warning += 1;
      }
      if (batch.checkedToday(now)) {
        checkedToday += 1;
      }
    }

    return {
      'total': batches.length,
      'expired': expired,
      'today': today,
      'critical': critical,
      'warning': warning,
      'checked_today': checkedToday,
    };
  }

  Future<bool> hasExpiredBatchForBarcode(String barcode) async {
    final trimmedBarcode = barcode.trim();
    if (trimmedBarcode.isEmpty) return false;

    final db = await database;
    final today = _formatDateOnly(DateTime.now());
    final rows = await db.query(
      'expiry_batches',
      columns: ['id'],
      where:
          "barcode = ? AND status = 'active' AND remaining_quantity > ? AND date(expiry_date) <= date(?)",
      whereArgs: [trimmedBarcode, _quantityEpsilon, today],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<bool> markExpiryBatchChecked({
    required int batchId,
    required String performedBy,
  }) async {
    if (batchId <= 0) return false;
    final db = await database;
    final now = DateTime.now().toIso8601String();

    try {
      await db.transaction((txn) async {
        final updated = await txn.update(
          'expiry_batches',
          {'last_checked_at': now, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [batchId],
        );
        if (updated == 0) {
          throw Exception('Expiry batch not found.');
        }

        await txn.insert('expiry_actions', {
          'batch_id': batchId,
          'action_type': 'checked',
          'quantity': null,
          'note': 'Shelf expiry checked',
          'performed_by': performedBy.trim(),
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error marking expiry batch checked: $e');
      return false;
    }
  }

  Future<bool> wasteExpiryBatch({
    required int batchId,
    required num quantity,
    required String performedBy,
    String note = '',
  }) async {
    final safeQuantity = _roundQuantity(quantity);
    if (batchId <= 0 || !_isPositiveQuantity(safeQuantity)) return false;

    final db = await database;
    final now = DateTime.now().toIso8601String();

    try {
      await db.transaction((txn) async {
        final batchRows = await txn.query(
          'expiry_batches',
          where: "id = ? AND status = 'active'",
          whereArgs: [batchId],
          limit: 1,
        );
        if (batchRows.isEmpty) {
          throw Exception('Expiry batch not found.');
        }

        final batch = ExpiryBatch.fromMap(batchRows.first);
        if (_quantityExceeds(safeQuantity, batch.remainingQuantity)) {
          throw Exception('Cannot waste more than remaining batch quantity.');
        }

        final productRows = await txn.query(
          'products',
          columns: ['stock'],
          where: 'barcode = ?',
          whereArgs: [batch.barcode],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw Exception('Product not found for expiry batch.');
        }

        final stockBefore = _parseQuantity(productRows.first['stock']);
        if (_quantityExceeds(safeQuantity, stockBefore)) {
          throw Exception('Cannot waste more than current product stock.');
        }

        final stockAfter = _roundQuantity(stockBefore - safeQuantity);
        final remainingAfter = _roundQuantity(
          batch.remainingQuantity - safeQuantity,
        );

        await txn.update(
          'products',
          {'stock': stockAfter, 'updated_at': now},
          where: 'barcode = ?',
          whereArgs: [batch.barcode],
        );

        await txn.update(
          'expiry_batches',
          {
            'remaining_quantity': remainingAfter,
            'status': remainingAfter <= _quantityEpsilon ? 'wasted' : 'active',
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [batchId],
        );

        await txn.insert('expiry_actions', {
          'batch_id': batchId,
          'action_type': 'wasted',
          'quantity': safeQuantity,
          'note': note.trim(),
          'performed_by': performedBy.trim(),
          'created_at': now,
        });

        await _insertInventoryMovement(
          txn,
          barcode: batch.barcode,
          productName: batch.productName,
          actionType: 'expiry_waste',
          quantityChange: -safeQuantity,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: note.trim().isEmpty
              ? 'Removed expired or near-expiry stock'
              : note.trim(),
          performedBy: performedBy,
          supplierId: batch.supplierId,
          supplierName: batch.supplierName.trim().isEmpty
              ? null
              : batch.supplierName.trim(),
          referenceId: batchId,
          referenceType: 'expiry_batch',
          createdAt: now,
        );

        await txn.insert('sync_queue', {
          'type': 'STOCK_ADJUST',
          'data': jsonEncode({
            'barcode': batch.barcode,
            'adjustment_type': 'decrease',
            'quantity': safeQuantity,
            'reason':
                'Expiry waste${note.trim().isEmpty ? '' : ': ${note.trim()}'}',
            'performed_by': performedBy,
            'updated_at': now,
            'branch': 'Hikkaduwa',
            'vendor': 'Alfasoft',
          }),
          'status': 'pending',
          'created_at': now,
        });
      });

      return true;
    } catch (e) {
      debugPrint('Error wasting expiry batch: $e');
      return false;
    }
  }

  Future<void> _deductExpiryBatchesForSale(
    DatabaseExecutor txn, {
    required String barcode,
    required double quantity,
    required String updatedAt,
  }) async {
    var remainingToDeduct = _roundQuantity(quantity);
    if (!_isPositiveQuantity(remainingToDeduct)) return;

    final rows = await txn.query(
      'expiry_batches',
      where: "barcode = ? AND status = 'active' AND remaining_quantity > ?",
      whereArgs: [barcode, _quantityEpsilon],
      orderBy: 'date(expiry_date) ASC, id ASC',
    );

    for (final row in rows) {
      if (!_isPositiveQuantity(remainingToDeduct)) break;
      final batchId = (row['id'] as num?)?.toInt() ?? 0;
      final remainingQuantity = _parseQuantity(row['remaining_quantity']);
      if (batchId <= 0 || !_isPositiveQuantity(remainingQuantity)) continue;

      final deductQuantity = remainingQuantity < remainingToDeduct
          ? remainingQuantity
          : remainingToDeduct;
      final nextRemaining = _roundQuantity(remainingQuantity - deductQuantity);

      await txn.update(
        'expiry_batches',
        {
          'remaining_quantity': nextRemaining,
          'status': nextRemaining <= _quantityEpsilon ? 'sold' : 'active',
          'updated_at': updatedAt,
        },
        where: 'id = ?',
        whereArgs: [batchId],
      );

      remainingToDeduct = _roundQuantity(remainingToDeduct - deductQuantity);
    }
  }

  Future<Map<String, dynamic>> getOrCreateOpenStockTakeSession({
    String defaultSessionName = 'Main Store Count',
  }) async {
    final db = await database;
    final existing = await db.query(
      'stock_take_sessions',
      where: "status = ?",
      whereArgs: ['open'],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return Map<String, dynamic>.from(existing.first);
    }

    final now = DateTime.now().toIso8601String();
    final sessionId = await db.insert('stock_take_sessions', {
      'session_name': defaultSessionName,
      'status': 'open',
      'total_products': 0,
      'counted_items': 0,
      'discrepancy_items': 0,
      'applied_items': 0,
      'started_at': now,
      'updated_at': now,
    });

    final created = await db.query(
      'stock_take_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    return Map<String, dynamic>.from(created.first);
  }

  Future<bool> renameStockTakeSession(int sessionId, String sessionName) async {
    final trimmed = sessionName.trim();
    if (sessionId <= 0 || trimmed.isEmpty) return false;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final updated = await db.update(
      'stock_take_sessions',
      {'session_name': trimmed, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return updated > 0;
  }

  Future<void> _refreshStockTakeSessionSummary(
    DatabaseExecutor db,
    int sessionId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS counted_items,
        SUM(CASE WHEN difference_qty != 0 THEN 1 ELSE 0 END) AS discrepancy_items
      FROM stock_take_items
      WHERE session_id = ?
      ''',
      [sessionId],
    );

    final countedItems = _parseInt(rows.first['counted_items']);
    final discrepancyItems = _parseInt(rows.first['discrepancy_items']);
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS total_products FROM products',
    );
    final totalProducts = _parseInt(totalRows.first['total_products']);

    await db.update(
      'stock_take_sessions',
      {
        'counted_items': countedItems,
        'discrepancy_items': discrepancyItems,
        'total_products': totalProducts,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<bool> saveStockTakeCount({
    required int sessionId,
    required Product product,
    required num countedQty,
  }) async {
    final safeCountedQty = _roundQuantity(countedQty);
    if (sessionId <= 0 || safeCountedQty < 0) return false;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    try {
      await db.transaction((txn) async {
        await txn.insert('stock_take_items', {
          'session_id': sessionId,
          'barcode': product.barcode,
          'product_name': product.name,
          'system_stock': product.stock,
          'counted_stock': safeCountedQty,
          'difference_qty': _roundQuantity(safeCountedQty - product.stock),
          'applied': 0,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.update(
          'stock_take_sessions',
          {'updated_at': now},
          where: 'id = ?',
          whereArgs: [sessionId],
        );

        await _refreshStockTakeSessionSummary(txn, sessionId);
      });
      return true;
    } catch (e) {
      debugPrint('Error saving stock take count: $e');
      return false;
    }
  }

  Future<bool> removeStockTakeCount({
    required int sessionId,
    required String barcode,
  }) async {
    if (sessionId <= 0 || barcode.trim().isEmpty) return false;
    final db = await database;
    try {
      await db.transaction((txn) async {
        await txn.delete(
          'stock_take_items',
          where: 'session_id = ? AND barcode = ?',
          whereArgs: [sessionId, barcode.trim()],
        );
        await _refreshStockTakeSessionSummary(txn, sessionId);
      });
      return true;
    } catch (e) {
      debugPrint('Error removing stock take count: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getStockTakeSessionItems(
    int sessionId,
  ) async {
    if (sessionId <= 0) return [];
    final db = await database;
    final rows = await db.query(
      'stock_take_items',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getCompletedStockTakeSessions({
    int limit = 20,
  }) async {
    final db = await database;
    final rows = await db.query(
      'stock_take_sessions',
      where: "status = ?",
      whereArgs: ['completed'],
      orderBy: 'completed_at DESC, id DESC',
      limit: limit,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<bool> discardOpenStockTakeSession(int sessionId) async {
    if (sessionId <= 0) return false;
    final db = await database;
    try {
      await db.delete(
        'stock_take_sessions',
        where: 'id = ? AND status = ?',
        whereArgs: [sessionId, 'open'],
      );
      return true;
    } catch (e) {
      debugPrint('Error discarding stock take session: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> applyStockTakeSession({
    required int sessionId,
    String? performedBy,
  }) async {
    final db = await database;

    final sessionRows = await db.query(
      'stock_take_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (sessionRows.isEmpty) {
      return {
        'success': false,
        'message': 'Stock take session not found.',
        'applied_count': 0,
        'discrepancy_count': 0,
      };
    }

    final session = Map<String, dynamic>.from(sessionRows.first);
    final sessionName = (session['session_name'] ?? 'Stock Take Session')
        .toString();
    final items = await getStockTakeSessionItems(sessionId);
    final discrepancies = items
        .where(
          (item) =>
              _parseQuantity(item['difference_qty']).abs() >= _quantityEpsilon,
        )
        .toList();

    if (discrepancies.isEmpty) {
      return {
        'success': false,
        'message': 'No discrepancies to apply.',
        'applied_count': 0,
        'discrepancy_count': 0,
      };
    }

    int appliedCount = 0;
    final failedBarcodes = <String>[];
    final appliedAt = DateTime.now().toIso8601String();

    for (final item in discrepancies) {
      final barcode = (item['barcode'] ?? '').toString();
      final countedStock = _parseQuantity(item['counted_stock']);
      final success = await adjustStockLocal(
        barcode,
        adjustmentType: 'set',
        quantity: countedStock,
        performedBy: performedBy,
        reason: 'Stock take reconciliation • $sessionName',
      );

      if (success) {
        appliedCount += 1;
        await db.update(
          'stock_take_items',
          {'applied': 1, 'applied_at': appliedAt, 'updated_at': appliedAt},
          where: 'session_id = ? AND barcode = ?',
          whereArgs: [sessionId, barcode],
        );
      } else {
        failedBarcodes.add(barcode);
      }
    }

    if (failedBarcodes.isEmpty) {
      final totalRows = await db.rawQuery(
        'SELECT COUNT(*) AS total_products FROM products',
      );
      final totalProducts = _parseInt(totalRows.first['total_products']);
      await db.update(
        'stock_take_sessions',
        {
          'status': 'completed',
          'total_products': totalProducts,
          'applied_items': appliedCount,
          'completed_at': appliedAt,
          'updated_at': appliedAt,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      return {
        'success': true,
        'message': 'Stock take applied for $appliedCount items.',
        'applied_count': appliedCount,
        'discrepancy_count': discrepancies.length,
      };
    }

    await _refreshStockTakeSessionSummary(db, sessionId);
    return {
      'success': false,
      'message': 'Some stock take items could not be applied.',
      'applied_count': appliedCount,
      'discrepancy_count': discrepancies.length,
      'failed_barcodes': failedBarcodes,
    };
  }

  Future<List<Map<String, dynamic>>> getSalesTrendByDay({
    String? cashierName,
    DateTime? start,
    DateTime? end,
  }) async {
    final db = await database;

    final startTime = start ?? DateTime.now();
    final endTime = end ?? DateTime.now();

    final salesConditions = <String>[
      'datetime(s.created_at) >= datetime(?)',
      'datetime(s.created_at) <= datetime(?)',
    ];
    final salesArgs = <Object?>[
      startTime.toIso8601String(),
      endTime.toIso8601String(),
    ];

    final trimmedCashier = cashierName?.trim();
    if (trimmedCashier != null && trimmedCashier.isNotEmpty) {
      salesConditions.add('s.cashier_name = ?');
      salesArgs.add(trimmedCashier);
    }

    final salesRows = await db.rawQuery('''
      SELECT
        date(s.created_at) AS sales_date,
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
        ) AS refund_total
      FROM sales s
      WHERE ${salesConditions.join(' AND ')}
      GROUP BY date(s.created_at)
      ORDER BY date(s.created_at) ASC
      ''', salesArgs);

    final itemConditions = <String>[
      "s.transaction_type = 'sale'",
      'datetime(s.created_at) >= datetime(?)',
      'datetime(s.created_at) <= datetime(?)',
    ];
    final itemArgs = <Object?>[
      startTime.toIso8601String(),
      endTime.toIso8601String(),
    ];

    if (trimmedCashier != null && trimmedCashier.isNotEmpty) {
      itemConditions.add('s.cashier_name = ?');
      itemArgs.add(trimmedCashier);
    }

    final itemRows = await db.rawQuery('''
      SELECT
        date(s.created_at) AS sales_date,
        COALESCE(SUM(si.quantity), 0) AS items_sold
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE ${itemConditions.join(' AND ')}
      GROUP BY date(s.created_at)
      ''', itemArgs);

    final itemsByDate = <String, int>{
      for (final row in itemRows)
        (row['sales_date'] ?? '').toString():
            (row['items_sold'] as num?)?.toInt() ?? 0,
    };

    return salesRows.map((row) {
      final salesDate = (row['sales_date'] ?? '').toString();
      final saleCount = (row['sale_count'] as num?)?.toInt() ?? 0;
      final refundCount = (row['refund_count'] as num?)?.toInt() ?? 0;
      final grossSales = ((row['gross_sales'] as num?) ?? 0).toDouble();
      final totalDiscounts = ((row['total_discounts'] as num?) ?? 0).toDouble();
      final netSales = ((row['net_sales'] as num?) ?? 0).toDouble();
      final refundTotal = ((row['refund_total'] as num?) ?? 0).toDouble();

      return {
        'sales_date': salesDate,
        'sale_count': saleCount,
        'refund_count': refundCount,
        'transaction_count': saleCount + refundCount,
        'gross_sales': _roundMoney(grossSales),
        'total_discounts': _roundMoney(totalDiscounts),
        'net_sales': _roundMoney(netSales),
        'refund_total': _roundMoney(refundTotal),
        'net_after_refunds': _roundMoney(netSales - refundTotal),
        'items_sold': itemsByDate[salesDate] ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getHourlySalesSummaryForDay({
    String? cashierName,
    required DateTime day,
  }) async {
    final db = await database;

    final startTime = DateTime(day.year, day.month, day.day);
    final endTime = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

    final salesConditions = <String>[
      'datetime(s.created_at) >= datetime(?)',
      'datetime(s.created_at) <= datetime(?)',
    ];
    final salesArgs = <Object?>[
      startTime.toIso8601String(),
      endTime.toIso8601String(),
    ];

    final trimmedCashier = cashierName?.trim();
    if (trimmedCashier != null && trimmedCashier.isNotEmpty) {
      salesConditions.add('s.cashier_name = ?');
      salesArgs.add(trimmedCashier);
    }

    final salesRows = await db.rawQuery('''
      SELECT
        strftime('%H', s.created_at) AS hour_key,
        COALESCE(SUM(CASE WHEN s.transaction_type = 'sale' THEN 1 ELSE 0 END), 0) AS sale_count,
        COALESCE(SUM(CASE WHEN s.transaction_type = 'refund' THEN 1 ELSE 0 END), 0) AS refund_count,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'sale' THEN ABS(s.total_amount) ELSE 0 END),
          0
        ) AS net_sales,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'refund' THEN ABS(s.total_amount) ELSE 0 END),
          0
        ) AS refund_total
      FROM sales s
      WHERE ${salesConditions.join(' AND ')}
      GROUP BY strftime('%H', s.created_at)
      ORDER BY hour_key ASC
      ''', salesArgs);

    final itemConditions = <String>[
      "s.transaction_type = 'sale'",
      'datetime(s.created_at) >= datetime(?)',
      'datetime(s.created_at) <= datetime(?)',
    ];
    final itemArgs = <Object?>[
      startTime.toIso8601String(),
      endTime.toIso8601String(),
    ];

    if (trimmedCashier != null && trimmedCashier.isNotEmpty) {
      itemConditions.add('s.cashier_name = ?');
      itemArgs.add(trimmedCashier);
    }

    final itemRows = await db.rawQuery('''
      SELECT
        strftime('%H', s.created_at) AS hour_key,
        COALESCE(SUM(si.quantity), 0) AS items_sold
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      WHERE ${itemConditions.join(' AND ')}
      GROUP BY strftime('%H', s.created_at)
      ORDER BY hour_key ASC
      ''', itemArgs);

    final itemsByHour = <String, int>{
      for (final row in itemRows)
        (row['hour_key'] ?? '').toString():
            (row['items_sold'] as num?)?.toInt() ?? 0,
    };

    return salesRows.map((row) {
      final hourKey = (row['hour_key'] ?? '00').toString();
      final saleCount = (row['sale_count'] as num?)?.toInt() ?? 0;
      final refundCount = (row['refund_count'] as num?)?.toInt() ?? 0;
      final netSales = ((row['net_sales'] as num?) ?? 0).toDouble();
      final refundTotal = ((row['refund_total'] as num?) ?? 0).toDouble();

      return {
        'hour': int.tryParse(hourKey) ?? 0,
        'hour_key': hourKey,
        'sale_count': saleCount,
        'refund_count': refundCount,
        'transaction_count': saleCount + refundCount,
        'net_sales': _roundMoney(netSales),
        'refund_total': _roundMoney(refundTotal),
        'net_after_refunds': _roundMoney(netSales - refundTotal),
        'items_sold': itemsByHour[hourKey] ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getProductPerformanceSummary({
    String? cashierName,
    DateTime? start,
    DateTime? end,
    int limit = 10,
  }) async {
    final db = await database;

    final startTime = start ?? DateTime.now();
    final endTime = end ?? DateTime.now();

    final conditions = <String>[
      "s.transaction_type IN ('sale', 'refund')",
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
        COALESCE(MAX(p.name), MAX(si.product_name)) AS product_name,
        CASE
          WHEN LOWER(COALESCE(MAX(p.quantity_type), '')) = 'weight' THEN 'weight'
          ELSE 'unit'
        END AS quantity_type,
        COALESCE(
          NULLIF(TRIM(MAX(p.unit_label)), ''),
          CASE
            WHEN LOWER(COALESCE(MAX(p.quantity_type), '')) = 'weight' THEN 'kg'
            ELSE 'pcs'
          END
        ) AS unit_label,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'sale' THEN si.quantity ELSE 0 END),
          0
        ) AS quantity_sold,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'refund' THEN si.quantity ELSE 0 END),
          0
        ) AS refunded_quantity,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'sale' THEN ABS(si.line_total) ELSE 0 END),
          0
        ) AS sales_amount,
        COALESCE(
          SUM(CASE WHEN s.transaction_type = 'refund' THEN ABS(si.line_total) ELSE 0 END),
          0
        ) AS refund_amount,
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' THEN ABS(si.line_total)
              ELSE -ABS(si.line_total)
            END
          ),
          0
        ) AS net_sales_after_refunds,
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' THEN (si.cost_price_snapshot * si.quantity)
              ELSE -(si.cost_price_snapshot * si.quantity)
            END
          ),
          0
        ) AS net_cost_amount
      FROM sales s
      INNER JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN products p ON p.barcode = si.barcode
      WHERE ${conditions.join(' AND ')}
      GROUP BY si.barcode
      ORDER BY net_sales_after_refunds DESC, quantity_sold DESC, product_name ASC
      LIMIT ?
      ''',
      [...args, limit],
    );

    return rows.map((row) {
      final quantitySold = ((row['quantity_sold'] as num?) ?? 0).toDouble();
      final refundedQuantity = ((row['refunded_quantity'] as num?) ?? 0)
          .toDouble();
      final salesAmount = ((row['sales_amount'] as num?) ?? 0).toDouble();
      final refundAmount = ((row['refund_amount'] as num?) ?? 0).toDouble();
      final netSalesAfterRefunds =
          ((row['net_sales_after_refunds'] as num?) ?? 0).toDouble();
      final netCostAmount = ((row['net_cost_amount'] as num?) ?? 0).toDouble();
      final estimatedProfit = _roundMoney(netSalesAfterRefunds - netCostAmount);
      final marginPercent = netSalesAfterRefunds <= 0
          ? 0.0
          : _roundMoney((estimatedProfit / netSalesAfterRefunds) * 100);

      return {
        'barcode': row['barcode'],
        'product_name': row['product_name'],
        'quantity_type': row['quantity_type'],
        'unit_label': row['unit_label'],
        'quantity_sold': quantitySold,
        'refunded_quantity': refundedQuantity,
        'net_quantity_sold': quantitySold - refundedQuantity,
        'sales_amount': _roundMoney(salesAmount),
        'refund_amount': _roundMoney(refundAmount),
        'net_sales_after_refunds': _roundMoney(netSalesAfterRefunds),
        'net_cost_amount': _roundMoney(netCostAmount),
        'estimated_profit': estimatedProfit,
        'margin_percent': marginPercent,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getSlowMovingProductsSummary({
    DateTime? start,
    DateTime? end,
    int limit = 10,
  }) async {
    final db = await database;

    final startTime = start ?? DateTime.now();
    final endTime = end ?? DateTime.now();

    final rows = await db.rawQuery(
      '''
      SELECT
        p.barcode,
        p.name AS product_name,
        p.category,
        p.quantity_type,
        p.unit_label,
        p.stock,
        p.min_stock_level,
        p.cost_price,
        p.selling_price,
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' THEN si.quantity
              ELSE 0
            END
          ),
          0
        ) AS quantity_sold,
        COALESCE(
          SUM(
            CASE
              WHEN s.transaction_type = 'sale' THEN ABS(si.line_total)
              ELSE 0
            END
          ),
          0
        ) AS sales_amount
      FROM products p
      LEFT JOIN sale_items si
        ON si.barcode = p.barcode
      LEFT JOIN sales s
        ON s.id = si.sale_id
       AND datetime(s.created_at) >= datetime(?)
       AND datetime(s.created_at) <= datetime(?)
      WHERE p.is_active = 1
        AND p.stock > 0
      GROUP BY
        p.barcode,
        p.name,
        p.category,
        p.quantity_type,
        p.unit_label,
        p.stock,
        p.min_stock_level,
        p.cost_price,
        p.selling_price
      ORDER BY
        quantity_sold ASC,
        p.stock DESC,
        (p.cost_price * p.stock) DESC,
        p.name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [startTime.toIso8601String(), endTime.toIso8601String(), limit],
    );

    return rows.map((row) {
      final stock = ((row['stock'] as num?) ?? 0).toDouble();
      final quantitySold = ((row['quantity_sold'] as num?) ?? 0).toDouble();
      final costPrice = ((row['cost_price'] as num?) ?? 0).toDouble();
      final sellingPrice = ((row['selling_price'] as num?) ?? 0).toDouble();
      final salesAmount = ((row['sales_amount'] as num?) ?? 0).toDouble();

      return {
        'barcode': row['barcode'],
        'product_name': row['product_name'],
        'category': row['category'],
        'quantity_type': row['quantity_type'],
        'unit_label': row['unit_label'],
        'stock': stock,
        'min_stock_level': (row['min_stock_level'] as num?)?.toInt() ?? 0,
        'cost_price': _roundMoney(costPrice),
        'selling_price': _roundMoney(sellingPrice),
        'quantity_sold': quantitySold,
        'sales_amount': _roundMoney(salesAmount),
        'stock_value': _roundMoney(costPrice * stock),
        'is_dead_stock': quantitySold <= 0,
      };
    }).toList();
  }
}
