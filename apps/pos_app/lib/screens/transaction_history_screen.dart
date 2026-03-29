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
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  String _filter = 'all';
  String _searchQuery = '';
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
      return id.contains(q) ||
          cashier.contains(q) ||
          payment.contains(q) ||
          type.contains(q) ||
          refundReason.contains(q);
    }).toList();
  }

  int get _saleCount => _transactions
      .where(
        (tx) => (tx['transaction_type'] ?? 'sale').toString().toLowerCase() == 'sale',
      )
      .length;

  int get _refundCount => _transactions
      .where(
        (tx) => (tx['transaction_type'] ?? 'sale').toString().toLowerCase() == 'refund',
      )
      .length;

  double get _salesTotal => _transactions
      .where(
        (tx) => (tx['transaction_type'] ?? 'sale').toString().toLowerCase() == 'sale',
      )
      .fold<double>(
        0,
        (sum, tx) => sum + (((tx['total_amount'] as num?) ?? 0).toDouble().abs()),
      );

  double get _refundTotal => _transactions
      .where(
        (tx) => (tx['transaction_type'] ?? 'sale').toString().toLowerCase() == 'refund',
      )
      .fold<double>(
        0,
        (sum, tx) => sum + (((tx['total_amount'] as num?) ?? 0).toDouble().abs()),
      );

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
      selectedColor: Colors.blue.shade100,
      labelStyle: TextStyle(
        color: selected ? Colors.blue.shade800 : Colors.grey.shade800,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected ? Colors.blue.shade200 : Colors.grey.shade300,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by transaction, cashier, payment, or type',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.blue.shade700),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFD),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _isRefreshing ? null : _refresh,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.refresh,
                              size: 18,
                              color: Colors.blue.shade700,
                            ),
                      const SizedBox(width: 8),
                      const Text(
                        'Refresh',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildFilterChip('all', 'All'),
              _buildFilterChip('sale', 'Sales'),
              _buildFilterChip('refund', 'Refunds'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type) {
    final color = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          color: type == 'refund' ? Colors.red.shade700 : Colors.green.shade700,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildMiniInfoCard(String title, String value) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final type = (tx['transaction_type'] ?? 'sale').toString().toLowerCase();
    final color = _typeColor(type);
    final total = ((tx['total_amount'] as num?) ?? 0).toDouble().abs();
    final id = tx['id'];
    final cashier = (tx['cashier_name'] ?? 'Unknown').toString();
    final itemQty = (tx['item_quantity_total'] as num?)?.toInt() ?? 0;
    final createdAt = (tx['created_at'] ?? '').toString();
    final originalSaleId = tx['original_sale_id'];
    final paymentMethod = (tx['payment_method'] ?? '').toString();
    final discountAmount =
        ((tx['discount_amount'] as num?) ?? 0).toDouble().abs();

    return InkWell(
      onTap: () async {
        await TransactionHistoryScreen.showReceiptDialogForTransaction(
          context,
          id as int,
        );
        if (mounted) {
          _loadTransactions();
        }
      },
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _buildTypeChip(type),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    cashier,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildMiniInfoCard('Items', itemQty.toString()),
                      _buildMiniInfoCard(
                        'Payment',
                        type == 'sale'
                            ? _paymentLabel(paymentMethod)
                            : 'Refund',
                      ),
                      _buildMiniInfoCard('Time', _formatDateTime(createdAt)),
                      if (type == 'sale' && discountAmount > 0)
                        _buildMiniInfoCard(
                          'Discount',
                          'Rs. ${discountAmount.toStringAsFixed(2)}',
                        ),
                      if (type == 'refund' && originalSaleId != null)
                        _buildMiniInfoCard(
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
                    color: type == 'refund'
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to view receipt',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          _searchQuery.trim().isEmpty
              ? 'No transactions found.'
              : 'No transactions match the current search.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = _visibleTransactions;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh transactions',
            onPressed: _isRefreshing ? null : _refresh,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildSummaryCard(
                      title: 'Transactions',
                      value: _transactions.length.toString(),
                      icon: Icons.receipt_long_outlined,
                      accent: Colors.blue,
                    ),
                    _buildSummaryCard(
                      title: 'Sales',
                      value: _saleCount.toString(),
                      icon: Icons.point_of_sale_outlined,
                      accent: Colors.green,
                    ),
                    _buildSummaryCard(
                      title: 'Refunds',
                      value: _refundCount.toString(),
                      icon: Icons.undo_outlined,
                      accent: Colors.red,
                    ),
                    _buildSummaryCard(
                      title: 'Net Sales',
                      value:
                          'Rs. ${(_salesTotal - _refundTotal).toStringAsFixed(2)}',
                      icon: Icons.payments_outlined,
                      accent: Colors.deepPurple,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildToolbarCard(),
                const SizedBox(height: 18),
                Text(
                  'Transactions (${visibleTransactions.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (visibleTransactions.isEmpty)
                  _buildEmptyState()
                else
                  ...visibleTransactions.map(
                    (tx) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildTransactionCard(tx),
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

  Widget buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(isRefund ? 'Refund Receipt' : 'Sale Receipt'),
        content: SizedBox(
          width: 620,
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
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    buildInfoChip(Icons.receipt_long, 'Transaction #$transactionId'),
                    buildInfoChip(
                      isRefund ? Icons.undo_outlined : Icons.point_of_sale_outlined,
                      isRefund ? 'Refund' : 'Sale',
                    ),
                    buildInfoChip(Icons.person_outline, cashier),
                    buildInfoChip(Icons.schedule_outlined, formatDateTime(createdAt)),
                    if (!isRefund)
                      buildInfoChip(Icons.payments_outlined, paymentLabel(paymentMethod)),
                    if (isRefund && originalSaleId != null)
                      buildInfoChip(Icons.link_outlined, 'Sale #$originalSaleId'),
                  ],
                ),
                if (isRefund && refundReason.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Reason: $refundReason',
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (!isRefund && paymentMethod == 'cash') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Amount Tendered: Rs. ${amountTendered.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Change: Rs. ${changeAmount.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ],
                if (!isRefund && paymentMethod == 'card') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Amount Charged: Rs. ${total.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
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
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Barcode: $barcode',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            buildInfoChip(
                              Icons.shopping_basket_outlined,
                              'Qty: $qty',
                            ),
                            buildInfoChip(
                              Icons.sell_outlined,
                              'Unit: Rs. ${unitPrice.toStringAsFixed(2)}',
                            ),
                            if (!isRefund && itemDiscount > 0)
                              buildInfoChip(
                                Icons.discount_outlined,
                                'Discount: Rs. ${itemDiscount.toStringAsFixed(2)}',
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Rs. ${shownLineTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
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
