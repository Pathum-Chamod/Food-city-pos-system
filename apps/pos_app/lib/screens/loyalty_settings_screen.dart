import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/loyalty_service.dart';
import '../services/permission_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/permission_guard.dart';

class LoyaltySettingsScreen extends StatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  State<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends State<LoyaltySettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _earnAmountController = TextEditingController();
  final _earnPointsController = TextEditingController();
  final _pointValueController = TextEditingController();
  final _minimumRedeemController = TextEditingController();
  final _maximumRedeemController = TextEditingController();
  final _categoryController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _productSearchFocusNode = FocusNode();

  LoyaltySettings? _settings;
  List<LoyaltyExclusion> _excludedCategories = const [];
  List<LoyaltyExclusion> _excludedProducts = const [];
  List<Product> _products = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _includeInactive = true;
  bool _isEnabled = true;
  String _roundingMode = 'floor';

  static const _brand = Color(0xFF2AAA8A);
  static const _danger = Color(0xFFE85D75);
  static const _success = Color(0xFF1FCF9A);
  static const _warning = Color(0xFFFFB65C);
  static const _blue = Color(0xFF4B8DFF);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _surface =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _surfaceSoft =>
      _isDark ? const Color(0xFF0B1628) : const Color(0xFFEFF5FB);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

  int? get _actorUserId {
    try {
      return context.read<AuthProvider>().currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? get _actorName {
    try {
      return context.read<AuthProvider>().currentUser?.name;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _earnAmountController.dispose();
    _earnPointsController.dispose();
    _pointValueController.dispose();
    _minimumRedeemController.dispose();
    _maximumRedeemController.dispose();
    _categoryController.dispose();
    _productSearchFocusNode.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging || _tabController.index != 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabController.index != 2) return;
      _productSearchFocusNode.requestFocus();
    });
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final service = LoyaltyService.instance;
      final results = await Future.wait([
        service.getSettings(),
        service.getExcludedCategories(activeOnly: !_includeInactive),
        service.getExcludedProducts(activeOnly: !_includeInactive),
        DatabaseHelper.instance.getProducts(),
      ]);
      final settings = results[0] as LoyaltySettings;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _excludedCategories = results[1] as List<LoyaltyExclusion>;
        _excludedProducts = results[2] as List<LoyaltyExclusion>;
        _products = results[3] as List<Product>;
        _isEnabled = settings.isEnabled;
        _roundingMode = settings.normalizedRoundingMode;
        _earnAmountController.text = settings.safeEarnRateAmount
            .toStringAsFixed(2);
        _earnPointsController.text = settings.safeEarnRatePoints.toString();
        _pointValueController.text = settings.safePointValueAmount
            .toStringAsFixed(2);
        _minimumRedeemController.text = settings.safeMinimumRedeemPoints
            .toString();
        _maximumRedeemController.text = settings.safeMaximumRedeemPercent
            .toStringAsFixed(0);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e);
    }
  }

  Future<void> _logLoyaltyUpdate(String description) async {
    await DatabaseHelper.instance.logSensitiveAction(
      actorUserId: _actorUserId,
      actorName: _actorName,
      actionType: 'loyalty_adjustment',
      description: description,
    );
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await LoyaltyService.instance.updateSettings(
        isEnabled: _isEnabled,
        earnRateAmount: _readDouble(_earnAmountController.text, 100),
        earnRatePoints: _readInt(_earnPointsController.text, 1),
        pointValueAmount: _readDouble(_pointValueController.text, 1),
        minimumRedeemPoints: _readInt(_minimumRedeemController.text, 100),
        maximumRedeemPercent: _readDouble(_maximumRedeemController.text, 20),
        allowCreditSaleEarn: false,
        roundingMode: _roundingMode,
      );
      await _logLoyaltyUpdate('Loyalty global settings updated');
      await _load();
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: 'Loyalty settings saved.',
        backgroundColor: Colors.green,
      );
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveCategory({LoyaltyExclusion? exclusion}) async {
    final controller = TextEditingController(text: exclusion?.value ?? '');
    var excludeEarning = exclusion?.excludeEarning ?? true;
    var excludeRedemption = exclusion?.excludeRedemption ?? false;
    var isActive = exclusion?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(exclusion == null ? 'Exclude Category' : 'Edit Category'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Product category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),
                SwitchListTile(
                  value: excludeEarning,
                  onChanged: (value) =>
                      setDialogState(() => excludeEarning = value),
                  title: const Text('Exclude from earning'),
                ),
                SwitchListTile(
                  value: excludeRedemption,
                  onChanged: (value) =>
                      setDialogState(() => excludeRedemption = value),
                  title: const Text('Exclude from redemption'),
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                  title: const Text('Active'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await LoyaltyService.instance.upsertExcludedCategory(
        id: exclusion?.id,
        categoryName: controller.text,
        excludeEarning: excludeEarning,
        excludeRedemption: excludeRedemption,
        isActive: isActive,
      );
      await _logLoyaltyUpdate(
        'Loyalty category rule updated for "${controller.text.trim()}"',
      );
      await _load();
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _saveProduct(
    Product product, {
    LoyaltyExclusion? exclusion,
  }) async {
    var excludeEarning = exclusion?.excludeEarning ?? true;
    var excludeRedemption = exclusion?.excludeRedemption ?? false;
    var isActive = exclusion?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(exclusion == null ? 'Exclude Product' : product.name),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.barcode} - ${product.category.trim().isEmpty ? 'General' : product.category}',
                  style: TextStyle(color: _textSecondary),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: excludeEarning,
                  onChanged: (value) =>
                      setDialogState(() => excludeEarning = value),
                  title: const Text('Exclude from earning'),
                  subtitle: const Text(
                    'Sales of this product will not earn points.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: excludeRedemption,
                  onChanged: (value) =>
                      setDialogState(() => excludeRedemption = value),
                  title: const Text('Exclude from redemption'),
                  subtitle: const Text(
                    'Points cannot be used against this item.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                  title: const Text('Active rule'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Rule'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await LoyaltyService.instance.upsertExcludedProduct(
        id: exclusion?.id,
        barcode: product.barcode,
        productNameSnapshot: product.name,
        excludeEarning: excludeEarning,
        excludeRedemption: excludeRedemption,
        isActive: isActive,
      );
      await _logLoyaltyUpdate(
        'Loyalty product rule updated for "${product.name}"',
      );
      _productSearchController.clear();
      await _load();
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  Future<void> _editProductExclusion(LoyaltyExclusion exclusion) async {
    var excludeEarning = exclusion.excludeEarning;
    var excludeRedemption = exclusion.excludeRedemption;
    var isActive = exclusion.isActive;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(exclusion.displayName),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exclusion.value, style: TextStyle(color: _textSecondary)),
                SwitchListTile(
                  value: excludeEarning,
                  onChanged: (value) =>
                      setDialogState(() => excludeEarning = value),
                  title: const Text('Exclude from earning'),
                ),
                SwitchListTile(
                  value: excludeRedemption,
                  onChanged: (value) =>
                      setDialogState(() => excludeRedemption = value),
                  title: const Text('Exclude from redemption'),
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                  title: const Text('Active'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    try {
      await LoyaltyService.instance.upsertExcludedProduct(
        id: exclusion.id,
        barcode: exclusion.value,
        productNameSnapshot: exclusion.displayName,
        excludeEarning: excludeEarning,
        excludeRedemption: excludeRedemption,
        isActive: isActive,
      );
      await _logLoyaltyUpdate(
        'Loyalty product rule updated for "${exclusion.displayName}"',
      );
      await _load();
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  void _showError(Object e) {
    AppSnackBar.show(
      context,
      message: e.toString().replaceFirst('Exception: ', ''),
      backgroundColor: _danger,
    );
  }

  double _readDouble(String value, double fallback) {
    final parsed = double.tryParse(value.trim());
    return parsed == null || parsed < 0 ? fallback : parsed;
  }

  int _readInt(String value, int fallback) {
    final parsed = int.tryParse(value.trim());
    return parsed == null || parsed < 0 ? fallback : parsed;
  }

  List<String> get _productCategories {
    final values =
        _products
            .map(
              (product) => product.category.trim().isEmpty
                  ? 'General'
                  : product.category.trim(),
            )
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<Product> get _productSearchResults {
    final query = _productSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final excluded = _excludedProducts.map((item) => item.value).toSet();
    return _products
        .where(
          (product) =>
              !excluded.contains(product.barcode) &&
              (product.name.toLowerCase().contains(query) ||
                  product.barcode.toLowerCase().contains(query) ||
                  product.category.toLowerCase().contains(query)),
        )
        .take(8)
        .toList();
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _brand.withValues(alpha: 0.24)),
          ),
          child: Icon(icon, color: _brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
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
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _textSecondary, size: 42),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _settingsTab() {
    final settings = _settings;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(
          children: [
            _metricCard(
              label: 'Global Status',
              value: _isEnabled ? 'Enabled' : 'Disabled',
              icon: _isEnabled
                  ? Icons.verified_rounded
                  : Icons.pause_circle_rounded,
              color: _isEnabled ? _success : _textSecondary,
            ),
            const SizedBox(width: 12),
            _metricCard(
              label: 'Earning Rule',
              value:
                  'Rs. ${_readDouble(_earnAmountController.text, 100).toStringAsFixed(0)} = ${_readInt(_earnPointsController.text, 1)} pt',
              icon: Icons.add_card_rounded,
              color: _brand,
            ),
            const SizedBox(width: 12),
            _metricCard(
              label: 'Point Value',
              value:
                  'Rs. ${_readDouble(_pointValueController.text, 1).toStringAsFixed(2)}',
              icon: Icons.savings_rounded,
              color: _blue,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                icon: Icons.card_giftcard_rounded,
                title: 'Program Rules',
                subtitle:
                    'Configure how customers earn and redeem loyalty points.',
                trailing: Switch(
                  value: _isEnabled,
                  activeThumbColor: _brand,
                  onChanged: (value) => setState(() => _isEnabled = value),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surfaceSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: _brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Points are calculated from the final paid total after pricing schemes, discounts, and redemption. Customer Credit sales do not earn points in V1.',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      controller: _earnAmountController,
                      label: 'Spend amount to earn',
                      icon: Icons.payments_outlined,
                      suffix: 'Rs.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numberField(
                      controller: _earnPointsController,
                      label: 'Earn points',
                      icon: Icons.add_circle_outline,
                      suffix: 'pts',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      controller: _pointValueController,
                      label: 'Point value',
                      icon: Icons.savings_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numberField(
                      controller: _minimumRedeemController,
                      label: 'Minimum redeem',
                      icon: Icons.pin_outlined,
                      suffix: 'pts',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numberField(
                      controller: _maximumRedeemController,
                      label: 'Max redeem',
                      icon: Icons.percent_rounded,
                      suffix: '%',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      settings == null
                          ? 'Save settings to activate the current loyalty rule.'
                          : 'Current rule: spend Rs. ${settings.safeEarnRateAmount.toStringAsFixed(2)} earns ${settings.safeEarnRatePoints} point${settings.safeEarnRatePoints == 1 ? '' : 's'}. 1 point = Rs. ${settings.safePointValueAmount.toStringAsFixed(2)}.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _categoriesTab() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                icon: Icons.category_outlined,
                title: 'Category Exclusions',
                subtitle:
                    'Control loyalty earning or redemption by product category.',
                trailing: _statusChip(
                  label: '${_excludedCategories.length} rules',
                  color: _brand,
                  icon: Icons.rule_rounded,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (value) {
                        final query = value.text.trim().toLowerCase();
                        if (query.isEmpty) return _productCategories;
                        return _productCategories.where(
                          (item) => item.toLowerCase().contains(query),
                        );
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            _categoryController.text = controller.text;
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Product category',
                                hintText: 'Select or type a category',
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                              onChanged: (value) =>
                                  _categoryController.text = value,
                            );
                          },
                      onSelected: (value) => _categoryController.text = value,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      final value = _categoryController.text.trim();
                      if (value.isEmpty) {
                        AppSnackBar.show(
                          context,
                          message: 'Select a product category first.',
                          backgroundColor: _danger,
                        );
                        return;
                      }
                      _saveCategory(
                        exclusion: LoyaltyExclusion(
                          target: LoyaltyExclusionTarget.category,
                          value: value,
                          createdAt: DateTime.now().toIso8601String(),
                          updatedAt: DateTime.now().toIso8601String(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Rule'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_excludedCategories.isEmpty)
          _emptyState(
            icon: Icons.category_outlined,
            title: 'No category exclusions',
            subtitle:
                'All product categories currently earn and redeem points.',
          )
        else
          ..._excludedCategories.map(
            (item) => _exclusionTile(
              item,
              icon: Icons.category_outlined,
              onTap: () => _saveCategory(exclusion: item),
            ),
          ),
      ],
    );
  }

  Widget _productsTab() {
    return StatefulBuilder(
      builder: (context, setLocalState) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  icon: Icons.inventory_2_outlined,
                  title: 'Product Exclusions',
                  subtitle:
                      'Apply loyalty restrictions to individual products.',
                  trailing: _statusChip(
                    label: '${_excludedProducts.length} rules',
                    color: _blue,
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _productSearchController,
                  focusNode: _productSearchFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Search product',
                    hintText: 'Name, barcode, or category',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setLocalState(() {}),
                ),
              ],
            ),
          ),
          if (_productSearchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: _productSearchResults
                    .map(
                      (product) => ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _brand.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${product.barcode} - ${product.category.trim().isEmpty ? 'General' : product.category}',
                        ),
                        trailing: FilledButton.icon(
                          onPressed: () => _saveProduct(product),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add Rule'),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_excludedProducts.isEmpty)
            _emptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No product exclusions',
              subtitle:
                  'All products currently follow the global loyalty rule.',
            )
          else
            ..._excludedProducts.map(
              (item) => _exclusionTile(
                item,
                icon: Icons.inventory_2_outlined,
                onTap: () => _editProductExclusion(item),
              ),
            ),
        ],
      ),
    );
  }

  Widget _exclusionTile(
    LoyaltyExclusion item, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final color = item.isActive ? _brand : _textSecondary;
    final badges = <Widget>[
      if (item.excludeEarning)
        _statusChip(
          label: 'No earning',
          color: _warning,
          icon: Icons.trending_down_rounded,
        ),
      if (item.excludeRedemption)
        _statusChip(
          label: 'No redemption',
          color: _danger,
          icon: Icons.block_rounded,
        ),
      if (!item.isActive)
        _statusChip(
          label: 'Inactive',
          color: _textSecondary,
          icon: Icons.visibility_off_rounded,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.target.label} - ${item.value}',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: badges),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.edit_rounded, color: _textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().can(PosPermission.loyaltyAdjust)) {
      return const PermissionGuard(
        permission: PosPermission.loyaltyAdjust,
        title: 'Loyalty access restricted',
        message: 'Only managers or full-access users can manage loyalty rules.',
        child: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Loyalty Settings'),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() => _includeInactive = !_includeInactive);
              _load();
            },
            icon: Icon(
              _includeInactive
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
            label: Text(_includeInactive ? 'Showing Inactive' : 'Active Only'),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: _brand.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _brand.withValues(alpha: 0.28)),
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(icon: Icon(Icons.tune_rounded), text: 'Settings'),
                    Tab(icon: Icon(Icons.category_outlined), text: 'Categories'),
                    Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Products'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _settingsTab(),
                        _categoriesTab(),
                        _productsTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
