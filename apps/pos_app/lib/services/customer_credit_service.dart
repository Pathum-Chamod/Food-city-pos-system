import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared/models/customer_credit_summary.dart';
import 'package:shared/models/customer_ledger_entry.dart';
import 'package:shared/models/customer_payment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'customer_service.dart';
import 'database_helper.dart';

class CustomerCreditValidationResult {
  const CustomerCreditValidationResult({
    required this.allowed,
    required this.requiresManagerApproval,
    required this.message,
    required this.summary,
    required this.previousBalance,
    required this.newBalance,
  });

  final bool allowed;
  final bool requiresManagerApproval;
  final String message;
  final CustomerCreditSummary summary;
  final double previousBalance;
  final double newBalance;
}

class CustomerCreditPostingResult {
  const CustomerCreditPostingResult({
    required this.customerId,
    required this.previousBalance,
    required this.newBalance,
    this.ledgerId,
    this.paymentId,
  });

  final int customerId;
  final double previousBalance;
  final double newBalance;
  final int? ledgerId;
  final int? paymentId;

  Map<String, dynamic> toMap() {
    return {
      'customer_id': customerId,
      'previous_balance': previousBalance,
      'new_balance': newBalance,
      'ledger_id': ledgerId,
      'payment_id': paymentId,
    };
  }
}

class CustomerCreditService {
  CustomerCreditService._();

  static final CustomerCreditService instance = CustomerCreditService._();

  static const String ledgerTable = 'customer_ledger';
  static const String paymentsTable = 'customer_payments';

  bool _storageReady = false;
  Future<void>? _ensureFuture;

  Future<Database> get _db async {
    await ensureCreditStorage();
    return DatabaseHelper.instance.database;
  }

  Future<void> ensureCreditStorage() async {
    if (_storageReady) return;
    _ensureFuture ??= _ensureCreditStorageInternal();
    await _ensureFuture;
    _storageReady = true;
  }

  Future<void> _ensureCreditStorageInternal() async {
    final db = await DatabaseHelper.instance.database;
    await CustomerService.instance.ensureCustomerStorage();

    await _addColumnIfMissing(
      db,
      'customers',
      'credit_enabled',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'customers',
      'credit_limit',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'customers',
      'current_credit_balance',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'customers',
      'credit_status',
      "TEXT NOT NULL DEFAULT 'normal'",
    );
    await _addColumnIfMissing(db, 'customers', 'credit_note', 'TEXT');

    await _addColumnIfMissing(
      db,
      'sales',
      'is_credit_sale',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'sales', 'credit_status', 'TEXT');
    await _addColumnIfMissing(db, 'sales', 'credit_ledger_id', 'INTEGER');
    await _addColumnIfMissing(db, 'sales', 'credit_approved_by', 'TEXT');
    await _addColumnIfMissing(
      db,
      'sales',
      'credit_previous_balance',
      'REAL',
    );
    await _addColumnIfMissing(db, 'sales', 'credit_new_balance', 'REAL');
    await _addColumnIfMissing(db, 'sales', 'credit_bill_amount', 'REAL');
    await _addColumnIfMissing(db, 'sales', 'credit_limit_snapshot', 'REAL');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $ledgerTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        balance_after REAL NOT NULL DEFAULT 0,
        reference_type TEXT,
        reference_id INTEGER,
        sale_id INTEGER,
        payment_id INTEGER,
        description TEXT,
        payment_method TEXT,
        performed_by TEXT,
        approved_by TEXT,
        created_at TEXT NOT NULL,
        voided_at TEXT,
        voided_by TEXT,
        void_reason TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $paymentsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        reference_note TEXT,
        cashier_name TEXT,
        received_by TEXT,
        created_at TEXT NOT NULL,
        voided_at TEXT,
        voided_by TEXT,
        void_reason TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer ON $ledgerTable(customer_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_ledger_sale ON $ledgerTable(sale_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_ledger_payment ON $ledgerTable(payment_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_payments_customer ON $paymentsTable(customer_id, created_at)',
    );
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

  double _roundMoney(num value) {
    return double.parse(value.toStringAsFixed(2));
  }

  String? _cleanOptional(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }

  String _normalizeCreditStatus(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'watchlist') return 'watchlist';
    if (normalized == 'blocked') return 'blocked';
    return 'normal';
  }

  String _normalizePaymentMethod(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'card') return 'card';
    if (normalized == 'bank_transfer') return 'bank_transfer';
    if (normalized == 'cheque') return 'cheque';
    if (normalized == 'other') return 'other';
    return 'cash';
  }

  double _readDouble(dynamic value, {double fallback = 0.0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  bool _readBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return fallback;
  }


  Map<String, dynamic> _customerSyncMap(dynamic customer) {
    if (customer == null) return <String, dynamic>{};

    return {
      'customer_id': customer.id,
      'customer_code': customer.customerCode,
      'customer_name': customer.name,
      'customer_phone': customer.phone,
      'customer_phone_normalized': customer.phoneNormalized,
      'customer_email': customer.email,
      'customer_address': customer.address,
      'customer_type': customer.customerType,
      'customer_notes': customer.notes,
      'customer_is_active': customer.isActive ? 1 : 0,
    };
  }

  Future<void> _enqueueSync(
    DatabaseExecutor executor,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      await executor.rawInsert(
        'INSERT INTO sync_queue (type, data, status, created_at) VALUES (?, ?, ?, ?)',
        [type, jsonEncode(data), 'pending', DateTime.now().toIso8601String()],
      );
    } catch (e) {
      debugPrint('⚠️ Credit sync queue insert failed: $e');
    }
  }

  Future<CustomerCreditSummary> getCreditSummary(int customerId) async {
    if (customerId <= 0) {
      return CustomerCreditSummary.empty(customerId);
    }

    final db = await _db;
    await recalculateCustomerBalance(customerId);

    final rows = await db.query(
      'customers',
      columns: const [
        'id',
        'credit_enabled',
        'credit_limit',
        'current_credit_balance',
        'credit_status',
        'credit_note',
      ],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return CustomerCreditSummary.empty(customerId);
    }

    final row = rows.first;
    return CustomerCreditSummary.fromMap({
      'customer_id': row['id'],
      'credit_enabled': row['credit_enabled'],
      'credit_limit': row['credit_limit'],
      'current_credit_balance': row['current_credit_balance'],
      'credit_status': row['credit_status'],
      'credit_note': row['credit_note'],
    });
  }

  Future<void> updateCreditSettings({
    required int customerId,
    required bool creditEnabled,
    required double creditLimit,
    required String creditStatus,
    String? creditNote,
    int? updatedBy,
  }) async {
    if (customerId <= 0) {
      throw Exception('Invalid customer.');
    }

    final db = await _db;
    final customer = await CustomerService.instance.getCustomerById(customerId);
    if (customer == null) {
      throw Exception('Customer not found.');
    }

    final safeLimit = creditLimit < 0 ? 0.0 : _roundMoney(creditLimit);

    await db.update(
      'customers',
      {
        'credit_enabled': creditEnabled ? 1 : 0,
        'credit_limit': safeLimit,
        'credit_status': _normalizeCreditStatus(creditStatus),
        'credit_note': _cleanOptional(creditNote),
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': updatedBy,
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );

    final currentBalance = await recalculateCustomerBalance(customerId);
    final updatedCustomer = await CustomerService.instance.getCustomerById(customerId);

    await _enqueueSync(db, 'CUSTOMER_CREDIT_SETTINGS', {
      ..._customerSyncMap(updatedCustomer ?? customer),
      'credit_enabled': creditEnabled ? 1 : 0,
      'credit_limit': safeLimit,
      'current_credit_balance': currentBalance,
      'credit_status': _normalizeCreditStatus(creditStatus),
      'credit_note': _cleanOptional(creditNote),
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<CustomerCreditValidationResult> validateCreditSale({
    required int customerId,
    required double saleTotal,
    bool managerApproved = false,
  }) async {
    final safeTotal = _roundMoney(saleTotal);
    final summary = await getCreditSummary(customerId);
    final previousBalance = summary.currentBalance;
    final newBalance = _roundMoney(previousBalance + safeTotal);

    if (customerId <= 0) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: false,
        message: 'Select a customer to use Customer Credit.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    final customer = await CustomerService.instance.getCustomerById(customerId);
    if (customer == null) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: false,
        message: 'Customer not found.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    if (!customer.isActive) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: false,
        message: 'Inactive customers cannot use credit.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    if (!summary.creditEnabled) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: false,
        message: 'Credit is not enabled for this customer.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    if (safeTotal <= 0) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: false,
        message: 'Credit sale amount must be greater than zero.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    if (summary.isBlocked && !managerApproved) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: true,
        message: 'Customer credit is blocked. Manager approval required.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    final exceedsLimit = summary.creditLimit > 0 && newBalance > summary.creditLimit;
    if (exceedsLimit && !managerApproved) {
      return CustomerCreditValidationResult(
        allowed: false,
        requiresManagerApproval: true,
        message: 'Credit limit exceeded. Manager approval required.',
        summary: summary,
        previousBalance: previousBalance,
        newBalance: newBalance,
      );
    }

    return CustomerCreditValidationResult(
      allowed: true,
      requiresManagerApproval: false,
      message: 'Credit sale allowed.',
      summary: summary,
      previousBalance: previousBalance,
      newBalance: newBalance,
    );
  }

  Future<CustomerCreditPostingResult> postCreditSale({
    required int customerId,
    required int saleId,
    required double amount,
    required String cashierName,
    String? approvedBy,
    bool managerApproved = false,
  }) async {
    if (customerId <= 0) {
      throw Exception('Select a customer to use Customer Credit.');
    }
    if (saleId <= 0) {
      throw Exception('Invalid sale reference.');
    }

    final safeAmount = _roundMoney(amount);
    if (safeAmount <= 0) {
      throw Exception('Credit sale amount must be greater than zero.');
    }

    final validation = await validateCreditSale(
      customerId: customerId,
      saleTotal: safeAmount,
      managerApproved: managerApproved || _cleanOptional(approvedBy) != null,
    );

    if (!validation.allowed && !validation.requiresManagerApproval) {
      throw Exception(validation.message);
    }
    if (!validation.allowed &&
        validation.requiresManagerApproval &&
        _cleanOptional(approvedBy) == null) {
      throw Exception(validation.message);
    }

    final customer = await CustomerService.instance.getCustomerById(customerId);
    final db = await _db;

    return db.transaction<CustomerCreditPostingResult>((txn) async {
      final previousBalance = await _calculateBalance(txn, customerId);
      final newBalance = _roundMoney(previousBalance + safeAmount);
      final now = DateTime.now().toIso8601String();

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': 'credit_sale',
        'debit': safeAmount,
        'credit': 0.0,
        'balance_after': newBalance,
        'reference_type': 'sale',
        'reference_id': saleId,
        'sale_id': saleId,
        'payment_id': null,
        'description': 'Credit sale #$saleId',
        'payment_method': 'customer_credit',
        'performed_by': _cleanOptional(cashierName),
        'approved_by': _cleanOptional(approvedBy),
        'created_at': now,
      });

      await txn.update(
        'customers',
        {
          'current_credit_balance': newBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      await txn.update(
        'sales',
        {
          'is_credit_sale': 1,
          'credit_status': 'posted',
          'credit_ledger_id': ledgerId,
          'credit_approved_by': _cleanOptional(approvedBy),
          'credit_previous_balance': previousBalance,
          'credit_new_balance': newBalance,
          'credit_bill_amount': safeAmount,
          'credit_limit_snapshot': validation.summary.creditLimit,
          'payment_method': 'customer_credit',
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );

      await _enqueueSync(txn, 'CREDIT_SALE_UPDATE', {
        ..._customerSyncMap(customer),
        'sale_id': saleId,
        'customer_id': customerId,
        'is_credit_sale': 1,
        'credit_status': 'posted',
        'credit_ledger_id': ledgerId,
        'credit_approved_by': _cleanOptional(approvedBy),
        'credit_previous_balance': previousBalance,
        'credit_new_balance': newBalance,
        'credit_bill_amount': safeAmount,
        'credit_limit_snapshot': validation.summary.creditLimit,
        'payment_method': 'customer_credit',
        'ledger_entry': {
          'ledger_id': ledgerId,
          'entry_type': 'credit_sale',
          'debit': safeAmount,
          'credit': 0.0,
          'balance_after': newBalance,
          'reference_type': 'sale',
          'reference_id': saleId,
          'sale_id': saleId,
          'description': 'Credit sale #$saleId',
          'payment_method': 'customer_credit',
          'performed_by': _cleanOptional(cashierName),
          'approved_by': _cleanOptional(approvedBy),
          'created_at': now,
        },
      });

      return CustomerCreditPostingResult(
        customerId: customerId,
        previousBalance: previousBalance,
        newBalance: newBalance,
        ledgerId: ledgerId,
      );
    });
  }

  Future<CustomerCreditPostingResult> receivePayment({
    required int customerId,
    required double amount,
    required String paymentMethod,
    required String receivedBy,
    String? cashierName,
    String? referenceNote,
  }) async {
    if (customerId <= 0) {
      throw Exception('Invalid customer.');
    }

    final safeAmount = _roundMoney(amount);
    if (safeAmount <= 0) {
      throw Exception('Payment amount must be greater than zero.');
    }

    final customer = await CustomerService.instance.getCustomerById(customerId);
    if (customer == null) {
      throw Exception('Customer not found.');
    }

    final db = await _db;

    return db.transaction<CustomerCreditPostingResult>((txn) async {
      final previousBalance = await _calculateBalance(txn, customerId);
      final newBalance = _roundMoney(previousBalance - safeAmount);
      final now = DateTime.now().toIso8601String();
      final normalizedMethod = _normalizePaymentMethod(paymentMethod);

      final paymentId = await txn.insert(paymentsTable, {
        'customer_id': customerId,
        'amount': safeAmount,
        'payment_method': normalizedMethod,
        'reference_note': _cleanOptional(referenceNote),
        'cashier_name': _cleanOptional(cashierName),
        'received_by': _cleanOptional(receivedBy),
        'created_at': now,
      });

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': 'payment',
        'debit': 0.0,
        'credit': safeAmount,
        'balance_after': newBalance,
        'reference_type': 'payment',
        'reference_id': paymentId,
        'sale_id': null,
        'payment_id': paymentId,
        'description': _cleanOptional(referenceNote) ?? 'Customer payment #$paymentId',
        'payment_method': normalizedMethod,
        'performed_by': _cleanOptional(receivedBy),
        'approved_by': null,
        'created_at': now,
      });

      await txn.update(
        'customers',
        {
          'current_credit_balance': newBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      await _enqueueSync(txn, 'CUSTOMER_PAYMENT', {
        ..._customerSyncMap(customer),
        'customer_id': customerId,
        'payment_id': paymentId,
        'ledger_id': ledgerId,
        'amount': safeAmount,
        'payment_method': normalizedMethod,
        'reference_note': _cleanOptional(referenceNote),
        'cashier_name': _cleanOptional(cashierName),
        'received_by': _cleanOptional(receivedBy),
        'previous_balance': previousBalance,
        'new_balance': newBalance,
        'created_at': now,
        'ledger_entry': {
          'ledger_id': ledgerId,
          'entry_type': 'payment',
          'debit': 0.0,
          'credit': safeAmount,
          'balance_after': newBalance,
          'reference_type': 'payment',
          'reference_id': paymentId,
          'payment_id': paymentId,
          'description': _cleanOptional(referenceNote) ?? 'Customer payment #$paymentId',
          'payment_method': normalizedMethod,
          'performed_by': _cleanOptional(receivedBy),
          'created_at': now,
        },
      });

      return CustomerCreditPostingResult(
        customerId: customerId,
        previousBalance: previousBalance,
        newBalance: newBalance,
        ledgerId: ledgerId,
        paymentId: paymentId,
      );
    });
  }

  Future<List<CustomerLedgerEntry>> getLedger({
    required int customerId,
    bool newestFirst = true,
    bool includeVoided = true,
    int limit = 300,
  }) async {
    if (customerId <= 0) return const [];

    final db = await _db;
    final whereParts = <String>['customer_id = ?'];
    final args = <Object?>[customerId];

    if (!includeVoided) {
      whereParts.add('(voided_at IS NULL OR TRIM(voided_at) = "")');
    }

    final rows = await db.query(
      ledgerTable,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: newestFirst
          ? 'datetime(created_at) DESC, id DESC'
          : 'datetime(created_at) ASC, id ASC',
      limit: limit <= 0 ? null : limit,
    );

    return rows.map(CustomerLedgerEntry.fromMap).toList();
  }

  Future<List<CustomerPayment>> getPayments({
    required int customerId,
    bool includeVoided = true,
    int limit = 200,
  }) async {
    if (customerId <= 0) return const [];

    final db = await _db;
    final whereParts = <String>['customer_id = ?'];
    final args = <Object?>[customerId];

    if (!includeVoided) {
      whereParts.add('(voided_at IS NULL OR TRIM(voided_at) = "")');
    }

    final rows = await db.query(
      paymentsTable,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'datetime(created_at) DESC, id DESC',
      limit: limit <= 0 ? null : limit,
    );

    return rows.map(CustomerPayment.fromMap).toList();
  }

  Future<double> recalculateCustomerBalance(int customerId) async {
    if (customerId <= 0) return 0.0;

    final db = await _db;
    final balance = await _calculateBalance(db, customerId);
    final rounded = _roundMoney(balance);

    await db.update(
      'customers',
      {
        'current_credit_balance': rounded,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [customerId],
    );

    return rounded;
  }

  Future<CustomerCreditPostingResult> postAdjustment({
    required int customerId,
    required double amount,
    required String adjustmentType,
    required String reason,
    required String performedBy,
    String? approvedBy,
  }) async {
    if (customerId <= 0) {
      throw Exception('Invalid customer.');
    }

    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw Exception('Adjustment reason is required.');
    }

    final safeAmount = _roundMoney(amount);
    if (safeAmount <= 0) {
      throw Exception('Adjustment amount must be greater than zero.');
    }

    final normalizedType = adjustmentType.trim().toLowerCase();
    final isDebit = normalizedType == 'debit_adjustment';
    final isCredit = normalizedType == 'credit_adjustment';
    if (!isDebit && !isCredit) {
      throw Exception('Invalid adjustment type.');
    }

    final customer = await CustomerService.instance.getCustomerById(customerId);
    final db = await _db;

    return db.transaction<CustomerCreditPostingResult>((txn) async {
      final previousBalance = await _calculateBalance(txn, customerId);
      final newBalance = _roundMoney(
        previousBalance + (isDebit ? safeAmount : -safeAmount),
      );
      final now = DateTime.now().toIso8601String();

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': isDebit ? 'debit_adjustment' : 'credit_adjustment',
        'debit': isDebit ? safeAmount : 0.0,
        'credit': isCredit ? safeAmount : 0.0,
        'balance_after': newBalance,
        'reference_type': 'adjustment',
        'reference_id': null,
        'sale_id': null,
        'payment_id': null,
        'description': cleanReason,
        'payment_method': null,
        'performed_by': _cleanOptional(performedBy),
        'approved_by': _cleanOptional(approvedBy),
        'created_at': now,
      });

      await txn.update(
        'customers',
        {
          'current_credit_balance': newBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      await _enqueueSync(txn, 'CUSTOMER_LEDGER_ADJUSTMENT', {
        ..._customerSyncMap(customer),
        'customer_id': customerId,
        'ledger_id': ledgerId,
        'entry_type': isDebit ? 'debit_adjustment' : 'credit_adjustment',
        'debit': isDebit ? safeAmount : 0.0,
        'credit': isCredit ? safeAmount : 0.0,
        'balance_after': newBalance,
        'previous_balance': previousBalance,
        'description': cleanReason,
        'performed_by': _cleanOptional(performedBy),
        'approved_by': _cleanOptional(approvedBy),
        'created_at': now,
      });

      return CustomerCreditPostingResult(
        customerId: customerId,
        previousBalance: previousBalance,
        newBalance: newBalance,
        ledgerId: ledgerId,
      );
    });
  }

  Future<CustomerCreditPostingResult> voidPayment({
    required int paymentId,
    required String voidedBy,
    required String reason,
  }) async {
    if (paymentId <= 0) {
      throw Exception('Invalid payment.');
    }

    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw Exception('Void reason is required.');
    }

    final db = await _db;
    final paymentRows = await db.query(
      paymentsTable,
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );

    if (paymentRows.isEmpty) {
      throw Exception('Payment not found.');
    }

    final payment = CustomerPayment.fromMap(paymentRows.first);
    if (payment.isVoided) {
      throw Exception('Payment is already voided.');
    }

    final customer = await CustomerService.instance.getCustomerById(payment.customerId);

    return db.transaction<CustomerCreditPostingResult>((txn) async {
      final previousBalance = await _calculateBalance(txn, payment.customerId);
      final newBalance = _roundMoney(previousBalance + payment.amount);
      final now = DateTime.now().toIso8601String();

      await txn.update(
        paymentsTable,
        {
          'voided_at': now,
          'voided_by': _cleanOptional(voidedBy),
          'void_reason': cleanReason,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      await txn.update(
        ledgerTable,
        {
          'voided_at': now,
          'voided_by': _cleanOptional(voidedBy),
          'void_reason': cleanReason,
        },
        where: 'entry_type = ? AND payment_id = ? AND (voided_at IS NULL OR TRIM(voided_at) = "")',
        whereArgs: ['payment', paymentId],
      );

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': payment.customerId,
        'entry_type': 'void_reversal',
        'debit': payment.amount,
        'credit': 0.0,
        'balance_after': newBalance,
        'reference_type': 'payment_void',
        'reference_id': paymentId,
        'sale_id': null,
        'payment_id': paymentId,
        'description': 'Voided payment #$paymentId: $cleanReason',
        'payment_method': payment.normalizedPaymentMethod,
        'performed_by': _cleanOptional(voidedBy),
        'approved_by': _cleanOptional(voidedBy),
        'created_at': now,
      });

      await txn.update(
        'customers',
        {
          'current_credit_balance': newBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [payment.customerId],
      );

      await _enqueueSync(txn, 'CUSTOMER_PAYMENT_VOID', {
        ..._customerSyncMap(customer),
        'customer_id': payment.customerId,
        'payment_id': paymentId,
        'void_ledger_id': ledgerId,
        'amount': payment.amount,
        'payment_method': payment.normalizedPaymentMethod,
        'voided_at': now,
        'voided_by': _cleanOptional(voidedBy),
        'void_reason': cleanReason,
        'previous_balance': previousBalance,
        'new_balance': newBalance,
        'ledger_entry': {
          'ledger_id': ledgerId,
          'entry_type': 'void_reversal',
          'debit': payment.amount,
          'credit': 0.0,
          'balance_after': newBalance,
          'reference_type': 'payment_void',
          'reference_id': paymentId,
          'payment_id': paymentId,
          'description': 'Voided payment #$paymentId: $cleanReason',
          'payment_method': payment.normalizedPaymentMethod,
          'performed_by': _cleanOptional(voidedBy),
          'approved_by': _cleanOptional(voidedBy),
          'created_at': now,
        },
      });

      return CustomerCreditPostingResult(
        customerId: payment.customerId,
        previousBalance: previousBalance,
        newBalance: newBalance,
        ledgerId: ledgerId,
        paymentId: paymentId,
      );
    });
  }


  Future<CustomerCreditPostingResult?> postCreditRefundFromOriginalSale({
    required int originalSaleId,
    required int refundSaleId,
    String? performedBy,
    String? approvedBy,
  }) async {
    if (originalSaleId <= 0 || refundSaleId <= 0) return null;

    final db = await _db;

    final existingRows = await db.query(
      ledgerTable,
      where: 'entry_type = ? AND sale_id = ?',
      whereArgs: ['refund', refundSaleId],
      limit: 1,
    );

    if (existingRows.isNotEmpty) {
      return null;
    }

    final originalRows = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [originalSaleId],
      limit: 1,
    );

    if (originalRows.isEmpty) return null;

    final original = Map<String, dynamic>.from(originalRows.first);
    final originalPaymentMethod =
        (original['payment_method'] ?? '').toString().toLowerCase();
    final originalCreditStatus =
        (original['credit_status'] ?? '').toString().toLowerCase();
    final isOriginalCreditSale = _readBool(original['is_credit_sale']) ||
        originalPaymentMethod == 'customer_credit' ||
        originalCreditStatus == 'posted';

    if (!isOriginalCreditSale) {
      return null;
    }

    final customerId = _readInt(original['customer_id']);
    if (customerId <= 0) {
      return null;
    }

    final refundRows = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [refundSaleId],
      limit: 1,
    );

    if (refundRows.isEmpty) {
      return null;
    }

    final refund = Map<String, dynamic>.from(refundRows.first);
    final refundTotal = _roundMoney(_readDouble(refund['total_amount']).abs());
    if (refundTotal <= 0) return null;

    final customer = await CustomerService.instance.getCustomerById(customerId);
    final creditLimit = _readDouble(original['credit_limit_snapshot']) > 0
        ? _readDouble(original['credit_limit_snapshot'])
        : (customer?.creditLimit ?? 0.0);

    return db.transaction<CustomerCreditPostingResult>((txn) async {
      final previousBalance = await _calculateBalance(txn, customerId);
      final newBalance = _roundMoney(previousBalance - refundTotal);
      final now = DateTime.now().toIso8601String();

      final ledgerId = await txn.insert(ledgerTable, {
        'customer_id': customerId,
        'entry_type': 'refund',
        'debit': 0.0,
        'credit': refundTotal,
        'balance_after': newBalance,
        'reference_type': 'refund',
        'reference_id': refundSaleId,
        'sale_id': refundSaleId,
        'payment_id': null,
        'description':
            'Credit refund #$refundSaleId for original sale #$originalSaleId',
        'payment_method': 'customer_credit_refund',
        'performed_by': _cleanOptional(performedBy),
        'approved_by': _cleanOptional(approvedBy),
        'created_at': now,
      });

      await txn.update(
        'customers',
        {
          'current_credit_balance': newBalance,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      await txn.update(
        'sales',
        {
          'customer_id': customerId,
          'customer_name_snapshot': original['customer_name_snapshot'],
          'customer_phone_snapshot': original['customer_phone_snapshot'],
          'customer_code_snapshot': original['customer_code_snapshot'],
          'payment_method': 'customer_credit_refund',
          'is_credit_sale': 0,
          'credit_status': 'refund_posted',
          'credit_ledger_id': ledgerId,
          'credit_approved_by': _cleanOptional(approvedBy),
          'credit_previous_balance': previousBalance,
          'credit_new_balance': newBalance,
          'credit_bill_amount': refundTotal,
          'credit_limit_snapshot': creditLimit,
        },
        where: 'id = ?',
        whereArgs: [refundSaleId],
      );

      await _enqueueSync(txn, 'CREDIT_REFUND_UPDATE', {
        ..._customerSyncMap(customer),
        'original_sale_id': originalSaleId,
        'refund_sale_id': refundSaleId,
        'customer_id': customerId,
        'customer_name_snapshot': original['customer_name_snapshot'],
        'customer_phone_snapshot': original['customer_phone_snapshot'],
        'customer_code_snapshot': original['customer_code_snapshot'],
        'is_credit_sale': 1,
        'credit_status': 'refund_posted',
        'credit_ledger_id': ledgerId,
        'credit_approved_by': _cleanOptional(approvedBy),
        'credit_previous_balance': previousBalance,
        'credit_new_balance': newBalance,
        'credit_bill_amount': refundTotal,
        'credit_limit_snapshot': creditLimit,
        'payment_method': 'customer_credit_refund',
        'ledger_entry': {
          'ledger_id': ledgerId,
          'entry_type': 'refund',
          'debit': 0.0,
          'credit': refundTotal,
          'balance_after': newBalance,
          'reference_type': 'refund',
          'reference_id': refundSaleId,
          'sale_id': refundSaleId,
          'description': 'Credit refund #$refundSaleId for original sale #$originalSaleId',
          'payment_method': 'customer_credit_refund',
          'performed_by': _cleanOptional(performedBy),
          'approved_by': _cleanOptional(approvedBy),
          'created_at': now,
        },
      });

      return CustomerCreditPostingResult(
        customerId: customerId,
        previousBalance: previousBalance,
        newBalance: newBalance,
        ledgerId: ledgerId,
      );
    });
  }

  Future<List<Map<String, dynamic>>> getCreditCustomersReport({
    bool includeZeroBalance = false,
    int limit = 300,
  }) async {
    final db = await _db;

    final where = includeZeroBalance
        ? '(COALESCE(c.credit_enabled, 0) = 1 OR ABS(COALESCE(c.current_credit_balance, 0)) > 0)'
        : 'ABS(COALESCE(c.current_credit_balance, 0)) > 0';

    final rows = await db.rawQuery(
      '''
      SELECT
        c.id,
        c.customer_code,
        c.name,
        c.phone,
        c.customer_type,
        c.is_active,
        COALESCE(c.credit_enabled, 0) AS credit_enabled,
        COALESCE(c.credit_limit, 0) AS credit_limit,
        COALESCE(c.current_credit_balance, 0) AS current_credit_balance,
        COALESCE(c.credit_status, 'normal') AS credit_status,
        c.credit_note,
        (
          SELECT MAX(l.created_at)
          FROM $ledgerTable l
          WHERE l.customer_id = c.id AND l.entry_type = 'payment'
        ) AS last_payment_at,
        (
          SELECT MAX(l.created_at)
          FROM $ledgerTable l
          WHERE l.customer_id = c.id AND l.entry_type = 'credit_sale'
        ) AS last_credit_sale_at
      FROM customers c
      WHERE $where
      ORDER BY COALESCE(c.current_credit_balance, 0) DESC,
               c.name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [limit <= 0 ? 300 : limit],
    );

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<double> _calculateBalance(
    DatabaseExecutor executor,
    int customerId,
  ) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(COALESCE(debit, 0) - COALESCE(credit, 0)), 0) AS balance
      FROM $ledgerTable
      WHERE customer_id = ?
      ''',
      [customerId],
    );

    return _roundMoney(_readDouble(rows.first['balance']));
  }

  Future<Map<String, dynamic>?> getCreditSaleInfo(int saleId) async {
    if (saleId <= 0) return null;

    final db = await _db;
    final rows = await db.query(
      'sales',
      columns: const [
        'id',
        'customer_id',
        'is_credit_sale',
        'credit_status',
        'credit_ledger_id',
        'credit_approved_by',
        'credit_previous_balance',
        'credit_new_balance',
        'credit_bill_amount',
        'credit_limit_snapshot',
      ],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    row['is_credit_sale'] = _readBool(row['is_credit_sale']);
    return row;
  }
}
