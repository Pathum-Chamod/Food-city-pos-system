import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/database_helper.dart';
import '../widgets/app_snackbar.dart';

enum InventoryHistoryFilter {
  all,
  receives,
  adjustments,
  counts,
  sales,
  refunds,
  priceChanges,
  minStock,
}

class InventoryHistoryScreen extends StatefulWidget {
  final String? initialBarcode;

  const InventoryHistoryScreen({super.key, this.initialBarcode});

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  static final Map<String, List<Map<String, dynamic>>> _historyCache = {};

  List<Map<String, dynamic>> _movements = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  InventoryHistoryFilter _selectedFilter = InventoryHistoryFilter.all;
  DateTime? _selectedDate;
  Timer? _searchDebounce;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _brand => const Color(0xFF2AAA8A);
  Color get _screenBg =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _screenBgAlt =>
      _isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get _panel =>
      _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _panelAlt =>
      _isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _muted =>
      _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _inputFill =>
      _isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC);
  Color get _shadow => Colors.black.withOpacity(_isDark ? 0.26 : 0.06);

  @override
  void initState() {
    super.initState();
    if (widget.initialBarcode != null &&
        widget.initialBarcode!.trim().isNotEmpty) {
      _searchController.text = widget.initialBarcode!.trim();
    }
    final cached = _historyCache[_cacheKey];
    if (cached != null) {
      _movements = cached.map((row) => Map<String, dynamic>.from(row)).toList();
      _isLoading = false;
    }
    _loadHistory(showLoader: cached == null);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<String>? get _selectedActionTypes {
    switch (_selectedFilter) {
      case InventoryHistoryFilter.receives:
        return ['stock_receive'];
      case InventoryHistoryFilter.adjustments:
        return ['stock_adjust_add', 'stock_adjust_remove', 'stock_adjust_set'];
      case InventoryHistoryFilter.counts:
        return ['stock_take_reconcile'];
      case InventoryHistoryFilter.sales:
        return ['sale'];
      case InventoryHistoryFilter.refunds:
        return ['refund'];
      case InventoryHistoryFilter.priceChanges:
        return [
          'price_change_cost',
          'price_change_selling',
          'price_change_wholesale',
          'price_change_sale',
        ];
      case InventoryHistoryFilter.minStock:
        return ['min_stock_change'];
      case InventoryHistoryFilter.all:
        return null;
    }
  }

  Future<void> _loadHistory({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final movements = await DatabaseHelper.instance.getInventoryMovements(
        limit: 200,
        barcode: widget.initialBarcode,
        actionTypes: _selectedActionTypes,
        searchQuery: widget.initialBarcode == null
            ? _searchController.text.trim()
            : '',
        onDate: _selectedDate,
        hydrateSuppliers: true,
      );

      if (!mounted) return;

      setState(() {
        _movements = movements;
        _isLoading = false;
      });
      _historyCache[_cacheKey] = movements
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load inventory history.',
        backgroundColor: Colors.red.shade700,
      );
    }
  }

  String get _cacheKey => [
    widget.initialBarcode?.trim() ?? '',
    _selectedFilter.name,
    _searchController.text.trim(),
    _selectedDate == null ? '' : _formatDateLabel(_selectedDate!),
  ].join('|');

  void _handleSearchChanged(String _) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _loadHistory(showLoader: false);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _selectedDate != null && !_selectedDate!.isAfter(today)
        ? _selectedDate!
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: today,
      selectableDayPredicate: (day) {
        final normalized = DateTime(day.year, day.month, day.day);
        return !normalized.isAfter(today);
      },
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _brand,
            onPrimary: Colors.white,
            surface: _panel,
            onSurface: _textPrimary,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: _panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadHistory(showLoader: false);
  }

  Future<void> _clearDate() async {
    if (_selectedDate == null) return;
    setState(() {
      _selectedDate = null;
    });
    await _loadHistory(showLoader: false);
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadHistory(showLoader: false);
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<T?> _showPremiumDialog<T>({
    required Widget child,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: barrierDismissible
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 240),
                        builder: (context, value, _) {
                          return BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 16 * value,
                              sigmaY: 16 * value,
                            ),
                            child: Container(
                              color: Colors.black.withOpacity(
                                _isDark ? 0.42 * value : 0.22 * value,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.94, end: 1),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, childWidget) {
                        return Transform.scale(
                          scale: value,
                          child: Opacity(
                            opacity: ((value - 0.94) / 0.06).clamp(0, 1),
                            child: childWidget,
                          ),
                        );
                      },
                      child: child,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _openMovementDetails(Map<String, dynamic> movement) async {
    final hydratedMovement = await DatabaseHelper.instance
        .hydrateInventoryMovementSupplierData(
          Map<String, dynamic>.from(movement),
        );

    if (!mounted) return;

    await _showPremiumDialog<void>(
      child: Container(
        width: 760,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _shadow,
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withOpacity(0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _badgeColor(
                        (hydratedMovement['action_type'] ?? '').toString(),
                      ).$2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _badgeColor(
                        (hydratedMovement['action_type'] ?? '').toString(),
                      ).$3,
                      color: _badgeColor(
                        (hydratedMovement['action_type'] ?? '').toString(),
                      ).$1,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _movementTitle(
                            (hydratedMovement['action_type'] ?? '').toString(),
                          ),
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (hydratedMovement['product_name'] ??
                                  'Unknown product')
                              .toString(),
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: _movementRowsSafe(hydratedMovement)
                      .map(
                        (row) => Container(
                          width: 340,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _panelSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.key,
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                row.value,
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<MapEntry<String, String>> _movementRows(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final hideProductRow =
        actionType == 'stock_receive' || actionType == 'stock_adjust_set';

    return <MapEntry<String, String>>[
      MapEntry('Action', _movementTitle(actionType)),
      if (!hideProductRow)
        MapEntry(
          'Product',
          (movement['product_name'] ?? 'Unknown product').toString(),
        ),
      MapEntry('Barcode', (movement['barcode'] ?? '-').toString()),
      MapEntry('When', _formatDateTime(movement['created_at']?.toString())),
      if ((movement['performed_by'] ?? '').toString().trim().isNotEmpty)
        MapEntry('User', movement['performed_by'].toString()),
      if ((movement['supplier_name'] ?? '').toString().trim().isNotEmpty)
        MapEntry('Supplier', movement['supplier_name'].toString()),
      if (movement['supplier_cost'] != null)
        MapEntry(
          'Supplier Cost',
          'Rs. ${_asDouble(movement['supplier_cost']).toStringAsFixed(2)}',
        ),
      if ((movement['batch_number'] ?? '').toString().trim().isNotEmpty)
        MapEntry('Batch', movement['batch_number'].toString()),
      if ((movement['expiry_date'] ?? '').toString().trim().isNotEmpty)
        MapEntry(
          'Expiry Date',
          _formatDateOnly(movement['expiry_date']?.toString()),
        ),
      if (movement['stock_before'] != null || movement['stock_after'] != null)
        MapEntry(
          'Stock',
          '${movement['stock_before'] ?? '-'} → ${movement['stock_after'] ?? '-'}',
        ),
      if (movement['old_price'] != null || movement['new_price'] != null)
        MapEntry(
          'Price',
          'Rs. ${_asDouble(movement['old_price']).toStringAsFixed(2)} → Rs. ${_asDouble(movement['new_price']).toStringAsFixed(2)}',
        ),
    ];
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _shadow,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(_isDark ? 0.18 : 0.12),
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
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required InventoryHistoryFilter filter,
  }) {
    final selected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: _brand.withOpacity(_isDark ? 0.18 : 0.12),
      backgroundColor: _inputFill,
      side: BorderSide(color: selected ? _brand : _border),
      labelStyle: TextStyle(
        color: selected ? _brand : _textSecondary,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      onSelected: (_) async {
        setState(() {
          _selectedFilter = filter;
        });
        await _loadHistory(showLoader: false);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Widget _buildDateChip() {
    final selected = _selectedDate != null;
    return ActionChip(
      avatar: Icon(
        Icons.calendar_month_rounded,
        size: 18,
        color: selected ? _brand : _textPrimary,
      ),
      label: Text(selected ? _formatDateLabel(_selectedDate!) : 'Pick Date'),
      onPressed: _pickDate,
      backgroundColor: selected
          ? _brand.withOpacity(_isDark ? 0.18 : 0.12)
          : _inputFill,
      side: BorderSide(color: selected ? _brand : _border),
      labelStyle: TextStyle(
        color: selected ? _brand : _textSecondary,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Widget _buildClearDateChip() {
    return ActionChip(
      avatar: Icon(Icons.close_rounded, size: 16, color: _textPrimary),
      label: const Text('Clear Date'),
      onPressed: _clearDate,
      backgroundColor: _inputFill,
      side: BorderSide(color: _border),
      labelStyle: TextStyle(
        color: _textSecondary,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  (Color, Color, IconData) _badgeColor(String actionType) {
    if (actionType.contains('product_create')) {
      return (
        const Color(0xFF7C8EA7),
        const Color(0xFF7C8EA7).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.inventory_2_outlined,
      );
    }
    if (actionType.contains('receive')) {
      return (
        const Color(0xFF1FCF9A),
        const Color(0xFF1FCF9A).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.inventory_2_rounded,
      );
    }
    if (actionType.contains('adjust')) {
      return (
        const Color(0xFFFFB65C),
        const Color(0xFFFFB65C).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.tune_rounded,
      );
    }
    if (actionType.contains('price')) {
      return (
        const Color(0xFF8B5CF6),
        const Color(0xFF8B5CF6).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.sell_rounded,
      );
    }
    if (actionType.contains('stock_take')) {
      return (
        const Color(0xFF17B8A6),
        const Color(0xFF17B8A6).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.playlist_add_check_circle_rounded,
      );
    }
    if (actionType.contains('refund')) {
      return (
        const Color(0xFFFF6B7A),
        const Color(0xFFFF6B7A).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.undo_rounded,
      );
    }
    if (actionType.contains('min_stock')) {
      return (
        const Color(0xFFE8A23D),
        const Color(0xFFE8A23D).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.warning_amber_rounded,
      );
    }
    if (actionType.contains('sale')) {
      return (
        const Color(0xFF4B8DFF),
        const Color(0xFF4B8DFF).withOpacity(_isDark ? 0.18 : 0.12),
        Icons.point_of_sale_rounded,
      );
    }
    return (
      const Color(0xFF4B8DFF),
      const Color(0xFF4B8DFF).withOpacity(_isDark ? 0.18 : 0.12),
      Icons.history_rounded,
    );
  }

  Widget _buildActionBadge(String actionType) {
    final badge = _badgeColor(actionType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badge.$2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badge.$1.withOpacity(0.28)),
      ),
      child: Text(
        _movementTitle(actionType),
        style: TextStyle(
          color: badge.$1,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMovementRecord(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final badge = _badgeColor(actionType);
    final productName = (movement['product_name'] ?? 'Unknown product')
        .toString();
    final barcode = (movement['barcode'] ?? '-').toString();
    final quantityChange = (movement['quantity_change'] as num?)?.toDouble();
    final oldPrice = movement['old_price'] as num?;
    final newPrice = movement['new_price'] as num?;
    final supplierName = (movement['supplier_name'] ?? '').toString().trim();
    final performedBy = (movement['performed_by'] ?? '').toString().trim();
    final reason = (movement['reason'] ?? '').toString().trim();
    final batchNumber = (movement['batch_number'] ?? '').toString().trim();
    final expiryDate = (movement['expiry_date'] ?? '').toString().trim();
    final stockBefore = movement['stock_before'];
    final stockAfter = movement['stock_after'];
    final supplierCost = movement['supplier_cost'];

    return InkWell(
      onTap: () => _openMovementDetails(movement),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    productName,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildMovementInlineMeta(
                  icon: Icons.qr_code_rounded,
                  text: barcode,
                  color: _textSecondary,
                ),
                _buildMovementMetaDivider(),
                _buildMovementInlineMeta(
                  icon: badge.$3,
                  text: _movementTitle(actionType),
                  color: badge.$1,
                ),
                _buildMovementMetaDivider(),
                _buildMovementInlineMeta(
                  icon: Icons.schedule_rounded,
                  text: _formatDateTime(movement['created_at']?.toString()),
                  color: _textSecondary,
                ),
                if (supplierName.isNotEmpty) ...[
                  _buildMovementMetaDivider(),
                  _buildMovementInlineMeta(
                    icon: Icons.local_shipping_outlined,
                    text: supplierName,
                    color: _brand,
                  ),
                ],
                if (batchNumber.isNotEmpty) ...[
                  _buildMovementMetaDivider(),
                  _buildMovementInlineMeta(
                    icon: Icons.sell_outlined,
                    text: 'Batch $batchNumber',
                    color: const Color(0xFF4B8DFF),
                  ),
                ],
                if (expiryDate.isNotEmpty) ...[
                  _buildMovementMetaDivider(),
                  _buildMovementInlineMeta(
                    icon: Icons.event_available_outlined,
                    text: 'Exp ${_formatDateOnly(expiryDate)}',
                    color: const Color(0xFFFFB65C),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (quantityChange != null)
                  _buildMovementInlineMeta(
                    icon: quantityChange >= 0
                        ? Icons.add_box_outlined
                        : Icons.indeterminate_check_box_outlined,
                    text: _movementQuantityText(actionType, quantityChange),
                    color: badge.$1,
                  )
                else if (oldPrice != null || newPrice != null)
                  _buildMovementInlineMeta(
                    icon: Icons.sell_outlined,
                    text: _movementPriceText(movement),
                    color: badge.$1,
                  ),
                if (stockBefore != null || stockAfter != null) ...[
                  _buildMovementMetaDivider(),
                  Text(
                    'Stock ${_movementStockText(stockBefore)} -> ${_movementStockText(stockAfter)}',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (supplierCost != null) ...[
                  _buildMovementMetaDivider(),
                  Text(
                    'Unit Rs. ${_asDouble(supplierCost).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            if (performedBy.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Processed by $performedBy',
                style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _panelSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  reason,
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
    );
  }

  Widget _buildMovementInlineMeta({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildMovementMetaDivider() {
    return Text(
      '•',
      style: TextStyle(
        color: _muted,
        fontWeight: FontWeight.w900,
        fontSize: 13,
      ),
    );
  }

  String _movementQuantityText(String actionType, double quantityChange) {
    final sign = quantityChange > 0
        ? '+'
        : quantityChange < 0
        ? '-'
        : '';
    final quantity = '$sign${_formatQuantity(quantityChange.abs())}';
    if (actionType.contains('receive')) return '$quantity received';
    if (actionType == 'sale') return '$quantity sold';
    if (actionType == 'refund') return '$quantity refunded';
    if (actionType.contains('remove')) return '$quantity removed';
    if (actionType.contains('add')) return '$quantity added';
    return '$quantity changed';
  }

  String _movementPriceText(Map<String, dynamic> movement) {
    return 'Rs. ${_asDouble(movement['old_price']).toStringAsFixed(2)} -> '
        'Rs. ${_asDouble(movement['new_price']).toStringAsFixed(2)}';
  }

  String _movementStockText(dynamic value) {
    return value == null ? '-' : _formatQuantity(value);
  }

  // ignore: unused_element
  Widget _buildMovementTile(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final quantityChange = (movement['quantity_change'] as num?)?.toDouble();
    final oldPrice = movement['old_price'] as num?;
    final newPrice = movement['new_price'] as num?;
    final badge = _badgeColor(actionType);

    String subtitle = _movementSubtitleSafe(movement);
    String trailing = _formatDateTime(movement['created_at']?.toString());

    if (quantityChange != null) {
      final baseTrailing = trailing;
      final sign = quantityChange > 0 ? '+' : '';
      trailing = '$sign$quantityChange • $trailing';
      trailing =
          '$sign${_formatQuantity(quantityChange.abs())} â€¢ $baseTrailing';
      trailing =
          '$sign${_formatQuantity(quantityChange.abs())} - $baseTrailing';
    } else if (oldPrice != null || newPrice != null) {
      trailing = 'Rs. ${newPrice?.toStringAsFixed(2) ?? '0.00'} • $trailing';
    }

    trailing = _movementTrailing(movement);

    return InkWell(
      onTap: () => _openMovementDetails(movement),
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: badge.$2,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(badge.$3, color: badge.$1, size: 20),
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
                          (movement['product_name'] ?? 'Unknown product')
                              .toString(),
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _buildActionBadge(actionType),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (movement['barcode'] ?? '-').toString(),
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 156,
              child: Text(
                trailing,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _movementTitle(String actionType) {
    switch (actionType) {
      case 'product_created':
        return 'Product Created';
      case 'product_updated':
        return 'Product Updated';
      case 'product_deleted':
        return 'Product Deleted';
      case 'stock_receive':
        return 'Stock Received';
      case 'stock_adjust_add':
        return 'Stock Added';
      case 'stock_adjust_remove':
        return 'Stock Removed';
      case 'stock_adjust_set':
        return 'Stock Set';
      case 'stock_take_reconcile':
        return 'Stock Reconciled';
      case 'price_change_cost':
        return 'Cost Price Changed';
      case 'price_change_selling':
        return 'Selling Price Changed';
      case 'price_change_wholesale':
        return 'Wholesale Price Changed';
      case 'price_change_sale':
        return 'Sale Price Changed';
      case 'min_stock_change':
        return 'Minimum Stock Changed';
      case 'sale':
        return 'Sold';
      case 'refund':
        return 'Refunded';
      default:
        return actionType.replaceAll('_', ' ');
    }
  }

  String _movementSubtitle(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final stockBefore = movement['stock_before'];
    final stockAfter = movement['stock_after'];
    final oldPrice = movement['old_price'];
    final newPrice = movement['new_price'];
    final reason = (movement['reason'] ?? '').toString().trim();
    final performedBy = (movement['performed_by'] ?? '').toString().trim();

    final pieces = <String>[];

    if (actionType.startsWith('price_change')) {
      pieces.add(
        'Rs. ${_asDouble(oldPrice).toStringAsFixed(2)} → Rs. ${_asDouble(newPrice).toStringAsFixed(2)}',
      );
    } else if (stockBefore != null || stockAfter != null) {
      pieces.add('${stockBefore ?? '-'} → ${stockAfter ?? '-'}');
    }

    if (reason.isNotEmpty) {
      pieces.add(reason);
    }

    if (performedBy.isNotEmpty) {
      pieces.add(performedBy);
    }

    return pieces.isEmpty ? 'Tap to view full details.' : pieces.join(' • ');
  }

  List<MapEntry<String, String>> _movementRowsSafe(
    Map<String, dynamic> movement,
  ) {
    final actionType = (movement['action_type'] ?? '').toString();
    final hideProductRow =
        actionType == 'stock_receive' || actionType == 'stock_adjust_set';
    final stockBefore = movement['stock_before'];
    final stockAfter = movement['stock_after'];

    return <MapEntry<String, String>>[
      MapEntry('Action', _movementTitle(actionType)),
      if (!hideProductRow)
        MapEntry(
          'Product',
          (movement['product_name'] ?? 'Unknown product').toString(),
        ),
      MapEntry('Barcode', (movement['barcode'] ?? '-').toString()),
      MapEntry('When', _formatDateTime(movement['created_at']?.toString())),
      if ((movement['performed_by'] ?? '').toString().trim().isNotEmpty)
        MapEntry('User', movement['performed_by'].toString()),
      if ((movement['supplier_name'] ?? '').toString().trim().isNotEmpty)
        MapEntry('Supplier', movement['supplier_name'].toString()),
      if (movement['supplier_cost'] != null)
        MapEntry(
          'Supplier Cost',
          'Rs. ${_asDouble(movement['supplier_cost']).toStringAsFixed(2)}',
        ),
      if ((movement['batch_number'] ?? '').toString().trim().isNotEmpty)
        MapEntry('Batch', movement['batch_number'].toString()),
      if ((movement['expiry_date'] ?? '').toString().trim().isNotEmpty)
        MapEntry(
          'Expiry Date',
          _formatDateOnly(movement['expiry_date']?.toString()),
        ),
      if (stockBefore != null || stockAfter != null)
        MapEntry(
          'Stock',
          '${stockBefore == null ? '-' : _formatQuantity(stockBefore)} -> '
              '${stockAfter == null ? '-' : _formatQuantity(stockAfter)}',
        ),
      if (movement['old_price'] != null || movement['new_price'] != null)
        MapEntry(
          'Price',
          'Rs. ${_asDouble(movement['old_price']).toStringAsFixed(2)} -> '
              'Rs. ${_asDouble(movement['new_price']).toStringAsFixed(2)}',
        ),
    ];
  }

  String _movementSubtitleSafe(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final stockBefore = movement['stock_before'];
    final stockAfter = movement['stock_after'];
    final oldPrice = movement['old_price'];
    final newPrice = movement['new_price'];
    final reason = (movement['reason'] ?? '').toString().trim();
    final performedBy = (movement['performed_by'] ?? '').toString().trim();

    final pieces = <String>[];

    if (actionType.startsWith('price_change')) {
      pieces.add(
        'Rs. ${_asDouble(oldPrice).toStringAsFixed(2)} -> '
        'Rs. ${_asDouble(newPrice).toStringAsFixed(2)}',
      );
    } else if (stockBefore != null || stockAfter != null) {
      pieces.add(
        '${stockBefore == null ? '-' : _formatQuantity(stockBefore)} -> '
        '${stockAfter == null ? '-' : _formatQuantity(stockAfter)}',
      );
    }

    if (reason.isNotEmpty) {
      pieces.add(reason);
    }

    if (performedBy.isNotEmpty) {
      pieces.add(performedBy);
    }

    final batchNumber = (movement['batch_number'] ?? '').toString().trim();
    if (batchNumber.isNotEmpty) {
      pieces.add('Batch $batchNumber');
    }

    final expiryDate = (movement['expiry_date'] ?? '').toString().trim();
    if (expiryDate.isNotEmpty) {
      pieces.add('Exp ${_formatDateOnly(expiryDate)}');
    }

    return pieces.isEmpty ? 'Tap to view full details.' : pieces.join(' - ');
  }

  String _movementTrailing(Map<String, dynamic> movement) {
    final quantityChange = (movement['quantity_change'] as num?)?.toDouble();
    final newPrice = (movement['new_price'] as num?)?.toDouble();
    final baseTrailing = _formatDateTime(movement['created_at']?.toString());

    if (quantityChange != null) {
      final sign = quantityChange > 0 ? '+' : '';
      return '$sign${_formatQuantity(quantityChange.abs())} - $baseTrailing';
    }

    if (newPrice != null) {
      return 'Rs. ${newPrice.toStringAsFixed(2)} - $baseTrailing';
    }

    return baseTrailing;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatQuantity(dynamic value, {int maxDecimals = 3}) {
    final quantity = _asDouble(value);
    if ((quantity - quantity.roundToDouble()).abs() < 0.000001) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}  $hour:$minute $meridiem';
  }

  String _formatDateOnly(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;

    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _formatDateLabel(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalMovements = _movements.length;
    final stockMovements = _movements.where((m) {
      final action = (m['action_type'] ?? '').toString();
      return action.startsWith('stock_') ||
          action == 'sale' ||
          action == 'refund';
    }).length;
    final priceMovements = _movements.where((m) {
      final action = (m['action_type'] ?? '').toString();
      return action.startsWith('price_change') || action == 'min_stock_change';
    }).length;

    return Scaffold(
      backgroundColor: _screenBg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_screenBg, _screenBgAlt],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: _brand))
              : RefreshIndicator(
                  color: _brand,
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_panelAlt, _panel],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: _border),
                          boxShadow: [
                            BoxShadow(
                              color: _shadow,
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.initialBarcode == null
                                        ? 'Inventory History Workspace'
                                        : 'Product History Workspace',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.initialBarcode == null
                                        ? 'Review stock movements, price changes, counts, sales, and refunds in one place.'
                                        : 'Focused activity history for the selected product barcode.',
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (widget.initialBarcode != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: _brand.withOpacity(
                                    _isDark ? 0.18 : 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _brand.withOpacity(0.28),
                                  ),
                                ),
                                child: Text(
                                  widget.initialBarcode!,
                                  style: TextStyle(
                                    color: _brand,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: _panelSoft,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _border),
                              ),
                              child: IconButton(
                                tooltip: 'Refresh history',
                                onPressed: _isRefreshing ? null : _refresh,
                                icon: _isRefreshing
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _brand,
                                        ),
                                      )
                                    : Icon(
                                        Icons.refresh_rounded,
                                        color: _brand,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              title: 'Total Records',
                              value: totalMovements.toString(),
                              accent: const Color(0xFF4B8DFF),
                              icon: Icons.history_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              title: 'Stock Records',
                              value: stockMovements.toString(),
                              accent: const Color(0xFF1FCF9A),
                              icon: Icons.inventory_2_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              title: 'Price Records',
                              value: priceMovements.toString(),
                              accent: const Color(0xFF8B5CF6),
                              icon: Icons.sell_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.initialBarcode == null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      style: TextStyle(color: _textPrimary),
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search by product, barcode, or reason',
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                        ),
                                        suffixIcon:
                                            _searchController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : IconButton(
                                                onPressed: () async {
                                                  _searchDebounce?.cancel();
                                                  _searchController.clear();
                                                  setState(() {});
                                                  await _loadHistory(
                                                    showLoader: false,
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                ),
                                              ),
                                      ),
                                      onChanged: _handleSearchChanged,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                            ],
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildFilterChip(
                                  label: 'All',
                                  filter: InventoryHistoryFilter.all,
                                ),
                                _buildFilterChip(
                                  label: 'Receives',
                                  filter: InventoryHistoryFilter.receives,
                                ),
                                _buildFilterChip(
                                  label: 'Adjustments',
                                  filter: InventoryHistoryFilter.adjustments,
                                ),
                                _buildFilterChip(
                                  label: 'Counts',
                                  filter: InventoryHistoryFilter.counts,
                                ),
                                _buildFilterChip(
                                  label: 'Sales',
                                  filter: InventoryHistoryFilter.sales,
                                ),
                                _buildFilterChip(
                                  label: 'Refunds',
                                  filter: InventoryHistoryFilter.refunds,
                                ),
                                _buildFilterChip(
                                  label: 'Price Changes',
                                  filter: InventoryHistoryFilter.priceChanges,
                                ),
                                _buildFilterChip(
                                  label: 'Min Stock',
                                  filter: InventoryHistoryFilter.minStock,
                                ),
                                _buildDateChip(),
                                if (_selectedDate != null)
                                  _buildClearDateChip(),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _panelSoft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: _textSecondary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      widget.initialBarcode == null
                                          ? 'Showing ${_movements.length} history records${_selectedDate != null ? ' for ${_formatDateLabel(_selectedDate!)}' : ''}. Limited to the latest 200 matches.'
                                          : 'Showing ${_movements.length} records for barcode ${widget.initialBarcode}${_selectedDate != null ? ' on ${_formatDateLabel(_selectedDate!)}' : ''}. Limited to the latest 200 matches.',
                                      style: TextStyle(
                                        color: _textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                18,
                                18,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'History Records',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_movements.length} shown',
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: _border),
                            if (_movements.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: _panelSoft,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.history_toggle_off_rounded,
                                        color: _muted,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'No inventory history records match the current search or filter.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _textSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 6,
                                ),
                                itemCount: _movements.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, color: _border),
                                itemBuilder: (context, index) =>
                                    _buildMovementRecord(_movements[index]),
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
