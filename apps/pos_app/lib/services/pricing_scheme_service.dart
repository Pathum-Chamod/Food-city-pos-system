import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'customer_service.dart';
import 'database_helper.dart';

class PricingSchemeService {
  PricingSchemeService._();

  static final PricingSchemeService instance = PricingSchemeService._();

  static const String customerCategoriesTable = 'customer_categories';
  static const String pricingSchemesTable = 'pricing_schemes';
  static const String pricingSchemeRulesTable = 'pricing_scheme_rules';

  Future<Database> get _db async {
    final db = await DatabaseHelper.instance.database;
    await CustomerService.instance.ensureCustomerStorage();
    return db;
  }

  Future<List<CustomerCategory>> getCustomerCategories({
    bool activeOnly = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      customerCategoriesTable,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'is_active DESC, name COLLATE NOCASE ASC',
    );

    return rows.map(CustomerCategory.fromMap).toList();
  }

  Future<Map<int, int>> getCustomerCountsByCategory() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT customer_category_id, COUNT(*) AS count
      FROM ${CustomerService.customersTable}
      WHERE customer_category_id IS NOT NULL
      GROUP BY customer_category_id
    ''');

    final result = <int, int>{};
    for (final row in rows) {
      final id = (row['customer_category_id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      result[id] = ((row['count'] as num?) ?? 0).toInt();
    }
    return result;
  }

  Future<CustomerCategory?> getCustomerCategoryById(int id) async {
    if (id <= 0) return null;
    final db = await _db;
    final rows = await db.query(
      customerCategoriesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CustomerCategory.fromMap(rows.first);
  }

  Future<int> createCustomerCategory({
    required String name,
    String? description,
    int? defaultPricingSchemeId,
  }) async {
    final cleanName = _requiredName(name, 'Category name is required.');
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final id = await db.insert(customerCategoriesTable, {
      'name': cleanName,
      'description': _cleanOptional(description),
      'default_pricing_scheme_id': _positiveOrNull(defaultPricingSchemeId),
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await _queueCustomerCategorySync(id);
    return id;
  }

  Future<void> updateCustomerCategory({
    required int id,
    required String name,
    String? description,
    int? defaultPricingSchemeId,
    bool isActive = true,
  }) async {
    if (id <= 0) throw Exception('Invalid customer category.');
    final cleanName = _requiredName(name, 'Category name is required.');
    final db = await _db;

    await db.update(
      customerCategoriesTable,
      {
        'name': cleanName,
        'description': _cleanOptional(description),
        'default_pricing_scheme_id': _positiveOrNull(defaultPricingSchemeId),
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queueCustomerCategorySync(id);
  }

  Future<void> setCustomerCategoryActive({
    required int id,
    required bool isActive,
  }) async {
    if (id <= 0) return;
    final db = await _db;
    await db.update(
      customerCategoriesTable,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queueCustomerCategorySync(id);
  }

  Future<void> deleteCustomerCategory({
    required int id,
  }) async {
    if (id <= 0) throw Exception('Invalid customer category.');
    final db = await _db;

    final assignedRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${CustomerService.customersTable}
      WHERE customer_category_id = ?
      ''',
      [id],
    );
    final assignedCount = ((assignedRows.first['count'] as num?) ?? 0).toInt();
    if (assignedCount > 0) {
      throw Exception(
        'Cannot delete category. $assignedCount customer(s) are assigned to it.',
      );
    }

    await db.delete(
      customerCategoriesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> assignCustomerCategory({
    required int customerId,
    int? customerCategoryId,
    int? updatedBy,
  }) async {
    if (customerId <= 0) throw Exception('Invalid customer.');
    final db = await _db;
    await db.update(
      CustomerService.customersTable,
      {
        'customer_category_id': _positiveOrNull(customerCategoryId),
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
    await _queueCustomerPricingAssignmentSync(customerId);
  }

  Future<void> assignCustomerPricingScheme({
    required int customerId,
    int? pricingSchemeId,
    int? updatedBy,
  }) async {
    if (customerId <= 0) throw Exception('Invalid customer.');
    final db = await _db;
    await db.update(
      CustomerService.customersTable,
      {
        'pricing_scheme_id': _pricingSchemeSelectionValue(pricingSchemeId),
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
    await _queueCustomerPricingAssignmentSync(customerId);
  }

  Future<List<PricingScheme>> getPricingSchemes({
    bool activeOnly = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      pricingSchemesTable,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'is_active DESC, priority ASC, name COLLATE NOCASE ASC',
    );

    return rows.map(PricingScheme.fromMap).toList();
  }

  Future<PricingScheme?> getPricingSchemeById(int id) async {
    if (id <= 0) return null;
    final db = await _db;
    final rows = await db.query(
      pricingSchemesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PricingScheme.fromMap(rows.first);
  }

  Future<Map<int, int>> getRuleCountsByScheme() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT scheme_id, COUNT(*) AS count
      FROM $pricingSchemeRulesTable
      GROUP BY scheme_id
    ''');

    final result = <int, int>{};
    for (final row in rows) {
      final id = (row['scheme_id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      result[id] = ((row['count'] as num?) ?? 0).toInt();
    }
    return result;
  }

  Future<Map<int, int>> getCategoryCountsByScheme() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT default_pricing_scheme_id, COUNT(*) AS count
      FROM $customerCategoriesTable
      WHERE default_pricing_scheme_id IS NOT NULL
      GROUP BY default_pricing_scheme_id
    ''');

    final result = <int, int>{};
    for (final row in rows) {
      final id = (row['default_pricing_scheme_id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      result[id] = ((row['count'] as num?) ?? 0).toInt();
    }
    return result;
  }

  Future<Map<int, int>> getCustomerCountsByDirectScheme() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT pricing_scheme_id, COUNT(*) AS count
      FROM ${CustomerService.customersTable}
      WHERE pricing_scheme_id IS NOT NULL
      GROUP BY pricing_scheme_id
    ''');

    final result = <int, int>{};
    for (final row in rows) {
      final id = (row['pricing_scheme_id'] as num?)?.toInt();
      if (id == null || id <= 0) continue;
      result[id] = ((row['count'] as num?) ?? 0).toInt();
    }
    return result;
  }

  Future<int> createPricingScheme({
    required String name,
    String? description,
    bool isActive = true,
    int priority = 100,
    int? userId,
  }) async {
    final cleanName = _requiredName(name, 'Pricing scheme name is required.');
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final id = await db.insert(pricingSchemesTable, {
      'name': cleanName,
      'description': _cleanOptional(description),
      'is_active': isActive ? 1 : 0,
      'priority': priority,
      'created_at': now,
      'updated_at': now,
      'created_by': userId,
      'updated_by': userId,
    });
    await _queuePricingSchemeSync(id);
    return id;
  }

  Future<void> updatePricingScheme({
    required int id,
    required String name,
    String? description,
    bool isActive = true,
    int priority = 100,
    int? updatedBy,
  }) async {
    if (id <= 0) throw Exception('Invalid pricing scheme.');
    final cleanName = _requiredName(name, 'Pricing scheme name is required.');
    final db = await _db;

    await db.update(
      pricingSchemesTable,
      {
        'name': cleanName,
        'description': _cleanOptional(description),
        'is_active': isActive ? 1 : 0,
        'priority': priority,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queuePricingSchemeSync(id);
  }

  Future<void> setPricingSchemeActive({
    required int id,
    required bool isActive,
    int? updatedBy,
  }) async {
    if (id <= 0) return;
    final db = await _db;
    await db.update(
      pricingSchemesTable,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queuePricingSchemeSync(id);
  }

  Future<void> deletePricingScheme({
    required int id,
  }) async {
    if (id <= 0) throw Exception('Invalid pricing scheme.');
    final db = await _db;

    final ruleRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM $pricingSchemeRulesTable
      WHERE scheme_id = ?
      ''',
      [id],
    );
    final ruleCount = ((ruleRows.first['count'] as num?) ?? 0).toInt();
    if (ruleCount > 0) {
      throw Exception(
        'Cannot delete scheme. Remove $ruleCount linked rule(s) first.',
      );
    }

    final categoryRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM $customerCategoriesTable
      WHERE default_pricing_scheme_id = ?
      ''',
      [id],
    );
    final categoryCount =
        ((categoryRows.first['count'] as num?) ?? 0).toInt();
    if (categoryCount > 0) {
      throw Exception(
        'Cannot delete scheme. It is used by $categoryCount category(ies).',
      );
    }

    final customerRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${CustomerService.customersTable}
      WHERE pricing_scheme_id = ?
      ''',
      [id],
    );
    final customerCount =
        ((customerRows.first['count'] as num?) ?? 0).toInt();
    if (customerCount > 0) {
      throw Exception(
        'Cannot delete scheme. It is directly assigned to $customerCount customer(s).',
      );
    }

    await db.delete(
      pricingSchemesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> duplicatePricingScheme({
    required int sourceSchemeId,
    String? newName,
    int? userId,
  }) async {
    if (sourceSchemeId <= 0) throw Exception('Invalid pricing scheme.');
    final db = await _db;
    final source = await getPricingSchemeById(sourceSchemeId);
    if (source == null) throw Exception('Pricing scheme not found.');

    final newSchemeId = await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final copyName = await _uniqueSchemeName(
        txn,
        newName?.trim().isNotEmpty == true
            ? newName!.trim()
            : '${source.displayName} Copy',
      );

      final newSchemeId = await txn.insert(pricingSchemesTable, {
        'name': copyName,
        'description': source.description,
        'is_active': source.isActive ? 1 : 0,
        'priority': source.priority,
        'created_at': now,
        'updated_at': now,
        'created_by': userId,
        'updated_by': userId,
      });

      final rules = await txn.query(
        pricingSchemeRulesTable,
        where: 'scheme_id = ?',
        whereArgs: [sourceSchemeId],
        orderBy: 'priority ASC, id ASC',
      );

      for (final rule in rules) {
        final data = Map<String, Object?>.from(rule);
        data
          ..remove('id')
          ..['scheme_id'] = newSchemeId
          ..['created_at'] = now
          ..['updated_at'] = now
          ..['created_by'] = userId
          ..['updated_by'] = userId;
        await txn.insert(pricingSchemeRulesTable, data);
      }

      return newSchemeId;
    });
    await _queuePricingSchemeSync(newSchemeId);
    final rules = await getRulesForScheme(newSchemeId);
    for (final rule in rules) {
      final ruleId = rule.id;
      if (ruleId != null && ruleId > 0) {
        await _queuePricingSchemeRuleSync(ruleId);
      }
    }
    return newSchemeId;
  }

  Future<List<PricingSchemeRule>> getRulesForScheme(
    int schemeId, {
    bool activeOnly = false,
  }) async {
    if (schemeId <= 0) return const [];
    final db = await _db;
    final rows = await db.query(
      pricingSchemeRulesTable,
      where: activeOnly ? 'scheme_id = ? AND is_active = 1' : 'scheme_id = ?',
      whereArgs: [schemeId],
      orderBy: 'is_active DESC, priority ASC, updated_at DESC, id DESC',
    );

    return rows.map(PricingSchemeRule.fromMap).toList();
  }

  Future<int> upsertPricingSchemeRule({
    int? id,
    required int schemeId,
    required PricingSchemeRuleApplyTo applyTo,
    String? category,
    String? barcode,
    String? productNameSnapshot,
    required PricingSchemeRuleType ruleType,
    ProductPriceType? priceType,
    double discountPercent = 0.0,
    double? fixedPrice,
    int priority = 100,
    bool isActive = true,
    String? note,
    int? userId,
  }) async {
    if (schemeId <= 0) throw Exception('Invalid pricing scheme.');
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final data = {
      'scheme_id': schemeId,
      'apply_to': applyTo.dbValue,
      'category': _cleanOptional(category),
      'barcode': _cleanOptional(barcode),
      'product_name_snapshot': _cleanOptional(productNameSnapshot),
      'rule_type': ruleType.dbValue,
      'price_type': priceType?.dbValue,
      'discount_percent': _clampPercent(discountPercent),
      'fixed_price': fixedPrice == null ? null : _roundMoney(fixedPrice),
      'priority': priority,
      'is_active': isActive ? 1 : 0,
      'note': _cleanOptional(note),
      'updated_at': now,
      'updated_by': userId,
    };

    if (id != null && id > 0) {
      await db.update(
        pricingSchemeRulesTable,
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _queuePricingSchemeRuleSync(id);
      return id;
    }

    final savedId = await db.insert(pricingSchemeRulesTable, {
      ...data,
      'created_at': now,
      'created_by': userId,
    });
    await _queuePricingSchemeRuleSync(savedId);
    return savedId;
  }

  Future<void> setPricingSchemeRuleActive({
    required int id,
    required bool isActive,
    int? updatedBy,
  }) async {
    if (id <= 0) return;
    final db = await _db;
    await db.update(
      pricingSchemeRulesTable,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queuePricingSchemeRuleSync(id);
  }

  Future<void> deletePricingSchemeRule({
    required int id,
  }) async {
    if (id <= 0) throw Exception('Invalid pricing rule.');
    final db = await _db;
    await db.delete(
      pricingSchemeRulesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _queueCustomerCategorySync(int id) async {
    await _queueRowSync(
      type: 'CUSTOMER_CATEGORY_UPSERT',
      table: customerCategoriesTable,
      id: id,
    );
  }

  Future<void> _queuePricingSchemeSync(int id) async {
    await _queueRowSync(
      type: 'PRICING_SCHEME_UPSERT',
      table: pricingSchemesTable,
      id: id,
    );
  }

  Future<void> _queuePricingSchemeRuleSync(int id) async {
    await _queueRowSync(
      type: 'PRICING_SCHEME_RULE_UPSERT',
      table: pricingSchemeRulesTable,
      id: id,
    );
  }

  Future<void> _queueCustomerPricingAssignmentSync(int customerId) async {
    if (customerId <= 0) return;

    final db = await _db;
    final rows = await db.query(
      CustomerService.customersTable,
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = Map<String, dynamic>.from(rows.first);
    await db.insert('sync_queue', {
      'type': 'CUSTOMER_PRICING_ASSIGNMENT',
      'data': jsonEncode({
        'customer_id': row['id'],
        'customer_code': row['customer_code'],
        'customer_name': row['name'],
        'customer_phone': row['phone'],
        'customer_phone_normalized': row['phone_normalized'],
        'customer_email': row['email'],
        'customer_address': row['address'],
        'customer_type': row['customer_type'],
        'customer_notes': row['notes'],
        'customer_is_active': row['is_active'],
        'customer_category_id': row['customer_category_id'],
        'pricing_scheme_id': row['pricing_scheme_id'],
        'updated_by': row['updated_by'],
        'updated_at': row['updated_at'],
      }),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _queueRowSync({
    required String type,
    required String table,
    required int id,
  }) async {
    if (id <= 0) return;

    final db = await _db;
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    await db.insert('sync_queue', {
      'type': type,
      'data': jsonEncode(Map<String, dynamic>.from(rows.first)),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  String _requiredName(String value, String message) {
    final clean = value.trim();
    if (clean.isEmpty) throw Exception(message);
    return clean;
  }

  String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  int? _positiveOrNull(int? value) {
    if (value == null || value <= 0) return null;
    return value;
  }

  int? _pricingSchemeSelectionValue(int? value) {
    if (value == null) return null;
    if (value == 0) return 0;
    if (value > 0) return value;
    return null;
  }

  double _clampPercent(double value) {
    if (value < 0) return 0.0;
    if (value > 100) return 100.0;
    return value;
  }

  double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  Future<String> _uniqueSchemeName(Transaction txn, String baseName) async {
    var candidate = baseName.trim();
    if (candidate.isEmpty) candidate = 'Pricing Scheme Copy';

    var suffix = 2;
    while (true) {
      final rows = await txn.query(
        pricingSchemesTable,
        columns: const ['id'],
        where: 'LOWER(name) = ?',
        whereArgs: [candidate.toLowerCase()],
        limit: 1,
      );
      if (rows.isEmpty) return candidate;

      candidate = '${baseName.trim()} $suffix';
      suffix += 1;
    }
  }
}
