import 'package:shared/models/customer.dart';
import 'package:shared/models/customer_ledger_entry.dart';
import 'package:shared/models/customer_payment.dart';
import 'package:shared/models/customer_payment_receipt.dart';

import 'customer_credit_service.dart';
import 'database_helper.dart';

class CustomerPaymentReceiptService {
  CustomerPaymentReceiptService._();

  static final CustomerPaymentReceiptService instance =
      CustomerPaymentReceiptService._();

  String formatReceiptNo(int paymentId) {
    return 'PAY-${paymentId.toString().padLeft(6, '0')}';
  }

  Future<CustomerPaymentReceipt?> getReceiptByPaymentId(int paymentId) async {
    if (paymentId <= 0) return null;

    await CustomerCreditService.instance.ensureCreditStorage();
    final db = await DatabaseHelper.instance.database;

    final paymentRows = await db.query(
      CustomerCreditService.paymentsTable,
      where: 'id = ?',
      whereArgs: [paymentId],
      limit: 1,
    );
    if (paymentRows.isEmpty) return null;

    final payment = CustomerPayment.fromMap(paymentRows.first);
    final ledgerRows = await db.query(
      CustomerCreditService.ledgerTable,
      where: 'entry_type = ? AND payment_id = ?',
      whereArgs: ['payment', paymentId],
      orderBy: 'id DESC',
      limit: 1,
    );

    final paymentLedger = ledgerRows.isEmpty
        ? null
        : CustomerLedgerEntry.fromMap(ledgerRows.first);
    final customerRows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [payment.customerId],
      limit: 1,
    );
    final customer = customerRows.isEmpty
        ? null
        : Customer.fromMap(customerRows.first);

    final newBalance = paymentLedger?.balanceAfter ?? 0.0;
    final previousBalance = paymentLedger == null
        ? payment.amount
        : _roundMoney(newBalance + payment.amount);
    final ledgerVoided = paymentLedger?.isVoided ?? false;

    return CustomerPaymentReceipt(
      paymentId: paymentId,
      receiptNo: formatReceiptNo(paymentId),
      customerId: payment.customerId,
      customerName: customer?.displayName ?? 'Customer #${payment.customerId}',
      customerCode: customer?.displayCode ?? 'CUS-${payment.customerId}',
      customerPhone: customer?.phone,
      amountPaid: payment.amount,
      previousBalance: previousBalance,
      newBalance: newBalance,
      paymentMethod: payment.normalizedPaymentMethod,
      referenceNote: payment.referenceNote,
      receivedBy: payment.receivedBy ?? paymentLedger?.performedBy,
      cashierName: payment.cashierName,
      createdAt: payment.createdAt,
      isVoided: payment.isVoided || ledgerVoided,
      voidedAt: payment.voidedAt ?? paymentLedger?.voidedAt,
      voidedBy: payment.voidedBy ?? paymentLedger?.voidedBy,
      voidReason: payment.voidReason ?? paymentLedger?.voidReason,
    );
  }

  double _roundMoney(num value) {
    return double.parse(value.toDouble().toStringAsFixed(2));
  }
}
