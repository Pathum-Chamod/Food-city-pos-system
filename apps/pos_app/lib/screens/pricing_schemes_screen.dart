import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/permission_service.dart';
import '../services/pricing_scheme_service.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/permission_guard.dart';
import 'pricing_scheme_dialog.dart';
import 'pricing_scheme_rules_screen.dart';

class PricingSchemesScreen extends StatefulWidget {
  const PricingSchemesScreen({super.key});

  @override
  State<PricingSchemesScreen> createState() => _PricingSchemesScreenState();
}

class _PricingSchemesScreenState extends State<PricingSchemesScreen> {
  List<PricingScheme> _schemes = [];
  Map<int, int> _ruleCounts = {};
  Map<int, int> _categoryCounts = {};
  Map<int, int> _customerCounts = {};
  bool _isLoading = true;
  bool _includeInactive = true;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _blue = Color(0xFF4B8DFF);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _success = Color(0xFF1FCF9A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
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
    _loadSchemes();
  }

  Future<void> _loadSchemes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = PricingSchemeService.instance;
      final results = await Future.wait([
        service.getPricingSchemes(activeOnly: !_includeInactive),
        service.getRuleCountsByScheme(),
        service.getCategoryCountsByScheme(),
        service.getCustomerCountsByDirectScheme(),
      ]);

      if (!mounted) return;
      setState(() {
        _schemes = results[0] as List<PricingScheme>;
        _ruleCounts = results[1] as Map<int, int>;
        _categoryCounts = results[2] as Map<int, int>;
        _customerCounts = results[3] as Map<int, int>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _schemes = [];
        _ruleCounts = {};
        _categoryCounts = {};
        _customerCounts = {};
        _isLoading = false;
      });
      _showMessage('Could not load pricing schemes.', color: _danger);
    }
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _logPricingUpdate(String description) async {
    await DatabaseHelper.instance.logSensitiveAction(
      actorUserId: _actorUserId,
      actorName: _actorName,
      actionType: 'pricing_update',
      description: description,
    );
  }

  Future<void> _addScheme() async {
    final result = await showPricingSchemeDialog(context: context);
    if (result == null) return;

    try {
      await PricingSchemeService.instance.createPricingScheme(
        name: result.name,
        description: result.description,
        isActive: result.isActive,
        priority: result.priority,
        userId: _actorUserId,
      );
      await _logPricingUpdate('Pricing scheme "${result.name}" added');
      _showMessage('Pricing scheme added.', color: _success);
      await _loadSchemes();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _editScheme(PricingScheme scheme) async {
    final result = await showPricingSchemeDialog(
      context: context,
      scheme: scheme,
    );
    if (result == null) return;

    try {
      await PricingSchemeService.instance.updatePricingScheme(
        id: scheme.id ?? 0,
        name: result.name,
        description: result.description,
        isActive: result.isActive,
        priority: result.priority,
        updatedBy: _actorUserId,
      );
      await _logPricingUpdate('Pricing scheme "${result.name}" updated');
      _showMessage('Pricing scheme updated.', color: _success);
      await _loadSchemes();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _duplicateScheme(PricingScheme scheme) async {
    final result = await showPricingSchemeDialog(
      context: context,
      scheme: scheme,
      initialName: '${scheme.displayName} Copy',
      title: 'Duplicate Scheme',
    );
    if (result == null) return;

    try {
      final newSchemeId = await PricingSchemeService.instance
          .duplicatePricingScheme(
            sourceSchemeId: scheme.id ?? 0,
            newName: result.name,
            userId: _actorUserId,
          );
      await PricingSchemeService.instance.updatePricingScheme(
        id: newSchemeId,
        name: result.name,
        description: result.description,
        isActive: result.isActive,
        priority: result.priority,
        updatedBy: _actorUserId,
      );
      await _logPricingUpdate(
        'Pricing scheme "${scheme.displayName}" duplicated as "${result.name}"',
      );
      _showMessage('Pricing scheme duplicated.', color: _success);
      await _loadSchemes();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _toggleActive(PricingScheme scheme) async {
    final id = scheme.id;
    if (id == null || id <= 0) return;

    try {
      await PricingSchemeService.instance.setPricingSchemeActive(
        id: id,
        isActive: !scheme.isActive,
        updatedBy: _actorUserId,
      );
      await _logPricingUpdate(
        'Pricing scheme "${scheme.displayName}" ${scheme.isActive ? 'deactivated' : 'reactivated'}',
      );
      _showMessage(
        scheme.isActive
            ? 'Pricing scheme deactivated.'
            : 'Pricing scheme reactivated.',
        color: scheme.isActive ? _warning : _success,
      );
      await _loadSchemes();
    } catch (e) {
      _showMessage(_cleanError(e), color: _danger);
    }
  }

  Future<void> _openRules(PricingScheme scheme) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PricingSchemeRulesScreen(scheme: scheme),
      ),
    );

    if (!mounted) return;
    await _loadSchemes();
  }

  Widget _summaryCard({
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
                      fontSize: 20,
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

  Widget _schemeCard(PricingScheme scheme) {
    final id = scheme.id ?? 0;
    final ruleCount = _ruleCounts[id] ?? 0;
    final categoryCount = _categoryCounts[id] ?? 0;
    final customerCount = _customerCounts[id] ?? 0;
    final tone = scheme.isActive ? _brand : _textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.isActive ? _border : _danger.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: _isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.sell_rounded, color: tone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        scheme.displayName,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      _chip(
                        scheme.isActive ? 'Active' : 'Inactive',
                        scheme.isActive ? _brand : _danger,
                      ),
                      _chip('Priority ${scheme.priority}', _blue),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$ruleCount rules - $categoryCount categories - $customerCount direct customers',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((scheme.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      scheme.description!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _openRules(scheme),
              icon: const Icon(Icons.rule_rounded),
              label: const Text('Rules'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Duplicate',
              onPressed: () => _duplicateScheme(scheme),
              icon: const Icon(Icons.copy_rounded),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Edit',
              onPressed: () => _editScheme(scheme),
              icon: const Icon(Icons.edit_rounded),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: scheme.isActive ? 'Deactivate' : 'Reactivate',
              onPressed: () => _toggleActive(scheme),
              icon: Icon(
                scheme.isActive
                    ? Icons.block_rounded
                    : Icons.check_circle_rounded,
                color: scheme.isActive ? _danger : _brand,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().can(PosPermission.pricingManage)) {
      return const PermissionGuard(
        permission: PosPermission.pricingManage,
        title: 'Pricing access restricted',
        message: 'Only managers or full-access users can manage pricing.',
        child: SizedBox.shrink(),
      );
    }

    final activeCount = _schemes.where((scheme) => scheme.isActive).length;
    final totalRules = _ruleCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Pricing Schemes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadSchemes,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addScheme,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Scheme'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Row(
                children: [
                  _summaryCard(
                    label: 'Schemes',
                    value: _schemes.length.toString(),
                    icon: Icons.sell_rounded,
                    color: _brand,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Active',
                    value: activeCount.toString(),
                    icon: Icons.verified_rounded,
                    color: _success,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    label: 'Rules',
                    value: totalRules.toString(),
                    icon: Icons.rule_rounded,
                    color: _blue,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Create reusable pricing schemes. Rules are added in the next batch.',
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      'Show inactive',
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Switch(
                      value: _includeInactive,
                      activeThumbColor: _brand,
                      onChanged: (value) {
                        setState(() {
                          _includeInactive = value;
                        });
                        _loadSchemes();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _schemes.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sell_rounded,
                                color: _textSecondary,
                                size: 44,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No pricing schemes found',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addScheme,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add Scheme'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _schemes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _schemeCard(_schemes[index]);
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
