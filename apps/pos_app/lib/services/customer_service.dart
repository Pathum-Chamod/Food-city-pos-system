import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/product.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';

class CustomerService {
  CustomerService._();

  static final CustomerService instance = CustomerService._();

  static const String customersTable = 'customers';

  Future<Database> get _db async {
    final db = await DatabaseHelper.instance.database;
    await ensureCustomerStorage();
    return db;
  }

  Future<void> ensureCustomerStorage() async {
    final db = await DatabaseHelper.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $customersTable (
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
        customer_category_id INTEGER,
        pricing_scheme_id INTEGER,
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
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON $customersTable(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON $customersTable(phone_normalized)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_code ON $customersTable(customer_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_active ON $customersTable(is_active)',
    );
    await _addColumnIfMissing(db, 'sales', 'customer_id', 'INTEGER');
    await _addColumnIfMissing(db, 'sales', 'customer_name_snapshot', 'TEXT');
    await _addColumnIfMissing(db, 'sales', 'customer_phone_snapshot', 'TEXT');
    await _addColumnIfMissing(db, 'sales', 'customer_code_snapshot', 'TEXT');

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

    await _addColumnIfMissing(
      db,
      customersTable,
      'pricing_enabled',
      "INTEGER NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(
      db,
      customersTable,
      'default_price_type',
      "TEXT NOT NULL DEFAULT 'selling'",
    );
    await _addColumnIfMissing(
      db,
      customersTable,
      'default_discount_percent',
      "REAL NOT NULL DEFAULT 0",
    );
    await _addColumnIfMissing(db, customersTable, 'pricing_note', 'TEXT');
    await _addColumnIfMissing(
      db,
      customersTable,
      'customer_category_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      customersTable,
      'pricing_scheme_id',
      'INTEGER',
    );

    await _ensurePricingSchemesStorage(db);
  }

  Future<void> _ensurePricingSchemesStorage(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        default_pricing_scheme_id INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pricing_schemes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        priority INTEGER NOT NULL DEFAULT 100,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by INTEGER,
        updated_by INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pricing_scheme_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scheme_id INTEGER NOT NULL,
        apply_to TEXT NOT NULL,
        category TEXT,
        barcode TEXT,
        product_name_snapshot TEXT,
        rule_type TEXT NOT NULL,
        price_type TEXT,
        discount_percent REAL NOT NULL DEFAULT 0,
        fixed_price REAL,
        priority INTEGER NOT NULL DEFAULT 100,
        is_active INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by INTEGER,
        updated_by INTEGER,
        FOREIGN KEY (scheme_id) REFERENCES pricing_schemes(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_categories_name
      ON customer_categories(name)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_categories_active
      ON customer_categories(is_active)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pricing_schemes_name
      ON pricing_schemes(name)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pricing_schemes_active
      ON pricing_schemes(is_active)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pricing_scheme_rules_scheme
      ON pricing_scheme_rules(scheme_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pricing_scheme_rules_active
      ON pricing_scheme_rules(is_active)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pricing_scheme_rules_target
      ON pricing_scheme_rules(apply_to, category, barcode)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pricing_scheme_rules_priority
      ON pricing_scheme_rules(scheme_id, priority, updated_at)
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_category ON $customersTable(customer_category_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_pricing_scheme ON $customersTable(pricing_scheme_id)',
    );

    await _seedDefaultCustomerCategories(db);
  }

  Future<void> _seedDefaultCustomerCategories(Database db) async {
    final now = DateTime.now().toIso8601String();
    const names = ['Regular', 'VIP', 'Wholesale', 'Staff'];
    for (final name in names) {
      await db.insert('customer_categories', {
        'name': name,
        'description': null,
        'default_pricing_scheme_id': null,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String columnDefinition,
  ) async {
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );

    if (tableRows.isEmpty) return;

    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((row) => row['name'] == columnName);
    if (exists) return;

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
    );
  }

  String normalizePhone(String input) {
    return Customer.normalizeSriLankanPhone(input);
  }

  String _normalizeCustomerType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'vip') return 'vip';
    if (normalized == 'wholesale') return 'wholesale';
    if (normalized == 'staff') return 'staff';
    return 'regular';
  }

  String _normalizePriceType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'wholesale') return 'wholesale';
    if (normalized == 'sale') return 'sale';
    return 'selling';
  }

  String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  Future<List<Customer>> getCustomers({
    String query = '',
    bool activeOnly = true,
    int limit = 100,
  }) async {
    final db = await _db;
    final trimmed = query.trim();
    final args = <Object?>[];
    final whereParts = <String>[];

    if (activeOnly) {
      whereParts.add('is_active = 1');
    }

    if (trimmed.isNotEmpty) {
      final phoneQuery = normalizePhone(trimmed);
      whereParts.add('''
        (
          LOWER(name) LIKE ?
          OR LOWER(COALESCE(customer_code, '')) LIKE ?
          OR COALESCE(phone, '') LIKE ?
          OR COALESCE(phone_normalized, '') LIKE ?
          OR LOWER(COALESCE(email, '')) LIKE ?
          OR LOWER(COALESCE(address, '')) LIKE ?
        )
      ''');

      final lower = '%${trimmed.toLowerCase()}%';
      args.addAll([
        lower,
        lower,
        '%$trimmed%',
        '%${phoneQuery.isEmpty ? trimmed : phoneQuery}%',
        lower,
        lower,
      ]);
    }

    final rows = await db.query(
      customersTable,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'is_active DESC, name COLLATE NOCASE ASC',
      limit: limit <= 0 ? null : limit,
    );

    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomerById(int id) async {
    if (id <= 0) return null;

    final db = await _db;
    final rows = await db.query(
      customersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<Customer?> findCustomerByPhone(String phone) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return null;

    final db = await _db;
    final rows = await db.query(
      customersTable,
      where: 'phone_normalized = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<Customer?> findCustomerByCode(String customerCode) async {
    final code = customerCode.trim();
    if (code.isEmpty) return null;

    final db = await _db;
    final rows = await db.query(
      customersTable,
      where: 'LOWER(customer_code) = ?',
      whereArgs: [code.toLowerCase()],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<int> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    String customerType = 'regular',
    String? notes,
    int? createdBy,
    bool preventDuplicatePhone = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Customer name is required.');
    }

    final normalizedPhone = normalizePhone(phone ?? '');
    if (preventDuplicatePhone && normalizedPhone.isNotEmpty) {
      final existing = await findCustomerByPhone(normalizedPhone);
      if (existing != null) {
        throw Exception(
          'A customer with this phone number already exists: ${existing.displayName}.',
        );
      }
    }

    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final id = await db.insert(customersTable, {
      'customer_code': null,
      'name': trimmedName,
      'phone': _cleanOptional(phone),
      'phone_normalized': normalizedPhone.isEmpty ? null : normalizedPhone,
      'email': _cleanOptional(email),
      'address': _cleanOptional(address),
      'customer_type': _normalizeCustomerType(customerType),
      'notes': _cleanOptional(notes),
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'created_by': createdBy,
      'updated_by': createdBy,
    });

    final customerCode = Customer.generateCustomerCode(id);
    await db.update(
      customersTable,
      {
        'customer_code': customerCode,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    return id;
  }

  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String customerType = 'regular',
    String? notes,
    bool isActive = true,
    int? updatedBy,
    bool preventDuplicatePhone = true,
  }) async {
    if (id <= 0) {
      throw Exception('Invalid customer.');
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Customer name is required.');
    }

    final normalizedPhone = normalizePhone(phone ?? '');
    if (preventDuplicatePhone && normalizedPhone.isNotEmpty) {
      final existing = await findCustomerByPhone(normalizedPhone);
      if (existing != null && existing.id != id) {
        throw Exception(
          'A customer with this phone number already exists: ${existing.displayName}.',
        );
      }
    }

    final db = await _db;
    final existing = await getCustomerById(id);
    if (existing == null) {
      throw Exception('Customer not found.');
    }

    await db.update(
      customersTable,
      {
        'name': trimmedName,
        'phone': _cleanOptional(phone),
        'phone_normalized': normalizedPhone.isEmpty ? null : normalizedPhone,
        'email': _cleanOptional(email),
        'address': _cleanOptional(address),
        'customer_type': _normalizeCustomerType(customerType),
        'notes': _cleanOptional(notes),
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateCustomerPricingSettings({
    required int customerId,
    required bool pricingEnabled,
    required String defaultPriceType,
    required double defaultDiscountPercent,
    String? pricingNote,
    int? updatedBy,
  }) async {
    if (customerId <= 0) {
      throw Exception('Invalid customer.');
    }

    final existing = await getCustomerById(customerId);
    if (existing == null) {
      throw Exception('Customer not found.');
    }

    final db = await _db;
    final safeDiscount = defaultDiscountPercent.clamp(0.0, 100.0).toDouble();

    await db.update(
      customersTable,
      {
        'pricing_enabled': pricingEnabled ? 1 : 0,
        'default_price_type': _normalizePriceType(defaultPriceType),
        'default_discount_percent': safeDiscount,
        'pricing_note': _cleanOptional(pricingNote),
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );

    final updated = await getCustomerById(customerId);
    if (updated != null) {
      await db.insert('sync_queue', {
        'type': 'CUSTOMER_PRICING_SETTINGS',
        'data': jsonEncode({
          'customer_id': updated.id,
          'customer_code': updated.customerCode,
          'customer_name': updated.name,
          'customer_phone': updated.phone,
          'customer_phone_normalized': updated.phoneNormalized,
          'customer_email': updated.email,
          'customer_address': updated.address,
          'customer_type': updated.customerType,
          'customer_notes': updated.notes,
          'customer_is_active': updated.isActive ? 1 : 0,
          'credit_enabled': updated.creditEnabled ? 1 : 0,
          'credit_limit': updated.creditLimit,
          'current_credit_balance': updated.currentCreditBalance,
          'credit_status': updated.creditStatus,
          'credit_note': updated.creditNote,
          'pricing_enabled': updated.pricingEnabled ? 1 : 0,
          'default_price_type': updated.defaultPriceType.dbValue,
          'default_discount_percent': updated.defaultDiscountPercent,
          'pricing_note': updated.pricingNote,
          'customer_category_id': updated.customerCategoryId,
          'pricing_scheme_id': updated.pricingSchemeId,
          'updated_by': updatedBy,
          'updated_at': updated.updatedAt,
        }),
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> deactivateCustomer({
    required int customerId,
    int? updatedBy,
  }) async {
    if (customerId <= 0) return;

    final db = await _db;
    await db.update(
      customersTable,
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  Future<void> reactivateCustomer({
    required int customerId,
    int? updatedBy,
  }) async {
    if (customerId <= 0) return;

    final db = await _db;
    await db.update(
      customersTable,
      {
        'is_active': 1,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  Future<void> attachCustomerToSale({
    required int saleId,
    Customer? customer,
  }) async {
    if (saleId <= 0) return;

    final db = await _db;
    await db.update(
      'sales',
      {
        'customer_id': customer?.id,
        'customer_name_snapshot': customer?.displayName,
        'customer_phone_snapshot': customer?.hasPhone == true
            ? customer?.phone?.trim()
            : null,
        'customer_code_snapshot': customer?.displayCode,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  Future<Map<String, dynamic>> getSaleCustomerSnapshotMap(int saleId) async {
    if (saleId <= 0) return const <String, dynamic>{};

    final db = await _db;
    final rows = await db.query(
      'sales',
      columns: const [
        'customer_id',
        'customer_name_snapshot',
        'customer_phone_snapshot',
        'customer_code_snapshot',
      ],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    if (rows.isEmpty) return const <String, dynamic>{};

    final row = Map<String, dynamic>.from(rows.first);
    final customerId = (row['customer_id'] as num?)?.toInt();
    final customerName = (row['customer_name_snapshot'] ?? '')
        .toString()
        .trim();
    final customerPhone = (row['customer_phone_snapshot'] ?? '')
        .toString()
        .trim();
    final customerCode = (row['customer_code_snapshot'] ?? '')
        .toString()
        .trim();

    if ((customerId == null || customerId <= 0) &&
        customerName.isEmpty &&
        customerPhone.isEmpty &&
        customerCode.isEmpty) {
      return const <String, dynamic>{};
    }

    return {
      'customer_id': customerId,
      'customer_name_snapshot': customerName.isEmpty ? null : customerName,
      'customer_phone_snapshot': customerPhone.isEmpty ? null : customerPhone,
      'customer_code_snapshot': customerCode.isEmpty ? null : customerCode,
    };
  }

  Future<Map<String, dynamic>> getCustomerSummary(int customerId) async {
    if (customerId <= 0) {
      return _emptySummary();
    }

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS transaction_count,
        COALESCE(SUM(CASE
          WHEN LOWER(COALESCE(transaction_type, 'sale')) = 'refund'
          THEN -ABS(total_amount)
          ELSE ABS(total_amount)
        END), 0) AS net_total_spent,
        COALESCE(SUM(CASE
          WHEN LOWER(COALESCE(transaction_type, 'sale')) = 'refund'
          THEN 1
          ELSE 0
        END), 0) AS refund_count,
        COALESCE(SUM(CASE
          WHEN LOWER(COALESCE(transaction_type, 'sale')) = 'refund'
          THEN 0
          ELSE 1
        END), 0) AS sale_count,
        MAX(created_at) AS last_purchase_at,
        MIN(created_at) AS first_purchase_at
      FROM sales
      WHERE customer_id = ?
      ''',
      [customerId],
    );

    final row = rows.isEmpty ? <String, dynamic>{} : rows.first;
    final saleCount = ((row['sale_count'] as num?) ?? 0).toInt();
    final netTotal = ((row['net_total_spent'] as num?) ?? 0).toDouble();

    return {
      'transaction_count': ((row['transaction_count'] as num?) ?? 0).toInt(),
      'sale_count': saleCount,
      'refund_count': ((row['refund_count'] as num?) ?? 0).toInt(),
      'net_total_spent': netTotal,
      'average_sale': saleCount <= 0 ? 0.0 : netTotal / saleCount,
      'first_purchase_at': row['first_purchase_at'],
      'last_purchase_at': row['last_purchase_at'],
    };
  }

  Map<String, dynamic> _emptySummary() {
    return {
      'transaction_count': 0,
      'sale_count': 0,
      'refund_count': 0,
      'net_total_spent': 0.0,
      'average_sale': 0.0,
      'first_purchase_at': null,
      'last_purchase_at': null,
    };
  }

  Future<List<Map<String, dynamic>>> getCustomerPurchaseHistory(
    int customerId, {
    int limit = 100,
  }) async {
    if (customerId <= 0) return const [];

    final db = await _db;
    final rows = await db.query(
      'sales',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'datetime(created_at) DESC, id DESC',
      limit: limit <= 0 ? null : limit,
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> getTopCustomers({int limit = 20}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT
        c.id,
        c.customer_code,
        c.name,
        c.phone,
        c.customer_type,
        c.is_active,
        COUNT(s.id) AS transaction_count,
        COALESCE(SUM(CASE
          WHEN LOWER(COALESCE(s.transaction_type, 'sale')) = 'refund'
          THEN -ABS(s.total_amount)
          ELSE ABS(s.total_amount)
        END), 0) AS net_total_spent,
        MAX(s.created_at) AS last_purchase_at
      FROM customers c
      LEFT JOIN sales s ON s.customer_id = c.id
      GROUP BY c.id
      ORDER BY net_total_spent DESC, transaction_count DESC, c.name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [limit <= 0 ? 20 : limit],
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Customer? customerFromHeldCartRow(Map<String, dynamic> row) {
    final id = (row['customer_id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;

    final name = (row['customer_name_snapshot'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final now = DateTime.now().toIso8601String();

    return Customer(
      id: id,
      customerCode: (row['customer_code_snapshot'] ?? '').toString(),
      name: name,
      phone: row['customer_phone_snapshot']?.toString(),
      phoneNormalized: normalizePhone(
        row['customer_phone_snapshot']?.toString() ?? '',
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  Customer? customerFromSaleRow(Map<String, dynamic> row) {
    final id = (row['customer_id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;

    final name = (row['customer_name_snapshot'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final now = DateTime.now().toIso8601String();

    return Customer(
      id: id,
      customerCode: (row['customer_code_snapshot'] ?? '').toString(),
      name: name,
      phone: row['customer_phone_snapshot']?.toString(),
      phoneNormalized: normalizePhone(
        row['customer_phone_snapshot']?.toString() ?? '',
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> saveCustomerSnapshotToHeldCart({
    required int heldCartId,
    Customer? customer,
  }) async {
    if (heldCartId <= 0) return;

    final db = await _db;
    await db.update(
      'held_carts',
      {
        'customer_id': customer?.id,
        'customer_name_snapshot': customer?.displayName,
        'customer_phone_snapshot': customer?.hasPhone == true
            ? customer?.phone?.trim()
            : null,
        'customer_code_snapshot': customer?.displayCode,
      },
      where: 'id = ?',
      whereArgs: [heldCartId],
    );
  }

  Future<void> saveCustomerSnapshotToLatestHeldCart({
    required String cartName,
    required String cashierName,
    Customer? customer,
  }) async {
    final cleanCartName = cartName.trim();
    final cleanCashierName = cashierName.trim();

    if (cleanCartName.isEmpty || cleanCashierName.isEmpty) return;

    final db = await _db;
    final rows = await db.query(
      'held_carts',
      columns: const ['id'],
      where: 'cart_name = ? AND cashier_name = ?',
      whereArgs: [cleanCartName, cleanCashierName],
      orderBy: 'datetime(updated_at) DESC, id DESC',
      limit: 1,
    );

    if (rows.isEmpty) return;

    final heldCartId = (rows.first['id'] as num?)?.toInt();
    if (heldCartId == null || heldCartId <= 0) return;

    await saveCustomerSnapshotToHeldCart(
      heldCartId: heldCartId,
      customer: customer,
    );
  }

  Future<void> debugSeedSampleCustomers() async {
    final db = await _db;
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $customersTable',
    );
    final count = ((countRows.first['count'] as num?) ?? 0).toInt();
    if (count > 0) return;

    final samples = [
      {
        'name': 'Nimal Perera',
        'phone': '0712345678',
        'customerType': 'regular',
        'address': 'Hikkaduwa',
      },
      {
        'name': 'Kamal Stores',
        'phone': '0771234567',
        'customerType': 'wholesale',
        'address': 'Galle',
      },
      {
        'name': 'Saman Kumara',
        'phone': '0759876543',
        'customerType': 'vip',
        'address': 'Ambalangoda',
      },
    ];

    for (final sample in samples) {
      try {
        await createCustomer(
          name: sample['name']!,
          phone: sample['phone'],
          customerType: sample['customerType']!,
          address: sample['address'],
        );
      } catch (e) {
        debugPrint('Sample customer seed skipped: $e');
      }
    }
  }
}
