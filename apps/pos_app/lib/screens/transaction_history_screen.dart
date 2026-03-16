import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import 'refund_transaction_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();

  static Future<void> showReceiptDialogForTransaction(
    BuildContext context,
    int saleId,
  ) async {
    final summary = await DatabaseHelper.instance.getTransactionSummary(saleId);
    final items = await DatabaseHelper.instance.getTransactionItems(saleId);

    if (!context.mounted) return;

    if (summary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final action = await showTransactionReceiptDialog(
      context,
      summary: summary,
      items: items,
    );

    if (!context.mounted) return;

    final type =
        (summary['transaction_type'] ?? 'sale').toString().toLowerCase();

    if (action == 'refund' && type == 'sale') {
      final refundSaleId = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (context) => RefundTransactionScreen(
            originalSaleId: saleId,
          ),
        ),
      );

      if (!context.mounted) return;

      if (refundSaleId != null) {
        await showReceiptDialogForTransaction(context, refundSaleId);
      }
    }
  }
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _isLoading = true;
  String _filter = 'all';
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
    });

    final type = _filter == 'all' ? null : _filter;

    final transactions = await DatabaseHelper.instance.getRecentTransactions(
      transactionType: type,
      limit: 100,
    );

    if (!mounted) return;

    setState(() {
      _transactions = transactions;
      _isLoading = false;
    });
  }

  Color _typeColor(String type) {
    return type == 'refund' ? Colors.red : Colors.green;
  }

  String _typeLabel(String type) {
    return type == 'refund' ? 'Refund' : 'Sale';
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

  String _paymentLabel(String? method) {
    switch ((method ?? '').toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'refund':
        return 'Refund';
      default:
        return 'N/A';
    }
  }

  Widget _buildFilterChip(String value, String label) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.grey[100],
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildFilterChip('all', 'All'),
                _buildFilterChip('sale', 'Sales'),
                _buildFilterChip('refund', 'Refunds'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                    ? const Center(
                        child: Text('No transactions found'),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTransactions,
                        child: ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final tx = _transactions[index];
                            final type =
                                (tx['transaction_type'] ?? 'sale').toString();
                            final color = _typeColor(type);
                            final total =
                                ((tx['total_amount'] as num?) ?? 0).toDouble();
                            final totalAbs = total.abs();
                            final id = tx['id'];
                            final cashier =
                                (tx['cashier_name'] ?? 'Unknown').toString();
                            final itemQty =
                                (tx['item_quantity_total'] as num?)?.toInt() ??
                                    0;
                            final createdAt =
                                (tx['created_at'] ?? '').toString();
                            final originalSaleId = tx['original_sale_id'];
                            final paymentMethod =
                                (tx['payment_method'] ?? '').toString();
                            final discountAmount =
                                ((tx['discount_amount'] as num?) ?? 0)
                                    .toDouble()
                                    .abs();

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(14),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Transaction #$id',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _typeLabel(type),
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Cashier: $cashier'),
                                      const SizedBox(height: 4),
                                      Text('Items: $itemQty'),
                                      const SizedBox(height: 4),
                                      if (type == 'sale')
                                        Text(
                                          'Payment: ${_paymentLabel(paymentMethod)}',
                                        ),
                                      if (type == 'sale' && discountAmount > 0)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Discount: Rs. ${discountAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      if (type == 'refund' &&
                                          originalSaleId != null) ...[
                                        const SizedBox(height: 4),
                                        Text('Refund of Sale #$originalSaleId'),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        'Time: ${_formatDateTime(createdAt)}',
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Total: Rs. ${totalAbs.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () async {
                                  await TransactionHistoryScreen
                                      .showReceiptDialogForTransaction(
                                    context,
                                    id as int,
                                  );
                                  if (mounted) {
                                    _loadTransactions();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
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
      case 'refund':
        return 'Refund';
      default:
        return 'N/A';
    }
  }

  final transactionType =
      (summary['transaction_type'] ?? 'sale').toString().toLowerCase();
  final isRefund = transactionType == 'refund';
  final subtotal =
      ((summary['subtotal_amount'] as num?) ?? 0).toDouble().abs();
  final discountType = (summary['discount_type'] ?? 'none').toString();
  final discountValue =
      ((summary['discount_value'] as num?) ?? 0).toDouble();
  final discountAmount =
      ((summary['discount_amount'] as num?) ?? 0).toDouble().abs();
  final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();
  final cashier = (summary['cashier_name'] ?? 'Unknown').toString();
  final createdAt = (summary['created_at'] ?? '').toString();
  final transactionId = summary['id'];
  final originalSaleId = summary['original_sale_id'];
  final refundReason = (summary['refund_reason'] ?? '').toString();
  final paymentMethod = (summary['payment_method'] ?? '').toString();
  final amountTendered =
      ((summary['amount_tendered'] as num?) ?? 0).toDouble();
  final changeAmount = ((summary['change_amount'] as num?) ?? 0).toDouble();

  String discountLabel() {
    if (discountAmount <= 0) return '';
    if (discountType == 'percent') {
      return '${discountValue.toStringAsFixed(discountValue % 1 == 0 ? 0 : 2)}%';
    }
    if (discountType == 'fixed') {
      return 'Rs. ${discountValue.toStringAsFixed(2)}';
    }
    return '';
  }

  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(isRefund ? 'Refund Receipt' : 'Sale Receipt'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Food City POS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text('Transaction #: $transactionId'),
                Text('Type: ${isRefund ? 'Refund' : 'Sale'}'),
                Text('Cashier: $cashier'),
                Text('Date/Time: ${formatDateTime(createdAt)}'),
                if (!isRefund) ...[
                  const SizedBox(height: 4),
                  Text('Payment Method: ${paymentLabel(paymentMethod)}'),
                  if (paymentMethod == 'cash') ...[
                    const SizedBox(height: 4),
                    Text(
                      'Amount Tendered: Rs. ${amountTendered.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Change: Rs. ${changeAmount.toStringAsFixed(2)}',
                    ),
                  ],
                  if (paymentMethod == 'card') ...[
                    const SizedBox(height: 4),
                    Text(
                      'Amount Charged: Rs. ${total.toStringAsFixed(2)}',
                    ),
                  ],
                ],
                if (isRefund && originalSaleId != null) ...[
                  const SizedBox(height: 4),
                  Text('Refund of Sale #: $originalSaleId'),
                ],
                if (isRefund && refundReason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Reason: $refundReason'),
                ],
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 6),
                ...items.map((item) {
                  final name = (item['product_name'] ?? 'Unknown').toString();
                  final barcode = (item['barcode'] ?? '').toString();
                  final qty = (item['quantity'] as num?)?.toInt() ?? 0;
                  final unitPrice =
                      ((item['unit_price'] as num?) ?? 0).toDouble();
                  final baseLineTotal =
                      ((item['base_line_total'] as num?) ?? 0).toDouble();
                  final itemDiscount =
                      ((item['item_discount_amount'] as num?) ?? 0).toDouble();
                  final finalLineTotal =
                      ((item['line_total'] as num?) ?? 0).toDouble().abs();

                  final shownLineTotal = isRefund
                      ? finalLineTotal
                      : (baseLineTotal > 0 ? baseLineTotal : finalLineTotal);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Barcode: $barcode',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Qty: $qty × Rs. ${unitPrice.toStringAsFixed(2)}'),
                        if (!isRefund && itemDiscount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Line Discount: Rs. ${itemDiscount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Rs. ${shownLineTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                if (!isRefund) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Subtotal: Rs. ${subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  if (discountAmount > 0) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Discount${discountLabel().isEmpty ? '' : ' (${discountLabel()})'}: -Rs. ${discountAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
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
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isRefund ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isRefund)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'refund'),
              child: const Text('Refund Items'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}