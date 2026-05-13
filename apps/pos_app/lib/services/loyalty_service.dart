import 'dart:convert';
import 'dart:math' as math;

import 'package:shared/shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'customer_service.dart';
import 'database_helper.dart';

class LoyaltyService {
  LoyaltyService._();

  static final LoyaltyService instance = LoyaltyService._();

  static const String settingsTable = 'loyalty_settings';
  static const String ledgerTable = 'loyalty_ledger';
  static const String excludedCategoriesTable = 'loyalty_excluded_categories';
  static const String excludedProductsTable = 'loyalty_excluded_products';

  bool _storageReady = false;
  Future<void>? _ensureFuture;

  Future<Database> get _db async {
    await ensureLoyaltyStorage();
    return DatabaseHelper.instance.database;
  }

  Future<void> ensureLoyaltyStorage() async {
    if (_storageReady) return;
    _ensureFuture ??= _ensureLoyaltyStorageInternal();
    await _ensureFuture;
    _storageReady = true;
  }

  Future<void> _ensureLoyaltyStorageInternal() async {
    final db = await DatabaseHelper.instance.database;
    await CustomerService.instance.ensureCustomerStorage();

    await _addColumnIfMissing(
      db,
      CustomerService.customersTable,
      'loyalty_enabled',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      CustomerService.customersTable,
      'loyalty_points_balance',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      CustomerService.customersTable,
      'loyalty_lifetime_earned',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      CustomerService.customersTable,
      'loyalty_lifetime_redeemed',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      db,
      'sales',
      'loyalty_points_earned',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'sales',
      'loyalty_points_redeemed',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'sales',
      'loyalty_redeemed_value',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'sales',
      'loyalty_earn_base_amount',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'sales',
      'loyalty_status',
      "TEXT NOT NULL DEFAULT 'none'",
    );
    await _addColumnIfMissing(db, 'sales', 'loyalty_note', 'TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $settingsTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        is_enabled INTEGER NOT NULL DEFAULT 1,
        earn_rate_amount REAL NOT NULL DEFAULT 100,
        earn_rate_points INTEGER NOT NULL DEFAULT 1,
        point_value_amount REAL NOT NULL DEFAULT 1,
        minimum_redeem_points INTEGER NOT NULL DEFAULT 100,
        maximum_redeem_percent REAL NOT NULL DEFAULT 20,
        allow_credit_sale_earn INTEGER NOT NULL DEFAULT 0,
        rounding_mode TEXT NOT NULL DEFAULT 'floor',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $ledgerTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        points_delta INTEGER NOT NULL,
        points_balance_after INTEGER NOT NULL,
        money_value REAL NOT NULL DEFAULT 0,
        sale_id INTEGER,
        refund_sale_id INTEGER,
        description TEXT,
        created_at TEXT NOT NULL,
        created_by TEXT,
        voided_at TEXT,
        voided_by TEXT,
        void_reason TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $excludedCategoriesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_name TEXT NOT NULL UNIQUE,
        exclude_earning INTEGER NOT NULL DEFAULT 1,
        exclude_redemption INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $excludedProductsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL UNIQUE,
        product_name_snapshot TEXT NOT NULL,
        exclude_earning INTEGER NOT NULL DEFAULT 1,
        exclude_redemption INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_loyalty ON ${CustomerService.customersTable}(loyalty_enabled, loyalty_points_balance)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_customer ON $ledgerTable(customer_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_sale ON $ledgerTable(sale_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_refund ON $ledgerTable(refund_sale_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_ledger_type ON $ledgerTable(entry_type, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_excluded_categories_active ON $excludedCategoriesTable(is_active, category_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loyalty_excluded_products_active ON $excludedProductsTable(is_active, barcode)',
    );

    await _seedDefaultSettings(db);
  }

  Future<void> _seedDefaultSettings(Database db) async {
    final defaults = LoyaltySettings.defaults();
    await db.insert(
      settingsTable,
      defaults.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<LoyaltySettings> getSettings() async {
    final db = await _db;
    final rows = await db.query(settingsTable, where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      await _seedDefaultSettings(db);
      return getSettings();
    }
    return LoyaltySettings.fromMap(rows.first);
  }

  Future<void> updateSettings({
    required bool isEnabled,
    required double earnRateAmount,
    required int earnRatePoints,
    required double pointValueAmount,
    required int minimumRedeemPoints,
    required double maximumRedeemPercent,
    bool allowCreditSaleEarn = false,
    String roundingMode = 'floor',
  }) async {
    final db = await _db;
    final existing = await getSettings();
    final updatedAt = DateTime.now().toIso8601String();
    final settings = LoyaltySettings(
      id: 1,
      isEnabled: isEnabled,
      earnRateAmount: earnRateAmount,
      earnRatePoints: earnRatePoints,
      pointValueAmount: pointValueAmount,
      minimumRedeemPoints: minimumRedeemPoints,
      maximumRedeemPercent: maximumRedeemPercent,
      allowCreditSaleEarn: allowCreditSaleEarn,
      roundingMode: roundingMode,
      createdAt: existing.createdAt,
      updatedAt: updatedAt,
    );
    await db.update(
      settingsTable,
      settings.toMap(),
      where: 'id = 1',
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.delete(
      'sync_queue',
      where: 'type = ? AND status = ?',
      whereArgs: ['LOYALTY_SETTINGS', 'pending'],
    );
    await db.insert('sync_queue', {
      'type': 'LOYALTY_SETTINGS',
      'data': jsonEncode(settings.toMap()),
      'status': 'pending',
      'created_at': updatedAt,
    });
  }

  int calculateEarnedPoints({
    required double eligibleAmount,
    required LoyaltySettings settings,
  }) {
    if (!settings.isEnabled || eligibleAmount <= 0) return 0;
    final rawPoints =
        eligibleAmount /
        settings.safeEarnRateAmount *
        settings.safeEarnRatePoints;
    switch (settings.normalizedRoundingMode) {
      case 'ceil':
        return rawPoints.ceil();
      case 'round':
        return rawPoints.round();
      case 'floor':
      default:
        return rawPoints.floor();
    }
  }

  int maxRedeemablePoints({
    required int currentPointsBalance,
    required double billTotal,
    required LoyaltySettings settings,
  }) {
    if (!settings.isEnabled || currentPointsBalance <= 0 || billTotal <= 0) {
      return 0;
    }
    final maxValue = billTotal * settings.safeMaximumRedeemPercent / 100;
    final maxByBill = (maxValue / settings.safePointValueAmount).floor();
    final allowed = math.min(currentPointsBalance, maxByBill);
    if (allowed < settings.safeMinimumRedeemPoints) return 0;
    return allowed;
  }

  Future<void> setCustomerLoyaltyEnabled({
    required int customerId,
    required bool enabled,
  }) async {
    if (customerId <= 0) throw Exception('Invalid customer.');
    final db = await _db;
    await db.update(
      CustomerService.customersTable,
      {
        'loyalty_enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
    await _queueCustomerLoyaltySettingsSync(customerId);
  }

  Future<int> earnPointsForSale({
    required int saleId,
    required Customer? customer,
    required double eligibleAmount,
    required String? paymentMethod,
    required bool isCreditSale,
    required bool isRefund,
    String? cashierName,
  }) async {
    final customerId = customer?.id ?? 0;
    if (saleId <= 0 || customerId <= 0 || isRefund || isCreditSale) return 0;

    final normalizedPaymentMethod = (paymentMethod ?? '').trim().toLowerCase();
    if (normalizedPaymentMethod != 'cash' &&
        normalizedPaymentMethod != 'card') {
      return 0;
    }

    final settings = await getSettings();
    if (!settings.isEnabled || !customer!.loyaltyEnabled) return 0;

    final safeEligibleAmount = await _eligibleEarnBaseForSale(
      saleId: saleId,
      paidTotal: eligibleAmount,
    );
    final points = calculateEarnedPoints(
      eligibleAmount: safeEligibleAmount,
      settings: settings,
    );
    if (points <= 0) {
      await _markSaleLoyaltySkipped(
        saleId: saleId,
        earnBaseAmount: safeEligibleAmount,
        note: 'Sale total did not earn loyalty points.',
      );
      return 0;
    }

    final db = await _db;
    return db.transaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        columns: const [
          'id',
          'transaction_type',
          'payment_method',
          'loyalty_points_earned',
          'loyalty_points_redeemed',
          'loyalty_status',
        ],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (saleRows.isEmpty) return 0;

      final sale = saleRows.first;
      final saleType = (sale['transaction_type'] ?? '')
          .toString()
          .toLowerCase();
      final salePaymentMethod = (sale['payment_method'] ?? '')
          .toString()
          .toLowerCase();
      final existingPoints = ((sale['loyalty_points_earned'] as num?) ?? 0)
          .toInt();
      final redeemedPoints = ((sale['loyalty_points_redeemed'] as num?) ?? 0)
          .toInt();
      final existingStatus = (sale['loyalty_status'] ?? '')
          .toString()
          .toLowerCase();

      if (existingPoints > 0 || existingStatus == 'earned') return 0;
      if (saleType == 'refund' ||
          (salePaymentMethod != 'cash' && salePaymentMethod != 'card')) {
        return 0;
      }

      final existingLedgerRows = await txn.query(
        ledgerTable,
        columns: const ['id'],
        where:
            'sale_id = ? AND entry_type = ? AND customer_id = ? AND voided_at IS NULL',
        whereArgs: [saleId, LoyaltyEntryType.earn.dbValue, customerId],
        limit: 1,
      );
      if (existingLedgerRows.isNotEmpty) return 0;

      final balance = await _currentBalance(txn, customerId);
      final nextBalance = balance + points;
      final now = DateTime.now().toIso8601String();

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': LoyaltyEntryType.earn.dbValue,
        'points_delta': points,
        'points_balance_after': nextBalance,
        'money_value': 0.0,
        'sale_id': saleId,
        'refund_sale_id': null,
        'description': 'Earned from sale #$saleId',
        'created_at': now,
        'created_by': _cleanOptional(cashierName),
      });

      await txn.update(
        'sales',
        {
          'loyalty_points_earned': points,
          'loyalty_earn_base_amount': safeEligibleAmount,
          'loyalty_status': redeemedPoints > 0 ? 'redeemed_earned' : 'earned',
          'loyalty_note': redeemedPoints > 0
              ? 'Redeemed $redeemedPoints point${redeemedPoints == 1 ? '' : 's'} and earned $points point${points == 1 ? '' : 's'}'
              : 'Earned $points point${points == 1 ? '' : 's'}',
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      await _updateCustomerLoyaltyCache(txn, customerId);
      await _queueLoyaltyLedgerSync(txn, ledgerId);
      await _queueLoyaltySaleUpdateSync(txn, saleId);
      return points;
    });
  }

  Future<int> redeemPointsForSale({
    required int saleId,
    required Customer? customer,
    required int pointsToRedeem,
    required double billTotalBeforeRedemption,
    String? cashierName,
  }) async {
    final customerId = customer?.id ?? 0;
    if (saleId <= 0 || customerId <= 0 || pointsToRedeem <= 0) return 0;

    final settings = await getSettings();
    if (!settings.isEnabled || !customer!.loyaltyEnabled) return 0;

    final maxAllowed = maxRedeemablePoints(
      currentPointsBalance: customer.loyaltyPointsBalance,
      billTotal: billTotalBeforeRedemption,
      settings: settings,
    );
    if (pointsToRedeem > maxAllowed) {
      throw Exception('Redeemable loyalty points exceeded.');
    }

    final redeemedValue = _roundMoney(
      pointsToRedeem * settings.safePointValueAmount,
    );
    if (redeemedValue <= 0) return 0;

    final db = await _db;
    return db.transaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        columns: const [
          'id',
          'transaction_type',
          'payment_method',
          'loyalty_points_redeemed',
        ],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (saleRows.isEmpty) return 0;

      final sale = saleRows.first;
      final saleType = (sale['transaction_type'] ?? '')
          .toString()
          .toLowerCase();
      final salePaymentMethod = (sale['payment_method'] ?? '')
          .toString()
          .toLowerCase();
      final existingRedeemed = ((sale['loyalty_points_redeemed'] as num?) ?? 0)
          .toInt();

      if (existingRedeemed > 0 ||
          saleType == 'refund' ||
          (salePaymentMethod != 'cash' && salePaymentMethod != 'card')) {
        return 0;
      }

      final existingLedgerRows = await txn.query(
        ledgerTable,
        columns: const ['id'],
        where:
            'sale_id = ? AND entry_type = ? AND customer_id = ? AND voided_at IS NULL',
        whereArgs: [saleId, LoyaltyEntryType.redeem.dbValue, customerId],
        limit: 1,
      );
      if (existingLedgerRows.isNotEmpty) return 0;

      final balance = await _currentBalance(txn, customerId);
      if (balance < pointsToRedeem) {
        throw Exception('Insufficient loyalty points.');
      }

      final nextBalance = balance - pointsToRedeem;
      final now = DateTime.now().toIso8601String();

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': LoyaltyEntryType.redeem.dbValue,
        'points_delta': -pointsToRedeem,
        'points_balance_after': nextBalance,
        'money_value': redeemedValue,
        'sale_id': saleId,
        'refund_sale_id': null,
        'description': 'Redeemed on sale #$saleId',
        'created_at': now,
        'created_by': _cleanOptional(cashierName),
      });

      await txn.update(
        'sales',
        {
          'loyalty_points_redeemed': pointsToRedeem,
          'loyalty_redeemed_value': redeemedValue,
          'loyalty_status': 'redeemed',
          'loyalty_note':
              'Redeemed $pointsToRedeem point${pointsToRedeem == 1 ? '' : 's'}',
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      await _updateCustomerLoyaltyCache(txn, customerId);
      await _queueLoyaltyLedgerSync(txn, ledgerId);
      await _queueLoyaltySaleUpdateSync(txn, saleId);
      return pointsToRedeem;
    });
  }

  Future<void> reverseLoyaltyForRefund({
    required int originalSaleId,
    required int refundSaleId,
    String? performedBy,
  }) async {
    if (originalSaleId <= 0 || refundSaleId <= 0) return;

    final db = await _db;
    await db.transaction((txn) async {
      final originalRows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [originalSaleId],
        limit: 1,
      );
      final refundRows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [refundSaleId],
        limit: 1,
      );
      if (originalRows.isEmpty || refundRows.isEmpty) return;

      final original = originalRows.first;
      final refund = refundRows.first;
      final customerId = ((original['customer_id'] as num?) ?? 0).toInt();
      if (customerId <= 0) return;

      final originalEarned = ((original['loyalty_points_earned'] as num?) ?? 0)
          .toInt();
      final originalRedeemed =
          ((original['loyalty_points_redeemed'] as num?) ?? 0).toInt();
      if (originalEarned <= 0 && originalRedeemed <= 0) return;

      final alreadyProcessed = await txn.query(
        ledgerTable,
        columns: const ['id'],
        where:
            'refund_sale_id = ? AND entry_type IN (?, ?) AND customer_id = ? AND voided_at IS NULL',
        whereArgs: [
          refundSaleId,
          LoyaltyEntryType.refundEarnReversal.dbValue,
          LoyaltyEntryType.refundRedeemRestore.dbValue,
          customerId,
        ],
        limit: 1,
      );
      if (alreadyProcessed.isNotEmpty) return;

      final originalItemTotal = await _saleItemTotal(txn, originalSaleId);
      final currentRefundItemTotal = await _saleItemTotal(txn, refundSaleId);
      if (originalItemTotal <= 0 || currentRefundItemTotal <= 0) return;

      final cumulativeRefundItemTotal = await _cumulativeRefundItemTotal(
        txn,
        originalSaleId,
      );
      final fullRefund =
          cumulativeRefundItemTotal + 0.000001 >= originalItemTotal;

      final alreadyEarnReversed = await _sumLoyaltyPoints(
        txn,
        customerId: customerId,
        originalSaleId: originalSaleId,
        entryType: LoyaltyEntryType.refundEarnReversal,
      );
      final targetEarnReversal = fullRefund
          ? originalEarned
          : (originalEarned * (cumulativeRefundItemTotal / originalItemTotal))
                .floor();
      final earnReversalPoints = targetEarnReversal - alreadyEarnReversed;

      final alreadyRedeemRestored = await _sumLoyaltyPoints(
        txn,
        customerId: customerId,
        originalSaleId: originalSaleId,
        entryType: LoyaltyEntryType.refundRedeemRestore,
      );
      final redeemRestorePoints = fullRefund
          ? originalRedeemed - alreadyRedeemRestored
          : 0;

      if (earnReversalPoints <= 0 && redeemRestorePoints <= 0) return;

      final now = DateTime.now().toIso8601String();
      final actor =
          _cleanOptional(performedBy) ??
          _cleanOptional(refund['cashier_name']?.toString());
      var balance = await _currentBalance(txn, customerId);

      if (earnReversalPoints > 0) {
        balance -= earnReversalPoints;
        final ledgerId = await txn.insert(ledgerTable, {
          'customer_id': customerId,
          'entry_type': LoyaltyEntryType.refundEarnReversal.dbValue,
          'points_delta': -earnReversalPoints,
          'points_balance_after': balance,
          'money_value': 0.0,
          'sale_id': originalSaleId,
          'refund_sale_id': refundSaleId,
          'description': 'Reversed earned points for refund #$refundSaleId',
          'created_at': now,
          'created_by': actor,
        });
        await _queueLoyaltyLedgerSync(txn, ledgerId);
      }

      double restoredMoneyValue = 0.0;
      if (redeemRestorePoints > 0) {
        final originalRedeemedValue =
            ((original['loyalty_redeemed_value'] as num?) ?? 0).toDouble();
        restoredMoneyValue = _roundMoney(
          originalRedeemed > 0
              ? originalRedeemedValue * (redeemRestorePoints / originalRedeemed)
              : 0.0,
        );
        balance += redeemRestorePoints;
        final ledgerId = await txn.insert(ledgerTable, {
          'customer_id': customerId,
          'entry_type': LoyaltyEntryType.refundRedeemRestore.dbValue,
          'points_delta': redeemRestorePoints,
          'points_balance_after': balance,
          'money_value': restoredMoneyValue,
          'sale_id': originalSaleId,
          'refund_sale_id': refundSaleId,
          'description': 'Restored redeemed points for refund #$refundSaleId',
          'created_at': now,
          'created_by': actor,
        });
        await _queueLoyaltyLedgerSync(txn, ledgerId);
      }

      final noteParts = <String>[
        if (earnReversalPoints > 0)
          'Reversed $earnReversalPoints earned point${earnReversalPoints == 1 ? '' : 's'}',
        if (redeemRestorePoints > 0)
          'Restored $redeemRestorePoints redeemed point${redeemRestorePoints == 1 ? '' : 's'}',
      ];

      await txn.update(
        'sales',
        {
          'customer_id': customerId,
          'customer_name_snapshot': original['customer_name_snapshot'],
          'customer_phone_snapshot': original['customer_phone_snapshot'],
          'customer_code_snapshot': original['customer_code_snapshot'],
          'loyalty_points_earned': -earnReversalPoints,
          'loyalty_points_redeemed': -redeemRestorePoints,
          'loyalty_redeemed_value': -restoredMoneyValue,
          'loyalty_status': redeemRestorePoints > 0
              ? 'refund_reversed_restored'
              : 'refund_reversed',
          'loyalty_note': noteParts.join('. '),
        },
        where: 'id = ?',
        whereArgs: [refundSaleId],
      );

      await _updateCustomerLoyaltyCache(txn, customerId);
      await _queueLoyaltySaleUpdateSync(txn, refundSaleId);
    });
  }

  Future<void> _markSaleLoyaltySkipped({
    required int saleId,
    required double earnBaseAmount,
    required String note,
  }) async {
    final db = await _db;
    await db.update(
      'sales',
      {
        'loyalty_points_earned': 0,
        'loyalty_earn_base_amount': earnBaseAmount,
        'loyalty_status': 'not_earned',
        'loyalty_note': note,
      },
      where: 'id = ? AND COALESCE(loyalty_status, ?) = ?',
      whereArgs: [saleId, 'none', 'none'],
    );
  }

  Future<List<LoyaltyLedgerEntry>> getLedgerEntries({
    required int customerId,
    int limit = 300,
  }) async {
    if (customerId <= 0) return const [];
    final db = await _db;
    final rows = await db.query(
      ledgerTable,
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'datetime(created_at) DESC, id DESC',
      limit: limit,
    );
    return rows.map(LoyaltyLedgerEntry.fromMap).toList();
  }

  Future<Map<String, dynamic>> getLoyaltyReportSummary() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(CASE WHEN COALESCE(c.loyalty_enabled, 1) = 1 THEN 1 END) AS enabled_customers,
        COUNT(CASE WHEN COALESCE(c.loyalty_enabled, 1) = 0 THEN 1 END) AS disabled_customers,
        COALESCE(SUM(COALESCE(c.loyalty_points_balance, 0)), 0) AS total_points_balance,
        COALESCE(SUM(COALESCE(c.loyalty_lifetime_earned, 0)), 0) AS total_lifetime_earned,
        COALESCE(SUM(COALESCE(c.loyalty_lifetime_redeemed, 0)), 0) AS total_lifetime_redeemed
      FROM customers c
      WHERE COALESCE(c.is_active, 1) = 1
    ''');

    final ledgerRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN entry_type = 'earn' THEN points_delta ELSE 0 END), 0) AS earned_points,
        COALESCE(SUM(CASE WHEN entry_type = 'redeem' THEN ABS(points_delta) ELSE 0 END), 0) AS redeemed_points,
        COALESCE(SUM(CASE WHEN entry_type = 'refund_earn_reversal' THEN ABS(points_delta) ELSE 0 END), 0) AS refund_reversed_points,
        COALESCE(SUM(CASE WHEN entry_type = 'refund_redeem_restore' THEN points_delta ELSE 0 END), 0) AS refund_restored_points,
        COALESCE(SUM(CASE WHEN entry_type = 'redeem' THEN money_value ELSE 0 END), 0) AS redeemed_value
      FROM $ledgerTable
      WHERE voided_at IS NULL
    ''');

    return {
      ...Map<String, dynamic>.from(rows.first),
      ...Map<String, dynamic>.from(ledgerRows.first),
    };
  }

  Future<List<Map<String, dynamic>>> getLoyaltyCustomersReport({
    String query = '',
    bool includeZeroBalance = true,
    bool activeOnly = true,
    int limit = 300,
  }) async {
    final db = await _db;
    final clauses = <String>[];
    final args = <Object?>[];

    if (activeOnly) {
      clauses.add('COALESCE(c.is_active, 1) = 1');
    }
    if (!includeZeroBalance) {
      clauses.add('COALESCE(c.loyalty_points_balance, 0) <> 0');
    }

    final search = query.trim().toLowerCase();
    if (search.isNotEmpty) {
      clauses.add(
        '(LOWER(COALESCE(c.customer_code, "")) LIKE ? OR LOWER(COALESCE(c.name, "")) LIKE ? OR LOWER(COALESCE(c.phone, "")) LIKE ?)',
      );
      final pattern = '%$search%';
      args
        ..add(pattern)
        ..add(pattern)
        ..add(pattern);
    }

    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return db.rawQuery(
      '''
      SELECT
        c.id,
        c.customer_code,
        c.name,
        c.phone,
        c.email,
        c.address,
        c.customer_type,
        c.notes,
        c.is_active,
        c.credit_enabled,
        c.credit_limit,
        c.current_credit_balance,
        c.credit_status,
        c.credit_note,
        c.customer_category_id,
        c.pricing_scheme_id,
        c.loyalty_enabled,
        c.loyalty_points_balance,
        c.loyalty_lifetime_earned,
        c.loyalty_lifetime_redeemed,
        c.created_at,
        c.updated_at,
        MAX(l.created_at) AS last_loyalty_at,
        COUNT(l.id) AS ledger_entry_count
      FROM customers c
      LEFT JOIN $ledgerTable l
        ON l.customer_id = c.id AND l.voided_at IS NULL
      $where
      GROUP BY c.id
      ORDER BY COALESCE(c.loyalty_points_balance, 0) DESC,
               LOWER(COALESCE(c.name, c.phone, c.customer_code)) ASC
      LIMIT ?
    ''',
      [...args, limit],
    );
  }

  Future<List<Map<String, dynamic>>> getLoyaltyLedgerReport({
    String entryType = 'all',
    int limit = 300,
  }) async {
    final db = await _db;
    final clauses = <String>['l.voided_at IS NULL'];
    final args = <Object?>[];
    final normalizedType = entryType.trim().toLowerCase();
    if (normalizedType != 'all') {
      clauses.add('l.entry_type = ?');
      args.add(normalizedType);
    }

    return db.rawQuery(
      '''
      SELECT
        l.*,
        c.customer_code,
        c.name AS customer_name,
        c.phone AS customer_phone
      FROM $ledgerTable l
      LEFT JOIN customers c ON c.id = l.customer_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY datetime(l.created_at) DESC, l.id DESC
      LIMIT ?
    ''',
      [...args, limit],
    );
  }

  Future<int> addLedgerEntry({
    required int customerId,
    required LoyaltyEntryType entryType,
    required int pointsDelta,
    double moneyValue = 0.0,
    int? saleId,
    int? refundSaleId,
    String? description,
    String? createdBy,
    String? createdAt,
  }) async {
    if (customerId <= 0) throw Exception('Invalid customer.');
    if (pointsDelta == 0) throw Exception('Points movement cannot be zero.');

    final db = await _db;
    return db.transaction((txn) async {
      final balance = await _currentBalance(txn, customerId);
      final nextBalance = balance + pointsDelta;
      if (nextBalance < 0) throw Exception('Insufficient loyalty points.');

      final now = createdAt ?? DateTime.now().toIso8601String();
      final id = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': entryType.dbValue,
        'points_delta': pointsDelta,
        'points_balance_after': nextBalance,
        'money_value': _roundMoney(moneyValue),
        'sale_id': saleId,
        'refund_sale_id': refundSaleId,
        'description': _cleanOptional(description),
        'created_at': now,
        'created_by': _cleanOptional(createdBy),
      });

      await _updateCustomerLoyaltyCache(txn, customerId);
      return id;
    });
  }

  Future<void> recalculateCustomerBalance(int customerId) async {
    if (customerId <= 0) return;
    final db = await _db;
    await db.transaction((txn) async {
      await _updateCustomerLoyaltyCache(txn, customerId);
    });
  }

  Future<List<LoyaltyExclusion>> getExcludedCategories({
    bool activeOnly = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      excludedCategoriesTable,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'is_active DESC, category_name COLLATE NOCASE ASC',
    );
    return rows.map(LoyaltyExclusion.fromCategoryMap).toList();
  }

  Future<List<LoyaltyExclusion>> getExcludedProducts({
    bool activeOnly = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      excludedProductsTable,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'is_active DESC, product_name_snapshot COLLATE NOCASE ASC',
    );
    return rows.map(LoyaltyExclusion.fromProductMap).toList();
  }

  Future<int> upsertExcludedCategory({
    int? id,
    required String categoryName,
    bool excludeEarning = true,
    bool excludeRedemption = false,
    bool isActive = true,
  }) async {
    final cleanName = categoryName.trim();
    if (cleanName.isEmpty) throw Exception('Category name is required.');
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final data = {
      'category_name': cleanName,
      'exclude_earning': excludeEarning ? 1 : 0,
      'exclude_redemption': excludeRedemption ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'updated_at': now,
    };
    if (id != null && id > 0) {
      await db.update(
        excludedCategoriesTable,
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _queueLoyaltyExclusionSync(
        type: 'LOYALTY_EXCLUDED_CATEGORY',
        data: {'id': id, ...data},
      );
      return id;
    }
    final insertedId = await db.insert(excludedCategoriesTable, {
      ...data,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _queueLoyaltyExclusionSync(
      type: 'LOYALTY_EXCLUDED_CATEGORY',
      data: {'id': insertedId, ...data, 'created_at': now},
    );
    return insertedId;
  }

  Future<int> upsertExcludedProduct({
    int? id,
    required String barcode,
    required String productNameSnapshot,
    bool excludeEarning = true,
    bool excludeRedemption = false,
    bool isActive = true,
  }) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) throw Exception('Product barcode is required.');
    final cleanName = productNameSnapshot.trim().isEmpty
        ? cleanBarcode
        : productNameSnapshot.trim();
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final data = {
      'barcode': cleanBarcode,
      'product_name_snapshot': cleanName,
      'exclude_earning': excludeEarning ? 1 : 0,
      'exclude_redemption': excludeRedemption ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'updated_at': now,
    };
    if (id != null && id > 0) {
      await db.update(
        excludedProductsTable,
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _queueLoyaltyExclusionSync(
        type: 'LOYALTY_EXCLUDED_PRODUCT',
        data: {'id': id, ...data},
      );
      return id;
    }
    final insertedId = await db.insert(excludedProductsTable, {
      ...data,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _queueLoyaltyExclusionSync(
      type: 'LOYALTY_EXCLUDED_PRODUCT',
      data: {'id': insertedId, ...data, 'created_at': now},
    );
    return insertedId;
  }

  Future<double> _eligibleEarnBaseForSale({
    required int saleId,
    required double paidTotal,
  }) async {
    final safePaidTotal = _roundMoney(paidTotal);
    if (saleId <= 0 || safePaidTotal <= 0) return safePaidTotal;

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(ABS(COALESCE(si.line_total, 0))), 0) AS item_total,
        COALESCE(SUM(CASE
          WHEN ep.id IS NULL AND ec.id IS NULL
          THEN ABS(COALESCE(si.line_total, 0))
          ELSE 0
        END), 0) AS eligible_total
      FROM sale_items si
      LEFT JOIN products p ON p.barcode = si.barcode
      LEFT JOIN $excludedProductsTable ep
        ON ep.barcode = si.barcode
       AND COALESCE(ep.is_active, 1) = 1
       AND COALESCE(ep.exclude_earning, 1) = 1
      LEFT JOIN $excludedCategoriesTable ec
        ON LOWER(ec.category_name) = LOWER(COALESCE(p.category, 'General'))
       AND COALESCE(ec.is_active, 1) = 1
       AND COALESCE(ec.exclude_earning, 1) = 1
      WHERE si.sale_id = ?
      ''',
      [saleId],
    );
    if (rows.isEmpty) return safePaidTotal;
    final row = rows.first;
    final itemTotal = ((row['item_total'] as num?) ?? 0).toDouble();
    final eligibleTotal = ((row['eligible_total'] as num?) ?? 0).toDouble();
    if (itemTotal <= 0) return safePaidTotal;
    return _roundMoney(safePaidTotal * (eligibleTotal / itemTotal));
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

  Future<int> _currentBalance(Transaction txn, int customerId) async {
    final rows = await txn.query(
      CustomerService.customersTable,
      columns: const ['loyalty_points_balance'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Customer not found.');
    return ((rows.first['loyalty_points_balance'] as num?) ?? 0).toInt();
  }

  Future<double> _saleItemTotal(Transaction txn, int saleId) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(ABS(COALESCE(line_total, 0))), 0) AS total
      FROM sale_items
      WHERE sale_id = ?
      ''',
      [saleId],
    );
    return _roundMoney(((rows.first['total'] as num?) ?? 0).toDouble());
  }

  Future<double> _cumulativeRefundItemTotal(
    Transaction txn,
    int originalSaleId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(ABS(COALESCE(si.line_total, 0))), 0) AS total
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      WHERE s.transaction_type = 'refund'
        AND s.original_sale_id = ?
      ''',
      [originalSaleId],
    );
    return _roundMoney(((rows.first['total'] as num?) ?? 0).toDouble());
  }

  Future<int> _sumLoyaltyPoints(
    Transaction txn, {
    required int customerId,
    required int originalSaleId,
    required LoyaltyEntryType entryType,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(ABS(points_delta)), 0) AS points
      FROM $ledgerTable
      WHERE customer_id = ?
        AND sale_id = ?
        AND entry_type = ?
        AND voided_at IS NULL
      ''',
      [customerId, originalSaleId, entryType.dbValue],
    );
    return ((rows.first['points'] as num?) ?? 0).toInt();
  }

  Future<void> _updateCustomerLoyaltyCache(
    Transaction txn,
    int customerId,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT
        COALESCE(SUM(points_delta), 0) AS balance,
        COALESCE(SUM(CASE
          WHEN entry_type = 'earn' THEN points_delta
          WHEN entry_type = 'refund_earn_reversal' THEN points_delta
          ELSE 0
        END), 0) AS lifetime_earned,
        COALESCE(SUM(CASE
          WHEN entry_type = 'redeem' THEN ABS(points_delta)
          WHEN entry_type = 'refund_redeem_restore' THEN -ABS(points_delta)
          ELSE 0
        END), 0) AS lifetime_redeemed
      FROM $ledgerTable
      WHERE customer_id = ? AND voided_at IS NULL
      ''',
      [customerId],
    );
    final row = rows.first;
    final balance = ((row['balance'] as num?) ?? 0).toInt();
    final lifetimeEarned = ((row['lifetime_earned'] as num?) ?? 0).toInt();
    final lifetimeRedeemed = ((row['lifetime_redeemed'] as num?) ?? 0).toInt();
    await txn.update(
      CustomerService.customersTable,
      {
        'loyalty_points_balance': balance,
        'loyalty_lifetime_earned': lifetimeEarned < 0 ? 0 : lifetimeEarned,
        'loyalty_lifetime_redeemed': lifetimeRedeemed < 0
            ? 0
            : lifetimeRedeemed,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }

  Future<void> _queueCustomerLoyaltySettingsSync(int customerId) async {
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
      'type': 'CUSTOMER_LOYALTY_SETTINGS',
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
        'loyalty_enabled': row['loyalty_enabled'],
        'loyalty_points_balance': row['loyalty_points_balance'],
        'loyalty_lifetime_earned': row['loyalty_lifetime_earned'],
        'loyalty_lifetime_redeemed': row['loyalty_lifetime_redeemed'],
        'updated_at': row['updated_at'],
      }),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _queueLoyaltyLedgerSync(Transaction txn, int ledgerId) async {
    if (ledgerId <= 0) return;
    final rows = await txn.query(
      ledgerTable,
      where: 'id = ?',
      whereArgs: [ledgerId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = Map<String, dynamic>.from(rows.first);
    await txn.insert('sync_queue', {
      'type': 'LOYALTY_LEDGER_ENTRY',
      'data': jsonEncode({
        'pos_ledger_id': row['id'],
        'customer_id': row['customer_id'],
        'entry_type': row['entry_type'],
        'points_delta': row['points_delta'],
        'points_balance_after': row['points_balance_after'],
        'money_value': row['money_value'],
        'sale_id': row['sale_id'],
        'refund_sale_id': row['refund_sale_id'],
        'description': row['description'],
        'created_at': row['created_at'],
        'created_by': row['created_by'],
        'voided_at': row['voided_at'],
        'voided_by': row['voided_by'],
        'void_reason': row['void_reason'],
      }),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _queueLoyaltySaleUpdateSync(Transaction txn, int saleId) async {
    if (saleId <= 0) return;
    final rows = await txn.query(
      'sales',
      columns: const [
        'id',
        'customer_id',
        'customer_name_snapshot',
        'customer_phone_snapshot',
        'customer_code_snapshot',
        'loyalty_points_earned',
        'loyalty_points_redeemed',
        'loyalty_redeemed_value',
        'loyalty_earn_base_amount',
        'loyalty_status',
        'loyalty_note',
        'created_at',
      ],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = Map<String, dynamic>.from(rows.first);
    await txn.insert('sync_queue', {
      'type': 'LOYALTY_SALE_UPDATE',
      'data': jsonEncode({
        'sale_id': row['id'],
        'local_sale_id': row['id'],
        'customer_id': row['customer_id'],
        'customer_name_snapshot': row['customer_name_snapshot'],
        'customer_phone_snapshot': row['customer_phone_snapshot'],
        'customer_code_snapshot': row['customer_code_snapshot'],
        'loyalty_points_earned': row['loyalty_points_earned'],
        'loyalty_points_redeemed': row['loyalty_points_redeemed'],
        'loyalty_redeemed_value': row['loyalty_redeemed_value'],
        'loyalty_earn_base_amount': row['loyalty_earn_base_amount'],
        'loyalty_status': row['loyalty_status'],
        'loyalty_note': row['loyalty_note'],
        'updated_at': row['created_at'],
      }),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _queueLoyaltyExclusionSync({
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final db = await _db;
    await db.insert('sync_queue', {
      'type': type,
      'data': jsonEncode(data),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  double _roundMoney(num value) {
    return double.parse(value.toStringAsFixed(2));
  }
}
