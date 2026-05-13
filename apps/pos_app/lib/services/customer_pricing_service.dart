import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';

class CustomerPricingService {
  CustomerPricingService._();

  static final CustomerPricingService instance = CustomerPricingService._();

  static const String productPricesTable = 'customer_product_prices';
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

    if (!customer.pricingEnabled) {
      return CustomerPricingResult(
        originalPrice: originalPrice,
        finalPrice: originalPrice,
      );
    }

    final currentType = ProductPriceTypeX.fromDb(currentPriceType);
    final defaultType = customer.defaultPriceType;
    final typePrice = _roundMoney(product.resolvePrice(defaultType));
    final defaultTypeChangesPrice =
        defaultType != currentType || typePrice != originalPrice;

    if (defaultTypeChangesPrice) {
      return CustomerPricingResult(
        originalPrice: originalPrice,
        finalPrice: typePrice,
        type: CustomerPricingType.customerDefaultPriceType,
        priceType: defaultType,
        discountAmount: _discountAmount(originalPrice, typePrice),
        note: defaultType.label,
      );
    }

    final discountPercent = customer.normalizedDefaultDiscountPercent;
    if (discountPercent > 0) {
      final finalPrice = _roundMoney(
        originalPrice - (originalPrice * (discountPercent / 100)),
      );
      return CustomerPricingResult(
        originalPrice: originalPrice,
        finalPrice: finalPrice,
        type: CustomerPricingType.customerDefaultDiscount,
        discountAmount: _discountAmount(originalPrice, finalPrice),
        note: '${discountPercent.toStringAsFixed(2)}%',
      );
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
