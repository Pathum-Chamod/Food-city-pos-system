import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';

class PresentationModeSettings {
  const PresentationModeSettings({
    required this.transactionInterval,
    required this.presentationPin,
  });

  final int transactionInterval;
  final String presentationPin;

  PresentationModeSettings copyWith({
    int? transactionInterval,
    String? presentationPin,
  }) {
    return PresentationModeSettings(
      transactionInterval: transactionInterval ?? this.transactionInterval,
      presentationPin: presentationPin ?? this.presentationPin,
    );
  }
}

class PresentationVisibleTransaction {
  const PresentationVisibleTransaction({
    required this.displayId,
    required this.realSaleId,
    required this.row,
  });

  final int displayId;
  final int realSaleId;
  final Map<String, dynamic> row;

  Map<String, dynamic> get displayRow {
    return {
      ...row,
      'real_sale_id': realSaleId,
      'display_transaction_id': displayId,
    };
  }
}

class PresentationCashierSummary {
  const PresentationCashierSummary({
    required this.transactionCount,
    required this.saleCount,
    required this.refundCount,
    required this.itemsSold,
    required this.salesTotal,
    required this.refundTotal,
    required this.netSales,
    required this.cashSales,
    required this.cardSales,
    required this.averageSale,
    required this.totalDiscounts,
  });

  final int transactionCount;
  final int saleCount;
  final int refundCount;
  final double itemsSold;
  final double salesTotal;
  final double refundTotal;
  final double netSales;
  final double cashSales;
  final double cardSales;
  final double averageSale;
  final double totalDiscounts;
}

class PresentationModeService {
  PresentationModeService._();

  static final PresentationModeService instance = PresentationModeService._();

  static const String _settingsTable = 'app_settings';
  static const String _transactionIntervalKey = 'presentation_transaction_interval';
  static const String _presentationPinKey = 'presentation_login_pin';
  static const int _defaultInterval = 3;
  static const String _defaultPresentationPin = '9090';
  static const int _minInterval = 1;
  static const int _maxInterval = 20;

  Future<Database> get _db async {
    final db = await DatabaseHelper.instance.database;
    await ensureStorage();
    return db;
  }

  Future<void> ensureStorage() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_settingsTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  int normalizeInterval(int value) {
    if (value < _minInterval) return _minInterval;
    if (value > _maxInterval) return _maxInterval;
    return value;
  }

  Future<String?> _getSetting(String key) async {
    final db = await _db;
    final rows = await db.query(
      _settingsTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> _setSetting(String key, String value) async {
    final db = await _db;
    await db.insert(
      _settingsTable,
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getTransactionInterval() async {
    final raw = await _getSetting(_transactionIntervalKey);
    final parsed = int.tryParse((raw ?? '').trim());
    return normalizeInterval(parsed ?? _defaultInterval);
  }

  Future<String> getPresentationPin() async {
    final raw = await _getSetting(_presentationPinKey);
    final pin = (raw ?? '').trim();
    if (RegExp(r'^\d{4}$').hasMatch(pin)) return pin;
    return _defaultPresentationPin;
  }

  Future<PresentationModeSettings> getSettings() async {
    return PresentationModeSettings(
      transactionInterval: await getTransactionInterval(),
      presentationPin: await getPresentationPin(),
    );
  }

  Future<void> saveSettings({
    required int transactionInterval,
    required String presentationPin,
    int? actorUserId,
    String actorName = 'System',
  }) async {
    final normalizedInterval = normalizeInterval(transactionInterval);
    final pin = presentationPin.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw Exception('Presentation PIN must be exactly 4 digits.');
    }

    await _setSetting(_transactionIntervalKey, normalizedInterval.toString());
    await _setSetting(_presentationPinKey, pin);
    await createOrUpdatePresentationUser(
      pin: pin,
      actorUserId: actorUserId,
      actorName: actorName,
    );
  }

  Future<void> createOrUpdatePresentationUser({
    required String pin,
    int? actorUserId,
    String actorName = 'System',
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    final duplicatePinRows = await db.query(
      'users',
      columns: ['id', 'name', 'role'],
      where: 'pin = ? AND LOWER(role) NOT IN (?, ?)',
      whereArgs: [pin, 'viewer', 'presentation'],
      limit: 1,
    );

    if (duplicatePinRows.isNotEmpty) {
      final name = (duplicatePinRows.first['name'] ?? 'another user').toString();
      throw Exception('PIN $pin is already used by $name. Choose another PIN.');
    }

    final existingRows = await db.query(
      'users',
      where: 'LOWER(role) IN (?, ?) OR name = ?',
      whereArgs: ['viewer', 'presentation', 'Presentation Login'],
      limit: 1,
    );

    if (existingRows.isEmpty) {
      await db.insert('users', {
        'name': 'Presentation Login',
        'role': 'viewer',
        'pin': pin,
        'is_active': 1,
        'has_full_access': 0,
        'created_at': now,
        'updated_at': now,
        'created_by': actorUserId,
        'updated_by': actorUserId,
      });
      return;
    }

    final userId = ((existingRows.first['id'] as num?) ?? 0).toInt();
    await db.update(
      'users',
      {
        'name': 'Presentation Login',
        'role': 'viewer',
        'pin': pin,
        'is_active': 1,
        'has_full_access': 0,
        'updated_at': now,
        'updated_by': actorUserId,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<PresentationVisibleTransaction>> getVisibleTransactions({
    String? transactionType,
    DateTime? start,
    DateTime? end,
    DateTime? presentationSessionStartedAt,
  }) async {
    final interval = await getTransactionInterval();
    final rows = await DatabaseHelper.instance.getRecentTransactions(
      transactionType: transactionType,
      start: start,
      end: end,
      limit: null,
    );

    final sorted = rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
      ..sort(_compareTransactionRowsAscending);

    final visible = <PresentationVisibleTransaction>[];

    for (var index = 0; index < sorted.length; index++) {
      final row = sorted[index];
      final realSaleId = ((row['id'] as num?) ?? 0).toInt();
      if (realSaleId <= 0) continue;

      final createdAt = _parseDate(row['created_at']);
      final isNewDuringPresentationSession =
          presentationSessionStartedAt != null &&
          createdAt != null &&
          !createdAt.isBefore(presentationSessionStartedAt);

      final passesInterval = interval <= 1 || index % interval == 0;
      if (!passesInterval && !isNewDuringPresentationSession) continue;

      visible.add(
        PresentationVisibleTransaction(
          displayId: visible.length + 1,
          realSaleId: realSaleId,
          row: row,
        ),
      );
    }

    return visible.reversed.toList();
  }


  Future<int?> getDisplayIdForRealSaleId({
    required int realSaleId,
    DateTime? presentationSessionStartedAt,
  }) async {
    if (realSaleId <= 0) return null;

    final visible = await getVisibleTransactions(
      presentationSessionStartedAt: presentationSessionStartedAt,
    );

    for (final tx in visible) {
      if (tx.realSaleId == realSaleId) {
        return tx.displayId;
      }
    }

    return null;
  }

  Future<PresentationCashierSummary> getCashierSummary({
    String? transactionType,
    DateTime? start,
    DateTime? end,
    DateTime? presentationSessionStartedAt,
  }) async {
    final visible = await getVisibleTransactions(
      transactionType: transactionType,
      start: start,
      end: end,
      presentationSessionStartedAt: presentationSessionStartedAt,
    );

    final saleIds = <int>[];

    var saleCount = 0;
    var refundCount = 0;
    var salesTotal = 0.0;
    var refundTotal = 0.0;
    var cashSales = 0.0;
    var cardSales = 0.0;
    var totalDiscounts = 0.0;

    for (final tx in visible) {
      final row = tx.row;
      final type = (row['transaction_type'] ?? 'sale').toString().toLowerCase();
      final paymentMethod = (row['payment_method'] ?? '').toString().toLowerCase();
      final total = (((row['total_amount'] as num?) ?? 0).toDouble()).abs();
      final discount = (((row['discount_amount'] as num?) ?? 0).toDouble()).abs();

      if (type == 'refund') {
        refundCount += 1;
        refundTotal += total;
        continue;
      }

      saleCount += 1;
      saleIds.add(tx.realSaleId);
      salesTotal += total;
      totalDiscounts += discount;
      if (paymentMethod == 'card') {
        cardSales += total;
      } else {
        cashSales += total;
      }
    }

    final itemsSold = await _getItemsSoldForSaleIds(saleIds);
    final netSales = salesTotal - refundTotal;
    final averageSale = saleCount == 0 ? 0.0 : netSales / saleCount;

    return PresentationCashierSummary(
      transactionCount: saleCount,
      saleCount: saleCount,
      refundCount: refundCount,
      itemsSold: itemsSold,
      salesTotal: salesTotal,
      refundTotal: refundTotal,
      netSales: netSales,
      cashSales: cashSales,
      cardSales: cardSales,
      averageSale: averageSale,
      totalDiscounts: totalDiscounts,
    );
  }

  Future<List<Map<String, dynamic>>> getTopSellingItemsSummary({
    DateTime? start,
    DateTime? end,
    DateTime? presentationSessionStartedAt,
    int limit = 6,
  }) async {
    final visible = await getVisibleTransactions(
      transactionType: 'sale',
      start: start,
      end: end,
      presentationSessionStartedAt: presentationSessionStartedAt,
    );

    final saleIds = visible
        .where(
          (tx) =>
              (tx.row['transaction_type'] ?? 'sale')
                  .toString()
                  .toLowerCase() ==
              'sale',
        )
        .map((tx) => tx.realSaleId)
        .where((id) => id > 0)
        .toList();

    if (saleIds.isEmpty) return <Map<String, dynamic>>[];

    final db = await _db;
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT
        si.barcode AS barcode,
        si.product_name AS product_name,
        COALESCE(MAX(p.quantity_type), 'unit') AS quantity_type,
        COALESCE(MAX(p.unit_label), 'pcs') AS unit_label,
        COALESCE(SUM(ABS(si.quantity)), 0) AS quantity_sold,
        COALESCE(SUM(ABS(si.line_total)), 0) AS net_sales_amount
      FROM sale_items si
      LEFT JOIN products p ON p.barcode = si.barcode
      WHERE si.sale_id IN ($placeholders)
      GROUP BY si.barcode, si.product_name
      ORDER BY net_sales_amount DESC, quantity_sold DESC
      LIMIT ?
      ''',
      [...saleIds, limit],
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<double> _getItemsSoldForSaleIds(List<int> saleIds) async {
    if (saleIds.isEmpty) return 0.0;
    final db = await _db;
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(ABS(quantity)), 0) AS items_sold
      FROM sale_items
      WHERE sale_id IN ($placeholders)
      ''',
      saleIds,
    );
    return ((rows.first['items_sold'] as num?) ?? 0).toDouble();
  }

  int _compareTransactionRowsAscending(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aDate = _parseDate(a['created_at']);
    final bDate = _parseDate(b['created_at']);
    if (aDate != null && bDate != null) {
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) return dateCompare;
    }

    final aId = ((a['id'] as num?) ?? 0).toInt();
    final bId = ((b['id'] as num?) ?? 0).toInt();
    return aId.compareTo(bId);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (e) {
      debugPrint('Presentation date parse error: $e');
      return null;
    }
  }
}
