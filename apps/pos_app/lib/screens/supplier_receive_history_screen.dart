import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../models/stock_receipt_record.dart';
import '../services/supplier_service.dart';
import '../widgets/app_snackbar.dart';

class SupplierReceiveHistoryScreen extends StatefulWidget {
  const SupplierReceiveHistoryScreen({super.key, this.supplier});

  final PosSupplier? supplier;

  @override
  State<SupplierReceiveHistoryScreen> createState() =>
      _SupplierReceiveHistoryScreenState();
}

class _SupplierReceiveHistoryScreenState
    extends State<SupplierReceiveHistoryScreen> {
  final SupplierService _supplierService = SupplierService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;
  List<StockReceiptRecord> _receipts = const [];
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SupplierHistoryPalette get _ui => SupplierHistoryPalette.of(context);

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final receipts = await _supplierService.getReceiveHistory(
        supplierId: widget.supplier?.id,
        search: '',
      );
      final summary = await _supplierService.getReceiveSummary(
        supplierId: widget.supplier?.id,
      );

      if (!mounted) return;

      setState(() {
        _receipts = receipts;
        _summary = summary;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      AppSnackBar.show(
        context,
        message: 'Could not load receive history.',
        backgroundColor: _ui.danger,
      );
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadData();
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  String _formatDate(String raw) {
    if (raw.trim().isEmpty) return 'No date';
    try {
      final date = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year} '
          '${two(date.hour)}:${two(date.minute)}';
    } catch (_) {
      return raw;
    }
  }

  String _formatDateOnly(String raw) {
    if (raw.trim().isEmpty) return 'No date';
    try {
      final date = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatCurrency(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final quantity = value.toDouble();
    if ((quantity - quantity.roundToDouble()).abs() < 0.000001) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  List<StockReceiptRecord> get _filteredReceipts {
    final rawQuery = _searchController.text.trim().toLowerCase();
    if (rawQuery.isEmpty) return _receipts;

    final tokens = rawQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.trim().isNotEmpty)
        .toList();

    bool matchesToken(StockReceiptRecord receipt, String token) {
      final createdAtText = _formatDate(receipt.createdAt).toLowerCase();
      final compactDateText = createdAtText
          .replaceAll('/', '')
          .replaceAll('-', '')
          .replaceAll(':', '')
          .replaceAll(' ', '');
      final rawCreatedAt = receipt.createdAt.toLowerCase();
      final expiryText = _formatDateOnly(receipt.expiryDate).toLowerCase();
      final compactExpiryText = expiryText
          .replaceAll('/', '')
          .replaceAll('-', '')
          .replaceAll(' ', '');
      final haystack = <String>[
        receipt.productName.toLowerCase(),
        receipt.barcode.toLowerCase(),
        receipt.supplierName.toLowerCase(),
        receipt.cashierName.toLowerCase(),
        receipt.referenceNote.toLowerCase(),
        receipt.batchNumber.toLowerCase(),
        receipt.expiryDate.toLowerCase(),
        expiryText,
        compactExpiryText,
        createdAtText,
        compactDateText,
        rawCreatedAt,
      ];

      return haystack.any((value) => value.contains(token));
    }

    return _receipts.where((receipt) {
      return tokens.every((token) => matchesToken(receipt, token));
    }).toList();
  }

  Map<String, dynamic> get _visibleSummary {
    if (_searchController.text.trim().isEmpty) {
      return _summary;
    }

    final filtered = _filteredReceipts;
    final totalUnits = filtered.fold<double>(
      0.0,
      (sum, receipt) => sum + receipt.quantity,
    );
    final totalCost = filtered.fold<double>(
      0.0,
      (sum, receipt) => sum + (receipt.cost * receipt.quantity),
    );

    return {
      'receipt_count': filtered.length,
      'total_units': totalUnits,
      'total_cost': totalCost,
    };
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? labelText,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    final ui = _ui;
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 20, color: ui.textMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: ui.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ui.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ui.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ui.brand, width: 1.4),
      ),
      hintStyle: TextStyle(color: ui.textMuted),
      labelStyle: TextStyle(color: ui.textSecondary),
      isDense: true,
    );
  }

  Widget _buildHeader() {
    final ui = _ui;
    final visibleSummary = _visibleSummary;
    final title = widget.supplier == null
        ? 'Receive History Workspace'
        : '${widget.supplier!.name} Receive History';

    final subtitle = widget.supplier == null
        ? 'Review stock receiving entries, supplier spend, and logged receiving activity.'
        : 'Review all stock receiving entries and spend recorded for this supplier.';

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ui.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(ui.isDark ? 0.22 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;

              final left = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ui.brandSoft, ui.blueSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ui.border),
                    ),
                    child: Icon(Icons.receipt_long_rounded, color: ui.brand),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: ui.textPrimary,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: ui.textSecondary,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (compact) {
                return left;
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: left)],
              );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 12.0;
              final columns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 700
                  ? 2
                  : 1;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (spacing * (columns - 1))) /
                        columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Receipts',
                      value:
                          (((visibleSummary['receipt_count'] as num?) ?? 0)
                                  .toInt())
                              .toString(),
                      subtitle: 'Logged receive entries',
                      icon: Icons.receipt_long_outlined,
                      color: ui.blue,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Units Received',
                      value: _formatQuantity(
                        (visibleSummary['total_units'] as num?) ?? 0,
                      ),
                      subtitle: 'Total stock units added',
                      icon: Icons.inventory_2_outlined,
                      color: ui.success,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Supplier Spend',
                      value: _formatCurrency(
                        ((visibleSummary['total_cost'] as num?) ?? 0)
                            .toDouble(),
                      ),
                      subtitle: 'Recorded receiving cost',
                      icon: Icons.payments_outlined,
                      color: ui.purple,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySurface({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final ui = _ui;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ui.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ui.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: ui.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: ui.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final ui = _ui;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ui.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          if (compact) {
            return Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: _fieldDecoration(
                    hintText:
                        'Search by product, supplier, barcode, cashier, note, or date',
                    icon: Icons.search_rounded,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _loadData();
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: ui.textMuted,
                            ),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadData(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isRefreshing ? null : _refresh,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ui.textPrimary,
                      side: BorderSide(color: ui.borderStrong),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: _isRefreshing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ui.brand,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh History'),
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: _fieldDecoration(
                    hintText:
                        'Search by product, supplier, barcode, cashier, note, or date',
                    icon: Icons.search_rounded,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _loadData();
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: ui.textMuted,
                            ),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadData(),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _isRefreshing ? null : _refresh,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ui.textPrimary,
                  side: BorderSide(color: ui.borderStrong),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isRefreshing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ui.brand,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh History'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEntriesSection() {
    final ui = _ui;
    final title = widget.supplier == null
        ? 'Receive Entries'
        : '${widget.supplier!.name} Receipts';

    return Container(
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ui.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ui.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Review received quantity, supplier cost, and cashier activity.',
                        style: TextStyle(
                          color: ui.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_filteredReceipts.length} entries',
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: ui.border),
          if (_filteredReceipts.isEmpty)
            _buildEmptyState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              itemCount: _filteredReceipts.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: ui.border),
              itemBuilder: (context, index) =>
                  _buildReceiptRow(_filteredReceipts[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(StockReceiptRecord receipt) {
    final ui = _ui;
    final totalCost = receipt.cost * receipt.quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  receipt.productName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: ui.textPrimary,
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
              _buildInlineMeta(
                icon: Icons.qr_code_rounded,
                text: receipt.barcode,
                color: ui.textSecondary,
              ),
              _buildMetaDivider(),
              _buildInlineMeta(
                icon: Icons.local_shipping_outlined,
                text: receipt.supplierName,
                color: ui.brand,
              ),
              _buildMetaDivider(),
              _buildInlineMeta(
                icon: Icons.schedule_rounded,
                text: _formatDate(receipt.createdAt),
                color: ui.textSecondary,
              ),
              if (receipt.batchNumber.trim().isNotEmpty) ...[
                _buildMetaDivider(),
                _buildInlineMeta(
                  icon: Icons.sell_outlined,
                  text: 'Batch ${receipt.batchNumber.trim()}',
                  color: ui.blue,
                ),
              ],
              if (receipt.expiryDate.trim().isNotEmpty) ...[
                _buildMetaDivider(),
                _buildInlineMeta(
                  icon: Icons.event_available_outlined,
                  text: 'Exp ${_formatDateOnly(receipt.expiryDate)}',
                  color: ui.warning,
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
              _buildInlineMeta(
                icon: Icons.add_box_outlined,
                text: '+${_formatQuantity(receipt.quantity)} received',
                color: ui.success,
              ),
              _buildMetaDivider(),
              Text(
                'Unit ${_formatCurrency(receipt.cost)}',
                style: TextStyle(
                  color: ui.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              _buildMetaDivider(),
              Text(
                'Total ${_formatCurrency(totalCost)}',
                style: TextStyle(
                  color: ui.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (receipt.cashierName.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Processed by ${receipt.cashierName.trim()}',
              style: TextStyle(
                color: ui.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
          if (receipt.referenceNote.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ui.surfaceSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ui.border),
              ),
              child: Text(
                receipt.referenceNote.trim(),
                style: TextStyle(
                  color: ui.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineMeta({
    required IconData icon,
    required String text,
    required Color color,
    double iconSize = 14,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaDivider() {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: _ui.textMuted.withOpacity(0.75),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _buildEmptyState() {
    final ui = _ui;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: ui.surfaceSoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ui.border),
              ),
              child: Icon(
                Icons.history_toggle_off,
                size: 36,
                color: ui.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No receive history recorded yet',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ui.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.trim().isEmpty
                  ? 'Supplier receive entries will appear here once stock is received.'
                  : 'No entries matched the current search. Try product, supplier, barcode, or date.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ui.textSecondary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = _ui;
    final title = widget.supplier == null
        ? 'Supplier Receive History'
        : '${widget.supplier!.name} History';

    return Scaffold(
      backgroundColor: ui.page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ui.page,
        foregroundColor: ui.textPrimary,
        title: Text(title),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: ui.brand))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildToolbar(),
                    const SizedBox(height: 16),
                    _buildEntriesSection(),
                  ],
                ),
              ),
            ),
    );
  }
}

class SupplierHistoryPalette {
  final bool isDark;
  final Color page;
  final Color pageAlt;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceAlt;
  final Color inputFill;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brand;
  final Color brandSoft;
  final Color blue;
  final Color blueSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color purple;

  const SupplierHistoryPalette({
    required this.isDark,
    required this.page,
    required this.pageAlt,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceAlt,
    required this.inputFill,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brand,
    required this.brandSoft,
    required this.blue,
    required this.blueSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.purple,
  });

  factory SupplierHistoryPalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brand = Color(0xFF2AAA8A);
    const blue = Color(0xFF4B8DFF);
    const success = Color(0xFF1FCF9A);
    const warning = Color(0xFFFFB65C);
    const danger = Color(0xFFFF6B7A);
    const purple = Color(0xFF8B5CF6);

    if (isDark) {
      return const SupplierHistoryPalette(
        isDark: true,
        page: Color(0xFF07111F),
        pageAlt: Color(0xFF0B1729),
        surface: Color(0xFF0F1C31),
        surfaceSoft: Color(0xFF14243C),
        surfaceAlt: Color(0xFF0A1627),
        inputFill: Color(0xFF0B1628),
        border: Color(0xFF23344D),
        borderStrong: Color(0xFF31445E),
        textPrimary: Color(0xFFF4F8FF),
        textSecondary: Color(0xFF9DB0C8),
        textMuted: Color(0xFF7F92AC),
        brand: brand,
        brandSoft: Color(0x142AAA8A),
        blue: blue,
        blueSoft: Color(0x184B8DFF),
        success: success,
        successSoft: Color(0x181FCF9A),
        warning: warning,
        warningSoft: Color(0x18FFB65C),
        danger: danger,
        dangerSoft: Color(0x18FF6B7A),
        purple: purple,
      );
    }

    return const SupplierHistoryPalette(
      isDark: false,
      page: Color(0xFFF4F7FB),
      pageAlt: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      surfaceSoft: Color(0xFFF8FAFD),
      surfaceAlt: Color(0xFFFBFCFE),
      inputFill: Color(0xFFF7F9FC),
      border: Color(0xFFD9E3EE),
      borderStrong: Color(0xFFCED9E5),
      textPrimary: Color(0xFF14263B),
      textSecondary: Color(0xFF667A92),
      textMuted: Color(0xFF778BA4),
      brand: brand,
      brandSoft: Color(0x142AAA8A),
      blue: blue,
      blueSoft: Color(0x144B8DFF),
      success: success,
      successSoft: Color(0x141FCF9A),
      warning: warning,
      warningSoft: Color(0x14FFB65C),
      danger: danger,
      dangerSoft: Color(0x14FF6B7A),
      purple: purple,
    );
  }
}
