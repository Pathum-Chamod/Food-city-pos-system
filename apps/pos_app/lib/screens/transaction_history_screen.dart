import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../services/customer_service.dart';
import '../services/customer_credit_service.dart';
import '../services/loyalty_service.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';
import 'refund_transaction_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();

  static String _formatQuantity(num value, {int maxDecimals = 3}) {
    final quantity = value.toDouble();
    if ((quantity - quantity.roundToDouble()).abs() < 0.000001) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static Future<Map<String, dynamic>?> _getTransactionSummaryWithCustomer(
    int saleId,
  ) async {
    final summary = await DatabaseHelper.instance.getTransactionSummary(saleId);
    if (summary == null) return null;

    final resolved = Map<String, dynamic>.from(summary);
    final customerSnapshot = await CustomerService.instance
        .getSaleCustomerSnapshotMap(saleId);
    resolved.addAll(customerSnapshot);

    final creditInfo = await CustomerCreditService.instance.getCreditSaleInfo(
      saleId,
    );
    if (creditInfo != null) {
      resolved.addAll(creditInfo);
    }

    final paymentMethod = (resolved['payment_method'] ?? '')
        .toString()
        .toLowerCase();
    final creditStatus = (resolved['credit_status'] ?? '')
        .toString()
        .toLowerCase();
    final isCreditSale =
        _readBool(resolved['is_credit_sale']) ||
        paymentMethod == 'customer_credit' ||
        paymentMethod == 'customer_credit_refund' ||
        creditStatus == 'refund_posted';
    final customerId = (resolved['customer_id'] as num?)?.toInt();
    if (isCreditSale &&
        (resolved['credit_limit_snapshot'] == null) &&
        customerId != null &&
        customerId > 0) {
      final creditSummary = await CustomerCreditService.instance
          .getCreditSummary(customerId);
      resolved['credit_limit_snapshot'] = creditSummary.creditLimit;
    }

    return resolved;
  }

  static String _readCustomerSnapshotText(
    Map<String, dynamic> summary,
    String key,
  ) {
    return (summary[key] ?? '').toString().trim();
  }

  static bool _readBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value.toInt() == 1;
    final text = value.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static String _customerPricingLabel(Map<String, dynamic> item) {
    final type = (item['customer_pricing_type'] ?? 'none')
        .toString()
        .trim()
        .toLowerCase();
    switch (type) {
      case 'customer_product_price':
        return 'Customer Price';
      case 'customer_direct_scheme':
        return 'Customer Scheme';
      case 'customer_category_scheme':
        return 'Category Scheme';
      case 'customer_default_price_type':
        final priceType = (item['price_category_used'] ?? 'selling')
            .toString()
            .trim()
            .toLowerCase();
        if (priceType == 'wholesale') return 'Wholesale Price';
        if (priceType == 'sale') return 'Sale Price';
        return 'Selling Price';
      case 'customer_default_discount':
        return 'Customer Discount';
      default:
        return '';
    }
  }

  static String _customerPricingDetail(Map<String, dynamic> item) {
    final label = _customerPricingLabel(item);
    if (label.isEmpty) return '';

    final original = ((item['customer_pricing_original_price'] as num?) ?? 0)
        .toDouble();
    final finalPrice = ((item['customer_pricing_final_price'] as num?) ?? 0)
        .toDouble();
    final discount = ((item['customer_pricing_discount_amount'] as num?) ?? 0)
        .toDouble();

    final parts = <String>[label];
    if (original > 0 && finalPrice > 0) {
      parts.add('Original Rs. ${original.toStringAsFixed(2)}');
      parts.add('Final Rs. ${finalPrice.toStringAsFixed(2)}');
    }
    if (discount > 0) {
      parts.add('Saved Rs. ${discount.toStringAsFixed(2)} each');
    }

    final note = (item['customer_pricing_note'] ?? '').toString().trim();
    if (note.isNotEmpty) {
      parts.add(note);
    }

    return parts.join(' | ');
  }

  static Future<void> showReceiptDialogForTransaction(
    BuildContext context,
    int saleId,
  ) async {
    final summary = await _getTransactionSummaryWithCustomer(saleId);
    final items = await DatabaseHelper.instance.getTransactionItems(saleId);

    if (!context.mounted) return;

    if (summary == null) {
      AppSnackBar.show(
        context,
        message: 'Transaction not found.',
        backgroundColor: Colors.red,
      );
      return;
    }

    final action = await showTransactionReceiptDialog(
      context,
      summary: summary,
      items: items,
    );

    if (!context.mounted) return;

    final type = (summary['transaction_type'] ?? 'sale')
        .toString()
        .toLowerCase();

    if (action == 'refund' && type == 'sale') {
      final refundSaleId = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (context) => RefundTransactionScreen(originalSaleId: saleId),
        ),
      );

      if (!context.mounted) return;

      if (refundSaleId != null) {
        try {
          await LoyaltyService.instance.reverseLoyaltyForRefund(
            originalSaleId: saleId,
            refundSaleId: refundSaleId,
          );
        } catch (e) {
          if (context.mounted) {
            AppSnackBar.show(
              context,
              message: e.toString().replaceFirst('Exception: ', ''),
              backgroundColor: Colors.orange,
            );
          }
        }

        try {
          final result = await CustomerCreditService.instance
              .postCreditRefundFromOriginalSale(
                originalSaleId: saleId,
                refundSaleId: refundSaleId,
                performedBy: (summary['cashier_name'] ?? 'Unknown').toString(),
              );

          if (context.mounted && result != null) {
            AppSnackBar.show(
              context,
              message:
                  'Credit balance adjusted. New balance Rs. ${result.newBalance.toStringAsFixed(2)}.',
              backgroundColor: Colors.green,
            );
          }
        } catch (e) {
          if (context.mounted) {
            AppSnackBar.show(
              context,
              message: e.toString().replaceFirst('Exception: ', ''),
              backgroundColor: Colors.orange,
            );
          }
        }

        await showReceiptDialogForTransaction(context, refundSaleId);
      }
    }

    if (!context.mounted) return;

    if (action == 'reprint') {
      await printReceiptForTransaction(context, saleId);
    }

    if (!context.mounted) return;

    if (action == 'pdf') {
      await saveReceiptPdfForTransaction(context, saleId);
    }
  }

  static Future<bool> printReceiptForTransaction(
    BuildContext context,
    int saleId,
  ) async {
    final printer = ReceiptPrinterService.instance;

    if (!printer.isConnected) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          message:
              'Receipt printer is not selected. Open Hardware Setup first.',
          backgroundColor: Colors.orange,
        );
      }
      return false;
    }

    final summary = await _getTransactionSummaryWithCustomer(saleId);
    final items = await DatabaseHelper.instance.getTransactionItems(saleId);

    if (!context.mounted) return false;

    if (summary == null) {
      AppSnackBar.show(
        context,
        message: 'Transaction not found.',
        backgroundColor: Colors.red,
      );
      return false;
    }

    final paymentMethod = (summary['payment_method'] ?? 'cash').toString();
    final cashierName = (summary['cashier_name'] ?? 'Unknown').toString();
    final subtotal = ((summary['subtotal_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final discountAmount = ((summary['discount_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final discountType = (summary['discount_type'] ?? 'none').toString();
    final discountValue = ((summary['discount_value'] as num?) ?? 0)
        .toDouble()
        .abs();
    final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
    final amountTendered = ((summary['amount_tendered'] as num?) ?? 0)
        .toDouble();
    final changeAmount = ((summary['change_amount'] as num?) ?? 0).toDouble();
    final isRefund =
        (summary['transaction_type'] ?? 'sale').toString().toLowerCase() ==
        'refund';
    final customerName = _readCustomerSnapshotText(
      summary,
      'customer_name_snapshot',
    );
    final customerPhone = _readCustomerSnapshotText(
      summary,
      'customer_phone_snapshot',
    );
    final customerCode = _readCustomerSnapshotText(
      summary,
      'customer_code_snapshot',
    );
    final paymentMethodLower = paymentMethod.toLowerCase();
    final creditStatus = (summary['credit_status'] ?? '')
        .toString()
        .toLowerCase();
    final isCreditSale =
        _readBool(summary['is_credit_sale']) ||
        paymentMethodLower == 'customer_credit' ||
        paymentMethodLower == 'customer_credit_refund' ||
        creditStatus == 'refund_posted';
    final creditPreviousBalance =
        ((summary['credit_previous_balance'] as num?) ?? 0).toDouble();
    final creditNewBalance = ((summary['credit_new_balance'] as num?) ?? 0)
        .toDouble();
    final creditBillAmount = ((summary['credit_bill_amount'] as num?) ?? total)
        .toDouble()
        .abs();
    final creditLimit = ((summary['credit_limit_snapshot'] as num?) ?? 0)
        .toDouble();
    final creditApprovedBy = (summary['credit_approved_by'] ?? '')
        .toString()
        .trim();
    final loyaltyPointsEarned =
        ((summary['loyalty_points_earned'] as num?) ?? 0).toInt();
    final loyaltyPointsRedeemed =
        ((summary['loyalty_points_redeemed'] as num?) ?? 0).toInt();
    final loyaltyRedeemedValue =
        ((summary['loyalty_redeemed_value'] as num?) ?? 0).toDouble();
    final loyaltyEarnBaseAmount =
        ((summary['loyalty_earn_base_amount'] as num?) ?? 0).toDouble();
    final loyaltyNote = (summary['loyalty_note'] ?? '').toString().trim();

    final receiptItems = items.map((item) {
      final finalLineTotal = ((item['line_total'] as num?) ?? 0)
          .toDouble()
          .abs();
      final baseLineTotal =
          ((item['base_line_total'] as num?) ?? finalLineTotal)
              .toDouble()
              .abs();
      final storedExplicitItemDiscount =
          ((item['explicit_item_discount_amount'] as num?) ?? 0)
              .toDouble()
              .abs();
      final storedCartDiscount = ((item['cart_discount_amount'] as num?) ?? 0)
          .toDouble()
          .abs();
      final storedCombinedItemDiscount =
          ((item['item_discount_amount'] as num?) ?? 0).toDouble().abs();
      final explicitItemDiscount = storedExplicitItemDiscount > 0
          ? storedExplicitItemDiscount
          : (storedCartDiscount <= 0 && discountType == 'none'
                ? storedCombinedItemDiscount
                : 0.0);
      final customerPricingApplied = _readBool(
        item['customer_pricing_applied'],
      );
      return {
        'name': (item['product_name'] ?? 'Item').toString(),
        'qty': ((item['quantity'] as num?) ?? 0).toDouble(),
        'unitPrice': ((item['unit_price'] as num?) ?? 0).toDouble(),
        'markedPrice':
            ((item['marked_price'] as num?) ??
                    (item['unit_price'] as num?) ??
                    0)
                .toDouble(),
        'priceType': (item['price_category_used'] ?? 'selling').toString(),
        'baseLineTotal': baseLineTotal,
        'itemDiscountType': (item['item_discount_type'] ?? 'none').toString(),
        'itemDiscountValue': ((item['item_discount_value'] as num?) ?? 0)
            .toDouble()
            .abs(),
        'itemDiscountAmount': explicitItemDiscount,
        'customerPricingDetail': customerPricingApplied
            ? _customerPricingDetail(item)
            : '',
        'lineTotal': baseLineTotal - explicitItemDiscount,
      };
    }).toList();
    final receiptItemDiscountTotal = receiptItems.fold<double>(
      0.0,
      (sum, item) =>
          sum + (((item['itemDiscountAmount'] as num?) ?? 0).toDouble()),
    );
    final receiptCartDiscountAmount =
        (discountAmount - receiptItemDiscountTotal)
            .clamp(0.0, discountAmount)
            .toDouble();
    final receiptSubtotal = receiptItems.fold<double>(
      0.0,
      (sum, item) => sum + (((item['lineTotal'] as num?) ?? 0).toDouble()),
    );

    final response = await printer.printReceipt(
      transactionId: saleId,
      cashierName: cashierName,
      paymentMethod: paymentMethod,
      customerName: customerName,
      customerPhone: customerPhone,
      customerCode: customerCode,
      items: receiptItems,
      subtotal: receiptSubtotal,
      discountAmount: receiptCartDiscountAmount,
      discountType: discountType,
      discountValue: discountValue,
      total: total,
      amountTendered: paymentMethod.toLowerCase() == 'cash'
          ? amountTendered
          : null,
      changeAmount: paymentMethod.toLowerCase() == 'cash' ? changeAmount : null,
      isRefund: isRefund,
      isCreditSale: isCreditSale,
      creditPreviousBalance: creditPreviousBalance,
      creditBillAmount: creditBillAmount,
      creditNewBalance: creditNewBalance,
      creditLimit: creditLimit,
      creditApprovedBy: creditApprovedBy,
      loyaltyPointsEarned: loyaltyPointsEarned,
      loyaltyPointsRedeemed: loyaltyPointsRedeemed,
      loyaltyRedeemedValue: loyaltyRedeemedValue,
      loyaltyEarnBaseAmount: loyaltyEarnBaseAmount,
      loyaltyNote: loyaltyNote,
    );

    if (!context.mounted) return response.isSuccess;

    AppSnackBar.show(
      context,
      message: response.message,
      backgroundColor: response.isSuccess ? Colors.green : Colors.orange,
    );

    return response.isSuccess;
  }

  static Future<bool> saveReceiptPdfForTransaction(
    BuildContext context,
    int saleId,
  ) async {
    final summary = await _getTransactionSummaryWithCustomer(saleId);
    final items = await DatabaseHelper.instance.getTransactionItems(saleId);

    if (!context.mounted) return false;

    if (summary == null) {
      AppSnackBar.show(
        context,
        message: 'Transaction not found.',
        backgroundColor: Colors.red,
      );
      return false;
    }

    final paymentMethod = (summary['payment_method'] ?? 'cash').toString();
    final cashierName = (summary['cashier_name'] ?? 'Unknown').toString();
    final subtotal = ((summary['subtotal_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final discountAmount = ((summary['discount_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final discountType = (summary['discount_type'] ?? 'none').toString();
    final discountValue = ((summary['discount_value'] as num?) ?? 0)
        .toDouble()
        .abs();
    final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
    final amountTendered = ((summary['amount_tendered'] as num?) ?? 0)
        .toDouble();
    final changeAmount = ((summary['change_amount'] as num?) ?? 0).toDouble();
    final isRefund =
        (summary['transaction_type'] ?? 'sale').toString().toLowerCase() ==
        'refund';
    final customerName = _readCustomerSnapshotText(
      summary,
      'customer_name_snapshot',
    );
    final customerPhone = _readCustomerSnapshotText(
      summary,
      'customer_phone_snapshot',
    );
    final customerCode = _readCustomerSnapshotText(
      summary,
      'customer_code_snapshot',
    );
    final paymentMethodLower = paymentMethod.toLowerCase();
    final creditStatus = (summary['credit_status'] ?? '')
        .toString()
        .toLowerCase();
    final isCreditSale =
        _readBool(summary['is_credit_sale']) ||
        paymentMethodLower == 'customer_credit' ||
        paymentMethodLower == 'customer_credit_refund' ||
        creditStatus == 'refund_posted';
    final creditPreviousBalance =
        ((summary['credit_previous_balance'] as num?) ?? 0).toDouble();
    final creditNewBalance = ((summary['credit_new_balance'] as num?) ?? 0)
        .toDouble();
    final creditBillAmount = ((summary['credit_bill_amount'] as num?) ?? total)
        .toDouble()
        .abs();
    final creditLimit = ((summary['credit_limit_snapshot'] as num?) ?? 0)
        .toDouble();
    final creditApprovedBy = (summary['credit_approved_by'] ?? '')
        .toString()
        .trim();
    final loyaltyPointsEarned =
        ((summary['loyalty_points_earned'] as num?) ?? 0).toInt();
    final loyaltyPointsRedeemed =
        ((summary['loyalty_points_redeemed'] as num?) ?? 0).toInt();
    final loyaltyRedeemedValue =
        ((summary['loyalty_redeemed_value'] as num?) ?? 0).toDouble();
    final loyaltyEarnBaseAmount =
        ((summary['loyalty_earn_base_amount'] as num?) ?? 0).toDouble();
    final loyaltyNote = (summary['loyalty_note'] ?? '').toString().trim();

    final receiptItems = items.map((item) {
      final finalLineTotal = ((item['line_total'] as num?) ?? 0)
          .toDouble()
          .abs();
      final baseLineTotal =
          ((item['base_line_total'] as num?) ?? finalLineTotal)
              .toDouble()
              .abs();
      final storedExplicitItemDiscount =
          ((item['explicit_item_discount_amount'] as num?) ?? 0)
              .toDouble()
              .abs();
      final storedCartDiscount = ((item['cart_discount_amount'] as num?) ?? 0)
          .toDouble()
          .abs();
      final storedCombinedItemDiscount =
          ((item['item_discount_amount'] as num?) ?? 0).toDouble().abs();
      final explicitItemDiscount = storedExplicitItemDiscount > 0
          ? storedExplicitItemDiscount
          : (storedCartDiscount <= 0 && discountType == 'none'
                ? storedCombinedItemDiscount
                : 0.0);
      final customerPricingApplied = _readBool(
        item['customer_pricing_applied'],
      );
      return {
        'name': (item['product_name'] ?? 'Item').toString(),
        'qty': ((item['quantity'] as num?) ?? 0).toDouble(),
        'unitPrice': ((item['unit_price'] as num?) ?? 0).toDouble(),
        'markedPrice':
            ((item['marked_price'] as num?) ??
                    (item['unit_price'] as num?) ??
                    0)
                .toDouble(),
        'priceType': (item['price_category_used'] ?? 'selling').toString(),
        'baseLineTotal': baseLineTotal,
        'itemDiscountType': (item['item_discount_type'] ?? 'none').toString(),
        'itemDiscountValue': ((item['item_discount_value'] as num?) ?? 0)
            .toDouble()
            .abs(),
        'itemDiscountAmount': explicitItemDiscount,
        'customerPricingDetail': customerPricingApplied
            ? _customerPricingDetail(item)
            : '',
        'lineTotal': baseLineTotal - explicitItemDiscount,
      };
    }).toList();
    final receiptItemDiscountTotal = receiptItems.fold<double>(
      0.0,
      (sum, item) =>
          sum + (((item['itemDiscountAmount'] as num?) ?? 0).toDouble()),
    );
    final receiptCartDiscountAmount =
        (discountAmount - receiptItemDiscountTotal)
            .clamp(0.0, discountAmount)
            .toDouble();
    final receiptSubtotal = receiptItems.fold<double>(
      0.0,
      (sum, item) => sum + (((item['lineTotal'] as num?) ?? 0).toDouble()),
    );

    final response = await ReceiptPdfService.instance.saveReceiptPdf(
      transactionId: saleId,
      cashierName: cashierName,
      paymentMethod: paymentMethod,
      customerName: customerName,
      customerPhone: customerPhone,
      customerCode: customerCode,
      items: receiptItems,
      subtotal: receiptSubtotal,
      discountAmount: receiptCartDiscountAmount,
      discountType: discountType,
      discountValue: discountValue,
      total: total,
      amountTendered: paymentMethod.toLowerCase() == 'cash'
          ? amountTendered
          : null,
      changeAmount: paymentMethod.toLowerCase() == 'cash' ? changeAmount : null,
      isRefund: isRefund,
      isCreditSale: isCreditSale,
      creditPreviousBalance: creditPreviousBalance,
      creditBillAmount: creditBillAmount,
      creditNewBalance: creditNewBalance,
      creditLimit: creditLimit,
      creditApprovedBy: creditApprovedBy,
      loyaltyPointsEarned: loyaltyPointsEarned,
      loyaltyPointsRedeemed: loyaltyPointsRedeemed,
      loyaltyRedeemedValue: loyaltyRedeemedValue,
      loyaltyEarnBaseAmount: loyaltyEarnBaseAmount,
      loyaltyNote: loyaltyNote,
    );

    if (!context.mounted) return response.isSuccess;

    AppSnackBar.show(
      context,
      message: response.message,
      backgroundColor: response.isSuccess ? Colors.green : Colors.orange,
    );

    return response.isSuccess;
  }
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  String _filter = 'all';
  String _dateFilter = 'all';
  String _searchQuery = '';
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final type = _filter == 'all' ? null : _filter;
    final selectedDay = _dateFilter == 'today'
        ? _normalizedDay(DateTime.now())
        : _dateFilter == 'specific'
        ? _selectedDate
        : null;
    final start = selectedDay == null
        ? null
        : DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final end = selectedDay == null
        ? null
        : DateTime(
            selectedDay.year,
            selectedDay.month,
            selectedDay.day,
            23,
            59,
            59,
            999,
          );

    final transactions = await DatabaseHelper.instance.getRecentTransactions(
      transactionType: type,
      start: start,
      end: end,
      limit: null,
    );

    final enrichedTransactions = <Map<String, dynamic>>[];
    for (final rawTransaction in transactions) {
      final transaction = Map<String, dynamic>.from(rawTransaction);
      final saleId =
          (transaction['id'] as num?)?.toInt() ??
          int.tryParse((transaction['id'] ?? '').toString()) ??
          0;

      if (saleId > 0) {
        final customerSnapshot = await CustomerService.instance
            .getSaleCustomerSnapshotMap(saleId);
        transaction.addAll(customerSnapshot);
      }

      enrichedTransactions.add(transaction);
    }

    if (!mounted) return;

    setState(() {
      _transactions = enrichedTransactions;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadTransactions();
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleTransactions {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _transactions;

    return _transactions.where((tx) {
      final id = (tx['id'] ?? '').toString().toLowerCase();
      final cashier = (tx['cashier_name'] ?? '').toString().toLowerCase();
      final payment = (tx['payment_method'] ?? '').toString().toLowerCase();
      final type = (tx['transaction_type'] ?? '').toString().toLowerCase();
      final refundReason = (tx['refund_reason'] ?? '').toString().toLowerCase();
      final customerName = (tx['customer_name_snapshot'] ?? '')
          .toString()
          .toLowerCase();
      final customerPhone = (tx['customer_phone_snapshot'] ?? '')
          .toString()
          .toLowerCase();
      final customerCode = (tx['customer_code_snapshot'] ?? '')
          .toString()
          .toLowerCase();
      final createdAt = (tx['created_at'] ?? '').toString();
      return id.contains(q) ||
          cashier.contains(q) ||
          payment.contains(q) ||
          type.contains(q) ||
          refundReason.contains(q) ||
          customerName.contains(q) ||
          customerPhone.contains(q) ||
          customerCode.contains(q) ||
          _matchesDateSearch(createdAt, q);
    }).toList();
  }

  int get _saleCount => _transactions
      .where(
        (tx) =>
            (tx['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'sale',
      )
      .length;

  int get _refundCount => _transactions
      .where(
        (tx) =>
            (tx['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'refund',
      )
      .length;

  double get _salesTotal => _transactions
      .where(
        (tx) =>
            (tx['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'sale',
      )
      .fold<double>(
        0,
        (sum, tx) =>
            sum + (((tx['total_amount'] as num?) ?? 0).toDouble().abs()),
      );

  double get _refundTotal => _transactions
      .where(
        (tx) =>
            (tx['transaction_type'] ?? 'sale').toString().toLowerCase() ==
            'refund',
      )
      .fold<double>(
        0,
        (sum, tx) =>
            sum + (((tx['total_amount'] as num?) ?? 0).toDouble().abs()),
      );

  bool get _isTodaySelected {
    return _dateFilter == 'today';
  }

  DateTime _normalizedDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = _normalizedDay(now);
    final selected = _selectedDate;
    final initialDate = selected != null && !selected.isAfter(today)
        ? selected
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: today,
      selectableDayPredicate: (day) {
        return !_normalizedDay(day).isAfter(today);
      },
      helpText: 'Select transaction date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _dateFilter = 'specific';
      _selectedDate = _normalizedDay(picked);
    });
    await _loadTransactions();
  }

  Future<void> _selectToday() async {
    if (_dateFilter == 'today') return;

    setState(() {
      _dateFilter = 'today';
      _selectedDate = null;
    });
    await _loadTransactions();
  }

  Future<void> _clearDateFilter() async {
    if (_dateFilter == 'all') return;

    setState(() {
      _dateFilter = 'all';
      _selectedDate = null;
    });
    await _loadTransactions();
  }

  String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $h:$min';
    } catch (_) {
      return raw;
    }
  }

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final quantity = value.toDouble();
    if ((quantity - quantity.roundToDouble()).abs() < 0.000001) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  bool _matchesDateSearch(String raw, String query) {
    if (raw.isEmpty || query.isEmpty) return false;

    DateTime? dt;
    try {
      dt = DateTime.parse(raw).toLocal();
    } catch (_) {
      return false;
    }

    final normalizedQuery = query.trim().toLowerCase();
    final digitsOnly = normalizedQuery.replaceAll(RegExp(r'[^0-9]'), '');
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');

    final searchableForms = <String>{
      '$yyyy-$mm-$dd',
      '$yyyy/$mm/$dd',
      '$dd-$mm-$yyyy',
      '$dd/$mm/$yyyy',
      '$yyyy$mm$dd',
      '$dd$mm$yyyy',
      '$mm$dd$yyyy',
      '$yyyy${dt.month}${dt.day}',
      '${dt.month}${dt.day}$yyyy',
      '${dt.day}$mm$yyyy',
      '${dt.month}$dd$yyyy',
      (_formatDateTime(raw).toLowerCase()),
    };

    if (searchableForms.any((value) => value.contains(normalizedQuery))) {
      return true;
    }

    if (digitsOnly.isEmpty) return false;

    final digitForms = <String>{
      '$yyyy$mm$dd',
      '$dd$mm$yyyy',
      '$mm$dd$yyyy',
      '$yyyy${dt.month}${dt.day}',
      '${dt.month}${dt.day}$yyyy',
      '${dt.day}$mm$yyyy',
      '${dt.month}$dd$yyyy',
    };

    return digitForms.any((value) => value.contains(digitsOnly));
  }

  String _paymentLabel(String? method) {
    switch ((method ?? '').toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'customer_credit':
        return 'Customer Credit';
      case 'customer_credit_refund':
        return 'Customer Credit Refund';
      case 'refund':
        return 'Refund';
      default:
        return 'N/A';
    }
  }

  String _customerName(Map<String, dynamic> tx) {
    return (tx['customer_name_snapshot'] ?? '').toString().trim();
  }

  bool _isCreditSale(Map<String, dynamic> tx) {
    final paymentMethod = (tx['payment_method'] ?? '').toString().toLowerCase();
    final creditStatus = (tx['credit_status'] ?? '').toString().toLowerCase();

    return TransactionHistoryScreen._readBool(tx['is_credit_sale']) ||
        paymentMethod == 'customer_credit' ||
        paymentMethod == 'customer_credit_refund' ||
        creditStatus == 'refund_posted';
  }

  String _customerSubtitle(Map<String, dynamic> tx) {
    final parts = <String>[];
    final code = (tx['customer_code_snapshot'] ?? '').toString().trim();
    final phone = (tx['customer_phone_snapshot'] ?? '').toString().trim();

    if (code.isNotEmpty) parts.add(code);
    if (phone.isNotEmpty) parts.add(phone);

    return parts.isEmpty ? 'Registered customer' : parts.join(' • ');
  }

  Color _typeColor(_TxPalette palette, String type) {
    return type == 'refund' ? palette.danger : palette.brand;
  }

  String _typeLabel(String type) {
    return type == 'refund' ? 'Refund' : 'Sale';
  }

  Widget _buildFilterChip(_TxPalette palette, String value, String label) {
    final selected = _filter == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
        _loadTransactions();
      },
      selectedColor: palette.brandSoft,
      backgroundColor: palette.soft,
      side: BorderSide(color: selected ? palette.brand : palette.border),
      labelStyle: TextStyle(
        color: selected ? palette.brand : palette.textSecondary,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildTodayChip(_TxPalette palette) {
    final selected = _isTodaySelected;

    return ChoiceChip(
      label: const Text('Today'),
      selected: selected,
      onSelected: (_) => _selectToday(),
      showCheckmark: false,
      selectedColor: palette.brandSoft,
      backgroundColor: palette.soft,
      side: BorderSide(
        color: selected ? palette.brand.withOpacity(0.25) : palette.border,
      ),
      labelStyle: TextStyle(
        color: selected ? palette.brand : palette.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDateChip(_TxPalette palette) {
    final selected = _dateFilter == 'specific';
    final label = selected && _selectedDate != null
        ? _formatDate(_selectedDate!)
        : 'Pick Date';

    return ActionChip(
      avatar: Icon(
        Icons.calendar_month_rounded,
        size: 18,
        color: selected ? Colors.white : palette.textPrimary,
      ),
      label: Text(label),
      onPressed: _pickDate,
      backgroundColor: selected ? palette.accentBlue : palette.soft,
      side: BorderSide(
        color: selected ? palette.accentBlue.withOpacity(0.35) : palette.border,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : palette.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildAllDatesChip(_TxPalette palette) {
    final selected = _dateFilter == 'all';

    return ChoiceChip(
      label: const Text('All Dates'),
      selected: selected,
      onSelected: (_) => _clearDateFilter(),
      showCheckmark: false,
      selectedColor: palette.brandSoft,
      backgroundColor: palette.soft,
      side: BorderSide(
        color: selected ? palette.brand.withOpacity(0.25) : palette.border,
      ),
      labelStyle: TextStyle(
        color: selected ? palette.brand : palette.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSummaryCard({
    required _TxPalette palette,
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withOpacity(palette.isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarCard(_TxPalette palette) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText:
                        'Search transaction, customer, phone, cashier, payment, or type',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: palette.brand,
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isRefreshing ? null : _refresh,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final typeFilters = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildFilterChip(palette, 'all', 'All'),
                  _buildFilterChip(palette, 'sale', 'Sales'),
                  _buildFilterChip(palette, 'refund', 'Refunds'),
                ],
              );
              final dateFilters = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  _buildAllDatesChip(palette),
                  _buildTodayChip(palette),
                  _buildDateChip(palette),
                ],
              );

              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    typeFilters,
                    const SizedBox(height: 10),
                    dateFilters,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: typeFilters),
                  const SizedBox(width: 12),
                  dateFilters,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCreditChip(_TxPalette palette, {String label = 'Credit Sale'}) {
    const color = Color(0xFFFFB65C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(palette.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTypeChip(_TxPalette palette, String type) {
    final color = _typeColor(palette, type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(palette.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildMiniInfoCard(_TxPalette palette, String title, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(_TxPalette palette, Map<String, dynamic> tx) {
    final type = (tx['transaction_type'] ?? 'sale').toString().toLowerCase();
    final color = _typeColor(palette, type);
    final total = ((tx['total_amount'] as num?) ?? 0).toDouble().abs();
    final id = tx['id'];
    final cashier = (tx['cashier_name'] ?? 'Unknown').toString();
    final itemCount = ((tx['item_line_count'] as num?) ?? 0).toInt();
    final createdAt = (tx['created_at'] ?? '').toString();
    final originalSaleId = tx['original_sale_id'];
    final paymentMethod = (tx['payment_method'] ?? '').toString();
    final discountAmount = ((tx['discount_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final customerName = _customerName(tx);
    final hasCustomer = customerName.isNotEmpty;
    final isCreditSale = _isCreditSale(tx);
    final creditPreviousBalance = ((tx['credit_previous_balance'] as num?) ?? 0)
        .toDouble();
    final creditNewBalance = ((tx['credit_new_balance'] as num?) ?? 0)
        .toDouble();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await TransactionHistoryScreen.showReceiptDialogForTransaction(
            context,
            id as int,
          );
          if (mounted) {
            _loadTransactions();
          }
        },
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Transaction #$id',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (isCreditSale) ...[
                          _buildCreditChip(
                            palette,
                            label: type == 'refund'
                                ? 'Credit Refund'
                                : 'Credit Sale',
                          ),
                          const SizedBox(width: 8),
                        ],
                        _buildTypeChip(palette, type),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      cashier,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildMiniInfoCard(
                          palette,
                          'Items',
                          itemCount.toString(),
                        ),
                        _buildMiniInfoCard(
                          palette,
                          'Time',
                          _formatDateTime(createdAt),
                        ),
                        if (hasCustomer)
                          _buildMiniInfoCard(
                            palette,
                            'Customer',
                            '$customerName\n${_customerSubtitle(tx)}',
                          ),
                        if (isCreditSale)
                          _buildMiniInfoCard(
                            palette,
                            'Credit Balance',
                            'Rs. ${creditPreviousBalance.toStringAsFixed(2)} → Rs. ${creditNewBalance.toStringAsFixed(2)}',
                          ),
                        if (type == 'sale' && discountAmount > 0)
                          _buildMiniInfoCard(
                            palette,
                            'Discount',
                            'Rs. ${discountAmount.toStringAsFixed(2)}',
                          ),
                        if (type == 'refund' && originalSaleId != null)
                          _buildMiniInfoCard(
                            palette,
                            'Original Sale',
                            '#$originalSaleId',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Rs. ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to view receipt',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(_TxPalette palette) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Center(
        child: Text(
          _searchQuery.trim().isEmpty
              ? 'No transactions found.'
              : 'No transactions match the current search.',
          style: TextStyle(
            color: palette.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_TxPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.surfaceAlt, palette.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaction History',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review sales, refunds, receipts, and cashier activity in one place.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _TxPalette.of(context);
    final visibleTransactions = _visibleTransactions;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.background, palette.backgroundAlt],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: palette.brand))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(palette),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildSummaryCard(
                          palette: palette,
                          title: 'Transactions',
                          value: _transactions.length.toString(),
                          icon: Icons.receipt_long_outlined,
                          accent: palette.accentBlue,
                        ),
                        _buildSummaryCard(
                          palette: palette,
                          title: 'Sales',
                          value: _saleCount.toString(),
                          icon: Icons.point_of_sale_outlined,
                          accent: palette.success,
                        ),
                        _buildSummaryCard(
                          palette: palette,
                          title: 'Refunds',
                          value: _refundCount.toString(),
                          icon: Icons.undo_outlined,
                          accent: palette.danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildToolbarCard(palette),
                    const SizedBox(height: 16),
                    Text(
                      'Transactions (${visibleTransactions.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (visibleTransactions.isEmpty)
                      _buildEmptyState(palette)
                    else
                      ...visibleTransactions.map(
                        (tx) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildTransactionCard(palette, tx),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

Future<String?> showTransactionReceiptDialog(
  BuildContext context, {
  required Map<String, dynamic> summary,
  required List<Map<String, dynamic>> items,
}) async {
  String formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $h:$min';
    } catch (_) {
      return raw;
    }
  }

  String paymentLabel(String? method) {
    switch ((method ?? '').toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'customer_credit':
        return 'Customer Credit';
      case 'customer_credit_refund':
        return 'Customer Credit Refund';
      case 'refund':
        return 'Refund';
      default:
        return 'N/A';
    }
  }

  final palette = _TxPalette.of(context);
  final transactionType = (summary['transaction_type'] ?? 'sale')
      .toString()
      .toLowerCase();
  final isRefund = transactionType == 'refund';
  final subtotal = ((summary['subtotal_amount'] as num?) ?? 0).toDouble().abs();
  final discountType = (summary['discount_type'] ?? 'none').toString();
  final discountValue = ((summary['discount_value'] as num?) ?? 0).toDouble();
  final discountAmount = ((summary['discount_amount'] as num?) ?? 0)
      .toDouble()
      .abs();
  final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
  final cashier = (summary['cashier_name'] ?? 'Unknown').toString();
  final createdAt = (summary['created_at'] ?? '').toString();
  final transactionId = summary['id'];
  final originalSaleId = summary['original_sale_id'];
  final refundReason = (summary['refund_reason'] ?? '').toString();
  final paymentMethod = (summary['payment_method'] ?? '').toString();
  final amountTendered = ((summary['amount_tendered'] as num?) ?? 0).toDouble();
  final changeAmount = ((summary['change_amount'] as num?) ?? 0).toDouble();
  final customerName = (summary['customer_name_snapshot'] ?? '')
      .toString()
      .trim();
  final customerPhone = (summary['customer_phone_snapshot'] ?? '')
      .toString()
      .trim();
  final customerCode = (summary['customer_code_snapshot'] ?? '')
      .toString()
      .trim();
  final hasCustomer = customerName.isNotEmpty;
  final isCreditSale =
      TransactionHistoryScreen._readBool(summary['is_credit_sale']) ||
      paymentMethod.toLowerCase() == 'customer_credit';
  final creditPreviousBalance =
      ((summary['credit_previous_balance'] as num?) ?? 0).toDouble();
  final creditNewBalance = ((summary['credit_new_balance'] as num?) ?? 0)
      .toDouble();
  final creditBillAmount = ((summary['credit_bill_amount'] as num?) ?? total)
      .toDouble()
      .abs();
  final creditLimit = ((summary['credit_limit_snapshot'] as num?) ?? 0)
      .toDouble();
  final creditApprovedBy = (summary['credit_approved_by'] ?? '')
      .toString()
      .trim();
  final loyaltyPointsEarned = ((summary['loyalty_points_earned'] as num?) ?? 0)
      .toInt();
  final loyaltyPointsRedeemed =
      ((summary['loyalty_points_redeemed'] as num?) ?? 0).toInt();
  final loyaltyRedeemedValue =
      ((summary['loyalty_redeemed_value'] as num?) ?? 0).toDouble();
  final loyaltyEarnBaseAmount =
      ((summary['loyalty_earn_base_amount'] as num?) ?? 0).toDouble();
  final loyaltyNote = (summary['loyalty_note'] ?? '').toString().trim();
  final hasLoyalty =
      loyaltyPointsEarned != 0 ||
      loyaltyPointsRedeemed != 0 ||
      loyaltyRedeemedValue.abs() > 0.000001 ||
      loyaltyNote.isNotEmpty;

  String formatPercent(num value) {
    final number = value.toDouble();
    return number.toStringAsFixed(number % 1 == 0 ? 0 : 2);
  }

  String discountPercentLabel({
    required double amount,
    required double base,
    required String type,
    required double value,
  }) {
    if (amount <= 0 || base <= 0) return '';
    if (type == 'percent' && value > 0) return formatPercent(value);
    return formatPercent((amount / base) * 100);
  }

  final receiptItems = items.map((item) {
    final rawLineTotal = ((item['line_total'] as num?) ?? 0).toDouble().abs();
    final baseLineTotal = ((item['base_line_total'] as num?) ?? rawLineTotal)
        .toDouble()
        .abs();
    final storedExplicitItemDiscount =
        ((item['explicit_item_discount_amount'] as num?) ?? 0).toDouble().abs();
    final storedCartDiscount = ((item['cart_discount_amount'] as num?) ?? 0)
        .toDouble()
        .abs();
    final storedCombinedItemDiscount =
        ((item['item_discount_amount'] as num?) ?? 0).toDouble().abs();
    final explicitItemDiscount = storedExplicitItemDiscount > 0
        ? storedExplicitItemDiscount
        : (storedCartDiscount <= 0 && discountType == 'none'
              ? storedCombinedItemDiscount
              : 0.0);
    final customerPricingApplied = TransactionHistoryScreen._readBool(
      item['customer_pricing_applied'],
    );
    final customerPricingDetail = customerPricingApplied
        ? TransactionHistoryScreen._customerPricingDetail(item)
        : '';
    return {
      'name': (item['product_name'] ?? 'Unknown').toString(),
      'barcode': (item['barcode'] ?? '').toString(),
      'quantity': ((item['quantity'] as num?) ?? 0).toDouble(),
      'unitPrice': ((item['unit_price'] as num?) ?? 0).toDouble(),
      'markedPrice':
          ((item['marked_price'] as num?) ?? (item['unit_price'] as num?) ?? 0)
              .toDouble(),
      'baseLineTotal': baseLineTotal,
      'itemDiscountType': (item['item_discount_type'] ?? 'none').toString(),
      'itemDiscountValue': ((item['item_discount_value'] as num?) ?? 0)
          .toDouble()
          .abs(),
      'itemDiscountAmount': explicitItemDiscount,
      'lineTotal': baseLineTotal - explicitItemDiscount,
      'customerPricingDetail': customerPricingDetail,
    };
  }).toList();
  final receiptItemDiscountTotal = receiptItems.fold<double>(
    0.0,
    (sum, item) =>
        sum + (((item['itemDiscountAmount'] as num?) ?? 0).toDouble()),
  );
  final receiptCartDiscountAmount = (discountAmount - receiptItemDiscountTotal)
      .clamp(0.0, discountAmount)
      .toDouble();
  final receiptSubtotal = receiptItems.fold<double>(
    0.0,
    (sum, item) => sum + (((item['lineTotal'] as num?) ?? 0).toDouble()),
  );

  String discountLabel() {
    if (receiptCartDiscountAmount <= 0) return '';
    if (discountType == 'percent') {
      return '${formatPercent(discountValue)}%';
    }
    if (discountType == 'fixed') {
      return 'Rs. ${discountValue.toStringAsFixed(2)}';
    }
    return '';
  }

  Widget receiptColumnHeader(String text, {bool alignRight = false}) {
    return Expanded(
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget receiptColumnValue(
    String text, {
    bool alignRight = false,
    Color? color,
  }) {
    return Expanded(
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          color: color ?? palette.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.soft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  return showPremiumDialog<String>(
    context: context,
    builder: (dialogContext) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: (isRefund ? palette.danger : palette.brand)
                                .withOpacity(palette.isDark ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isRefund
                                ? Icons.undo_rounded
                                : Icons.receipt_long_rounded,
                            color: isRefund ? palette.danger : palette.brand,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isRefund ? 'Refund Receipt' : 'Sale Receipt',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Food City POS',
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              buildInfoChip(
                                Icons.receipt_long_rounded,
                                'Transaction #$transactionId',
                              ),
                              buildInfoChip(
                                isRefund
                                    ? Icons.undo_outlined
                                    : Icons.point_of_sale_outlined,
                                isRefund ? 'Refund' : 'Sale',
                              ),
                              buildInfoChip(
                                Icons.person_outline_rounded,
                                cashier,
                              ),
                              if (hasCustomer)
                                buildInfoChip(
                                  Icons.badge_outlined,
                                  customerName,
                                ),
                              buildInfoChip(
                                Icons.schedule_outlined,
                                formatDateTime(createdAt),
                              ),
                              if (!isRefund)
                                buildInfoChip(
                                  isCreditSale
                                      ? Icons.account_balance_wallet_outlined
                                      : Icons.payments_outlined,
                                  paymentLabel(paymentMethod),
                                ),
                              if (isRefund && originalSaleId != null)
                                buildInfoChip(
                                  Icons.link_outlined,
                                  'Sale #$originalSaleId',
                                ),
                            ],
                          ),
                          if (hasCustomer) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: palette.soft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: palette.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_pin_circle_outlined,
                                    color: palette.brand,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      [
                                        'Customer: $customerName',
                                        if (customerCode.isNotEmpty)
                                          customerCode,
                                        if (customerPhone.isNotEmpty)
                                          customerPhone,
                                      ].join(' • '),
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isRefund && refundReason.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: palette.soft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: palette.border),
                              ),
                              child: Text(
                                'Reason: $refundReason',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (!isRefund && paymentMethod == 'cash') ...[
                            const SizedBox(height: 14),
                            Text(
                              'Amount Tendered: Rs. ${amountTendered.toStringAsFixed(2)}',
                              style: TextStyle(color: palette.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Change: Rs. ${changeAmount.toStringAsFixed(2)}',
                              style: TextStyle(color: palette.textSecondary),
                            ),
                          ],
                          if (!isRefund && paymentMethod == 'card') ...[
                            const SizedBox(height: 14),
                            Text(
                              'Amount Charged: Rs. ${total.toStringAsFixed(2)}',
                              style: TextStyle(color: palette.textSecondary),
                            ),
                          ],
                          if (isCreditSale) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFB65C,
                                ).withOpacity(palette.isDark ? 0.16 : 0.10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFB65C,
                                  ).withOpacity(0.28),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.account_balance_wallet_outlined,
                                        color: Color(0xFFFFB65C),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Customer Credit Details',
                                        style: TextStyle(
                                          color: palette.textPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Previous Balance: Rs. ${creditPreviousBalance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${isRefund ? 'This Refund' : 'This Bill'}: Rs. ${creditBillAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'New Balance: Rs. ${creditNewBalance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (creditLimit > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Credit Limit: Rs. ${creditLimit.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (creditApprovedBy.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Approved By: $creditApprovedBy',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (hasLoyalty) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: palette.brand.withValues(
                                  alpha: palette.isDark ? 0.14 : 0.08,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: palette.brand.withValues(alpha: 0.24),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.card_giftcard_outlined,
                                        color: palette.brand,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Loyalty Details',
                                        style: TextStyle(
                                          color: palette.textPrimary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (loyaltyPointsRedeemed != 0)
                                    Text(
                                      'Redeemed: ${loyaltyPointsRedeemed.abs()} point${loyaltyPointsRedeemed.abs() == 1 ? '' : 's'}'
                                      '${loyaltyRedeemedValue.abs() > 0.000001 ? ' (${loyaltyRedeemedValue.abs().toStringAsFixed(2)} value)' : ''}',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  if (loyaltyPointsEarned != 0) ...[
                                    if (loyaltyPointsRedeemed != 0)
                                      const SizedBox(height: 4),
                                    Text(
                                      '${isRefund ? 'Reversed' : 'Earned'}: ${loyaltyPointsEarned.abs()} point${loyaltyPointsEarned.abs() == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (!isRefund &&
                                      loyaltyEarnBaseAmount.abs() >
                                          0.000001) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Earn base: Rs. ${loyaltyEarnBaseAmount.abs().toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (loyaltyNote.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      loyaltyNote,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Divider(color: palette.border),
                          const SizedBox(height: 8),
                          ...receiptItems.map((item) {
                            final name = (item['name'] ?? 'Unknown').toString();
                            final barcode = (item['barcode'] ?? '').toString();
                            final qty = ((item['quantity'] as num?) ?? 0)
                                .toDouble();
                            final qtyLabel =
                                TransactionHistoryScreen._formatQuantity(qty);
                            final unitPrice = ((item['unitPrice'] as num?) ?? 0)
                                .toDouble();
                            final markedPrice =
                                ((item['markedPrice'] as num?) ?? unitPrice)
                                    .toDouble();
                            final baseLineTotal =
                                ((item['baseLineTotal'] as num?) ?? 0)
                                    .toDouble();
                            final itemDiscount =
                                ((item['itemDiscountAmount'] as num?) ?? 0)
                                    .toDouble();
                            final itemDiscountType =
                                (item['itemDiscountType'] ?? 'none').toString();
                            final itemDiscountValue =
                                ((item['itemDiscountValue'] as num?) ?? 0)
                                    .toDouble();
                            final finalLineTotal =
                                ((item['lineTotal'] as num?) ?? 0).toDouble();
                            final customerPricingDetail =
                                (item['customerPricingDetail'] ?? '')
                                    .toString()
                                    .trim();
                            final discountPercent = discountPercentLabel(
                              amount: itemDiscount,
                              base: baseLineTotal,
                              type: itemDiscountType,
                              value: itemDiscountValue,
                            );
                            final unitPriceText =
                                !isRefund &&
                                    itemDiscount > 0 &&
                                    discountPercent.isNotEmpty
                                ? 'Rs. ${unitPrice.toStringAsFixed(2)} (-$discountPercent%)'
                                : 'Rs. ${unitPrice.toStringAsFixed(2)}';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: palette.border),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                        if (barcode.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Barcode: $barcode',
                                            style: TextStyle(
                                              color: palette.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            receiptColumnHeader('Unit price'),
                                            receiptColumnHeader('Mark price'),
                                            receiptColumnHeader(
                                              'Qty',
                                              alignRight: true,
                                            ),
                                            receiptColumnHeader(
                                              'Total',
                                              alignRight: true,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            receiptColumnValue(
                                              unitPriceText,
                                              color:
                                                  !isRefund && itemDiscount > 0
                                                  ? palette.danger
                                                  : palette.textPrimary,
                                            ),
                                            receiptColumnValue(
                                              'Rs. ${markedPrice.toStringAsFixed(2)}',
                                            ),
                                            receiptColumnValue(
                                              qtyLabel,
                                              alignRight: true,
                                            ),
                                            receiptColumnValue(
                                              'Rs. ${finalLineTotal.toStringAsFixed(2)}',
                                              alignRight: true,
                                            ),
                                          ],
                                        ),
                                        if (customerPricingDetail
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.brand.withValues(
                                                alpha: palette.isDark
                                                    ? 0.16
                                                    : 0.09,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: palette.brand.withValues(
                                                  alpha: 0.24,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.local_offer_outlined,
                                                  color: palette.brand,
                                                  size: 15,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    customerPricingDetail,
                                                    style: TextStyle(
                                                      color:
                                                          palette.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 12,
                                                      height: 1.25,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          if (!isRefund) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Subtotal: Rs. ${receiptSubtotal.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (receiptCartDiscountAmount > 0) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Discount${discountLabel().isEmpty ? '' : ' (${discountLabel()})'}: -Rs. ${receiptCartDiscountAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: palette.danger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total: Rs. ${total.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: isRefund
                                    ? palette.danger
                                    : palette.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.pop(dialogContext, 'pdf'),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Save PDF'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.pop(dialogContext, 'reprint'),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Reprint'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (!isRefund)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, 'refund'),
                              child: const Text('Refund Items'),
                            ),
                          ),
                        if (!isRefund) const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _TxPalette {
  const _TxPalette({required this.isDark});

  final bool isDark;

  static _TxPalette of(BuildContext context) {
    return _TxPalette(isDark: Theme.of(context).brightness == Brightness.dark);
  }

  Color get background =>
      isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get backgroundAlt =>
      isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get surface =>
      isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get surfaceAlt =>
      isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get soft => isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get border =>
      isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get textPrimary =>
      isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get textSecondary =>
      isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get brand => const Color(0xFF2AAA8A);
  Color get brandSoft => brand.withOpacity(isDark ? 0.16 : 0.10);
  Color get accentBlue => const Color(0xFF4B8DFF);
  Color get success => const Color(0xFF1FCF9A);
  Color get danger => const Color(0xFFFF6B7A);
  Color get shadow => Colors.black.withOpacity(isDark ? 0.26 : 0.05);
}
