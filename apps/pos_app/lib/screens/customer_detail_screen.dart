import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/customer_category.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/customer_credit_summary.dart';
import 'package:shared/models/loyalty_settings.dart';
import 'package:shared/models/pricing_scheme.dart';

import '../providers/auth_provider.dart';
import '../services/customer_credit_service.dart';
import '../services/customer_pricing_service.dart';
import '../services/customer_service.dart';
import '../services/database_helper.dart';
import '../services/loyalty_service.dart';
import '../services/permission_service.dart';
import '../services/pricing_scheme_service.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/app_snackbar.dart';
import 'customer_category_assignment_dialog.dart';
import 'customer_credit_settings_dialog.dart';
import 'customer_form_dialog.dart';
import 'customer_ledger_screen.dart';
import 'customer_loyalty_ledger_screen.dart';
import 'customer_product_prices_screen.dart';
import 'customer_payment_dialog.dart';
import 'customer_payment_receipt_dialog.dart';
import 'transaction_history_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer? _customer;
  CustomerCreditSummary? _creditSummary;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _history = [];
  List<CustomerCategory> _categories = [];
  List<PricingScheme> _schemes = [];
  LoyaltySettings? _loyaltySettings;
  int _activeCustomerRuleCount = 0;
  bool _isLoading = true;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _success = Color(0xFF1FCF9A);

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

  @override
  void initState() {
    super.initState();
    _loadCustomer();
  }

  Future<void> _loadCustomer() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = CustomerService.instance;
      final customer = await service.getCustomerById(widget.customerId);
      final summary = await service.getCustomerSummary(widget.customerId);
      final history = await service.getCustomerPurchaseHistory(
        widget.customerId,
      );
      final creditSummary = await CustomerCreditService.instance
          .getCreditSummary(widget.customerId);
      final activeCustomerRuleCount = await CustomerPricingService.instance
          .countRulesForCustomer(widget.customerId);
      final categories = await PricingSchemeService.instance
          .getCustomerCategories(activeOnly: false);
      final schemes = await PricingSchemeService.instance.getPricingSchemes(
        activeOnly: false,
      );
      final loyaltySettings = await LoyaltyService.instance.getSettings();

      if (!mounted) return;
      setState(() {
        _customer = customer;
        _summary = summary;
        _history = history;
        _creditSummary = creditSummary;
        _categories = categories;
        _schemes = schemes;
        _loyaltySettings = loyaltySettings;
        _activeCustomerRuleCount = activeCustomerRuleCount;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _customer = null;
        _summary = {};
        _history = [];
        _creditSummary = null;
        _categories = [];
        _schemes = [];
        _loyaltySettings = null;
        _activeCustomerRuleCount = 0;
        _isLoading = false;
      });
      _showMessage('Could not load customer details.', color: _danger);
    }
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
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
      _showMessage(
        'You do not have permission for this action.',
        color: _danger,
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
      message: 'Enter an active manager or full-access PIN to continue.',
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
      targetUserId: _customer?.id,
      targetUserName: _customer?.displayName,
      description: description,
    );
  }

  Future<void> _editCustomer() async {
    final customer = _customer;
    if (customer == null) return;

    final updated = await showCustomerFormDialog(
      context: context,
      customer: customer,
    );

    if (!mounted || updated == null) return;
    _showMessage('Customer updated.', color: _success);
    await _loadCustomer();
  }

  Future<void> _openCreditSettings() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;
    final allowed = await _requirePermission(
      permission: PosPermission.customerCreditManage,
      title: 'Credit Settings Approval',
      description: 'Credit settings opened for ${customer.displayName}',
    );
    if (!allowed || !mounted) return;

    final saved = await showCustomerCreditSettingsDialog(
      context: context,
      customerId: customer.id!,
      customerName: customer.displayName,
      initialSummary: _creditSummary,
    );

    if (!mounted || !saved) return;
    await _logSensitiveAction(
      actionType: 'credit_settings_update',
      description: 'Credit settings updated for ${customer.displayName}',
    );
    _showMessage('Credit settings updated.', color: _success);
    await _loadCustomer();
  }

  Future<void> _openProductPrices() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;
    final allowed = await _requirePermission(
      permission: PosPermission.pricingManage,
      title: 'Customer Pricing Approval',
      description:
          'Customer-specific pricing opened for ${customer.displayName}',
    );
    if (!allowed || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerProductPricesScreen(customer: customer),
      ),
    );

    if (!mounted) return;
    await _loadCustomer();
  }

  Future<void> _openCategoryAssignment() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;
    final allowed = await _requirePermission(
      permission: PosPermission.pricingManage,
      title: 'Customer Pricing Assignment Approval',
      description:
          'Customer category/scheme assignment for ${customer.displayName}',
    );
    if (!allowed || !mounted) return;

    final result = await showCustomerCategoryAssignmentDialog(
      context: context,
      customer: customer,
      categories: _categories,
      schemes: _schemes,
    );

    if (!mounted || result == null) return;

    try {
      final service = PricingSchemeService.instance;
      await service.assignCustomerCategory(
        customerId: customer.id!,
        customerCategoryId: result.customerCategoryId,
      );
      await service.assignCustomerPricingScheme(
        customerId: customer.id!,
        pricingSchemeId: result.pricingSchemeId,
      );
      await _logSensitiveAction(
        actionType: 'pricing_update',
        description:
            'Customer pricing assignment updated for ${customer.displayName}',
      );
      _showMessage('Customer category assignment updated.', color: _success);
      await _loadCustomer();
    } catch (e) {
      _showMessage('Could not update category assignment.', color: _danger);
    }
  }

  Future<void> _openCustomerLedger() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerLedgerScreen(
          customerId: customer.id!,
          customerName: customer.displayName,
          initialSummary: _creditSummary,
        ),
      ),
    );

    if (!mounted) return;
    await _loadCustomer();
  }

  Future<void> _openLoyaltyLedger() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerLoyaltyLedgerScreen(customer: customer),
      ),
    );

    if (!mounted) return;
    await _loadCustomer();
  }

  Future<void> _setCustomerLoyaltyEnabled(bool enabled) async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;
    final allowed = await _requirePermission(
      permission: PosPermission.loyaltyAdjust,
      title: 'Loyalty Update Approval',
      description:
          'Loyalty ${enabled ? 'enabled' : 'disabled'} for ${customer.displayName}',
    );
    if (!allowed || !mounted) return;

    try {
      await LoyaltyService.instance.setCustomerLoyaltyEnabled(
        customerId: customer.id!,
        enabled: enabled,
      );
      if (!mounted) return;
      _showMessage(
        enabled
            ? 'Loyalty enabled for customer.'
            : 'Loyalty disabled for customer.',
        color: _success,
      );
      await _logSensitiveAction(
        actionType: 'loyalty_adjustment',
        description:
            'Loyalty ${enabled ? 'enabled' : 'disabled'} for ${customer.displayName}',
      );
      await _loadCustomer();
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not update loyalty status.', color: _danger);
    }
  }

  Future<void> _receiveCustomerPayment() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;
    final allowed = await _requirePermission(
      permission: PosPermission.customerCreditReceivePayment,
      title: 'Receive Credit Payment Approval',
      description:
          'Receive customer credit payment for ${customer.displayName}',
    );
    if (!allowed || !mounted) return;

    final saved = await showCustomerPaymentDialog(
      context: context,
      customerId: customer.id!,
      customerName: customer.displayName,
      initialSummary: _creditSummary,
      receivedBy:
          context.read<AuthProvider>().currentUser?.name.trim().isNotEmpty ==
              true
          ? context.read<AuthProvider>().currentUser!.name.trim()
          : 'Unknown',
    );

    if (!mounted || saved == null) return;
    _showMessage('Customer payment saved.', color: _success);
    if (saved.paymentId != null) {
      await showCustomerPaymentReceiptDialog(
        context: context,
        paymentId: saved.paymentId!,
        paymentJustSaved: true,
      );
    }
    if (!mounted) return;
    await _loadCustomer();
  }

  Future<void> _openReceipt(int saleId) async {
    if (saleId <= 0) return;
    await TransactionHistoryScreen.showReceiptDialogForTransaction(
      context,
      saleId,
    );
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return text;
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
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
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
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
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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

  Widget _profileCard(Customer customer) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: _brand.withValues(alpha: _isDark ? 0.18 : 0.12),
            child: Text(
              customer.displayName.trim().isEmpty
                  ? 'C'
                  : customer.displayName.trim()[0].toUpperCase(),
              style: TextStyle(
                color: _brand,
                fontWeight: FontWeight.w900,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      customer.displayName,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!customer.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _danger.withValues(
                            alpha: _isDark ? 0.18 : 0.10,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _danger.withValues(alpha: 0.24),
                          ),
                        ),
                        child: const Text(
                          'Inactive',
                          style: TextStyle(
                            color: _danger,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    _infoLine(Icons.badge_rounded, customer.displayCode),
                    _infoLine(Icons.phone_rounded, customer.displayPhone),
                    if (customer.hasEmail)
                      _infoLine(Icons.email_rounded, customer.email!),
                    if (customer.hasAddress)
                      _infoLine(Icons.location_on_rounded, customer.address!),
                  ],
                ),
                if (customer.hasNotes) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _panelSoft,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      customer.notes!,
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          ElevatedButton.icon(
            onPressed: _editCustomer,
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _creditAccountCard(Customer customer) {
    final summary =
        _creditSummary ?? CustomerCreditSummary.empty(customer.id ?? 0);
    final balanceColor = summary.currentBalance > 0
        ? _warning
        : summary.currentBalance < 0
        ? _blue
        : _brand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _creditMiniMetric(
          label: 'Balance',
          value: _money(summary.currentBalance),
          icon: Icons.payments_rounded,
          color: balanceColor,
          prominent: true,
        ),
        const SizedBox(height: 10),
        _creditMiniMetric(
          label: 'Limit',
          value: _money(summary.creditLimit),
          icon: Icons.speed_rounded,
          color: _brand,
        ),
        const SizedBox(height: 10),
        _creditMiniMetric(
          label: summary.availableCredit < 0 ? 'Over Limit By' : 'Available',
          value: _money(summary.availableCredit.abs()),
          icon: summary.availableCredit < 0
              ? Icons.warning_rounded
              : Icons.trending_up_rounded,
          color: summary.availableCredit < 0 ? _danger : _blue,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _openCustomerLedger,
          icon: const Icon(Icons.list_alt_rounded),
          label: const Text('View Ledger'),
        ),
        const Spacer(),
        if ((summary.creditNote ?? '').trim().isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _panelSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.note_alt_rounded, color: _textSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.creditNote!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        ElevatedButton.icon(
          onPressed: _receiveCustomerPayment,
          icon: const Icon(Icons.payments_rounded),
          label: const Text('Receive Payment'),
        ),
      ],
    );
  }

  Widget _creditMiniMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool prominent = false,
  }) {
    final effectiveIconColor = prominent
        ? color
        : color.withValues(alpha: 0.72);
    final effectiveValueColor = prominent ? _textPrimary : _textSecondary;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: effectiveIconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveValueColor,
                    fontWeight: FontWeight.w900,
                    fontSize: prominent ? 18 : 16,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loyaltyCard(Customer customer) {
    final settings = _loyaltySettings ?? LoyaltySettings.defaults();
    final redeemValue =
        customer.loyaltyPointsBalance * settings.safePointValueAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stackedMiniMetric(
          label: 'Points Balance',
          value: customer.loyaltyPointsBalance.toString(),
          icon: Icons.stars_rounded,
          color: _brand,
          prominent: true,
        ),
        const SizedBox(height: 10),
        _stackedMiniMetric(
          label: 'Redeem Value',
          value: _money(redeemValue),
          icon: Icons.payments_rounded,
          color: _blue,
        ),
        const SizedBox(height: 10),
        _stackedMiniMetric(
          label: 'Lifetime Earned',
          value: customer.loyaltyLifetimeEarned.toString(),
          icon: Icons.trending_up_rounded,
          color: _success,
        ),
        const SizedBox(height: 10),
        _stackedMiniMetric(
          label: 'Lifetime Redeemed',
          value: customer.loyaltyLifetimeRedeemed.toString(),
          icon: Icons.redeem_rounded,
          color: _warning,
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _openLoyaltyLedger,
          icon: const Icon(Icons.list_alt_rounded),
          label: const Text('View Loyalty Ledger'),
        ),
      ],
    );
  }

  Widget _pricingDiscountsCard(Customer customer) {
    final hasCustomerRules = _activeCustomerRuleCount > 0;
    final statusColor = hasCustomerRules ? _brand : _textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: _border, height: 1),
        const SizedBox(height: 14),
        Text(
          'Special Prices & Discounts',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Customer-only prices or discounts for all items, categories, or products.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _textSecondary,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.24)),
              ),
              child: Text(
                '$_activeCustomerRuleCount Active Rules',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openProductPrices,
                icon: const Icon(Icons.price_change_rounded),
                label: const Text('Manage Rules'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _categorySchemeCard(Customer customer) {
    final category = _categoryFor(customer.customerCategoryId);
    final noSchemeSelected = customer.pricingSchemeId == 0;
    final directScheme = _schemeFor(customer.pricingSchemeId);
    final inheritedScheme = _schemeFor(category?.defaultPricingSchemeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stackedMiniMetric(
          label: 'Category',
          value: _categoryDisplayName(category),
          icon: Icons.groups_2_rounded,
          color: _brand,
          muted: false,
        ),
        const SizedBox(height: 10),
        _stackedMiniMetric(
          label: 'Inherited Scheme',
          value: _schemeDisplayName(inheritedScheme),
          icon: Icons.call_merge_rounded,
          color: _warning,
          muted: false,
        ),
        const SizedBox(height: 10),
        _stackedMiniMetric(
          label: 'Direct Scheme',
          value: noSchemeSelected
              ? 'No Scheme'
              : _schemeDisplayName(directScheme),
          icon: Icons.sell_rounded,
          color: _blue,
          muted: false,
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _openCategoryAssignment,
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Edit Assignment'),
        ),
      ],
    );
  }

  CustomerCategory? _categoryFor(int? id) {
    if (id == null || id <= 0) return null;
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  PricingScheme? _schemeFor(int? id) {
    if (id == null || id <= 0) return null;
    for (final scheme in _schemes) {
      if (scheme.id == id) return scheme;
    }
    return null;
  }

  String _categoryDisplayName(CustomerCategory? category) {
    if (category == null) return 'None';
    return category.isActive
        ? category.displayName
        : '${category.displayName} (inactive)';
  }

  String _schemeDisplayName(PricingScheme? scheme) {
    if (scheme == null) return 'None';
    return scheme.isActive
        ? scheme.displayName
        : '${scheme.displayName} (inactive)';
  }

  Widget _stackedMiniMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool prominent = false,
    bool muted = true,
  }) {
    final effectiveIconColor = prominent || !muted
        ? color
        : color.withValues(alpha: 0.72);
    final effectiveValueColor = prominent || !muted
        ? _textPrimary
        : _textSecondary;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: effectiveIconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveValueColor,
                    fontWeight: FontWeight.w900,
                    fontSize: prominent ? 18 : 16,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loyaltyToggle(Customer customer) {
    final settings = _loyaltySettings ?? LoyaltySettings.defaults();
    final enabled = settings.isEnabled && customer.loyaltyEnabled;
    final toggleColor = enabled ? _brand : _textSecondary;

    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: toggleColor.withValues(alpha: _isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: toggleColor.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            enabled ? 'On' : 'Off',
            style: TextStyle(
              color: toggleColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: customer.loyaltyEnabled,
              activeThumbColor: _brand,
              inactiveThumbColor: _textSecondary,
              inactiveTrackColor: _textSecondary.withValues(alpha: 0.22),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) =>
                  _setCustomerLoyaltyEnabled(!customer.loyaltyEnabled),
            ),
          ),
        ],
      ),
    );
  }

  Widget _creditSettingsButton(Customer customer) {
    final summary =
        _creditSummary ?? CustomerCreditSummary.empty(customer.id ?? 0);
    return ElevatedButton.icon(
      onPressed: _openCreditSettings,
      icon: const Icon(Icons.settings_rounded),
      label: Text(summary.creditEnabled ? 'Edit Settings' : 'Enable Credit'),
    );
  }

  Widget _customerProgramGroups(Customer customer) {
    Widget loyaltyColumn() => _detailGroupColumn(
      title: 'Loyalty',
      subtitle: 'Points, redemption value, and earning status.',
      icon: Icons.card_giftcard_rounded,
      color: _brand,
      trailing: _loyaltyToggle(customer),
      children: [Expanded(child: _loyaltyCard(customer))],
    );

    Widget pricingColumn() => _detailGroupColumn(
      title: 'Pricing Scheme',
      subtitle: 'Category assignment, schemes, and customer-only prices.',
      icon: Icons.account_tree_rounded,
      color: _blue,
      children: [
        _categorySchemeCard(customer),
        const Spacer(),
        _pricingDiscountsCard(customer),
      ],
    );

    Widget creditColumn() => _detailGroupColumn(
      title: 'Credit Account',
      subtitle: 'Balance, credit limit, ledger, and payments.',
      icon: Icons.account_balance_wallet_rounded,
      color: _warning,
      trailing: _creditSettingsButton(customer),
      children: [Expanded(child: _creditAccountCard(customer))],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useThreeColumns = constraints.maxWidth >= 1280;
        if (!useThreeColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 520, child: loyaltyColumn()),
              const SizedBox(height: 18),
              SizedBox(height: 520, child: pricingColumn()),
              const SizedBox(height: 18),
              SizedBox(height: 520, child: creditColumn()),
            ],
          );
        }

        return SizedBox(
          height: 520,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: loyaltyColumn()),
              const SizedBox(width: 16),
              Expanded(child: pricingColumn()),
              const SizedBox(width: 16),
              Expanded(child: creditColumn()),
            ],
          ),
        );
      },
    );
  }

  Widget _detailGroupColumn({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF0B182A) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        boxShadow: [
          if (!_isDark)
            BoxShadow(
              color: const Color(0xFF16314F).withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _textSecondary),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _historyRow(Map<String, dynamic> row) {
    final saleId = ((row['id'] as num?) ?? 0).toInt();
    final type = (row['transaction_type'] ?? 'sale').toString().toLowerCase();
    final isRefund = type == 'refund';
    final total = ((row['total_amount'] as num?) ?? 0).toDouble();
    final payment = (row['payment_method'] ?? '-').toString();
    final cashier = (row['cashier_name'] ?? '-').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (isRefund ? _danger : _brand).withValues(
                alpha: _isDark ? 0.16 : 0.10,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isRefund ? Icons.restart_alt_rounded : Icons.receipt_long_rounded,
              color: isRefund ? _danger : _brand,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaction #$saleId',
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(row['created_at'])} • $payment • $cashier',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            isRefund ? '-${_money(total.abs())}' : _money(total),
            style: TextStyle(
              color: isRefund ? _danger : _textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customer;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Customer Details'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadCustomer,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : customer == null
          ? Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                ),
                child: const Text(
                  'Customer not found.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _profileCard(customer),
                    const SizedBox(height: 16),
                    _customerProgramGroups(customer),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _metricCard(
                          label: 'Total Spent',
                          value: _money(
                            ((_summary['net_total_spent'] as num?) ?? 0)
                                .toDouble(),
                          ),
                          icon: Icons.payments_rounded,
                          color: _brand,
                        ),
                        const SizedBox(width: 12),
                        _metricCard(
                          label: 'Sales',
                          value:
                              (((_summary['sale_count'] as num?) ?? 0).toInt())
                                  .toString(),
                          icon: Icons.shopping_bag_rounded,
                          color: _blue,
                        ),
                        const SizedBox(width: 12),
                        _metricCard(
                          label: 'Average Sale',
                          value: _money(
                            ((_summary['average_sale'] as num?) ?? 0)
                                .toDouble(),
                          ),
                          icon: Icons.bar_chart_rounded,
                          color: _warning,
                        ),
                        const SizedBox(width: 12),
                        _metricCard(
                          label: 'Refunds',
                          value:
                              (((_summary['refund_count'] as num?) ?? 0)
                                      .toInt())
                                  .toString(),
                          icon: Icons.restart_alt_rounded,
                          color: _danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _infoBlock(
                              'First purchase',
                              _formatDate(_summary['first_purchase_at']),
                            ),
                          ),
                          Container(width: 1, height: 42, color: _border),
                          Expanded(
                            child: _infoBlock(
                              'Last purchase',
                              _formatDate(_summary['last_purchase_at']),
                            ),
                          ),
                          Container(width: 1, height: 42, color: _border),
                          Expanded(
                            child: _infoBlock(
                              'Total transactions',
                              (((_summary['transaction_count'] as num?) ?? 0)
                                      .toInt())
                                  .toString(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Purchase History',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_history.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _border),
                        ),
                        child: Text(
                          'No linked purchases yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return InkWell(onTap: () => _openReceipt((((_history[index]['id'] as num?) ?? 0).toInt())), child: _historyRow(_history[index]));
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _infoBlock(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
