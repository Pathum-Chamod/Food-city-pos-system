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
      final next = current - 1;
      if (next <= 0) {
        _selectedQty.remove(barcode);
      } else {
        _selectedQty[barcode] = next;
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

  int get _selectedLineCount => _selectedRefundItems.length;

  int get _selectedUnitsCount =>
      _selectedQty.values.fold<int>(0, (sum, qty) => sum + qty);

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

  Widget _buildHeader(_RefundPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [palette.surfaceAlt, palette.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildCircleButton(
            palette: palette,
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Linked Refund Workspace',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review the original sale, choose refundable quantities, then submit for approval.',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _buildHeaderPill(
            palette: palette,
            icon: Icons.receipt_long_rounded,
            label: 'Sale #${widget.originalSaleId}',
            tone: palette.danger,
            soft: palette.dangerSoft,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRail(_RefundPalette palette) {
    Widget step({
      required int number,
      required String title,
      required String subtitle,
      required Color tone,
      required bool active,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? tone.withOpacity(palette.isDark ? 0.18 : 0.10) : palette.soft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? tone.withOpacity(0.40) : palette.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: active ? tone.withOpacity(palette.isDark ? 0.22 : 0.14) : palette.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: active ? tone.withOpacity(0.30) : palette.border),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: active ? tone : palette.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        step(
          number: 1,
          title: 'Review sale',
          subtitle: 'Original bill context',
          tone: palette.accentBlue,
          active: true,
        ),
        const SizedBox(width: 12),
        step(
          number: 2,
          title: 'Select items',
          subtitle: 'Choose refund quantities',
          tone: palette.brand,
          active: true,
        ),
        const SizedBox(width: 12),
        step(
          number: 3,
          title: 'Approval',
          subtitle: 'Reason and manager PIN',
          tone: palette.danger,
          active: _selectedLineCount > 0,
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required _RefundPalette palette,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: palette.soft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Icon(icon, color: palette.textPrimary),
        ),
      ),
    );
  }

  Widget _buildHeaderPill({
    required _RefundPalette palette,
    required IconData icon,
    required String label,
    required Color tone,
    required Color soft,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleOverview(_RefundPalette palette, Map<String, dynamic> summary) {
    final cashierName = (summary['cashier_name'] ?? 'Unknown').toString();
    final dateText =
        _formatSummaryDateTime((summary['created_at'] ?? '').toString());
    final total = ((summary['total_amount'] as num?) ?? 0).toDouble().abs();

    Widget tile({
      required String title,
      required String value,
      required IconData icon,
      required Color tone,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tone.withOpacity(palette.isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tone, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(
          title: 'Original Sale',
          value: '#${summary['id']}',
          icon: Icons.receipt_long_outlined,
          tone: palette.accentBlue,
        ),
        const SizedBox(width: 12),
        tile(
          title: 'Cashier',
          value: cashierName,
          icon: Icons.person_outline_rounded,
          tone: palette.brand,
        ),
        const SizedBox(width: 12),
        tile(
          title: 'Date / Time',
          value: dateText,
          icon: Icons.schedule_rounded,
          tone: palette.success,
        ),
        const SizedBox(width: 12),
        tile(
          title: 'Sale Total',
          value: 'Rs. ${total.toStringAsFixed(2)}',
          icon: Icons.payments_outlined,
          tone: palette.warning,
        ),
      ],
    );
  }

  Widget _buildItemsSection(_RefundPalette palette) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refundable Items',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose the quantities to refund. Remaining quantity already respects earlier linked refunds.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildHeaderPill(
                palette: palette,
                icon: Icons.widgets_outlined,
                label: '${_refundableItems.length} item${_refundableItems.length == 1 ? '' : 's'}',
                tone: palette.accentBlue,
                soft: palette.accentBlueSoft,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_refundableItems.isEmpty)
            _buildEmptyStateInline(palette, 'No items found for this sale')
          else
            ..._refundableItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildRefundItemCard(palette, item),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRefundItemCard(_RefundPalette palette, Map<String, dynamic> item) {
    final barcode = (item['barcode'] ?? '').toString();
    final name = (item['product_name'] ?? 'Unknown').toString();
    final unitPrice = ((item['unit_price'] as num?) ?? 0).toDouble();
    final originalQty = (item['original_quantity'] as num?)?.toInt() ?? 0;
    final refundedQty = (item['refunded_quantity'] as num?)?.toInt() ?? 0;
    final refundableQty = (item['refundable_quantity'] as num?)?.toInt() ?? 0;
    final selectedQty = _selectedFor(barcode);
    final refundAmount = unitPrice * selectedQty;
    final hasSelection = selectedQty > 0;

    Widget statChip(String title, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.soft,
            borderRadius: BorderRadius.circular(14),
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
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasSelection ? palette.brandSoftStrong : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasSelection ? palette.brand.withOpacity(0.30) : palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withOpacity(hasSelection ? 0.9 : 0.7),
            blurRadius: hasSelection ? 18 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasSelection
                      ? palette.brand.withOpacity(palette.isDark ? 0.18 : 0.12)
                      : palette.soft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasSelection
                        ? palette.brand.withOpacity(0.24)
                        : palette.border,
                  ),
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: hasSelection ? palette.brand : palette.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Barcode: $barcode',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: palette.dangerSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.danger.withOpacity(0.20)),
                ),
                child: Text(
                  'Rs. ${refundAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: palette.danger,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    _buildQtyButton(
                      palette: palette,
                      icon: Icons.remove_rounded,
                      onTap: selectedQty > 0 ? () => _decreaseQty(barcode) : null,
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '$selectedQty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    _buildQtyButton(
                      palette: palette,
                      icon: Icons.add_rounded,
                      onTap: refundableQty > selectedQty
                          ? () => _increaseQty(barcode, refundableQty)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              statChip('Unit Price', 'Rs. ${unitPrice.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              statChip('Sold', '$originalQty'),
              const SizedBox(width: 8),
              statChip('Refunded', '$refundedQty'),
              const SizedBox(width: 8),
              statChip('Remaining', '$refundableQty'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQtyButton({
    required _RefundPalette palette,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: enabled ? palette.soft : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? palette.accentBlue : palette.textSecondary.withOpacity(0.45),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(_RefundPalette palette, bool hasRefundableQty) {
    final summary = _saleSummary;
    final total = ((summary?['total_amount'] as num?) ?? 0).toDouble().abs();
    final previewItems = _selectedRefundItems.take(4).toList();

    Widget stat(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.dangerSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.assignment_return_rounded, color: palette.danger),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refund Summary',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Complete the reason and approval to finalize this linked refund.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.soft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                stat('Original Sale', 'Rs. ${total.toStringAsFixed(2)}'),
                stat('Selected Lines', '$_selectedLineCount'),
                stat('Selected Units', '$_selectedUnitsCount'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: palette.dangerSoft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.danger.withOpacity(0.24)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Refund Total',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Rs. ${_refundTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: palette.danger,
                                fontWeight: FontWeight.w900,
                                fontSize: 26,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: palette.danger.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.undo_rounded, color: palette.danger),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Refund reason',
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Explain why this linked refund is being processed...',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Selected items preview',
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          if (previewItems.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.soft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                'No items selected yet.',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...previewItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.soft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (item['product_name'] ?? 'Item').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item['quantity']} × Rs. ${(((item['unit_price'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Rs. ${((((item['unit_price'] as num?) ?? 0).toDouble()) * (((item['quantity'] as num?) ?? 0).toInt())).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: palette.danger,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_selectedLineCount > previewItems.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${_selectedLineCount - previewItems.length} more selected',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!hasRefundableQty || _isProcessing) ? null : _processRefund,
              icon: Icon(
                _isProcessing ? Icons.sync_rounded : Icons.lock_open_rounded,
                size: 18,
              ),
              label: Text(_isProcessing ? 'Processing...' : 'Process Linked Refund'),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.danger,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateInline(_RefundPalette palette, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: palette.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStatePage(_RefundPalette palette, String text) {
    return Center(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: palette.soft,
                shape: BoxShape.circle,
                border: Border.all(color: palette.border),
              ),
              child: Icon(Icons.inventory_2_outlined, color: palette.textSecondary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _RefundPalette.of(context);
    final summary = _saleSummary;
    final hasRefundableQty = _refundableItems.any(
      (item) => ((item['refundable_quantity'] as num?)?.toInt() ?? 0) > 0,
    );

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
              : summary == null
                  ? _buildEmptyStatePage(palette, 'Transaction not found')
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildHeader(palette),
                          const SizedBox(height: 14),
                          _buildSaleOverview(palette, summary),
                          const SizedBox(height: 16),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 9,
                                  child: SingleChildScrollView(
                                    child: _buildItemsSection(palette),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 360,
                                  child: _buildSidebar(palette, hasRefundableQty),
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
  }
}

class _RefundPalette {
  const _RefundPalette({required this.isDark});

  final bool isDark;

  static _RefundPalette of(BuildContext context) {
    return _RefundPalette(
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  Color get background =>
      isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get backgroundAlt =>
      isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get surface =>
      isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get surfaceAlt =>
      isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get soft =>
      isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get border =>
      isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get textPrimary =>
      isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get textSecondary =>
      isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get brand => const Color(0xFF2AAA8A);
  Color get brandSoftStrong => brand.withOpacity(isDark ? 0.10 : 0.06);
  Color get brandSoft => brand.withOpacity(isDark ? 0.16 : 0.10);
  Color get accentBlue => const Color(0xFF4B8DFF);
  Color get accentBlueSoft => accentBlue.withOpacity(isDark ? 0.16 : 0.10);
  Color get success => const Color(0xFF1FCF9A);
  Color get warning => const Color(0xFFFFB65C);
  Color get danger => const Color(0xFFFF6B7A);
  Color get dangerSoft => danger.withOpacity(isDark ? 0.16 : 0.10);
  Color get shadow => Colors.black.withOpacity(isDark ? 0.26 : 0.05);
}
