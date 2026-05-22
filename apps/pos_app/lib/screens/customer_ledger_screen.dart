import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/customer_credit_summary.dart';
import 'package:shared/models/customer_ledger_entry.dart';

import '../providers/auth_provider.dart';
import '../services/customer_credit_service.dart';
import '../services/database_helper.dart';
import '../services/permission_service.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/app_snackbar.dart';
import 'customer_payment_dialog.dart';
import 'customer_payment_receipt_dialog.dart';
import 'customer_credit_adjustment_dialog.dart';

class CustomerLedgerScreen extends StatefulWidget {
  const CustomerLedgerScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.initialSummary,
  });

  final int customerId;
  final String customerName;
  final CustomerCreditSummary? initialSummary;

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  CustomerCreditSummary? _summary;
  List<CustomerLedgerEntry> _entries = [];
  bool _isLoading = true;
  String _filter = 'all';

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  List<CustomerLedgerEntry> get _filteredEntries {
    if (_filter == 'all') return _entries;

    if (_filter == 'adjustments') {
      return _entries
          .where(
            (entry) =>
                entry.normalizedType == 'debit_adjustment' ||
                entry.normalizedType == 'credit_adjustment',
          )
          .toList();
    }

    return _entries.where((entry) => entry.normalizedType == _filter).toList();
  }

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final summary = await CustomerCreditService.instance.getCreditSummary(
        widget.customerId,
      );
      final entries = await CustomerCreditService.instance.getLedger(
        customerId: widget.customerId,
        newestFirst: true,
        includeVoided: true,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load customer ledger.',
        backgroundColor: _danger,
      );
    }
  }

  Future<void> _receivePayment() async {
    final allowed = await _requirePermission(
      permission: PosPermission.customerCreditReceivePayment,
      title: 'Receive Credit Payment Approval',
      description: 'Receive customer credit payment for ${widget.customerName}',
    );
    if (!allowed || !mounted) return;

    final saved = await showCustomerPaymentDialog(
      context: context,
      customerId: widget.customerId,
      customerName: widget.customerName,
      initialSummary: _summary,
      receivedBy:
          context.read<AuthProvider>().currentUser?.name.trim().isNotEmpty ==
              true
          ? context.read<AuthProvider>().currentUser!.name.trim()
          : 'Unknown',
    );

    if (!mounted || saved == null) return;
    if (saved.paymentId != null) {
      await showCustomerPaymentReceiptDialog(
        context: context,
        paymentId: saved.paymentId!,
        paymentJustSaved: true,
      );
    }
    if (!mounted) return;
    await _loadLedger();
  }

  Future<void> _openPaymentReceipt(CustomerLedgerEntry entry) async {
    final paymentId = entry.paymentId;
    if (paymentId == null || paymentId <= 0) return;

    await showCustomerPaymentReceiptDialog(
      context: context,
      paymentId: paymentId,
    );
  }

  Future<void> _postAdjustment() async {
    final allowed = await _requirePermission(
      permission: PosPermission.customerCreditAdjust,
      title: 'Credit Adjustment Approval',
      description: 'Credit adjustment for ${widget.customerName}',
    );
    if (!allowed || !mounted) return;

    final saved = await showCustomerCreditAdjustmentDialog(
      context: context,
      customerId: widget.customerId,
      customerName: widget.customerName,
      initialSummary: _summary,
    );

    if (!mounted || !saved) return;
    await _logSensitiveAction(
      actionType: 'credit_adjustment',
      description: 'Customer credit adjusted for ${widget.customerName}',
    );
    await _loadLedger();
  }

  Future<void> _voidPayment(CustomerLedgerEntry entry) async {
    final paymentId = entry.paymentId;
    if (paymentId == null || paymentId <= 0 || entry.isVoided) return;
    final allowed = await _requirePermission(
      permission: PosPermission.customerCreditVoidPayment,
      title: 'Void Credit Payment Approval',
      description: 'Void payment #$paymentId for ${widget.customerName}',
    );
    if (!allowed || !mounted) return;

    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Void Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This will void the customer payment and create a reversal ledger entry. The original payment will remain in history.',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Void reason',
                  hintText: 'Required',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  AppSnackBar.show(
                    dialogContext,
                    message: 'Void reason is required.',
                    backgroundColor: _danger,
                  );
                  return;
                }
                Navigator.pop(dialogContext, reason);
              },
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Void Payment'),
            ),
          ],
        );
      },
    );

    reasonController.dispose();

    if (reason == null || reason.trim().isEmpty || !mounted) return;

    try {
      await CustomerCreditService.instance.voidPayment(
        paymentId: paymentId,
        voidedBy:
            context.read<AuthProvider>().currentUser?.name.trim().isNotEmpty ==
                true
            ? context.read<AuthProvider>().currentUser!.name.trim()
            : 'Manager',
        reason: reason,
      );
      await _logSensitiveAction(
        actionType: 'payment_void',
        description:
            'Voided customer payment #$paymentId for ${widget.customerName}',
      );

      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: 'Payment voided and reversal entry added.',
        backgroundColor: _brand,
      );
      await _loadLedger();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      AppSnackBar.show(
        context,
        message: message.isEmpty ? 'Could not void payment.' : message,
        backgroundColor: _danger,
      );
    }
  }

  Future<bool> _requirePermission({
    required String permission,
    required String title,
    required String description,
  }) async {
    final auth = context.read<AuthProvider>();
    if (auth.can(permission)) return true;
    if (!PermissionService.requiresManagerApproval(
      auth.currentUser,
      permission,
    )) {
      AppSnackBar.show(
        context,
        message: 'You do not have permission for this action.',
        backgroundColor: _danger,
      );
      return false;
    }

    var approved = false;
    await AdminDialogs.showPinDialog(
      context,
      () {
        approved = true;
      },
      title: title,
      requesterUserId: auth.currentUser?.id,
      requesterUserName: auth.currentUser?.name,
      approvalDescription: description,
    );
    return approved;
  }

  Future<void> _logSensitiveAction({
    required String actionType,
    required String description,
  }) async {
    final auth = context.read<AuthProvider>();
    await DatabaseHelper.instance.logSensitiveAction(
      actorUserId: auth.currentUser?.id,
      actorName: auth.currentUser?.name,
      actionType: actionType,
      targetUserId: widget.customerId,
      targetUserName: widget.customerName,
      description: description,
    );
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Color _entryColor(CustomerLedgerEntry entry) {
    switch (entry.normalizedType) {
      case 'credit_sale':
        return _warning;
      case 'payment':
        return _brand;
      case 'refund':
      case 'credit_adjustment':
        return _blue;
      case 'debit_adjustment':
      case 'void_reversal':
        return _danger;
      default:
        return _textSecondary;
    }
  }

  Widget _summaryCard() {
    final summary = _summary ?? CustomerCreditSummary.empty(widget.customerId);
    final balanceColor = summary.currentBalance > 0
        ? _warning
        : summary.currentBalance < 0
        ? _blue
        : _brand;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _metric(
            label: 'Balance',
            value: _money(summary.currentBalance),
            icon: Icons.account_balance_wallet_rounded,
            color: balanceColor,
          ),
          const SizedBox(width: 12),
          _metric(
            label: 'Limit',
            value: _money(summary.creditLimit),
            icon: Icons.speed_rounded,
            color: _brand,
          ),
          const SizedBox(width: 12),
          _metric(
            label: summary.availableCredit < 0 ? 'Over Limit' : 'Available',
            value: _money(summary.availableCredit.abs()),
            icon: summary.availableCredit < 0
                ? Icons.warning_rounded
                : Icons.trending_up_rounded,
            color: summary.availableCredit < 0 ? _danger : _blue,
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _panelSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
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

  Widget _filterBar() {
    final filters = [
      ('all', 'All'),
      ('credit_sale', 'Credit Sales'),
      ('payment', 'Payments'),
      ('refund', 'Refunds'),
      ('adjustments', 'Adjustments'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((filter) {
        final selected = _filter == filter.$1;
        return ChoiceChip(
          label: Text(filter.$2),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _filter = filter.$1;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _ledgerActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(120, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        foregroundColor: _brand,
        side: BorderSide(color: _brand.withValues(alpha: 0.42)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Widget _entryCard(CustomerLedgerEntry entry) {
    final color = _entryColor(entry);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: entry.isVoided ? _danger.withValues(alpha: 0.30) : _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              entry.normalizedType == 'payment'
                  ? Icons.south_west_rounded
                  : entry.normalizedType == 'credit_sale'
                  ? Icons.north_east_rounded
                  : Icons.receipt_long_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      entry.typeLabel,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    if (entry.isVoided)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _danger.withValues(
                            alpha: _isDark ? 0.18 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Voided',
                          style: TextStyle(
                            color: _danger,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description?.trim().isNotEmpty == true
                      ? entry.description!.trim()
                      : _formatDate(entry.createdAt),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(entry.createdAt),
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (entry.normalizedType == 'payment' && entry.paymentId != null) ...[
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Payment receipt',
              onPressed: () => _openPaymentReceipt(entry),
              icon: const Icon(Icons.receipt_long_rounded),
              color: _brand,
            ),
            if (!entry.isVoided)
              IconButton(
                tooltip: 'Void payment',
                onPressed: () => _voidPayment(entry),
                icon: const Icon(Icons.undo_rounded),
                color: _danger,
              ),
            const SizedBox(width: 14),
          ] else ...[
            const SizedBox(width: 14),
          ],
          _amountRow(entry),
        ],
      ),
    );
  }

  Widget _amountRow(CustomerLedgerEntry entry) {
    return SizedBox(
      width: 410,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _amountItem('Debit', entry.debit, _warning),
          const SizedBox(width: 18),
          _amountItem('Credit', entry.credit, _brand),
          const SizedBox(width: 18),
          _amountItem('Balance', entry.balanceAfter, _textPrimary, emphasize: true),
        ],
      ),
    );
  }

  Widget _amountItem(
    String label,
    double amount,
    Color color, {
    bool emphasize = false,
  }) {
    return SizedBox(
      width: 125,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money(amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: emphasize ? 14 : 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: Text('${widget.customerName} Ledger'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadLedger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _summaryCard(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _filterBar()),
                  const SizedBox(width: 12),
                  _ledgerActionButton(
                    onPressed: _postAdjustment,
                    icon: Icons.tune_rounded,
                    label: 'Adjustment',
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _receivePayment,
                    icon: const Icon(Icons.payments_rounded),
                    label: const Text('Receive Payment'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : entries.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _border),
                          ),
                          child: Text(
                            'No ledger entries found.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _entryCard(entries[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
