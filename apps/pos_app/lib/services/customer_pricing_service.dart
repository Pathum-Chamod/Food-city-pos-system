import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';

class CustomerPricingService {
  CustomerPricingService._();

  static final CustomerPricingService instance = CustomerPricingService._();

  static const String productPricesTable = 'customer_product_prices';
  static const String customerPricingRulesTable = 'customer_pricing_rules';
  static const String customerCategoriesTable = 'customer_categories';
  static const String pricingSchemesTable = 'pricing_schemes';
  static const String pricingSchemeRulesTable = 'pricing_scheme_rules';

  Future<Database> get _db async {
    final db = await DatabaseHelper.instance.database;
    await ensureCustomerPricingStorage();
    return db;
  }

  Future<void> ensureCustomerPricingStorage() async {
    final db = await DatabaseHelper.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $productPricesTable (
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
      ON $productPricesTable(customer_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_product_prices_barcode
      ON $productPricesTable(barcode)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_product_prices_active
      ON $productPricesTable(is_active)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $customerPricingRulesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
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
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_pricing_rules_customer
      ON $customerPricingRulesTable(customer_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_pricing_rules_target
      ON $customerPricingRulesTable(customer_id, apply_to, category, barcode)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_pricing_rules_active
      ON $customerPricingRulesTable(customer_id, is_active, priority)
    ''');
  }

  Future<CustomerPricingResult> resolvePriceForProduct({
    required Customer? customer,
    required Product product,
    required double currentUnitPrice,
    required String currentPriceType,
  }) async {
    final originalPrice = _roundMoney(currentUnitPrice);
    if (customer == null) {
      return CustomerPricingResult(
        originalPrice: originalPrice,
        finalPrice: originalPrice,
      );
    }

    final customerId = customer.id;
    if (customerId == null || customerId <= 0) {
      return CustomerPricingResult(
        originalPrice: originalPrice,
        finalPrice: originalPrice,
      );
    }

    final customerRuleResult = await _resolveCustomerRulePriceForProduct(
      customerId: customerId,
      product: product,
      originalPrice: originalPrice,
    );
    if (customerRuleResult != null) return customerRuleResult;

    final specialPrice = await getActiveProductPrice(
      customerId: customerId,
      barcode: product.barcode,
    );
    if (specialPrice != null) {
      final finalPrice = _roundMoney(specialPrice.fixedPrice);
      return CustomerPricingResult(
        originalPrice: originalPrice,
        finalPrice: finalPrice,
        type: CustomerPricingType.customerProductPrice,
        ruleId: specialPrice.id,
        discountAmount: _discountAmount(originalPrice, finalPrice),
        note: specialPrice.note,
      );
    }

    final directSchemeResult = await _resolveSchemePriceForProduct(
      schemeId: customer.pricingSchemeId,
      pricingType: CustomerPricingType.customerDirectScheme,
      product: product,
      originalPrice: originalPrice,
    );
    if (directSchemeResult != null) return directSchemeResult;

    if (customer.pricingSchemeId != 0) {
      final categorySchemeId = await _getCategoryPricingSchemeId(
        customer.customerCategoryId,
      );
      final categorySchemeResult = await _resolveSchemePriceForProduct(
        schemeId: categorySchemeId,
        pricingType: CustomerPricingType.customerCategoryScheme,
        product: product,
        originalPrice: originalPrice,
      );
      if (categorySchemeResult != null) return categorySchemeResult;
    }

    return CustomerPricingResult(
      originalPrice: originalPrice,
      finalPrice: originalPrice,
    );
  }

  Future<int?> _getCategoryPricingSchemeId(int? customerCategoryId) async {
    if (customerCategoryId == null || customerCategoryId <= 0) return null;

    final db = await _db;
    final rows = await db.query(
      customerCategoriesTable,
      columns: const ['default_pricing_scheme_id'],
      where: 'id = ? AND is_active = 1',
      whereArgs: [customerCategoryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final schemeId = (rows.first['default_pricing_scheme_id'] as num?)?.toInt();
    if (schemeId == null || schemeId <= 0) return null;
    return schemeId;
  }

  Future<CustomerPricingResult?> _resolveSchemePriceForProduct({
    required int? schemeId,
    required CustomerPricingType pricingType,
    required Product product,
    required double originalPrice,
  }) async {
    if (schemeId == null || schemeId <= 0) return null;

    final rule = await _getBestActiveSchemeRule(
      schemeId: schemeId,
      product: product,
    );
    if (rule == null) return null;

    switch (rule.ruleType) {
      case PricingSchemeRuleType.priceType:
        final priceType = rule.priceType ?? ProductPriceType.selling;
        final finalPrice = _roundMoney(product.resolvePrice(priceType));
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: finalPrice,
          type: pricingType,
          priceType: priceType,
          ruleId: rule.id,
          discountAmount: _discountAmount(originalPrice, finalPrice),
          note: _schemeNote(rule, priceType.label),
        );
      case PricingSchemeRuleType.percentDiscount:
        final percent = rule.normalizedDiscountPercent;
        final finalPrice = _roundMoney(
          originalPrice - (originalPrice * (percent / 100)),
        );
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: finalPrice,
          type: pricingType,
          ruleId: rule.id,
          discountAmount: _discountAmount(originalPrice, finalPrice),
          note: _schemeNote(rule, '${percent.toStringAsFixed(2)}%'),
        );
      case PricingSchemeRuleType.fixedPrice:
        final finalPrice = _roundMoney(rule.fixedPrice ?? originalPrice);
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: finalPrice,
          type: pricingType,
          ruleId: rule.id,
          discountAmount: _discountAmount(originalPrice, finalPrice),
          note: _schemeNote(rule, 'Fixed Price'),
        );
      case PricingSchemeRuleType.noDiscount:
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: originalPrice,
          type: pricingType,
          ruleId: rule.id,
          discountAmount: 0.0,
          note: _schemeNote(rule, 'No Discount'),
        );
    }
  }

  Future<CustomerPricingResult?> _resolveCustomerRulePriceForProduct({
    required int customerId,
    required Product product,
    required double originalPrice,
  }) async {
    final rule = await _getBestActiveCustomerRule(
      customerId: customerId,
      product: product,
    );
    if (rule == null) return null;
    return _resultForRule(
      ruleType: rule.ruleType,
      priceType: rule.priceType,
      discountPercent: rule.normalizedDiscountPercent,
      fixedPrice: rule.fixedPrice,
      ruleId: rule.id,
      product: product,
      originalPrice: originalPrice,
      note: rule.note,
    );
  }

  CustomerPricingResult _resultForRule({
    required PricingSchemeRuleType ruleType,
    required ProductPriceType? priceType,
    required double discountPercent,
    required double? fixedPrice,
    required int? ruleId,
    required Product product,
    required double originalPrice,
    String? note,
  }) {
    switch (ruleType) {
      case PricingSchemeRuleType.priceType:
        final resolvedPriceType = priceType ?? ProductPriceType.selling;
        final finalPrice = _roundMoney(product.resolvePrice(resolvedPriceType));
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: finalPrice,
          type: CustomerPricingType.customerProductPrice,
          priceType: resolvedPriceType,
          ruleId: ruleId,
          discountAmount: _discountAmount(originalPrice, finalPrice),
          note: _cleanOptional(note) ?? resolvedPriceType.label,
        );
      case PricingSchemeRuleType.percentDiscount:
        final finalPrice = _roundMoney(
          originalPrice - (originalPrice * (discountPercent / 100)),
        );
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: finalPrice,
          type: CustomerPricingType.customerProductPrice,
          ruleId: ruleId,
          discountAmount: _discountAmount(originalPrice, finalPrice),
          note:
              _cleanOptional(note) ?? '${discountPercent.toStringAsFixed(2)}%',
        );
      case PricingSchemeRuleType.fixedPrice:
        final finalPrice = _roundMoney(fixedPrice ?? originalPrice);
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: finalPrice,
          type: CustomerPricingType.customerProductPrice,
          ruleId: ruleId,
          discountAmount: _discountAmount(originalPrice, finalPrice),
          note: _cleanOptional(note) ?? 'Fixed Price',
        );
      case PricingSchemeRuleType.noDiscount:
        return CustomerPricingResult(
          originalPrice: originalPrice,
          finalPrice: originalPrice,
          type: CustomerPricingType.customerProductPrice,
          ruleId: ruleId,
          discountAmount: 0.0,
          note: _cleanOptional(note) ?? 'No Discount',
        );
    }
  }

  Future<CustomerPricingRule?> _getBestActiveCustomerRule({
    required int customerId,
    required Product product,
  }) async {
    final cleanBarcode = product.barcode.trim();
    final cleanCategory = product.category.trim();
    if (customerId <= 0 || cleanBarcode.isEmpty) return null;

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM $customerPricingRulesTable
      WHERE customer_id = ?
        AND is_active = 1
        AND (
          (apply_to = 'product' AND LOWER(barcode) = LOWER(?))
          OR (apply_to = 'category' AND LOWER(category) = LOWER(?))
          OR apply_to = 'all'
        )
      ORDER BY
        CASE apply_to
          WHEN 'product' THEN 0
          WHEN 'category' THEN 1
          ELSE 2
        END ASC,
        priority ASC,
        updated_at DESC,
        id DESC
      LIMIT 1
      ''',
      [customerId, cleanBarcode, cleanCategory],
    );
    if (rows.isEmpty) return null;
    return CustomerPricingRule.fromMap(rows.first);
  }

  Future<List<CustomerPricingRule>> getRulesForCustomer(
    int customerId, {
    bool activeOnly = false,
  }) async {
    if (customerId <= 0) return const [];
    final db = await _db;
    final rows = await db.query(
      customerPricingRulesTable,
      where: activeOnly
          ? 'customer_id = ? AND is_active = 1'
          : 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'is_active DESC, priority ASC, updated_at DESC, id DESC',
    );
    return rows.map(CustomerPricingRule.fromMap).toList();
  }

  Future<int> countRulesForCustomer(int customerId) async {
    if (customerId <= 0) return 0;
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM $customerPricingRulesTable
      WHERE customer_id = ? AND is_active = 1
      ''',
      [customerId],
    );
    return ((rows.first['count'] as num?) ?? 0).toInt();
  }

  Future<int> upsertCustomerRule({
    int? id,
    required int customerId,
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
    if (customerId <= 0) throw Exception('Invalid customer.');
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final data = {
      'customer_id': customerId,
      'apply_to': applyTo.dbValue,
      'category': _cleanOptional(category),
      'barcode': _cleanOptional(barcode),
      'product_name_snapshot': _cleanOptional(productNameSnapshot),
      'rule_type': ruleType.dbValue,
      'price_type': priceType?.dbValue,
      'discount_percent': discountPercent.clamp(0.0, 100.0),
      'fixed_price': fixedPrice == null ? null : _roundMoney(fixedPrice),
      'priority': priority,
      'is_active': isActive ? 1 : 0,
      'note': _cleanOptional(note),
      'updated_at': now,
      'updated_by': userId,
    };
    if (id != null && id > 0) {
      await db.update(
        customerPricingRulesTable,
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return db.insert(customerPricingRulesTable, {
      ...data,
      'created_at': now,
      'created_by': userId,
    });
  }

  Future<void> setCustomerRuleActive({
    required int id,
    required bool isActive,
    int? updatedBy,
  }) async {
    if (id <= 0) return;
    final db = await _db;
    await db.update(
      customerPricingRulesTable,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<PricingSchemeRule?> _getBestActiveSchemeRule({
    required int schemeId,
    required Product product,
  }) async {
    final cleanBarcode = product.barcode.trim();
    final cleanCategory = product.category.trim();
    if (schemeId <= 0 || cleanBarcode.isEmpty) return null;

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT r.*
      FROM $pricingSchemeRulesTable r
      INNER JOIN $pricingSchemesTable s ON s.id = r.scheme_id
      WHERE r.scheme_id = ?
        AND r.is_active = 1
        AND s.is_active = 1
        AND (
          (r.apply_to = 'product' AND LOWER(r.barcode) = LOWER(?))
          OR (r.apply_to = 'category' AND LOWER(r.category) = LOWER(?))
          OR r.apply_to = 'all'
        )
      ORDER BY
        CASE r.apply_to
          WHEN 'product' THEN 0
          WHEN 'category' THEN 1
          ELSE 2
        END ASC,
        r.priority ASC,
        r.updated_at DESC,
        r.id DESC
      LIMIT 1
      ''',
      [schemeId, cleanBarcode, cleanCategory],
    );
    if (rows.isEmpty) return null;
    return PricingSchemeRule.fromMap(rows.first);
  }

  Future<CustomerProductPrice?> getActiveProductPrice({
    required int customerId,
    required String barcode,
  }) async {
    if (customerId <= 0 || barcode.trim().isEmpty) return null;

    final db = await _db;
    final rows = await db.query(
      productPricesTable,
      where: 'customer_id = ? AND barcode = ? AND is_active = 1',
      whereArgs: [customerId, barcode.trim()],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return CustomerProductPrice.fromMap(rows.first);
  }

  Future<List<CustomerProductPrice>> getProductPricesForCustomer(
    int customerId, {
    bool activeOnly = false,
  }) async {
    if (customerId <= 0) return const [];

    final db = await _db;
    final rows = await db.query(
      productPricesTable,
      where: activeOnly
          ? 'customer_id = ? AND is_active = 1'
          : 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'is_active DESC, product_name_snapshot COLLATE NOCASE ASC',
    );

    return rows.map(CustomerProductPrice.fromMap).toList();
  }

  Future<int> countProductPricesForCustomer(
    int customerId, {
    bool activeOnly = true,
  }) async {
    if (customerId <= 0) return 0;

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM $productPricesTable
      WHERE customer_id = ?
        ${activeOnly ? 'AND is_active = 1' : ''}
      ''',
      [customerId],
    );

    return ((rows.first['count'] as num?) ?? 0).toInt();
  }

  Future<int> upsertProductPrice({
    int? id,
    required int customerId,
    required String barcode,
    required String productNameSnapshot,
    required double fixedPrice,
    bool isActive = true,
    String? note,
    int? userId,
  }) async {
    if (customerId <= 0) throw Exception('Invalid customer.');
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) throw Exception('Product barcode is required.');
    final cleanName = productNameSnapshot.trim();
    if (cleanName.isEmpty) throw Exception('Product name is required.');
    if (fixedPrice < 0) throw Exception('Fixed price cannot be negative.');

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final cleanNote = _cleanOptional(note);

    int savedId;
    if (id != null && id > 0) {
      await db.update(
        productPricesTable,
        {
          'customer_id': customerId,
          'barcode': cleanBarcode,
          'product_name_snapshot': cleanName,
          'fixed_price': _roundMoney(fixedPrice),
          'is_active': isActive ? 1 : 0,
          'note': cleanNote,
          'updated_at': now,
          'updated_by': userId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      savedId = id;
      await _queueProductPriceSync(savedId);
      return savedId;
    }

    final existing = await db.query(
      productPricesTable,
      columns: const ['id'],
      where: 'customer_id = ? AND barcode = ?',
      whereArgs: [customerId, cleanBarcode],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingId = (existing.first['id'] as num).toInt();
      await db.update(
        productPricesTable,
        {
          'product_name_snapshot': cleanName,
          'fixed_price': _roundMoney(fixedPrice),
          'is_active': isActive ? 1 : 0,
          'note': cleanNote,
          'updated_at': now,
          'updated_by': userId,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
      savedId = existingId;
      await _queueProductPriceSync(savedId);
      return savedId;
    }

    savedId = await db.insert(productPricesTable, {
      'customer_id': customerId,
      'barcode': cleanBarcode,
      'product_name_snapshot': cleanName,
      'fixed_price': _roundMoney(fixedPrice),
      'is_active': isActive ? 1 : 0,
      'note': cleanNote,
      'created_at': now,
      'updated_at': now,
      'created_by': userId,
      'updated_by': userId,
    });
    await _queueProductPriceSync(savedId);
    return savedId;
  }

  Future<void> setProductPriceActive({
    required int id,
    required bool isActive,
    int? updatedBy,
  }) async {
    if (id <= 0) return;

    final db = await _db;
    await db.update(
      productPricesTable,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _queueProductPriceSync(id);
  }

  Future<void> _queueProductPriceSync(int id) async {
    if (id <= 0) return;

    final db = await _db;
    final rows = await db.query(
      productPricesTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = Map<String, dynamic>.from(rows.first);
    await db.insert('sync_queue', {
      'type': 'CUSTOMER_PRODUCT_PRICE_UPSERT',
      'data': jsonEncode({
        'id': row['id'],
        'customer_product_price_id': row['id'],
        'customer_id': row['customer_id'],
        'barcode': row['barcode'],
        'product_name_snapshot': row['product_name_snapshot'],
        'fixed_price': row['fixed_price'],
        'is_active': row['is_active'],
        'note': row['note'],
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
        'created_by': row['created_by'],
        'updated_by': row['updated_by'],
      }),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  double _discountAmount(double originalPrice, double finalPrice) {
    final discount = originalPrice - finalPrice;
    return discount <= 0 ? 0.0 : _roundMoney(discount);
  }

  double _roundMoney(num value) {
    return double.parse(value.toStringAsFixed(2));
  }

  String _schemeNote(PricingSchemeRule rule, String fallback) {
    final note = _cleanOptional(rule.note);
    if (note != null) return note;
    return fallback;
  }

  String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
