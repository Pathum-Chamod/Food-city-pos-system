import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/expiry_batch.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../widgets/app_snackbar.dart';

class ExpiryAlertsScreen extends StatefulWidget {
  const ExpiryAlertsScreen({super.key});

  @override
  State<ExpiryAlertsScreen> createState() => _ExpiryAlertsScreenState();
}

class _ExpiryAlertsScreenState extends State<ExpiryAlertsScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<ExpiryBatch> _batches = [];
  Map<String, int> _summary = const {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _search = '';

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      AppSnackBar.show(context, message: 'Could not load expiry alerts.');
    }
  }

  String get _performedBy {
    final user = context.read<AuthProvider>().currentUser;
    return user?.name.trim().isNotEmpty == true ? user!.name : 'Manager';
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Waste Expiry Batch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(batch.productName),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Quantity to waste (${batch.unitLabel})',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Waste Stock'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      qtyController.dispose();
      noteController.dispose();
      return;
    }

    final qty = double.tryParse(qtyController.text.trim());
    final note = noteController.text.trim();
    qtyController.dispose();
    noteController.dispose();

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

  Widget _batchCard(ExpiryBatch batch) {
    final now = DateTime.now();
    final days = batch.daysLeft(now);
    final color = _statusColor(days);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                        batch.productName,
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
                      _formatQuantity(batch.remainingQuantity, batch.unitLabel),
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
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
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
