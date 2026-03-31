import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/pos_feature_flags.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../widgets/admin_dialogs.dart';

class RefundTransactionScreen extends StatefulWidget {
  final int originalSaleId;

  const RefundTransactionScreen({
    super.key,
    required this.originalSaleId,
  });

  @override
  State<RefundTransactionScreen> createState() =>
      _RefundTransactionScreenState();
}

class _RefundTransactionScreenState extends State<RefundTransactionScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;

  Map<String, dynamic>? _saleSummary;
  List<Map<String, dynamic>> _refundableItems = [];
  final Map<String, int> _selectedQty = {};

  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRefundableData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadRefundableData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final summary = await DatabaseHelper.instance.getTransactionSummary(
        widget.originalSaleId,
      );
      final items = await DatabaseHelper.instance.getRefundableItemsForSale(
        widget.originalSaleId,
      );

      if (!mounted) return;

      setState(() {
        _saleSummary = summary;
        _refundableItems = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  String _formatSummaryDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }

  int _selectedFor(String barcode) => _selectedQty[barcode] ?? 0;

  void _increaseQty(String barcode, int refundableQty) {
    final current = _selectedFor(barcode);
    if (current >= refundableQty) return;

    setState(() {
      _selectedQty[barcode] = current + 1;
    });
  }

  void _decreaseQty(String barcode) {
    final current = _selectedFor(barcode);
    if (current <= 0) return;

    setState(() {
      final newQty = current - 1;
      if (newQty <= 0) {
        _selectedQty.remove(barcode);
      } else {
        _selectedQty[barcode] = newQty;
      }
    });
  }

  double get _refundTotal {
    double total = 0;

    for (final item in _refundableItems) {
      final barcode = (item['barcode'] ?? '').toString();
      final unitPrice = ((item['unit_price'] as num?) ?? 0).toDouble();
      final qty = _selectedFor(barcode);

      total += unitPrice * qty;
    }

    return total;
  }

  List<Map<String, dynamic>> get _selectedRefundItems {
    return _refundableItems
        .map((item) {
          final barcode = (item['barcode'] ?? '').toString();
          final qty = _selectedFor(barcode);

          if (qty <= 0) return null;

          return {
            'barcode': barcode,
            'product_name': (item['product_name'] ?? 'Unknown').toString(),
            'unit_price': ((item['unit_price'] as num?) ?? 0).toDouble(),
            'quantity': qty,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  String _buildApprovalDescription({
    required String requesterName,
    required int itemCount,
    required double refundTotal,
    required String refundReason,
  }) {
    final trimmedReason = refundReason.trim();
    final safeReason =
        trimmedReason.isEmpty ? 'No reason provided' : trimmedReason;

    return 'Approved linked refund for sale #${widget.originalSaleId} '
        'requested by $requesterName '
        '($itemCount ${itemCount == 1 ? 'item' : 'items'}, '
        'Rs. ${refundTotal.toStringAsFixed(2)}). '
        'Reason: $safeReason';
  }

  Future<void> _processRefund() async {
    if (_isProcessing) return;

    final selectedItems = _selectedRefundItems;
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one item to refund.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final refundReason = _reasonController.text.trim();
    if (refundReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refund reason is required.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (PosFeatureFlags.enableShiftManagement) {
      final cashierName =
          context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
      final openShift =
          await DatabaseHelper.instance.getOpenShiftForCashier(cashierName);

      if (openShift == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open a shift before processing refunds.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final auth = context.read<AuthProvider>();
    final requester = auth.currentUser;
    final requesterName = requester?.name ?? 'Unknown';

    final approved = await AdminDialogs.showPinDialog(
      context,
      () => _processRefundAfterApproval(selectedItems),
      title: 'Approval Required',
      message:
          'Enter an active manager or full-access PIN to approve this refund.',
      requesterUserId: requester?.id,
      requesterUserName: requesterName,
      approvalDescription: _buildApprovalDescription(
        requesterName: requesterName,
        itemCount: selectedItems.length,
        refundTotal: _refundTotal,
        refundReason: refundReason,
      ),
    );

    if (!approved || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Refund approved by manager.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _processRefundAfterApproval(
    List<Map<String, dynamic>> selectedItems,
  ) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final cashierName =
          context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

      final refundSaleId = await DatabaseHelper.instance.processRefundFromSale(
        originalSaleId: widget.originalSaleId,
        refundItems: selectedItems,
        cashierName: cashierName,
        refundReason: _reasonController.text.trim(),
      );

      await SyncService().syncNow();
      await SyncService().refreshProductsFromBackend();

      if (!mounted) return;

      Navigator.pop(context, refundSaleId);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    double valueFontSize = 18,
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
            color: Colors.black.withValues(alpha: 0.04),
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
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
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
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: valueFontSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfoCard(String title, String value) {
    return Container(
      width: 150,
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

  Widget _buildQtyButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFF3F6FB) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? const Color(0xFFDCE5F0) : Colors.grey.shade200,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.blue.shade800 : Colors.grey.shade400,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildRefundItemCard(Map<String, dynamic> item) {
    final barcode = (item['barcode'] ?? '').toString();
    final name = (item['product_name'] ?? 'Unknown').toString();
    final unitPrice = ((item['unit_price'] as num?) ?? 0).toDouble();
    final originalQty = (item['original_quantity'] as num?)?.toInt() ?? 0;
    final refundedQty = (item['refunded_quantity'] as num?)?.toInt() ?? 0;
    final refundableQty = (item['refundable_quantity'] as num?)?.toInt() ?? 0;
    final selectedQty = _selectedFor(barcode);
    final refundAmount = unitPrice * selectedQty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Barcode: $barcode',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildMiniInfoCard(
                      'Unit Price',
                      'Rs. ${unitPrice.toStringAsFixed(2)}',
                    ),
                    _buildMiniInfoCard('Sold', originalQty.toString()),
                    _buildMiniInfoCard('Refunded', refundedQty.toString()),
                    _buildMiniInfoCard('Remaining', refundableQty.toString()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    'Refund: Rs. ${refundAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildQtyButton(
                      icon: Icons.remove,
                      onTap: selectedQty > 0 ? () => _decreaseQty(barcode) : null,
                    ),
                    Container(
                      width: 56,
                      alignment: Alignment.center,
                      child: Text(
                        '$selectedQty',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _buildQtyButton(
                      icon: Icons.add,
                      onTap: refundableQty > selectedQty
                          ? () => _increaseQty(barcode, refundableQty)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(Map<String, dynamic> summary) {
    final cashierName = (summary['cashier_name'] ?? 'Unknown').toString();
    final dateText =
        _formatSummaryDateTime((summary['created_at'] ?? '').toString());
    final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();

    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildSummaryCard(
              title: 'Original Sale',
              value: '#${summary['id']}',
              icon: Icons.receipt_long_outlined,
              accent: Colors.blue,
            ),
            _buildSummaryCard(
              title: 'Cashier',
              value: cashierName,
              icon: Icons.person_outline,
              accent: Colors.deepPurple,
            ),
            _buildSummaryCard(
              title: 'Date / Time',
              value: dateText,
              valueFontSize: 16,
              icon: Icons.schedule_outlined,
              accent: Colors.green,
            ),
            _buildSummaryCard(
              title: 'Sale Total',
              value: 'Rs. ${total.toStringAsFixed(2)}',
              icon: Icons.payments_outlined,
              accent: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Select the quantities to refund from this sale. Remaining quantities are limited by previous linked refunds.',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Items (${_refundableItems.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomPanel(bool hasRefundableQty) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _reasonController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Refund Reason',
                hintText: 'Enter reason for refund',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.red.shade400),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Selected Items: ${_selectedRefundItems.length}',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Refund Total: Rs. ${_refundTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (!hasRefundableQty || _isProcessing)
                    ? null
                    : _processRefund,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'PROCESS LINKED REFUND',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(child: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _saleSummary;
    final hasRefundableQty = _refundableItems.any(
      (item) => ((item['refundable_quantity'] as num?)?.toInt() ?? 0) > 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Refund Items'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : summary == null
              ? _buildEmptyState('Transaction not found')
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildSummaryHeader(summary),
                          const SizedBox(height: 18),
                          if (_refundableItems.isEmpty)
                            _buildEmptyState('No items found for this sale')
                          else
                            ..._refundableItems.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildRefundItemCard(item),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _buildBottomPanel(hasRefundableQty),
                  ],
                ),
    );
  }
}
