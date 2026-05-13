import 'package:flutter/material.dart';
import 'package:shared/models/customer_category.dart';
import 'package:shared/models/customer.dart';
import 'package:shared/models/customer_credit_summary.dart';
import 'package:shared/models/loyalty_settings.dart';
import 'package:shared/models/pricing_scheme.dart';

import '../services/customer_credit_service.dart';
import '../services/customer_pricing_service.dart';
import '../services/customer_service.dart';
import '../services/loyalty_service.dart';
import '../services/pricing_scheme_service.dart';
import '../widgets/app_snackbar.dart';
import 'customer_category_assignment_dialog.dart';
import 'customer_credit_settings_dialog.dart';
import 'customer_form_dialog.dart';
import 'customer_ledger_screen.dart';
import 'customer_loyalty_ledger_screen.dart';
import 'customer_product_prices_screen.dart';
import 'customer_payment_dialog.dart';
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

    final saved = await showCustomerCreditSettingsDialog(
      context: context,
      customerId: customer.id!,
      customerName: customer.displayName,
      initialSummary: _creditSummary,
    );

    if (!mounted || !saved) return;
    _showMessage('Credit settings updated.', color: _success);
    await _loadCustomer();
  }

  Future<void> _openProductPrices() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;

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
      await _loadCustomer();
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not update loyalty status.', color: _danger);
    }
  }

  Future<void> _receiveCustomerPayment() async {
    final customer = _customer;
    if (customer == null || customer.id == null) return;

    final saved = await showCustomerPaymentDialog(
      context: context,
      customerId: customer.id!,
      customerName: customer.displayName,
      initialSummary: _creditSummary,
    );

    if (!mounted || !saved) return;
    _showMessage('Customer payment saved.', color: _success);
    await _loadCustomer();
  }

  Color _creditStatusColor(CustomerCreditSummary summary) {
    if (summary.isBlocked) return _danger;
    if (summary.isWatchlist) return _warning;
    if (summary.isOverLimit) return _danger;
    if (!summary.creditEnabled) return _textSecondary;
    return _brand;
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
    final statusColor = _creditStatusColor(summary);
    final balanceColor = summary.currentBalance > 0
        ? _warning
        : summary.currentBalance < 0
        ? _blue
        : _brand;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: summary.creditEnabled
              ? statusColor.withValues(alpha: 0.38)
              : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: statusColor,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credit Account',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.creditEnabled
                          ? '${summary.statusLabel} • ${summary.isOverLimit ? 'Over limit' : 'Available credit ${_money(summary.availableCredit)}'}'
                          : 'Credit is not enabled for this customer.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  summary.creditEnabled ? summary.statusLabel : 'Disabled',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _openCreditSettings,
                icon: const Icon(Icons.settings_rounded),
                label: Text(
                  summary.creditEnabled ? 'Edit Settings' : 'Enable Credit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _creditMiniMetric(
                label: 'Balance',
                value: _money(summary.currentBalance),
                icon: Icons.payments_rounded,
                color: balanceColor,
              ),
              const SizedBox(width: 10),
              _creditMiniMetric(
                label: 'Limit',
                value: _money(summary.creditLimit),
                icon: Icons.speed_rounded,
                color: _brand,
              ),
              const SizedBox(width: 10),
              _creditMiniMetric(
                label: summary.availableCredit < 0
                    ? 'Over Limit By'
                    : 'Available',
                value: _money(summary.availableCredit.abs()),
                icon: summary.availableCredit < 0
                    ? Icons.warning_rounded
                    : Icons.trending_up_rounded,
                color: summary.availableCredit < 0 ? _danger : _blue,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openCustomerLedger,
                  icon: const Icon(Icons.list_alt_rounded),
                  label: const Text('View Ledger'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _receiveCustomerPayment,
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('Receive Payment'),
                ),
              ),
            ],
          ),
          if ((summary.creditNote ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
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
          ],
        ],
      ),
    );
  }

  Widget _creditMiniMetric({
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
            Icon(icon, color: color, size: 20),
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

  Widget _loyaltyCard(Customer customer) {
    final settings = _loyaltySettings ?? LoyaltySettings.defaults();
    final isGloballyEnabled = settings.isEnabled;
    final isCustomerEnabled = customer.loyaltyEnabled;
    final isActive = isGloballyEnabled && isCustomerEnabled;
    final statusColor = isActive
        ? _brand
        : isGloballyEnabled
        ? _warning
        : _textSecondary;
    final statusLabel = isActive
        ? 'Enabled'
        : isGloballyEnabled
        ? 'Customer Off'
        : 'Module Off';
    final redeemValue =
        customer.loyaltyPointsBalance * settings.safePointValueAmount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isActive ? _brand.withValues(alpha: 0.34) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: statusColor,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loyalty Points',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !isGloballyEnabled
                          ? 'Global loyalty is disabled in settings.'
                          : isCustomerEnabled
                          ? 'Customer can earn and redeem points when eligible.'
                          : 'Customer is excluded from earning and redeeming points.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _setCustomerLoyaltyEnabled(!isCustomerEnabled),
                icon: Icon(
                  isCustomerEnabled
                      ? Icons.block_rounded
                      : Icons.check_circle_rounded,
                ),
                label: Text(isCustomerEnabled ? 'Disable' : 'Enable'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _pricingMiniMetric(
                label: 'Points Balance',
                value: customer.loyaltyPointsBalance.toString(),
                icon: Icons.stars_rounded,
                color: _brand,
              ),
              const SizedBox(width: 10),
              _pricingMiniMetric(
                label: 'Redeem Value',
                value: _money(redeemValue),
                icon: Icons.payments_rounded,
                color: _blue,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pricingMiniMetric(
                label: 'Lifetime Earned',
                value: customer.loyaltyLifetimeEarned.toString(),
                icon: Icons.trending_up_rounded,
                color: _success,
              ),
              const SizedBox(width: 10),
              _pricingMiniMetric(
                label: 'Lifetime Redeemed',
                value: customer.loyaltyLifetimeRedeemed.toString(),
                icon: Icons.redeem_rounded,
                color: _warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openLoyaltyLedger,
                  icon: const Icon(Icons.list_alt_rounded),
                  label: const Text('View Loyalty Ledger'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pricingDiscountsCard(Customer customer) {
    final hasCustomerRules = _activeCustomerRuleCount > 0;
    final statusColor = hasCustomerRules ? _brand : _textSecondary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: hasCustomerRules ? _brand.withValues(alpha: 0.34) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(
                  Icons.local_offer_rounded,
                  color: statusColor,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Special Prices & Discounts',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set customer-only rules for all items, item categories, or specific products.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  '$_activeCustomerRuleCount Rules',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _openProductPrices,
                icon: const Icon(Icons.price_change_rounded),
                label: const Text('Manage Rules'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _pricingMiniMetric(
                label: 'Active Rules',
                value: _activeCustomerRuleCount.toString(),
                icon: Icons.inventory_2_rounded,
                color: _brand,
              ),
              const SizedBox(width: 10),
              _pricingMiniMetric(
                label: 'Rule Targets',
                value: 'All / Category / Item',
                icon: Icons.category_rounded,
                color: _warning,
              ),
              const SizedBox(width: 10),
              _pricingMiniMetric(
                label: 'Rule Actions',
                value: 'Price / Discount',
                icon: Icons.tune_rounded,
                color: _blue,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openProductPrices,
                  icon: const Icon(Icons.price_change_rounded),
                  label: const Text('Manage Customer Item & Category Rules'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categorySchemeCard(Customer customer) {
    final category = _categoryFor(customer.customerCategoryId);
    final noSchemeSelected = customer.pricingSchemeId == 0;
    final directScheme = _schemeFor(customer.pricingSchemeId);
    final inheritedScheme = _schemeFor(category?.defaultPricingSchemeId);
    final activeScheme = noSchemeSelected
        ? null
        : directScheme ?? inheritedScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: _isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _blue.withValues(alpha: 0.24)),
                ),
                child: const Icon(
                  Icons.account_tree_rounded,
                  color: _blue,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category & Scheme',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeScheme == null
                          ? noSchemeSelected
                                ? 'No pricing scheme is applied for this customer.'
                                : 'No pricing scheme is assigned yet.'
                          : directScheme == null
                          ? 'Using category default scheme.'
                          : 'Using direct customer scheme.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _openCategoryAssignment,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Edit Assignment'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _pricingMiniMetric(
                label: 'Category',
                value: _categoryDisplayName(category),
                icon: Icons.groups_2_rounded,
                color: _brand,
              ),
              const SizedBox(width: 10),
              _pricingMiniMetric(
                label: 'Inherited Scheme',
                value: _schemeDisplayName(inheritedScheme),
                icon: Icons.call_merge_rounded,
                color: _warning,
              ),
              const SizedBox(width: 10),
              _pricingMiniMetric(
                label: 'Direct Scheme',
                value: noSchemeSelected
                    ? 'No Scheme'
                    : _schemeDisplayName(directScheme),
                icon: Icons.sell_rounded,
                color: _blue,
              ),
            ],
          ),
        ],
      ),
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

  Widget _pricingMiniMetric({
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
            Icon(icon, color: color, size: 20),
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
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _openReceipt(saleId),
            icon: const Icon(Icons.visibility_rounded, size: 16),
            label: const Text('Receipt'),
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
                    _creditAccountCard(customer),
                    const SizedBox(height: 16),
                    _loyaltyCard(customer),
                    const SizedBox(height: 16),
                    _categorySchemeCard(customer),
                    const SizedBox(height: 16),
                    _pricingDiscountsCard(customer),
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
                          return _historyRow(_history[index]);
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
