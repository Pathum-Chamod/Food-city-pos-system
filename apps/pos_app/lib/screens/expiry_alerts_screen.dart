import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/expiry_batch.dart';
import '../navigation/pos_route_names.dart';
import '../navigation/route_search_focus_registry.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../services/database_helper.dart';
import '../utils/product_name_helper.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

class ExpiryAlertsScreen extends StatefulWidget {
  const ExpiryAlertsScreen({super.key, this.pointBatchId});

  final int? pointBatchId;

  @override
  State<ExpiryAlertsScreen> createState() => _ExpiryAlertsScreenState();
}

class _ExpiryAlertsScreenState extends State<ExpiryAlertsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _batchKeys = <int, GlobalKey>{};

  List<ExpiryBatch> _batches = [];
  Map<String, int> _summary = const {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _search = '';
  int? _pointedBatchId;
  bool _pointFlashOn = false;
  bool _hasAutoPointed = false;
  Timer? _pointTimer;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _background =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _panelAlt =>
      _isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _brand => const Color(0xFF2AAA8A);
  Color get _success => const Color(0xFF1FCF9A);
  Color get _warning => const Color(0xFFFFB65C);
  Color get _danger => const Color(0xFFFF6B7A);
  Color get _blue => const Color(0xFF4B8DFF);

  @override
  void initState() {
    super.initState();
    _loadData();
    RouteSearchFocusRegistry.register(
      PosRouteNames.expiryAlerts,
      _focusSearchField,
    );
    _focusSearchField();
  }

  @override
  void dispose() {
    _pointTimer?.cancel();
    RouteSearchFocusRegistry.unregister(
      PosRouteNames.expiryAlerts,
      _focusSearchField,
    );
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      final context = _searchFocusNode.context;
      final position = context == null
          ? null
          : Scrollable.maybeOf(context)?.position;
      if (position != null) {
        position.animateTo(
          position.minScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      final primaryController = PrimaryScrollController.maybeOf(this.context);
      if (primaryController?.hasClients != true) return;
      primaryController!.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
      });
    } else {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      final batches = await DatabaseHelper.instance.getExpiryAlertBatches(
        search: _search,
        onlyAlerting: false,
      );
      final summary = await DatabaseHelper.instance.getExpiryAlertSummary();
      if (!mounted) return;
      setState(() {
        _batches = batches;
        _summary = summary;
        _isLoading = false;
        _isRefreshing = false;
      });
      _schedulePointToBatch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      AppSnackBar.show(context, message: 'Could not load expiry alerts.');
    }
  }

  void _schedulePointToBatch() {
    final batchId = widget.pointBatchId;
    if (batchId == null || _hasAutoPointed) return;
    _hasAutoPointed = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pointToBatch(batchId);
    });
  }

  Future<void> _pointToBatch(int batchId, {int attempt = 0}) async {
    if (!mounted) return;

    final context = _batchKeys[batchId]?.currentContext;
    if (context == null) {
      if (attempt < 4) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          _pointToBatch(batchId, attempt: attempt + 1);
        });
      }
      return;
    }

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      alignment: 0.24,
    );

    if (!mounted) return;
    setState(() {
      _pointedBatchId = batchId;
      _pointFlashOn = true;
    });

    _pointTimer?.cancel();
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted || _pointedBatchId != batchId) return;
      setState(() {
        _pointFlashOn = false;
      });
    });
    _pointTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted || _pointedBatchId != batchId) return;
      setState(() {
        _pointedBatchId = null;
        _pointFlashOn = false;
      });
    });
  }

  String get _performedBy {
    final user = context.read<AuthProvider>().currentUser;
    return user?.name.trim().isNotEmpty == true ? user!.name : 'Manager';
  }

  String _displayBatchProductName(ExpiryBatch batch) {
    return ProductNameHelper.displayNameFromParts(
      englishName: batch.productName,
      sinhalaName: batch.productNameSi,
      barcode: batch.barcode,
      language: context.read<LanguageProvider>().language,
    );
  }

  String _formatQuantity(num value, String unitLabel) {
    final safe = value.toDouble().abs() < 0.000001 ? 0.0 : value.toDouble();
    final text = safe.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    final unit = unitLabel.trim().isEmpty ? 'pcs' : unitLabel.trim();
    return '$text $unit';
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _daysText(int days) {
    if (days < 0) return '${days.abs()} days overdue';
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return '$days days left';
  }

  Color _statusColor(int days) {
    if (days < 0) return _danger;
    if (days <= 7) return _warning;
    if (days <= 30) return _brand;
    return _blue;
  }

  String _bucketTitle(ExpiryBatch batch, DateTime now) {
    final days = batch.daysLeft(now);
    if (days < 0) return 'Expired';
    if (days == 0) return 'Expires Today';
    if (days <= 7) return '1-7 Days';
    if (days <= 30) return '8-30 Days';
    return 'Watch List';
  }

  Map<String, List<ExpiryBatch>> _groupedBatches() {
    final now = DateTime.now();
    final groups = <String, List<ExpiryBatch>>{};
    for (final batch in _batches) {
      final title = _bucketTitle(batch, now);
      groups.putIfAbsent(title, () => []).add(batch);
    }

    const order = [
      'Expired',
      'Expires Today',
      '1-7 Days',
      '8-30 Days',
      'Watch List',
    ];

    return {
      for (final key in order)
        if (groups[key]?.isNotEmpty == true) key: groups[key]!,
    };
  }

  Future<void> _markChecked(ExpiryBatch batch) async {
    final success = await DatabaseHelper.instance.markExpiryBatchChecked(
      batchId: batch.id,
      performedBy: _performedBy,
    );
    if (!mounted) return;
    if (success) {
      AppSnackBar.show(context, message: 'Batch marked checked.');
      await _loadData(showLoader: false);
    } else {
      AppSnackBar.show(context, message: 'Could not mark batch checked.');
    }
  }

  Future<void> _wasteBatch(ExpiryBatch batch) async {
    final qtyController = TextEditingController(
      text: batch.remainingQuantity
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'\.?0+$'), ''),
    );
    final noteController = TextEditingController(text: 'Expired stock removed');
    final qtyFocusNode = FocusNode();
    final noteFocusNode = FocusNode();
    final days = batch.daysLeft(DateTime.now());
    final statusColor = _statusColor(days);

    final confirmed = await showPremiumDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        void submit() => Navigator.pop(dialogContext, true);

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;

            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(dialogContext, false);
              return KeyEventResult.handled;
            }

            final isSubmit =
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter;
            if (isSubmit && HardwareKeyboard.instance.isControlPressed) {
              submit();
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                decoration: _panelDecoration(color: _panel, radius: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _danger.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.delete_sweep_rounded,
                            color: _danger,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Waste Expiry Batch',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _displayBatchProductName(batch),
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _danger.withValues(alpha: _isDark ? 0.14 : 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _danger.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Remove this quantity from saleable expiry stock only after checking the shelf.',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _batchInfoChip(
                                Icons.event_busy_rounded,
                                _daysText(days),
                                statusColor,
                              ),
                              _batchInfoChip(
                                Icons.event_rounded,
                                'Expiry ${_formatDate(batch.expiryDate)}',
                                statusColor,
                              ),
                              _batchInfoChip(
                                Icons.inventory_2_rounded,
                                'Remaining ${_formatQuantity(batch.remainingQuantity, batch.unitLabel)}',
                                _blue,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: qtyController,
                      focusNode: qtyFocusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: _dialogFieldDecoration(
                        label: 'Quantity to waste (${batch.unitLabel})',
                        helperText:
                            'Use the checked shelf quantity. It cannot exceed the remaining batch stock.',
                      ),
                      onSubmitted: (_) => noteFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      focusNode: noteFocusNode,
                      maxLines: 2,
                      textInputAction: TextInputAction.done,
                      decoration: _dialogFieldDecoration(
                        label: 'Note',
                        helperText:
                            'Example: Expired stock removed from shelf.',
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Keyboard: Esc cancels, Ctrl+Enter wastes stock.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              backgroundColor: _danger,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: submit,
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete_sweep_rounded, size: 18),
                                  SizedBox(width: 7),
                                  Text('Waste Stock'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) {
      qtyController.dispose();
      noteController.dispose();
      qtyFocusNode.dispose();
      noteFocusNode.dispose();
      return;
    }

    final qty = double.tryParse(qtyController.text.trim());
    final note = noteController.text.trim();
    qtyController.dispose();
    noteController.dispose();
    qtyFocusNode.dispose();
    noteFocusNode.dispose();

    if (qty == null || qty <= 0) {
      if (!mounted) return;
      AppSnackBar.show(context, message: 'Enter a valid quantity.');
      return;
    }

    final success = await DatabaseHelper.instance.wasteExpiryBatch(
      batchId: batch.id,
      quantity: qty,
      performedBy: _performedBy,
      note: note,
    );

    if (!mounted) return;
    if (success) {
      AppSnackBar.show(context, message: 'Expired stock removed.');
      await _loadData(showLoader: false);
    } else {
      AppSnackBar.show(context, message: 'Could not waste this batch.');
    }
  }

  BoxDecoration _panelDecoration({Color? color, double radius = 22}) {
    return BoxDecoration(
      color: color ?? _panel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: _isDark ? 0.24 : 0.05),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  InputDecoration _dialogFieldDecoration({
    required String label,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      filled: true,
      fillColor: _isDark ? const Color(0xFF0C1728) : const Color(0xFFF2F6FA),
      labelStyle: TextStyle(color: _textSecondary),
      helperStyle: TextStyle(color: _textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _brand, width: 1.4),
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _panelDecoration(color: _panel, radius: 18),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: _isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
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
                      fontWeight: FontWeight.w700,
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

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _batchInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchCard(ExpiryBatch batch) {
    final now = DateTime.now();
    final days = batch.daysLeft(now);
    final color = _statusColor(days);
    final isPointed = _pointedBatchId == batch.id;
    final showFlash = isPointed && _pointFlashOn;
    final key = _batchKeys.putIfAbsent(batch.id, () => GlobalKey());

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _panelDecoration(color: _panelAlt, radius: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: _isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.event_busy_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _displayBatchProductName(batch),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusChip(_daysText(days), color),
                          if (batch.checkedToday(now)) ...[
                            const SizedBox(width: 6),
                            _statusChip('Checked', _success),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 7,
                        children: [
                          _detail('Barcode', batch.barcode),
                          _detail(
                            'Batch',
                            batch.batchNumber.trim().isEmpty
                                ? 'Not recorded'
                                : batch.batchNumber,
                          ),
                          _detail('Supplier', batch.supplierName),
                          _detail(
                            'Remaining',
                            _formatQuantity(
                              batch.remainingQuantity,
                              batch.unitLabel,
                            ),
                          ),
                          _detail('Expiry', _formatDate(batch.expiryDate)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _markChecked(batch),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                      ),
                      label: const Text('Checked'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _danger),
                      onPressed: () => _wasteBatch(batch),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('Waste'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 2200),
                curve: Curves.easeOutCubic,
                opacity: showFlash ? (_isDark ? 0.55 : 0.42) : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: value.trim().isEmpty ? 'Not recorded' : value,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupedBatches();

    return Column(
      children: [
        Row(
          children: [
            _metricCard(
              'Tracked batches',
              '${_summary['total'] ?? 0}',
              Icons.notifications_active_outlined,
              _brand,
            ),
            const SizedBox(width: 10),
            _metricCard(
              'Expired',
              '${_summary['expired'] ?? 0}',
              Icons.error_outline_rounded,
              _danger,
            ),
            const SizedBox(width: 10),
            _metricCard(
              '1-7 days',
              '${_summary['critical'] ?? 0}',
              Icons.warning_amber_rounded,
              _warning,
            ),
            const SizedBox(width: 10),
            _metricCard(
              'Checked today',
              '${_summary['checked_today'] ?? 0}',
              Icons.task_alt_rounded,
              _success,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _panelDecoration(color: _panel, radius: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  onChanged: (value) {
                    _search = value;
                    _loadData(showLoader: false);
                  },
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search product, barcode, batch, or supplier',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: grouped.isEmpty
              ? Center(
                  child: Text(
                    _search.trim().isEmpty
                        ? 'No expiry batches recorded yet.'
                        : 'No batches matched your search.',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  children: [
                    for (final entry in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      ...entry.value.map(_batchCard),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Expiry Alerts'),
        actions: [
          TextButton.icon(
            onPressed: _isRefreshing
                ? null
                : () => _loadData(showLoader: false),
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(_isRefreshing ? 'Refreshing' : 'Refresh'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(padding: const EdgeInsets.all(16), child: _buildContent()),
    );
  }
}
