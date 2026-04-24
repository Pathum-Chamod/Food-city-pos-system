import 'dart:io';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../models/supplier_product_mapping.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import 'inventory_history_screen.dart';
import 'stock_take_screen.dart';
import 'supplier_receive_history_screen.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/premium_dialog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

enum InventoryFilter {
  all,
  inStock,
  lowStock,
  outOfStock,
  inactive,
}

class _InventoryApprovalResult {
  const _InventoryApprovalResult({
    required this.approverId,
    required this.approverName,
  });

  final int approverId;
  final String approverName;
}

class _BulkImportPreviewRow {
  const _BulkImportPreviewRow({
    required this.rowNumber,
    required this.data,
    required this.isExisting,
    required this.errors,
  });

  final int rowNumber;
  final Map<String, dynamic> data;
  final bool isExisting;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Product> _products = [];
  List<Map<String, dynamic>> _recentMovements = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _searchQuery = '';
  InventoryFilter _selectedFilter = InventoryFilter.all;
  bool _isBulkDeleteMode = false;
  final Set<String> _selectedProductBarcodes = <String>{};
  String? _bulkDeletePerformedByLabel;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _screenBackground =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _screenBackgroundAlt =>
      _isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get _panelColor =>
      _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _panelAlt =>
      _isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get _borderColor =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _mutedIcon =>
      _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _brandColor => const Color(0xFF2AAA8A);
  Color get _brandSoft => _brandColor.withOpacity(_isDark ? 0.16 : 0.10);
  Color get _accentBlue => const Color(0xFF4B8DFF);
  Color get _accentBlueSoft => _accentBlue.withOpacity(_isDark ? 0.18 : 0.10);
  Color get _successColor => const Color(0xFF1FCF9A);
  Color get _successSoft => _successColor.withOpacity(_isDark ? 0.18 : 0.12);
  Color get _warningColor => const Color(0xFFFFB65C);
  Color get _warningSoft => _warningColor.withOpacity(_isDark ? 0.20 : 0.14);
  Color get _dangerColor => const Color(0xFFFF6B7A);
  Color get _dangerSoft => _dangerColor.withOpacity(_isDark ? 0.20 : 0.12);
  Color get _inputFill =>
      _isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC);
  Color get _shadowColor => Colors.black.withOpacity(_isDark ? 0.24 : 0.04);

  BoxDecoration _panelDecoration({Color? color, double radius = 22}) {
    return BoxDecoration(
      color: color ?? _panelColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _borderColor),
      boxShadow: [
        BoxShadow(
          color: _shadowColor,
          blurRadius: _isDark ? 26 : 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  BoxDecoration _softDecoration({Color? color, double radius = 16}) {
    return BoxDecoration(
      color: color ?? _panelSoft,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _borderColor),
    );
  }



  Future<T?> _showInventoryPopup<T>({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget Function(BuildContext dialogContext, StateSetter setPopupState)
        bodyBuilder,
    double maxWidth = 760,
    double maxHeightFactor = 0.88,
  }) {
    return showPremiumDialog<T>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setPopupState) {
            final mediaQuery = MediaQuery.of(dialogContext);
            return Center(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  24 + mediaQuery.viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight: mediaQuery.size.height * maxHeightFactor,
                  ),
                  child: Container(
                    decoration: _panelDecoration(radius: 30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _textSecondary.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _brandSoft,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _brandColor.withOpacity(0.20),
                                  ),
                                ),
                                child: Icon(icon, color: _brandColor, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: _textPrimary,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                      ),
                                    ),
                                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          color: _textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: bodyBuilder(dialogContext, setPopupState),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPopupMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(color: _panelSoft, radius: 18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(_isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPopupHintCard({
    required IconData icon,
    required String title,
    required String message,
    Color? accent,
  }) {
    final tone = accent ?? _brandColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withOpacity(_isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tone.withOpacity(_isDark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 19),
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
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
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

  String _formatCurrency(double value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _saleMetricValue(Product product) {
    final salePrice = product.salePrice;
    if (salePrice != null && salePrice > 0) {
      return _formatCurrency(salePrice);
    }
    return 'Not set';
  }

  Color _saleMetricAccent(Product product) {
    final salePrice = product.salePrice;
    if (product.saleEnabled && salePrice != null && salePrice > 0) {
      return _warningColor;
    }
    return _textSecondary;
  }

  Widget _buildProductDetailMetrics(Product product) {
    final metrics = [
      (
        title: 'Stock',
        value: _formatProductQuantity(product, product.stock),
        icon: Icons.layers_outlined,
        accent: _accentBlue,
      ),
      (
        title: 'Selling',
        value: _formatCurrency(product.sellingPrice),
        icon: Icons.sell_outlined,
        accent: _brandColor,
      ),
      (
        title: 'Wholesale',
        value: _formatCurrency(product.wholesalePrice),
        icon: Icons.local_offer_outlined,
        accent: const Color(0xFF8B5CF6),
      ),
      (
        title: 'Sale',
        value: _saleMetricValue(product),
        icon: Icons.discount_outlined,
        accent: _saleMetricAccent(product),
      ),
      (
        title: 'Cost',
        value: _formatCurrency(product.costPrice),
        icon: Icons.payments_outlined,
        accent: _warningColor,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 880
            ? 5
            : maxWidth >= 680
                ? 3
                : maxWidth >= 460
                    ? 2
                    : 1;
        final spacing = 10.0;
        final tileWidth =
            ((maxWidth - (spacing * (columns - 1))) / columns).clamp(0.0, 220.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: tileWidth,
                  child: _buildPopupMetricCard(
                    title: metric.title,
                    value: metric.value,
                    icon: metric.icon,
                    accent: metric.accent,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData(showLoader: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final products = await DatabaseHelper.instance.getProducts();
      final movements = await DatabaseHelper.instance.getInventoryMovements(
        limit: 8,
      );

      if (!mounted) return;

      setState(() {
        _products = products;
        _recentMovements = movements;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage('Could not load inventory data.', isError: true);
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadData(showLoader: false);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: isError ? _dangerColor : _successColor,
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String confirmText = 'Confirm',
    bool isDestructive = false,
  }) async {
    final confirmed = await showPremiumDialog<bool>(
      context: context,
      builder: (dialogContext) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: _panelDecoration(),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    color: _textSecondary,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isDestructive ? _dangerColor : _brandColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(confirmText),
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

    return confirmed ?? false;
  }

  String? _validateNonNegativeMoney(String rawValue, {required String label}) {
    final value = double.tryParse(rawValue.trim());
    if (value == null) return 'Enter a valid $label.';
    if (value < 0) return '$label cannot be negative.';
    return null;
  }

  String? _validatePositiveInt(String rawValue, {required String label, bool allowZero = false}) {
    final value = int.tryParse(rawValue.trim());
    if (value == null) return 'Enter a valid $label.';
    if (allowZero) {
      if (value < 0) return '$label cannot be negative.';
    } else {
      if (value <= 0) return '$label must be greater than 0.';
    }
    return null;
  }

  String? _validateQuantityInput(
    String rawValue, {
    required String label,
    required ProductQuantityType quantityType,
    bool allowZero = false,
  }) {
    final value = _tryParseQuantityInput(rawValue, quantityType);
    if (value == null) return 'Enter a valid $label.';
    if (allowZero) {
      if (value < 0) return '$label cannot be negative.';
    } else if (value <= 0) {
      return '$label must be greater than 0.';
    }
    return null;
  }

  double? _tryParseQuantityInput(
    String rawValue,
    ProductQuantityType quantityType,
  ) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    if (quantityType == ProductQuantityType.weight) {
      return double.tryParse(trimmed);
    }
    final value = int.tryParse(trimmed);
    return value?.toDouble();
  }

  double _parseQuantityInput(
    String rawValue,
    ProductQuantityType quantityType,
  ) {
    return _tryParseQuantityInput(rawValue, quantityType) ?? 0.0;
  }

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final quantity = value.toDouble();
    if (quantity.abs() < 0.000001) {
      return '0';
    }
    if ((quantity - quantity.roundToDouble()).abs() < 0.000001) {
      return quantity.round().toString();
    }
    return quantity
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatQuantityWithUnitLabel(num value, String unitLabel) {
    final trimmedUnitLabel = unitLabel.trim();
    if (trimmedUnitLabel.isEmpty) return _formatQuantity(value);
    return '${_formatQuantity(value)} $trimmedUnitLabel';
  }

  String _formatProductQuantity(Product product, num value) {
    return _formatQuantityWithUnitLabel(value, product.unitLabel);
  }

  void _disposeControllersNextFrame(List<TextEditingController> controllers) {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }

  String _normalizeImportHeader(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(' ', '_');
    switch (normalized) {
      case 'product_name':
        return 'name';
      case 'price':
        return 'selling_price';
      case 'cost':
        return 'cost_price';
      case 'stock_qty':
      case 'qty':
      case 'quantity':
      case 'opening_qty':
        return 'stock';
      case 'minimum_stock':
      case 'min_stock':
        return 'min_stock_level';
      case 'measurement_type':
      case 'measure_type':
      case 'item_type':
        return 'quantity_type';
      case 'unit':
      case 'unit_name':
      case 'stock_unit':
        return 'unit_label';
      default:
        return normalized;
    }
  }

  bool _parseImportBool(String? value, {bool fallback = false}) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return fallback;
    if ({'1', 'true', 'yes', 'y', 'on'}.contains(normalized)) return true;
    if ({'0', 'false', 'no', 'n', 'off'}.contains(normalized)) return false;
    return fallback;
  }

  String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  ProductQuantityType _parseImportQuantityType(String? value) {
    return ProductQuantityTypeX.fromDb(value);
  }

  String _normalizeUnitLabelInput(
    String? value,
    ProductQuantityType quantityType,
  ) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    return quantityType.defaultUnitLabel;
  }

  void _syncUnitLabelWithQuantityType({
    required TextEditingController controller,
    required ProductQuantityType previousType,
    required ProductQuantityType nextType,
  }) {
    final currentValue = controller.text.trim();
    if (currentValue.isEmpty || currentValue == previousType.defaultUnitLabel) {
      controller.text = nextType.defaultUnitLabel;
    }
  }

  Widget _buildMeasurementFields({
    required ProductQuantityType quantityType,
    required ValueChanged<ProductQuantityType> onQuantityTypeChanged,
    required TextEditingController unitLabelController,
  }) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<ProductQuantityType>(
            initialValue: quantityType,
            decoration: const InputDecoration(labelText: 'Quantity type'),
            items: ProductQuantityType.values
                .map(
                  (type) => DropdownMenuItem<ProductQuantityType>(
                    value: type,
                    child: Text(type.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              onQuantityTypeChanged(value);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: unitLabelController,
            decoration: InputDecoration(
              labelText: 'Unit label',
              helperText: quantityType == ProductQuantityType.weight
                  ? 'Examples: kg, g, lb'
                  : 'Examples: pcs, pack, bottle',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadBulkImportTemplate() async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Bulk Upload Template',
        fileName: 'food_city_product_import_template.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (path == null || path.trim().isEmpty) return;

      final csvText = const ListToCsvConverter().convert([
        [
          'barcode',
          'name',
          'category',
          'cost_price',
          'selling_price',
          'wholesale_price',
          'sale_price',
          'sale_enabled',
          'quantity_type',
          'unit_label',
          'stock',
          'min_stock_level',
        ],
        [
          '4790000000001',
          'Sample Product',
          'General',
          '80.00',
          '100.00',
          '95.00',
          '90.00',
          'false',
          'unit',
          'pcs',
          '25',
          '5',
        ],
      ]);

      await File(path).writeAsString(csvText);
      if (!mounted) return;
      _showMessage('CSV template saved successfully.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not save CSV template.', isError: true);
    }
  }

  Future<List<_BulkImportPreviewRow>> _parseBulkImportFile(String path) async {
    final text = await File(path).readAsString();
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text);

    if (rows.isEmpty) {
      return const [];
    }

    final headers = rows.first
        .map((cell) => _normalizeImportHeader(cell?.toString() ?? ''))
        .toList();
    final indexByHeader = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      final key = headers[i];
      if (key.isNotEmpty && !indexByHeader.containsKey(key)) {
        indexByHeader[key] = i;
      }
    }

    if (!indexByHeader.containsKey('barcode') ||
        !indexByHeader.containsKey('name') ||
        !indexByHeader.containsKey('selling_price')) {
      throw Exception('CSV must include barcode, name, and selling_price columns.');
    }

    String readValue(List<dynamic> row, String key) {
      final index = indexByHeader[key];
      if (index == null || index >= row.length) return '';
      return _stringValue(row[index]);
    }

    final existingByBarcode = {
      for (final product in _products) product.barcode.trim().toLowerCase(): product,
    };
    final seenBarcodes = <String>{};
    final preview = <_BulkImportPreviewRow>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => _stringValue(cell).isEmpty)) {
        continue;
      }

      final rowNumber = i + 1;
      final barcode = readValue(row, 'barcode');
      final name = readValue(row, 'name');
      final category = readValue(row, 'category').isEmpty ? 'General' : readValue(row, 'category');
      final costPriceRaw = readValue(row, 'cost_price');
      final sellingPriceRaw = readValue(row, 'selling_price');
      final wholesalePriceRaw = readValue(row, 'wholesale_price');
      final salePriceRaw = readValue(row, 'sale_price');
      final saleEnabledRaw = readValue(row, 'sale_enabled');
      final quantityTypeRaw = readValue(row, 'quantity_type');
      final unitLabelRaw = readValue(row, 'unit_label');
      final stockRaw = readValue(row, 'stock');
      final minStockRaw = readValue(row, 'min_stock_level');

      final errors = <String>[];
      final normalizedBarcode = barcode.trim().toLowerCase();
      if (barcode.trim().isEmpty) errors.add('Barcode is required');
      if (name.trim().isEmpty) errors.add('Name is required');
      if (sellingPriceRaw.trim().isEmpty) errors.add('Selling price is required');
      if (normalizedBarcode.isNotEmpty && seenBarcodes.contains(normalizedBarcode)) {
        errors.add('Duplicate barcode in file');
      }

      final normalizedQuantityType = quantityTypeRaw.trim().toLowerCase();
      if (normalizedQuantityType.isNotEmpty &&
          normalizedQuantityType != 'unit' &&
          normalizedQuantityType != 'weight') {
        errors.add('Quantity type must be unit or weight');
      }
      final quantityType = _parseImportQuantityType(quantityTypeRaw);
      final unitLabel = _normalizeUnitLabelInput(unitLabelRaw, quantityType);


      double? costPrice;
      if (costPriceRaw.trim().isEmpty) {
        costPrice = 0;
      } else {
        costPrice = double.tryParse(costPriceRaw.trim());
        if (costPrice == null) {
          errors.add('Invalid cost price');
        } else if (costPrice < 0) {
          errors.add('Cost price cannot be negative');
        }
      }

      double? sellingPrice = double.tryParse(sellingPriceRaw.trim());
      if (sellingPrice == null) {
        errors.add('Invalid selling price');
      } else if (sellingPrice <= 0) {
        errors.add('Selling price must be greater than 0');
      }

      double? wholesalePrice;
      if (wholesalePriceRaw.trim().isNotEmpty) {
        wholesalePrice = double.tryParse(wholesalePriceRaw.trim());
        if (wholesalePrice == null) {
          errors.add('Invalid wholesale price');
        } else if (wholesalePrice < 0) {
          errors.add('Wholesale price cannot be negative');
        }
      }

      double? salePrice;
      if (salePriceRaw.trim().isNotEmpty) {
        salePrice = double.tryParse(salePriceRaw.trim());
        if (salePrice == null) {
          errors.add('Invalid sale price');
        } else if (salePrice < 0) {
          errors.add('Sale price cannot be negative');
        }
      }

      final saleEnabled = _parseImportBool(saleEnabledRaw, fallback: false);
      if (saleEnabled && (salePrice == null || salePrice <= 0)) {
        errors.add('Active sale needs a valid sale price');
      }

      int? stock;
      if (stockRaw.trim().isEmpty) {
        stock = 0;
      } else {
        stock = int.tryParse(stockRaw.trim());
        if (stock == null) {
          errors.add('Invalid stock');
        } else if (stock < 0) {
          errors.add('Stock cannot be negative');
        }
      }

      int? minStock;
      if (minStockRaw.trim().isEmpty) {
        minStock = 0;
      } else {
        minStock = int.tryParse(minStockRaw.trim());
        if (minStock == null) {
          errors.add('Invalid minimum stock level');
        } else if (minStock < 0) {
          errors.add('Minimum stock cannot be negative');
        }
      }

      if (normalizedBarcode.isNotEmpty) {
        seenBarcodes.add(normalizedBarcode);
      }

      final isExisting = normalizedBarcode.isNotEmpty && existingByBarcode.containsKey(normalizedBarcode);

      preview.add(_BulkImportPreviewRow(
        rowNumber: rowNumber,
        isExisting: isExisting,
        errors: errors,
        data: {
          'barcode': barcode.trim(),
          'name': name.trim(),
          'category': category.trim(),
          'cost_price': costPrice ?? 0.0,
          'selling_price': sellingPrice ?? 0.0,
          'wholesale_price': wholesalePrice,
          'sale_price': salePrice,
          'sale_enabled': saleEnabled,
          'quantity_type': quantityType.dbValue,
          'unit_label': unitLabel,
          'stock': stock ?? 0,
          'opening_stock': stock ?? 0,
          'min_stock_level': minStock ?? 0,
        },
      ));
    }

    return preview;
  }

  Map<String, dynamic>? get _currentUserMap {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return null;
    return {
      'id': user.id,
      'name': user.name,
      'role': user.role,
      'has_full_access': user.hasFullAccess,
    };
  }

  int? get _currentUserId => _currentUserMap?['id'] as int?;

  String get _currentUserName {
    final raw = (_currentUserMap?['name'] ?? '').toString().trim();
    return raw.isEmpty ? 'Unknown User' : raw;
  }

  bool get _currentUserIsManager {
    return context.read<AuthProvider>().hasManagementAccess;
  }

  String _buildPerformedByLabel(String? approverName) {
    final currentName = _currentUserName;
    if (_currentUserIsManager) {
      return currentName;
    }
    if (approverName == null || approverName.trim().isEmpty) {
      return currentName;
    }
    return '$currentName (approved by ${approverName.trim()})';
  }

  Future<_InventoryApprovalResult?> _requireManagerApproval({
    required String actionLabel,
    required String description,
  }) async {
    if (_currentUserIsManager) {
      return _InventoryApprovalResult(
        approverId: _currentUserId ?? 0,
        approverName: _currentUserName,
      );
    }

    final pinController = TextEditingController();
    String? errorText;
    bool isVerifying = false;

    final approver = await showPremiumDialog<_InventoryApprovalResult?>(
      context: context,
      barrierDismissible: !isVerifying,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> verify() async {
              final pin = pinController.text.trim();
              if (pin.isEmpty) {
                setDialogState(() {
                  errorText = 'Enter approval PIN.';
                });
                return;
              }

              setDialogState(() {
                isVerifying = true;
                errorText = null;
              });

              try {
                final user = await DatabaseHelper.instance.findUserByPin(pin);

                if (!dialogContext.mounted) return;

                if (user == null) {
                  setDialogState(() {
                    isVerifying = false;
                    errorText = 'Invalid PIN.';
                  });
                  return;
                }

                final userId = ((user['id'] as num?) ?? 0).toInt();
                final userName = (user['name'] ?? 'Manager').toString();
                final role = (user['role'] ?? '').toString().toLowerCase();
                final isActive = ((user['is_active'] as num?) ?? 1).toInt() == 1;
                final hasFullAccess =
                    ((user['has_full_access'] as num?) ?? 0).toInt() == 1 ||
                    (user['has_full_access'] == true);
                final canApprove = role == 'manager' || hasFullAccess;

                if (!isActive) {
                  setDialogState(() {
                    isVerifying = false;
                    errorText = 'This approver account is inactive.';
                  });
                  return;
                }

                if (!canApprove) {
                  setDialogState(() {
                    isVerifying = false;
                    errorText = 'PIN does not belong to a manager or full-access user.';
                  });
                  return;
                }

                await DatabaseHelper.instance.logManagerApproval(
                  actorUserId: userId,
                  actorName: userName,
                  targetUserId: _currentUserId,
                  targetUserName: _currentUserName,
                  description: description,
                );

                if (!dialogContext.mounted) return;
                Navigator.pop(
                  dialogContext,
                  _InventoryApprovalResult(
                    approverId: userId,
                    approverName: userName,
                  ),
                );
              } catch (_) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isVerifying = false;
                  errorText = 'Approval failed. Please try again.';
                });
              }
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  decoration: _panelDecoration(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manager Approval Required',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter manager or full-access PIN to $actionLabel.',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: pinController,
                        obscureText: true,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: _textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Approval PIN',
                          errorText: errorText,
                        ),
                        onSubmitted: (_) {
                          if (!isVerifying) {
                            verify();
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isVerifying
                                  ? null
                                  : () => Navigator.pop(dialogContext, null),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isVerifying ? null : verify,
                              child: isVerifying
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    _disposeControllersNextFrame([pinController]);

    if (approver == null && mounted) {
      _showMessage('Manager approval is required to continue.', isError: true);
    }

    return approver;
  }

  List<Product> get _filteredProducts {

    final query = _searchQuery.trim().toLowerCase();

    return _products.where((product) {
      final matchesSearch = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case InventoryFilter.inStock:
          return product.isActive && product.stock > product.minStockLevel;
        case InventoryFilter.lowStock:
          return product.isActive && product.isLowStock;
        case InventoryFilter.outOfStock:
          return product.isActive && product.isOutOfStock;
        case InventoryFilter.inactive:
          return !product.isActive;
        case InventoryFilter.all:
          return true;
      }
    }).toList();
  }

  int get _lowStockCount => _products.where((p) => p.isActive && p.isLowStock).length;
  int get _outOfStockCount => _products.where((p) => p.isActive && p.isOutOfStock).length;
  int get _activeProductCount => _products.where((p) => p.isActive).length;
  double get _stockValue => _products.fold<double>(
        0,
        (sum, product) => sum + (product.costPrice * product.stock),
      );

  Future<Product?> _pickProduct({
    required String title,
  }) async {
    IconData pickerIcon = Icons.inventory_2_outlined;
    String pickerSubtitle = 'Choose an inventory item to continue.';
    String hintTitle = 'Search active products';
    String hintMessage =
        'Find an item quickly by product name, barcode, or category and continue in one tap.';

    if (title.toLowerCase().contains('receive')) {
      pickerIcon = Icons.inventory_2_rounded;
      pickerSubtitle = 'Pick the item that is receiving new stock.';
      hintTitle = 'Receive against an existing item';
      hintMessage =
          'Select the product first, then we will capture supplier, quantity, and unit cost details.';
    } else if (title.toLowerCase().contains('adjust')) {
      pickerIcon = Icons.tune_rounded;
      pickerSubtitle = 'Choose the item whose stock needs correction.';
      hintTitle = 'Adjust live stock safely';
      hintMessage =
          'Open a product from the list to add, remove, or set the exact stock quantity.';
    } else if (title.toLowerCase().contains('price')) {
      pickerIcon = Icons.sell_rounded;
      pickerSubtitle = 'Choose the item whose pricing should be updated.';
      hintTitle = 'Update product pricing';
      hintMessage =
          'Select a product to edit selling, wholesale, sale, or cost price from the next step.';
    }

    final showPrice = title.toLowerCase().contains('price');
    final showStockMeta = !showPrice;
    final showStockStatusChip = !showPrice;
    String localQuery = '';

    return _showInventoryPopup<Product>(
      icon: pickerIcon,
      title: title,
      subtitle: pickerSubtitle,
      maxWidth: 760,
      maxHeightFactor: 0.86,
      bodyBuilder: (dialogContext, setPopupState) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            final normalizedQuery = localQuery.trim().toLowerCase();
            final visibleProducts = _products.where((product) {
              if (!product.isActive) return false;
              if (normalizedQuery.isEmpty) return true;
              return product.name.toLowerCase().contains(normalizedQuery) ||
                  product.barcode.toLowerCase().contains(normalizedQuery) ||
                  product.category.toLowerCase().contains(normalizedQuery);
            }).toList()
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            void updateQuery(String value) {
              setPopupState(() {
                localQuery = value;
              });
              setInnerState(() {});
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPopupHintCard(
                  icon: pickerIcon,
                  title: hintTitle,
                  message: hintMessage,
                ),
                const SizedBox(height: 18),
                TextField(
                  autofocus: true,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name, barcode, or category',
                    hintStyle: TextStyle(color: _textSecondary),
                    prefixIcon: Icon(Icons.search_rounded, color: _mutedIcon),
                    suffixIcon: localQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => updateQuery(''),
                            icon: Icon(Icons.close_rounded, color: _mutedIcon),
                          ),
                    filled: true,
                    fillColor: _inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: _brandColor, width: 1.4),
                    ),
                  ),
                  onChanged: updateQuery,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '${visibleProducts.length} product${visibleProducts.length == 1 ? '' : 's'} available',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: visibleProducts.isEmpty
                      ? Container(
                          width: double.infinity,
                          decoration: _softDecoration(color: _panelSoft, radius: 22),
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 42,
                                color: _mutedIcon,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No matching products found.',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Try a different product name, barcode, or category.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: visibleProducts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final product = visibleProducts[index];
                            final stockAccent = product.isOutOfStock
                                ? _dangerColor
                                : product.isLowStock
                                    ? _warningColor
                                    : _brandColor;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => Navigator.pop(dialogContext, product),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _panelSoft,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.name,
                                              style: TextStyle(
                                                color: _textPrimary,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                                height: 1.15,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  product.barcode,
                                                  style: TextStyle(
                                                    color: _textSecondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (showStockMeta)
                                                  Text(
                                                    '|',
                                                    style: TextStyle(
                                                      color: _textSecondary,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                Text(
                                                  product.category,
                                                  style: TextStyle(
                                                    color: _textSecondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '•',
                                                  style: TextStyle(
                                                    color: _textSecondary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                if (showStockMeta)
                                                  Text(
                                                    'Stock ${_formatProductQuantity(product, product.stock)}',
                                                    style: TextStyle(
                                                      color: stockAccent,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (showPrice || showStockStatusChip)
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (showPrice)
                                              Text(
                                                _formatCurrency(product.sellingPrice),
                                                style: TextStyle(
                                                  color: _brandColor,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            if (showPrice && showStockStatusChip)
                                              const SizedBox(height: 8),
                                            if (showStockStatusChip)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: stockAccent.withOpacity(
                                                    _isDark ? 0.16 : 0.10,
                                                  ),
                                                  borderRadius: BorderRadius.circular(999),
                                                  border: Border.all(
                                                    color: stockAccent.withOpacity(0.22),
                                                  ),
                                                ),
                                                child: Text(
                                                  product.isOutOfStock
                                                      ? 'Out of stock'
                                                      : product.isLowStock
                                                          ? 'Low stock'
                                                          : 'In stock',
                                                  style: TextStyle(
                                                    color: stockAccent,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    /* return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        String localQuery = '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final visibleProducts = _products.where((product) {
              if (!product.isActive) return false;
              if (localQuery.trim().isEmpty) return true;
              final q = localQuery.trim().toLowerCase();
              return product.name.toLowerCase().contains(q) ||
                  product.barcode.toLowerCase().contains(q) ||
                  product.category.toLowerCase().contains(q);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search by name, barcode, or category',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            localQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visibleProducts.isEmpty
                            ? const Center(
                                child: Text('No matching products found.'),
                              )
                            : ListView.separated(
                                itemCount: visibleProducts.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final product = visibleProducts[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    title: Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${product.barcode} • ${product.category} • ${product.quantityType.label} (${product.unitLabel}) • Stock ${_formatProductQuantity(product, product.stock)}',
                                    ),
                                    trailing: Text(
                                      'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green,
                                      ),
                                    ),
                                    onTap: () => Navigator.pop(context, product),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ); */
  }


  Future<void> _openAddProductFlow() async {
    final approval = await _requireManagerApproval(
      actionLabel: 'add a new product',
      description: 'Approved product creation requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final nameController = TextEditingController();
    final barcodeController = TextEditingController();
    final categoryController = TextEditingController(text: 'General');
    final costPriceController = TextEditingController();
    final sellingPriceController = TextEditingController();
    final wholesalePriceController = TextEditingController();
    final salePriceController = TextEditingController();
    final openingStockController = TextEditingController(text: '0');
    final minStockController = TextEditingController(text: '0');
    final unitLabelController = TextEditingController(text: 'pcs');
    bool saleEnabled = false;
    ProductQuantityType quantityType = ProductQuantityType.unit;

    final saved = await _showInventoryPopup<bool>(
      icon: Icons.add_box_outlined,
      title: 'Add Product',
      subtitle: 'Create a new inventory item with pricing and opening stock.',
      maxWidth: 760,
      bodyBuilder: (dialogContext, setPopupState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopupHintCard(
                icon: Icons.inventory_2_outlined,
                title: 'New inventory item',
                message:
                    'Add the core identity, prices, and opening quantity in one step.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Product name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: barcodeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              _buildMeasurementFields(
                quantityType: quantityType,
                unitLabelController: unitLabelController,
                onQuantityTypeChanged: (value) {
                  setPopupState(() {
                    final previousType = quantityType;
                    quantityType = value;
                    _syncUnitLabelWithQuantityType(
                      controller: unitLabelController,
                      previousType: previousType,
                      nextType: value,
                    );
                  });
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: costPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cost price'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: sellingPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Selling price'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wholesalePriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Wholesale price (optional)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: salePriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Sale price (optional)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _softDecoration(color: _panelSoft, radius: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sale price active',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enable when this product should bill using the sale price in Sale mode.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: saleEnabled,
                      onChanged: (value) {
                        setPopupState(() {
                          saleEnabled = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: openingStockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Opening stock'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: minStockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min stock'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final barcode = barcodeController.text.trim();
                        final category = categoryController.text.trim();

                        if (name.isEmpty) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Enter a product name.',
                          );
                          return;
                        }
                        if (barcode.isEmpty) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Enter a barcode.',
                          );
                          return;
                        }
                        final barcodeExists = _products.any(
                          (item) =>
                              item.barcode.trim().toLowerCase() ==
                              barcode.toLowerCase(),
                        );
                        if (barcodeExists) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'A product with this barcode already exists.',
                          );
                          return;
                        }

                        final costError = _validateNonNegativeMoney(
                          costPriceController.text,
                          label: 'cost price',
                        );
                        if (costError != null) {
                          AppSnackBar.show(dialogContext, message: costError);
                          return;
                        }

                        final sellingError = _validateNonNegativeMoney(
                          sellingPriceController.text,
                          label: 'selling price',
                        );
                        if (sellingError != null) {
                          AppSnackBar.show(dialogContext, message: sellingError);
                          return;
                        }

                        final openingStockError = _validatePositiveInt(
                          openingStockController.text,
                          label: 'opening stock',
                          allowZero: true,
                        );
                        if (openingStockError != null) {
                          AppSnackBar.show(
                            dialogContext,
                            message: openingStockError,
                          );
                          return;
                        }

                        final minStockError = _validatePositiveInt(
                          minStockController.text,
                          label: 'minimum stock level',
                          allowZero: true,
                        );
                        if (minStockError != null) {
                          AppSnackBar.show(dialogContext, message: minStockError);
                          return;
                        }

                        final rawWholesale = wholesalePriceController.text.trim();
                        if (rawWholesale.isNotEmpty) {
                          final wholesaleError = _validateNonNegativeMoney(
                            rawWholesale,
                            label: 'wholesale price',
                          );
                          if (wholesaleError != null) {
                            AppSnackBar.show(
                              dialogContext,
                              message: wholesaleError,
                            );
                            return;
                          }
                        }

                        final rawSale = salePriceController.text.trim();
                        if (rawSale.isNotEmpty) {
                          final saleError = _validateNonNegativeMoney(
                            rawSale,
                            label: 'sale price',
                          );
                          if (saleError != null) {
                            AppSnackBar.show(dialogContext, message: saleError);
                            return;
                          }
                        }

                        final sellingPrice =
                            double.parse(sellingPriceController.text.trim());
                        if (sellingPrice <= 0) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Selling price must be greater than 0.',
                          );
                          return;
                        }

                        final costPrice =
                            double.parse(costPriceController.text.trim());
                        final wholesalePrice = rawWholesale.isEmpty
                            ? sellingPrice
                            : double.parse(rawWholesale);
                        final salePrice =
                            rawSale.isEmpty ? null : double.parse(rawSale);
                        final openingStock =
                            int.parse(openingStockController.text.trim());
                        final minStock = int.parse(minStockController.text.trim());
                        final normalizedUnitLabel = _normalizeUnitLabelInput(
                          unitLabelController.text,
                          quantityType,
                        );

                        if (saleEnabled && (salePrice == null || salePrice <= 0)) {
                          AppSnackBar.show(
                            dialogContext,
                            message:
                                'Enter a valid sale price before activating sale mode.',
                          );
                          return;
                        }

                        final confirmed = await _confirmAction(
                          title: 'Confirm Add Product',
                          message:
                              'Create $name as ${quantityType == ProductQuantityType.weight ? 'a weighted' : 'a unit'} item with opening stock of $openingStock $normalizedUnitLabel?',
                          confirmText: 'Create',
                        );
                        if (!confirmed) return;

                        final success =
                            await DatabaseHelper.instance.createProductLocal(
                          barcode: barcode,
                          name: name,
                          category: category.isEmpty ? 'General' : category,
                          costPrice: costPrice,
                          sellingPrice: sellingPrice,
                          quantityType: quantityType,
                          unitLabel: normalizedUnitLabel,
                          wholesalePrice: wholesalePrice,
                          salePrice: salePrice,
                          saleEnabled: saleEnabled,
                          openingStock: openingStock,
                          minStockLevel: minStock,
                          changedBy: changedBy,
                        );

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, success);
                      },
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Create Product'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    _disposeControllersNextFrame([
      nameController,
      barcodeController,
      categoryController,
      costPriceController,
      sellingPriceController,
      wholesalePriceController,
      salePriceController,
      openingStockController,
      minStockController,
      unitLabelController,
    ]);

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Product added successfully.');
    } else if (saved == false) {
      _showMessage('Could not create product.', isError: true);
    }
  }


  void _exitBulkDeleteMode() {
    if (!mounted) return;
    setState(() {
      _isBulkDeleteMode = false;
      _selectedProductBarcodes.clear();
      _bulkDeletePerformedByLabel = null;
    });
  }

  Future<void> _enterBulkDeleteMode() async {
    final approval = await _requireManagerApproval(
      actionLabel: 'bulk delete products',
      description: 'Approved bulk delete mode requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;

    setState(() {
      _isBulkDeleteMode = true;
      _selectedProductBarcodes.clear();
      _bulkDeletePerformedByLabel = _buildPerformedByLabel(approval.approverName);
    });
  }

  void _toggleProductSelection(Product product) {
    setState(() {
      if (_selectedProductBarcodes.contains(product.barcode)) {
        _selectedProductBarcodes.remove(product.barcode);
      } else {
        _selectedProductBarcodes.add(product.barcode);
      }
    });
  }

  bool get _allVisibleProductsSelected {
    final visible = _filteredProducts;
    return visible.isNotEmpty &&
        visible.every((product) => _selectedProductBarcodes.contains(product.barcode));
  }

  void _toggleSelectAllVisibleProducts() {
    final visible = _filteredProducts;
    if (visible.isEmpty) return;

    setState(() {
      final allSelected = visible.every(
        (product) => _selectedProductBarcodes.contains(product.barcode),
      );

      if (allSelected) {
        _selectedProductBarcodes.removeAll(
          visible.map((product) => product.barcode),
        );
      } else {
        _selectedProductBarcodes.addAll(
          visible.map((product) => product.barcode),
        );
      }
    });
  }

  Future<void> _confirmBulkDeleteSelected() async {
    if (_selectedProductBarcodes.isEmpty) {
      _showMessage('Select at least one product to delete.', isError: true);
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Confirm Bulk Delete',
      message:
          'Delete ${_selectedProductBarcodes.length} selected products from inventory? This cannot be undone.',
      confirmText: 'Delete Selected',
      isDestructive: true,
    );
    if (!confirmed) return;

    final deletedCount = await DatabaseHelper.instance.bulkDeleteProductsLocal(
      _selectedProductBarcodes.toList(),
      changedBy: _bulkDeletePerformedByLabel ?? _currentUserName,
    );

    if (!mounted) return;

    if (deletedCount > 0) {
      _exitBulkDeleteMode();
      await _loadData(showLoader: false);
      _showMessage('$deletedCount product(s) deleted successfully.');
    } else {
      _showMessage('Could not bulk delete products.', isError: true);
    }
  }

  Future<void> _openEditProductFlow(Product product) async {
    final approval = await _requireManagerApproval(
      actionLabel: 'edit ${product.name}',
      description:
          'Approved product edit for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final nameController = TextEditingController(text: product.name);
    final categoryController = TextEditingController(text: product.category);
    final costPriceController = TextEditingController(
      text: product.costPrice.toStringAsFixed(2),
    );
    final sellingPriceController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );
    final wholesalePriceController = TextEditingController(
      text: product.wholesalePrice.toStringAsFixed(2),
    );
    final salePriceController = TextEditingController(
      text: product.salePrice == null
          ? ''
          : product.salePrice!.toStringAsFixed(2),
    );
    final minStockController = TextEditingController(
      text: product.minStockLevel.toString(),
    );
    final unitLabelController = TextEditingController(text: product.unitLabel);
    bool saleEnabled = product.saleEnabled;
    ProductQuantityType quantityType = product.quantityType;

    final saved = await _showInventoryPopup<bool>(
      icon: Icons.edit_outlined,
      title: 'Edit Product',
      subtitle: 'Update prices and product details without changing quantity.',
      maxWidth: 780,
      bodyBuilder: (dialogContext, setPopupState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: _softDecoration(color: _panelSoft, radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Barcode',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.barcode,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Product name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              _buildMeasurementFields(
                quantityType: quantityType,
                unitLabelController: unitLabelController,
                onQuantityTypeChanged: (value) {
                  setPopupState(() {
                    final previousType = quantityType;
                    quantityType = value;
                    _syncUnitLabelWithQuantityType(
                      controller: unitLabelController,
                      previousType: previousType,
                      nextType: value,
                    );
                  });
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: costPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cost price'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: sellingPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Selling price'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wholesalePriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Wholesale price'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: salePriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Sale price (optional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _softDecoration(color: _panelSoft, radius: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sale price active',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Disable to fall back to the normal selling price during billing.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: saleEnabled,
                      onChanged: (value) {
                        setPopupState(() {
                          saleEnabled = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: minStockController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Minimum stock level'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final category = categoryController.text.trim();

                        if (name.isEmpty) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Enter a product name.',
                          );
                          return;
                        }

                        final costError = _validateNonNegativeMoney(
                          costPriceController.text,
                          label: 'cost price',
                        );
                        if (costError != null) {
                          AppSnackBar.show(dialogContext, message: costError);
                          return;
                        }

                        final sellingError = _validateNonNegativeMoney(
                          sellingPriceController.text,
                          label: 'selling price',
                        );
                        if (sellingError != null) {
                          AppSnackBar.show(dialogContext, message: sellingError);
                          return;
                        }

                        final minStockError = _validatePositiveInt(
                          minStockController.text,
                          label: 'minimum stock level',
                          allowZero: true,
                        );
                        if (minStockError != null) {
                          AppSnackBar.show(dialogContext, message: minStockError);
                          return;
                        }

                        final rawWholesale = wholesalePriceController.text.trim();
                        if (rawWholesale.isNotEmpty) {
                          final wholesaleError = _validateNonNegativeMoney(
                            rawWholesale,
                            label: 'wholesale price',
                          );
                          if (wholesaleError != null) {
                            AppSnackBar.show(
                              dialogContext,
                              message: wholesaleError,
                            );
                            return;
                          }
                        }

                        final rawSale = salePriceController.text.trim();
                        if (rawSale.isNotEmpty) {
                          final saleError = _validateNonNegativeMoney(
                            rawSale,
                            label: 'sale price',
                          );
                          if (saleError != null) {
                            AppSnackBar.show(dialogContext, message: saleError);
                            return;
                          }
                        }

                        final sellingPrice =
                            double.parse(sellingPriceController.text.trim());
                        if (sellingPrice <= 0) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Selling price must be greater than 0.',
                          );
                          return;
                        }

                        final costPrice =
                            double.parse(costPriceController.text.trim());
                        final wholesalePrice = rawWholesale.isEmpty
                            ? sellingPrice
                            : double.parse(rawWholesale);
                        final salePrice =
                            rawSale.isEmpty ? null : double.parse(rawSale);
                        final minStock = int.parse(minStockController.text.trim());
                        final normalizedUnitLabel = _normalizeUnitLabelInput(
                          unitLabelController.text,
                          quantityType,
                        );

                        if (saleEnabled && (salePrice == null || salePrice <= 0)) {
                          AppSnackBar.show(
                            dialogContext,
                            message:
                                'Enter a valid sale price before activating sale mode.',
                          );
                          return;
                        }

                        final normalizedCategory =
                            category.isEmpty ? 'General' : category;
                        final normalizedWholesale = double.parse(
                          ((wholesalePrice <= 0 ? sellingPrice : wholesalePrice)
                                  .toStringAsFixed(2)),
                        );
                        final normalizedSalePrice = salePrice == null
                            ? null
                            : double.parse(salePrice.toStringAsFixed(2));

                        final noChanges =
                            name == product.name &&
                            normalizedCategory == product.category &&
                            quantityType == product.quantityType &&
                            normalizedUnitLabel == product.unitLabel &&
                            double.parse(costPrice.toStringAsFixed(2)) ==
                                double.parse(product.costPrice.toStringAsFixed(2)) &&
                            double.parse(sellingPrice.toStringAsFixed(2)) ==
                                double.parse(product.sellingPrice.toStringAsFixed(2)) &&
                            normalizedWholesale ==
                                double.parse(product.wholesalePrice.toStringAsFixed(2)) &&
                            ((normalizedSalePrice == null &&
                                    product.salePrice == null) ||
                                (normalizedSalePrice != null &&
                                    product.salePrice != null &&
                                    normalizedSalePrice ==
                                        double.parse(product.salePrice!
                                            .toStringAsFixed(2)))) &&
                            saleEnabled == product.saleEnabled &&
                            minStock == product.minStockLevel;

                        if (noChanges) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'No changes detected.',
                          );
                          Navigator.pop(dialogContext, null);
                          return;
                        }

                        final confirmed = await _confirmAction(
                          title: 'Confirm Product Update',
                          message: 'Save changes for ${product.name}?',
                          confirmText: 'Save Changes',
                        );
                        if (!confirmed) return;

                        final success = await DatabaseHelper.instance
                            .updateProductDetailsLocal(
                          barcode: product.barcode,
                          name: name,
                          category: category.isEmpty ? 'General' : category,
                          costPrice: costPrice,
                          sellingPrice: sellingPrice,
                          quantityType: quantityType,
                          unitLabel: normalizedUnitLabel,
                          wholesalePrice: wholesalePrice,
                          salePrice: salePrice,
                          saleEnabled: saleEnabled,
                          minStockLevel: minStock,
                          changedBy: changedBy,
                        );

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, success);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Save Product Changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    _disposeControllersNextFrame([
      nameController,
      categoryController,
      costPriceController,
      sellingPriceController,
      wholesalePriceController,
      salePriceController,
      minStockController,
      unitLabelController,
    ]);

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Product updated successfully.');
    } else if (saved == false) {
      _showMessage('Could not update product.', isError: true);
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final approval = await _requireManagerApproval(
      actionLabel: 'delete ${product.name}',
      description:
          'Approved product delete for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final confirmed = await _confirmAction(
      title: 'Delete Product',
      message:
          'Delete ${product.name} from inventory? This cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;

    final success = await DatabaseHelper.instance.deleteProductLocal(
      product.barcode,
      changedBy: changedBy,
    );

    if (!mounted) return;
    if (success) {
      await _loadData(showLoader: false);
      _showMessage('Product deleted successfully.');
    } else {
      _showMessage('Could not delete product.', isError: true);
    }
  }

  Future<void> _handleProductMenuAction(String value, Product product) async {
    switch (value) {
      case 'edit':
        await _openEditProductFlow(product);
        break;
      case 'delete':
        await _deleteProduct(product);
        break;
      case 'history':
        await _openInventoryHistoryScreen(barcode: product.barcode);
        break;
    }
  }

  Future<void> _openBulkUploadFlow() async {
    final approval = await _requireManagerApproval(
      actionLabel: 'bulk upload products',
      description: 'Approved bulk product upload requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    String? selectedFileName;
    List<_BulkImportPreviewRow> previewRows = [];
    bool isParsing = false;
    bool isImporting = false;

    final imported = await _showInventoryPopup<bool>(
      icon: Icons.upload_file_rounded,
      title: 'Bulk Upload Products',
      subtitle: 'Preview what will be created or updated before importing.',
      maxWidth: 940,
      maxHeightFactor: 0.90,
      bodyBuilder: (dialogContext, setPopupState) {
        Future<void> pickCsvFile() async {
          setPopupState(() {
            isParsing = true;
          });

          try {
            final picked = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['csv'],
              allowMultiple: false,
            );

            if (picked == null || picked.files.isEmpty) {
              setPopupState(() {
                isParsing = false;
              });
              return;
            }

            final file = picked.files.single;
            final path = file.path;
            if (path == null || path.trim().isEmpty) {
              throw Exception('Selected file path is not available.');
            }

            final parsed = await _parseBulkImportFile(path);
            setPopupState(() {
              selectedFileName = file.name;
              previewRows = parsed;
              isParsing = false;
            });
          } catch (e) {
            setPopupState(() {
              isParsing = false;
              previewRows = [];
            });
            if (!dialogContext.mounted) return;
            AppSnackBar.show(
              dialogContext,
              message: e.toString().replaceFirst('Exception: ', ''),
            );
          }
        }

        final validRows = previewRows.where((row) => row.isValid).toList();
        final createCount =
            validRows.where((row) => !row.isExisting).length;
        final updateCount =
            validRows.where((row) => row.isExisting).length;
        final failedCount = previewRows.where((row) => !row.isValid).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: isParsing || isImporting ? null : pickCsvFile,
                  icon: const Icon(Icons.file_open_rounded),
                  label: const Text('Choose CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: isParsing || isImporting
                      ? null
                      : _downloadBulkImportTemplate,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download Template'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (selectedFileName != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: _softDecoration(color: _panelSoft, radius: 18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _accentBlueSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.description_outlined,
                        color: _accentBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selectedFileName!,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${previewRows.length} rows',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            else
              _buildPopupHintCard(
                icon: Icons.table_view_outlined,
                title: 'No CSV file selected yet',
                message:
                    'Download the template, fill your product list, then choose the CSV to preview it here.',
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildPopupMetricCard(
                  title: 'Valid',
                  value: validRows.length.toString(),
                  icon: Icons.check_circle_outline_rounded,
                  accent: _successColor,
                ),
                _buildPopupMetricCard(
                  title: 'Create',
                  value: createCount.toString(),
                  icon: Icons.add_box_outlined,
                  accent: _accentBlue,
                ),
                _buildPopupMetricCard(
                  title: 'Update',
                  value: updateCount.toString(),
                  icon: Icons.sync_alt_rounded,
                  accent: Colors.deepPurple,
                ),
                _buildPopupMetricCard(
                  title: 'Failed',
                  value: failedCount.toString(),
                  icon: Icons.error_outline_rounded,
                  accent: _dangerColor,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: _softDecoration(color: _panelAlt, radius: 24),
                padding: const EdgeInsets.all(12),
                child: isParsing
                    ? Center(
                        child: CircularProgressIndicator(color: _brandColor),
                      )
                    : previewRows.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.table_rows_outlined,
                                    size: 42,
                                    color: _mutedIcon,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nothing to preview yet',
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Choose a CSV file to review rows before importing.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: previewRows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = previewRows[index];
                              final data = row.data;
                              final accent = row.isValid
                                  ? (row.isExisting
                                      ? Colors.deepPurple
                                      : _accentBlue)
                                  : _dangerColor;
                              final badgeText = row.isValid
                                  ? (row.isExisting ? 'UPDATE' : 'CREATE')
                                  : 'ERROR';

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _panelSoft,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: accent.withOpacity(0.20),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Row ${row.rowNumber} • ${data['name']}',
                                            style: TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                              color: accent.withOpacity(0.20),
                                            ),
                                          ),
                                          child: Text(
                                            badgeText,
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${data['barcode']} • ${data['category']}',
                                      style: TextStyle(
                                        color: _textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Sell Rs. ${(data['selling_price'] as num).toStringAsFixed(2)} | ${(data['quantity_type'] ?? 'unit').toString()} (${data['unit_label']}) | Stock ${data['stock']} | Min ${data['min_stock_level']}',
                                      style: TextStyle(
                                        color: _textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (!row.isValid) ...[
                                      const SizedBox(height: 10),
                                      ...row.errors.map(
                                        (error) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Text(
                                            '• $error',
                                            style: TextStyle(
                                              color: _dangerColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: isImporting || validRows.isEmpty
                        ? null
                        : () async {
                            final confirmed = await _confirmAction(
                              title: 'Confirm Bulk Upload',
                              message:
                                  'Import ${validRows.length} valid rows? ${createCount > 0 ? '$createCount will be created. ' : ''}${updateCount > 0 ? '$updateCount will be updated.' : ''}',
                              confirmText: 'Import',
                            );
                            if (!confirmed) return;

                            setPopupState(() {
                              isImporting = true;
                            });

                            try {
                              final result = await DatabaseHelper.instance
                                  .bulkUpsertProductsLocal(
                                rows: validRows
                                    .map((row) => row.data)
                                    .toList(),
                                changedBy: changedBy,
                              );
                              if (!dialogContext.mounted) return;
                              Navigator.pop(
                                dialogContext,
                                (result['created'] as int) +
                                        (result['updated'] as int) >
                                    0,
                              );
                            } catch (e) {
                              setPopupState(() {
                                isImporting = false;
                              });
                              if (!dialogContext.mounted) return;
                              AppSnackBar.show(
                                dialogContext,
                                message:
                                    e.toString().replaceFirst('Exception: ', ''),
                              );
                            }
                          },
                    icon: isImporting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_check_circle_rounded),
                    label: Text(
                      isImporting ? 'Importing...' : 'Import Valid Rows',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (imported == true) {
      await _loadData(showLoader: false);
      _showMessage('Bulk upload completed successfully.');
    }
  }

  Future<void> _openReceiveFlow({Product? initialProduct}) async {
    final product = initialProduct ??
        await _pickProduct(title: 'Select a product to receive');
    if (product == null || !mounted) return;

    final mappings = await DatabaseHelper.instance.getMappingsForProduct(
      product.barcode,
    );
    if (mappings.isEmpty) {
      _showMessage(
        'No supplier is assigned to this product yet. Assign a supplier first before receiving stock.',
        isError: true,
      );
      return;
    }

    final suppliers = await DatabaseHelper.instance.getMappedSuppliersForProduct(
      product.barcode,
    );
    if (suppliers.isEmpty) {
      _showMessage(
        'Mapped suppliers for this product could not be loaded. Check supplier mappings and try again.',
        isError: true,
      );
      return;
    }

    final mappingBySupplierId = {
      for (final mapping in mappings) mapping.supplierId: mapping,
    };
    final preferredMapping = mappings.firstWhere(
      (mapping) => mapping.isPreferred,
      orElse: () => mappings.first,
    );

    final approval = await _requireManagerApproval(
      actionLabel: 'receive stock for ${product.name}',
      description:
          'Approved stock receive for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final qtyController = TextEditingController();
    final preferredCost = preferredMapping.defaultUnitCost > 0
        ? preferredMapping.defaultUnitCost
        : product.costPrice;
    final costController = TextEditingController(
      text: preferredCost > 0 ? preferredCost.toStringAsFixed(2) : '',
    );
    final noteController = TextEditingController();
    final isWeighted = product.quantityType == ProductQuantityType.weight;
    final quantityLabel = isWeighted
        ? 'Received ${product.unitLabel.trim().isEmpty ? 'weight' : product.unitLabel.trim()}'
        : 'Received quantity';
    int? selectedSupplierId = preferredMapping.supplierId;
    bool setAsPrimary = false;

    final saved = await _showInventoryPopup<bool>(
      icon: Icons.inventory_2_rounded,
      title: 'Receive Stock',
      subtitle: '${product.name} • ${product.barcode}',
      maxWidth: 760,
      bodyBuilder: (dialogContext, setPopupState) {
        final selectedSupplier = selectedSupplierId == null
            ? null
            : suppliers
                .where((supplier) => supplier.id == selectedSupplierId)
                .cast<PosSupplier?>()
                .firstOrNull;
        final selectedMapping = selectedSupplierId == null
            ? null
            : mappingBySupplierId[selectedSupplierId];

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildPopupMetricCard(
                    title: 'Current stock',
                    value: _formatProductQuantity(product, product.stock),
                    icon: Icons.layers_outlined,
                    accent: _accentBlue,
                  ),
                  _buildPopupMetricCard(
                    title: 'Preferred cost',
                    value: 'Rs. ${preferredCost.toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                    accent: _brandColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: selectedSupplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: suppliers
                    .map(
                      (supplier) => DropdownMenuItem<int>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final mapping = mappingBySupplierId[value];
                  setPopupState(() {
                    selectedSupplierId = value;
                    setAsPrimary = value != preferredMapping.supplierId;
                    final mappedCost = mapping?.defaultUnitCost ?? 0;
                    final resolvedCost =
                        mappedCost > 0 ? mappedCost : product.costPrice;
                    costController.text = resolvedCost > 0
                        ? resolvedCost.toStringAsFixed(2)
                        : '';
                  });
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Only suppliers already linked to this product are shown here.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (selectedSupplier != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: _softDecoration(color: _panelSoft, radius: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedSupplier.name,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selectedSupplier.phone.trim().isEmpty
                            ? 'Phone not available'
                            : 'Phone • ${selectedSupplier.phone.trim()}',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (selectedMapping != null &&
                          selectedMapping.defaultUnitCost > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Mapped cost • Rs. ${selectedMapping.defaultUnitCost.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: isWeighted,
                      ),
                      inputFormatters: [
                        isWeighted
                            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                            : FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: quantityLabel,
                        helperText: isWeighted
                            ? 'Enter the received ${product.unitLabel}. Example: 2.5'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: costController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Unit cost (optional)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _softDecoration(color: _panelSoft, radius: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Set as primary supplier',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selectedSupplierId == preferredMapping.supplierId
                                ? 'This supplier is already the primary supplier for this product.'
                                : 'Use this supplier as the default option for future receive entries.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: setAsPrimary,
                      onChanged: selectedSupplierId == null ||
                              selectedSupplierId == preferredMapping.supplierId
                          ? null
                          : (value) {
                              setPopupState(() {
                                setAsPrimary = value;
                              });
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (selectedSupplierId == null) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Select a mapped supplier first.',
                          );
                          return;
                        }

                        final qtyError = _validateQuantityInput(
                          qtyController.text,
                          label: 'quantity',
                          quantityType: product.quantityType,
                        );
                        if (qtyError != null) {
                          AppSnackBar.show(dialogContext, message: qtyError);
                          return;
                        }

                        final rawCost = costController.text.trim();
                        if (rawCost.isNotEmpty) {
                          final costError = _validateNonNegativeMoney(
                            rawCost,
                            label: 'unit cost',
                          );
                          if (costError != null) {
                            AppSnackBar.show(dialogContext, message: costError);
                            return;
                          }
                        }

                        final supplier = suppliers.firstWhere(
                          (item) => item.id == selectedSupplierId,
                        );
                        final selectedMapping = mappingBySupplierId[selectedSupplierId];
                        if (selectedMapping == null) {
                          AppSnackBar.show(
                            dialogContext,
                            message:
                                'This supplier is not linked to the selected product.',
                          );
                          return;
                        }

                        final qty = _parseQuantityInput(
                          qtyController.text,
                          product.quantityType,
                        );
                        final unitCost =
                            rawCost.isEmpty ? null : double.parse(rawCost);
                        final resolvedCost = unitCost ??
                            (selectedMapping.defaultUnitCost > 0
                                ? selectedMapping.defaultUnitCost
                                : product.costPrice);

                        final confirmed = await _confirmAction(
                          title: 'Confirm Stock Receive',
                          message:
                              'Receive ${_formatProductQuantity(product, qty)} of ${product.name} from ${supplier.name}? This will increase stock immediately.',
                          confirmText: 'Receive',
                        );
                        if (!confirmed) return;

                        final success = await DatabaseHelper.instance
                            .receiveStockLocal(
                          product.barcode,
                          qty,
                          unitCost: unitCost,
                          performedBy: changedBy,
                          reason: noteController.text.trim(),
                          supplierId: supplier.id,
                          supplierName: supplier.name,
                        );

                        if (!success) {
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, false);
                          return;
                        }

                        await DatabaseHelper.instance.insertStockReceipt(
                          barcode: product.barcode,
                          productName: product.name,
                          quantity: qty,
                          supplierId: supplier.id,
                          supplierName: supplier.name,
                          cost: resolvedCost,
                          referenceNote: noteController.text.trim(),
                          cashierName: changedBy,
                          backendStatus: 'local',
                        );

                        if (setAsPrimary) {
                          await DatabaseHelper.instance.upsertSupplierProductMapping(
                            selectedMapping.copyWith(
                              isPreferred: true,
                              defaultUnitCost: resolvedCost,
                              updatedAt: DateTime.now().toIso8601String(),
                            ),
                          );
                        } else if (resolvedCost > 0 &&
                            resolvedCost != selectedMapping.defaultUnitCost) {
                          await DatabaseHelper.instance.upsertSupplierProductMapping(
                            selectedMapping.copyWith(
                              defaultUnitCost: resolvedCost,
                              updatedAt: DateTime.now().toIso8601String(),
                            ),
                          );
                        }

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, true);
                      },
                      icon: const Icon(Icons.inventory_2_rounded),
                      label: const Text('Save Receive Entry'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    _disposeControllersNextFrame([
      qtyController,
      costController,
      noteController,
    ]);

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Stock received successfully.');
    } else if (saved == false) {
      _showMessage('Could not save stock receive entry.', isError: true);
    }
  }

  Future<void> _showSupplierInfoSheet(Product product) async {
    final preferredMapping =
        await DatabaseHelper.instance.getPreferredSupplierMapping(product.barcode);
    final suppliers = await DatabaseHelper.instance.getSuppliers();
    final currentSupplier = preferredMapping == null
        ? null
        : suppliers
            .where((supplier) => supplier.id == preferredMapping.supplierId)
            .cast<PosSupplier?>()
            .firstOrNull;
    final receipts = preferredMapping == null
        ? []
        : await DatabaseHelper.instance.getStockReceipts(
            supplierId: preferredMapping.supplierId,
            search: product.barcode,
            limit: 20,
          );
    final dynamic lastReceipt = receipts.isEmpty ? null : receipts.first;

    if (!mounted) return;

    await _showInventoryPopup<void>(
      icon: Icons.local_shipping_outlined,
      title: 'Supplier Info',
      subtitle: '${product.name} • ${product.barcode}',
      maxWidth: 720,
      maxHeightFactor: 0.72,
      bodyBuilder: (dialogContext, setPopupState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentSupplier == null)
                _buildPopupHintCard(
                  icon: Icons.info_outline_rounded,
                  title: 'No supplier assigned yet',
                  message:
                      'Assign a preferred supplier so receiving stock becomes faster and supplier history stays linked to this product.',
                  accent: _warningColor,
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: _softDecoration(color: _panelSoft, radius: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _brandSoft,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.factory_outlined,
                              color: _brandColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSupplier.name,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  currentSupplier.phone.trim().isEmpty
                                      ? 'Phone not available'
                                      : 'Phone • ${currentSupplier.phone.trim()}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _brandSoft,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _brandColor.withOpacity(0.24),
                              ),
                            ),
                            child: Text(
                              'Primary supplier',
                              style: TextStyle(
                                color: _brandColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildPopupMetricCard(
                            title: 'Default cost',
                            value: preferredMapping != null &&
                                    preferredMapping.defaultUnitCost > 0
                                ? 'Rs. ${preferredMapping.defaultUnitCost.toStringAsFixed(2)}'
                                : 'Not set',
                            icon: Icons.payments_outlined,
                            accent: const Color(0xFF8B5CF6),
                          ),
                          if (lastReceipt != null)
                            _buildPopupMetricCard(
                              title: 'Last cost',
                              value:
                                  'Rs. ${(((lastReceipt.cost as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                              icon: Icons.receipt_long_outlined,
                              accent: _accentBlue,
                            ),
                          if (lastReceipt != null)
                            _buildPopupMetricCard(
                              title: 'Last received',
                              value: _formatDateTime(
                                (lastReceipt.createdAt ?? '').toString(),
                              ),
                              icon: Icons.schedule_outlined,
                              accent: _warningColor,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await Future.delayed(const Duration(milliseconds: 120));
                      if (!mounted) return;
                      await _openReceiveFlow(initialProduct: product);
                    },
                    icon: const Icon(Icons.inventory_2_rounded),
                    label: const Text('Receive Stock'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final supplier = await _pickSupplierForProduct(product);
                      if (supplier == null || !mounted) return;
                      await DatabaseHelper.instance.upsertSupplierProductMapping(
                        SupplierProductMapping(
                          barcode: product.barcode,
                          productName: product.name,
                          supplierId: supplier.id,
                          supplierName: supplier.name,
                          isPreferred: true,
                          defaultUnitCost: product.costPrice,
                          minimumOrderQuantity: 1,
                          packSize: 1,
                          leadTimeDays: 0,
                          note: '',
                          updatedAt: DateTime.now().toIso8601String(),
                        ),
                      );
                      if (!mounted) return;
                      _showMessage('Supplier saved for ${product.name}.');
                      await _loadData(showLoader: false);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                    },
                    icon: const Icon(Icons.link_outlined),
                    label: Text(
                      currentSupplier == null
                          ? 'Assign Supplier'
                          : 'Change Supplier',
                    ),
                  ),
                  if (currentSupplier != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await Future.delayed(const Duration(milliseconds: 120));
                        if (!mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SupplierReceiveHistoryScreen(supplier: currentSupplier),
                          ),
                        );
                        if (!mounted) return;
                        await _loadData(showLoader: false);
                      },
                      icon: const Icon(Icons.history_outlined),
                      label: const Text('View History'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<PosSupplier?> _pickSupplierForProduct(Product product) async {
    final suppliers = await DatabaseHelper.instance.getSuppliers();
    if (suppliers.isEmpty) {
      _showMessage('No suppliers available. Add a supplier first.', isError: true);
      return null;
    }

    if (!mounted) return null;

    return showModalBottomSheet<PosSupplier>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        String localQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final visibleSuppliers = suppliers.where((supplier) {
              if (localQuery.trim().isEmpty) return true;
              final q = localQuery.trim().toLowerCase();
              return supplier.name.toLowerCase().contains(q) ||
                  supplier.phone.toLowerCase().contains(q) ||
                  supplier.id.toString().contains(q);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Supplier • ${product.name}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search supplier by name or phone',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            localQuery = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visibleSuppliers.isEmpty
                            ? const Center(
                                child: Text('No matching suppliers found.'),
                              )
                            : ListView.separated(
                                itemCount: visibleSuppliers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final supplier = visibleSuppliers[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    title: Text(
                                      supplier.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      supplier.phone.trim().isEmpty
                                          ? 'Phone not available'
                                          : 'Phone: ${supplier.phone.trim()}',
                                    ),
                                    onTap: () => Navigator.pop(context, supplier),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAdjustFlow({Product? initialProduct}) async {
    final product = initialProduct ??
        await _pickProduct(title: 'Select a product to adjust');
    if (product == null || !mounted) return;

    final approval = await _requireManagerApproval(
      actionLabel: 'adjust stock for ${product.name}',
      description:
          'Approved stock adjustment for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    final isWeighted = product.quantityType == ProductQuantityType.weight;
    final quantityLabel = isWeighted
        ? product.unitLabel.trim().isEmpty
            ? 'weight'
            : product.unitLabel.trim()
        : 'quantity';
    String adjustmentType = 'add';

    final saved = await _showInventoryPopup<bool>(
      icon: Icons.tune_rounded,
      title: 'Stock Adjustment',
      subtitle:
          '${product.name} • Current stock ${_formatProductQuantity(product, product.stock)}',
      maxWidth: 620,
      bodyBuilder: (dialogContext, setPopupState) {
        final previewQty =
            _tryParseQuantityInput(qtyController.text, product.quantityType) ?? 0.0;
        double resultingStock = product.stock;
        switch (adjustmentType) {
          case 'add':
            resultingStock = product.stock + previewQty;
            break;
          case 'remove':
            resultingStock = product.stock - previewQty;
            break;
          case 'set':
            resultingStock = previewQty;
            break;
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildPopupMetricCard(
                    title: 'Current stock',
                    value: _formatProductQuantity(product, product.stock),
                    icon: Icons.layers_outlined,
                    accent: _accentBlue,
                  ),
                  _buildPopupMetricCard(
                    title: 'After change',
                    value: _formatProductQuantity(product, resultingStock),
                    icon: Icons.timeline_rounded,
                    accent: resultingStock < 0 ? _dangerColor : _brandColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: adjustmentType,
                decoration: const InputDecoration(labelText: 'Adjustment type'),
                items: const [
                  DropdownMenuItem(value: 'add', child: Text('Add Stock')),
                  DropdownMenuItem(value: 'remove', child: Text('Remove Stock')),
                  DropdownMenuItem(value: 'set', child: Text('Set Exact Stock')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setPopupState(() {
                    adjustmentType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: isWeighted,
                ),
                inputFormatters: [
                  isWeighted
                      ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      : FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setPopupState(() {}),
                decoration: InputDecoration(
                  labelText: adjustmentType == 'set'
                      ? 'Final stock $quantityLabel'
                      : quantityLabel,
                  helperText: isWeighted
                      ? 'Weighted items can use decimals like 0.75.'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final qtyError = _validateQuantityInput(
                          qtyController.text,
                          label: adjustmentType == 'set'
                              ? 'final stock quantity'
                              : 'quantity',
                          allowZero: adjustmentType == 'set',
                          quantityType: product.quantityType,
                        );
                        if (qtyError != null) {
                          AppSnackBar.show(dialogContext, message: qtyError);
                          return;
                        }

                        final qty = _parseQuantityInput(
                          qtyController.text,
                          product.quantityType,
                        );
                        double resultingStock;
                        switch (adjustmentType) {
                          case 'add':
                            resultingStock = product.stock + qty;
                            break;
                          case 'remove':
                            resultingStock = product.stock - qty;
                            break;
                          case 'set':
                          default:
                            resultingStock = qty;
                            break;
                        }

                        if (resultingStock < 0) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Resulting stock cannot be negative.',
                          );
                          return;
                        }

                        final actionLabel = adjustmentType == 'add'
                            ? 'increase stock'
                            : adjustmentType == 'remove'
                                ? 'decrease stock'
                                : 'set exact stock';
                        final confirmed = await _confirmAction(
                          title: 'Confirm Stock Adjustment',
                          message:
                              'This will $actionLabel for ${product.name}. Final stock will be ${_formatProductQuantity(product, resultingStock)}.',
                          confirmText: 'Apply',
                        );
                        if (!confirmed) return;

                        final success = await DatabaseHelper.instance
                            .adjustStockLocal(
                          product.barcode,
                          adjustmentType: adjustmentType,
                          quantity: qty,
                          performedBy: changedBy,
                          reason: reasonController.text.trim(),
                        );

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, success);
                      },
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Save Adjustment'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    _disposeControllersNextFrame([
      qtyController,
      reasonController,
    ]);

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Stock adjusted successfully.');
    } else if (saved == false) {
      _showMessage('Could not save stock adjustment.', isError: true);
    }
  }

  Future<void> _openMinStockDialog(Product product) async {
    final approval = await _requireManagerApproval(
      actionLabel: 'update minimum stock for ${product.name}',
      description:
          'Approved minimum stock update for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final controller = TextEditingController(
      text: product.minStockLevel.toString(),
    );

    final changed = await _showInventoryPopup<bool>(
      icon: Icons.warning_amber_rounded,
      title: 'Update Minimum Stock',
      subtitle: '${product.name} • ${product.barcode}',
      maxWidth: 560,
      maxHeightFactor: 0.54,
      bodyBuilder: (dialogContext, setPopupState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPopupHintCard(
                icon: Icons.info_outline_rounded,
                title: 'Low-stock alert threshold',
                message:
                    'This value controls when the product appears as low stock across inventory and POS views.',
                accent: _warningColor,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildPopupMetricCard(
                    title: 'Current stock',
                    value: _formatProductQuantity(product, product.stock),
                    icon: Icons.inventory_2_outlined,
                    accent: _accentBlue,
                  ),
                  _buildPopupMetricCard(
                    title: 'Current minimum',
                    value: '${product.minStockLevel}',
                    icon: Icons.flag_outlined,
                    accent: _warningColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minimum stock level',
                  hintText: 'Enter the alert threshold',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final error = _validatePositiveInt(
                          controller.text,
                          label: 'minimum stock level',
                          allowZero: true,
                        );
                        if (error != null) {
                          _showMessage(error, isError: true);
                          return;
                        }
                        final value = int.parse(controller.text.trim());
                        final confirmed = await _confirmAction(
                          title: 'Confirm Minimum Stock Update',
                          message:
                              'Set minimum stock for ${product.name} to $value?',
                          confirmText: 'Save',
                        );
                        if (!confirmed) return;

                        final success = await DatabaseHelper.instance
                            .updateProductMinStockLevelLocal(
                          product.barcode,
                          value,
                          changedBy: changedBy,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, success);
                      },
                      child: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    _disposeControllersNextFrame([controller]);

    if (changed == true) {
      await _loadData(showLoader: false);
      _showMessage('Minimum stock updated.');
    } else if (changed == false) {
      _showMessage('Could not update minimum stock.', isError: true);
    }
  }

  Future<void> _openPriceChangeFlow({Product? initialProduct}) async {
    final product = initialProduct ??
        await _pickProduct(title: 'Select a product to change price');
    if (product == null || !mounted) return;

    final approval = await _requireManagerApproval(
      actionLabel: 'change prices for ${product.name}',
      description:
          'Approved price change for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

    final valueController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    String priceType = 'selling';
    bool saleEnabled = product.saleEnabled;

    final saved = await _showInventoryPopup<bool>(
      icon: Icons.sell_rounded,
      title: 'Change Price',
      subtitle: '${product.name} • ${product.barcode}',
      maxWidth: 660,
      bodyBuilder: (dialogContext, setPopupState) {
        void syncField() {
          switch (priceType) {
            case 'cost':
              valueController.text = product.costPrice.toStringAsFixed(2);
              break;
            case 'wholesale':
              valueController.text = product.wholesalePrice.toStringAsFixed(2);
              break;
            case 'sale':
              valueController.text =
                  (product.salePrice ?? product.sellingPrice).toStringAsFixed(2);
              saleEnabled = product.saleEnabled;
              break;
            case 'selling':
            default:
              valueController.text = product.sellingPrice.toStringAsFixed(2);
              break;
          }
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildPopupMetricCard(
                    title: 'Selling',
                    value: 'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                    icon: Icons.sell_outlined,
                    accent: _brandColor,
                  ),
                  _buildPopupMetricCard(
                    title: 'Wholesale',
                    value: 'Rs. ${product.wholesalePrice.toStringAsFixed(2)}',
                    icon: Icons.local_offer_outlined,
                    accent: Colors.deepPurple,
                  ),
                  _buildPopupMetricCard(
                    title: 'Sale',
                    value: product.salePrice == null
                        ? 'Not set'
                        : 'Rs. ${product.salePrice!.toStringAsFixed(2)}',
                    icon: Icons.discount_outlined,
                    accent: _warningColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: priceType,
                decoration: const InputDecoration(labelText: 'Price field'),
                items: const [
                  DropdownMenuItem(value: 'selling', child: Text('Selling Price')),
                  DropdownMenuItem(
                    value: 'wholesale',
                    child: Text('Wholesale Price'),
                  ),
                  DropdownMenuItem(value: 'sale', child: Text('Sale Price')),
                  DropdownMenuItem(value: 'cost', child: Text('Cost Price')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setPopupState(() {
                    priceType = value;
                    syncField();
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'New price'),
              ),
              if (priceType == 'sale') ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: _softDecoration(color: _panelSoft, radius: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sale price active',
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'If disabled, billing falls back to the normal selling price.',
                              style: TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: saleEnabled,
                        onChanged: (value) {
                          setPopupState(() {
                            saleEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Reason / note (optional)'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final priceError = _validateNonNegativeMoney(
                          valueController.text,
                          label: 'price',
                        );
                        if (priceError != null) {
                          AppSnackBar.show(dialogContext, message: priceError);
                          return;
                        }

                        final newPrice = double.parse(valueController.text.trim());
                        if (priceType == 'sale' && saleEnabled && newPrice <= 0) {
                          AppSnackBar.show(
                            dialogContext,
                            message: 'Active sale price must be greater than 0.',
                          );
                          return;
                        }

                        final confirmed = await _confirmAction(
                          title: 'Confirm Price Change',
                          message:
                              'Update ${product.name} ${priceType.toUpperCase()} price to Rs. ${newPrice.toStringAsFixed(2)}?',
                          confirmText: 'Update',
                        );
                        if (!confirmed) return;

                        final success = await DatabaseHelper.instance
                            .updateProductPriceLocal(
                          product.barcode,
                          newPrice,
                          priceType: priceType,
                          changedBy: changedBy,
                          reason: noteController.text.trim(),
                          saleEnabled: priceType == 'sale' ? saleEnabled : null,
                        );

                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, success);
                      },
                      icon: const Icon(Icons.sell_rounded),
                      label: const Text('Save Price Change'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    _disposeControllersNextFrame([
      valueController,
      noteController,
    ]);

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Price updated successfully.');
    } else if (saved == false) {
      _showMessage('Could not update price.', isError: true);
    }
  }



  Future<void> _openStockTakeScreen({String? barcode}) async {
    final approval = await _requireManagerApproval(
      actionLabel: 'open stock take',
      description: barcode == null || barcode.trim().isEmpty
          ? 'Approved stock take access requested by $_currentUserName'
          : 'Approved stock take access for barcode ${barcode.trim()} requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockTakeScreen(
          initialBarcode: barcode,
          performedByLabel: _buildPerformedByLabel(approval.approverName),
        ),
      ),
    );

    if (!mounted) return;
    await _loadData(showLoader: false);
  }

  Future<void> _openInventoryHistoryScreen({String? barcode}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryHistoryScreen(initialBarcode: barcode),
      ),
    );

    if (!mounted) return;
    await _loadData(showLoader: false);
  }

  Future<void> _openRecentActivitySheet({String? barcode}) async {
    final movements = await DatabaseHelper.instance.getInventoryMovements(
      limit: 100,
      barcode: barcode,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    barcode == null ? 'Inventory Activity' : 'Product Activity',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: movements.isEmpty
                        ? const Center(
                            child: Text('No inventory activity found.'),
                          )
                        : ListView.separated(
                            itemCount: movements.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final movement = movements[index];
                              return _buildMovementTile(movement);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openProductDetail(Product product) async {
    final movements = await DatabaseHelper.instance.getInventoryMovements(
      limit: 8,
      barcode: product.barcode,
    );

    if (!mounted) return;

    await _showInventoryPopup<void>(
      icon: Icons.inventory_2_outlined,
      title: product.name,
      subtitle:
          '${product.barcode} • ${product.category} • ${product.quantityType.label} (${product.unitLabel})',
      maxWidth: 980,
      maxHeightFactor: 0.90,
      bodyBuilder: (dialogContext, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(product),
                if (product.wholesalePrice > 0 &&
                    product.wholesalePrice != product.sellingPrice)
                  _buildPriceAvailabilityChip(
                    'Wholesale active',
                    Colors.deepPurple,
                  ),
                if (product.hasSalePrice)
                  _buildPriceAvailabilityChip(
                    'Sale active',
                    _warningColor,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _buildProductDetailMetrics(product),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _openReceiveFlow(initialProduct: product);
                  },
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: const Text('Receive'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _openAdjustFlow(initialProduct: product);
                  },
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Adjust'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _openPriceChangeFlow(initialProduct: product);
                  },
                  icon: const Icon(Icons.sell_rounded),
                  label: const Text('Change Price'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _openEditProductFlow(product);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Item'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _deleteProduct(product);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _openStockTakeScreen(barcode: product.barcode);
                  },
                  icon: const Icon(Icons.playlist_add_check_circle_rounded),
                  label: const Text('Count'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _openMinStockDialog(product);
                  },
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Min Stock'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 120));
                    if (!mounted) return;
                    await _showSupplierInfoSheet(product);
                  },
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Supplier Info'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'Recent activity',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Future.delayed(const Duration(milliseconds: 120), () {
                      if (!mounted) return;
                      _openInventoryHistoryScreen(barcode: product.barcode);
                    });
                  },
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: movements.isEmpty
                  ? Center(
                      child: Text(
                        'No stock or price movement yet.',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final movement = movements[index];
                        return _buildMovementTile(movement);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(color: _panelColor, radius: 20),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(_isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 22),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
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

  Widget _buildQuickActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: _brandColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required InventoryFilter filter,
  }) {
    final isSelected = _selectedFilter == filter;
    final tone = isSelected ? _brandColor : _textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _selectedFilter = filter;
          });
        },
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _brandSoft : _inputFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? _brandColor : _borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(Product product) {
    late final Color color;
    late final Color background;
    late final String label;

    if (!product.isActive) {
      color = _textSecondary;
      background = _panelSoft;
      label = 'Inactive';
    } else if (product.isOutOfStock) {
      color = _dangerColor;
      background = _dangerSoft;
      label = 'Out of stock';
    } else if (product.isLowStock) {
      color = _warningColor;
      background = _warningSoft;
      label = 'Low stock';
    } else {
      color = _successColor;
      background = _successSoft;
      label = 'In stock';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildPriceAvailabilityChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, String value) {
    return Container(
      width: 146,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementTile(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();

    String subtitle = _movementSubtitleSafe(movement);
    String trailing = _movementTrailingSafe(movement);
    Color accent = _accentBlue;
    IconData icon = Icons.history_rounded;

    if (actionType.contains('deleted')) {
      accent = _dangerColor;
      icon = Icons.delete_outline_rounded;
    } else if (actionType.contains('product_')) {
      accent = _accentBlue;
      icon = Icons.inventory_2_outlined;
    } else if (actionType.contains('receive')) {
      accent = _successColor;
      icon = Icons.inventory_2_rounded;
    } else if (actionType.contains('adjust')) {
      accent = _warningColor;
      icon = Icons.tune_rounded;
    } else if (actionType.contains('price')) {
      accent = const Color(0xFF8B5CF6);
      icon = Icons.sell_outlined;
    } else if (actionType.contains('sale')) {
      accent = _brandColor;
      icon = Icons.point_of_sale_rounded;
    } else if (actionType.contains('refund')) {
      accent = _dangerColor;
      icon = Icons.restart_alt_rounded;
    }


    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(_isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _movementTitle(actionType),
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  (movement['product_name'] ?? 'Unknown product').toString(),
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 132,
            child: Text(
              trailing,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
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

    return pieces.join(' • ');
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
        'Rs. ${_asDouble(oldPrice).toStringAsFixed(2)} -> Rs. ${_asDouble(newPrice).toStringAsFixed(2)}',
      );
    } else if (stockBefore != null || stockAfter != null) {
      final beforeLabel = stockBefore == null ? '-' : _formatQuantity(_asDouble(stockBefore));
      final afterLabel = stockAfter == null ? '-' : _formatQuantity(_asDouble(stockAfter));
      pieces.add('$beforeLabel -> $afterLabel');
    }

    if (reason.isNotEmpty) {
      pieces.add(reason);
    }

    if (performedBy.isNotEmpty) {
      pieces.add(performedBy);
    }

    return pieces.join(' - ');
  }

  String _movementTrailingSafe(Map<String, dynamic> movement) {
    final quantityChange = (movement['quantity_change'] as num?)?.toDouble();
    final newPrice = (movement['new_price'] as num?)?.toDouble();
    final baseTrailing = _formatDateTime(movement['created_at']?.toString());


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

  Color _shadeColor(Color color) {
    return color;
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return isoString;

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }


  Widget _buildActionIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(10),
            decoration: _softDecoration(color: _panelSoft, radius: 14),
            child: Icon(icon, size: 18, color: iconColor ?? _textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_panelAlt, _panelColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _shadowColor,
            blurRadius: _isDark ? 28 : 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildActionIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBulkDeleteMode ? 'Bulk Delete Inventory' : 'Inventory Workspace',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isBulkDeleteMode
                      ? 'Select products to remove, then confirm the bulk delete action.'
                      : 'Manage products, stock receiving, pricing, and inventory activity from one place.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_isBulkDeleteMode) ...[
            _buildPriceAvailabilityChip(
              '${_selectedProductBarcodes.length} selected',
              _dangerColor,
            ),
            const SizedBox(width: 10),
          ],
          _buildActionIconButton(
            icon: _isRefreshing ? Icons.sync_rounded : Icons.refresh_rounded,
            tooltip: 'Refresh inventory',
            onTap: _isRefreshing ? null : _refresh,
            iconColor: _isRefreshing ? _brandColor : _brandColor,
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(Product product) {
    final isSelectedForDelete = _selectedProductBarcodes.contains(product.barcode);
    final statusColor = product.isOutOfStock
        ? _dangerColor
        : (product.isLowStock ? _warningColor : _brandColor);
    final statusSoft = product.isOutOfStock
        ? _dangerSoft
        : (product.isLowStock ? _warningSoft : _brandSoft);

    Widget statPill({
      required String label,
      required String value,
      Color? accent,
    }) {
      final tone = accent ?? _accentBlue;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                color: tone,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    Widget miniAction({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      required Color iconColor,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _panelAlt,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_isBulkDeleteMode) {
            _toggleProductSelection(product);
          } else {
            _openProductDetail(product);
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _panelSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelectedForDelete ? _dangerColor : _borderColor,
              width: isSelectedForDelete ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isBulkDeleteMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Checkbox(
                    value: isSelectedForDelete,
                    onChanged: (_) => _toggleProductSelection(product),
                    activeColor: _dangerColor,
                  ),
                ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${product.barcode} • ${product.category}',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildStatusChip(product),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 112,
                          child: statPill(
                            label: 'Stock',
                            value: _formatProductQuantity(product, product.stock),
                            accent: _textPrimary,
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: statPill(
                            label: 'Selling',
                            value: _formatCurrency(product.sellingPrice),
                            accent: _brandColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (product.wholesalePrice > 0 &&
                            product.wholesalePrice != product.sellingPrice)
                          _buildPriceAvailabilityChip('Wholesale active', const Color(0xFF8B5CF6)),
                        if (product.hasSalePrice)
                          _buildPriceAvailabilityChip('Sale active', _warningColor),
                        if (!product.isActive)
                          _buildPriceAvailabilityChip('Inactive item', _textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isBulkDeleteMode) ...[
                const SizedBox(width: 12),
                Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        miniAction(
                          icon: Icons.inventory_2_rounded,
                          tooltip: 'Receive stock',
                          onTap: () => _openReceiveFlow(initialProduct: product),
                          iconColor: _brandColor,
                        ),
                        const SizedBox(width: 8),
                        miniAction(
                          icon: Icons.tune_rounded,
                          tooltip: 'Adjust stock',
                          onTap: () => _openAdjustFlow(initialProduct: product),
                          iconColor: _warningColor,
                        ),
                        const SizedBox(width: 8),
                        miniAction(
                          icon: Icons.sell_outlined,
                          tooltip: 'Change price',
                          onTap: () => _openPriceChangeFlow(initialProduct: product),
                          iconColor: const Color(0xFF8B5CF6),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          tooltip: 'More actions',
                          onSelected: (value) => _handleProductMenuAction(value, product),
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Text('Edit Item'),
                            ),
                            PopupMenuItem<String>(
                              value: 'history',
                              child: Text('View History'),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text(
                                'Delete Item',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _panelAlt,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleProducts = _filteredProducts;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: _brandColor,
          backgroundColor: _panelColor,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_screenBackground, _screenBackgroundAlt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Products',
                        value: _activeProductCount.toString(),
                        icon: Icons.inventory_2_outlined,
                        accent: _accentBlue,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Low Stock',
                        value: _lowStockCount.toString(),
                        icon: Icons.warning_amber_rounded,
                        accent: _warningColor,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Out of Stock',
                        value: _outOfStockCount.toString(),
                        icon: Icons.remove_shopping_cart_rounded,
                        accent: _dangerColor,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Stock Value',
                        value: 'Rs. ${_stockValue.toStringAsFixed(2)}',
                        icon: Icons.payments_outlined,
                        accent: _successColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _panelDecoration(color: _panelColor),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(color: _textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search by name, barcode, or category',
                                hintStyle: TextStyle(color: _textSecondary),
                                prefixIcon: Icon(Icons.search_rounded, color: _mutedIcon),
                                suffixIcon: _searchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                        icon: Icon(Icons.close_rounded, color: _mutedIcon),
                                      ),
                                filled: true,
                                fillColor: _inputFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: _borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: _borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: _brandColor, width: 1.4),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildActionIconButton(
                            icon: Icons.history_rounded,
                            tooltip: 'View full history',
                            onTap: () => _openInventoryHistoryScreen(),
                            iconColor: _accentBlue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFilterChip(label: 'All', filter: InventoryFilter.all),
                          _buildFilterChip(label: 'In Stock', filter: InventoryFilter.inStock),
                          _buildFilterChip(label: 'Low Stock', filter: InventoryFilter.lowStock),
                          _buildFilterChip(label: 'Out of Stock', filter: InventoryFilter.outOfStock),
                          _buildFilterChip(label: 'Inactive', filter: InventoryFilter.inactive),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildQuickActionButton(
                            title: 'Add Product',
                            icon: Icons.add_box_outlined,
                            onTap: () => _openAddProductFlow(),
                          ),
                          _buildQuickActionButton(
                            title: 'Bulk Upload',
                            icon: Icons.upload_file_outlined,
                            onTap: () => _openBulkUploadFlow(),
                          ),
                          _buildQuickActionButton(
                            title: _isBulkDeleteMode ? 'Exit Bulk Delete' : 'Bulk Delete',
                            icon: _isBulkDeleteMode ? Icons.close_rounded : Icons.delete_outline_rounded,
                            onTap: _isBulkDeleteMode ? _exitBulkDeleteMode : _enterBulkDeleteMode,
                          ),
                          _buildQuickActionButton(
                            title: 'Receive Stock',
                            icon: Icons.inventory_2_rounded,
                            onTap: () => _openReceiveFlow(),
                          ),
                          _buildQuickActionButton(
                            title: 'Adjust Stock',
                            icon: Icons.tune_rounded,
                            onTap: () => _openAdjustFlow(),
                          ),
                          _buildQuickActionButton(
                            title: 'Change Price',
                            icon: Icons.sell_outlined,
                            onTap: () => _openPriceChangeFlow(),
                          ),
                          _buildQuickActionButton(
                            title: 'Count Stock',
                            icon: Icons.playlist_add_check_circle_outlined,
                            onTap: () => _openStockTakeScreen(),
                          ),
                        ],
                      ),
                      if (_isBulkDeleteMode) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _dangerSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _dangerColor.withOpacity(0.24)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedProductBarcodes.isEmpty
                                      ? 'Bulk delete mode is active. Select items to remove.'
                                      : '${_selectedProductBarcodes.length} product(s) selected for deletion.',
                                  style: TextStyle(
                                    color: _dangerColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                onPressed: visibleProducts.isEmpty ? null : _toggleSelectAllVisibleProducts,
                                child: Text(_allVisibleProductsSelected ? 'Clear All' : 'Select All'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _selectedProductBarcodes.isEmpty ? null : _confirmBulkDeleteSelected,
                                style: ElevatedButton.styleFrom(backgroundColor: _dangerColor),
                                child: const Text('Delete Selected'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _panelDecoration(color: _panelColor),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _isBulkDeleteMode
                                ? 'Select Products to Delete (${_selectedProductBarcodes.length})'
                                : 'Inventory Products',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${visibleProducts.length} shown',
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isBulkDeleteMode
                            ? 'Tap rows to select or deselect products from the current filtered list.'
                            : 'Open a product to manage stock, prices, supplier details, and recent movement.',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (visibleProducts.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: _panelAlt,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 40, color: _mutedIcon),
                              const SizedBox(height: 12),
                              Text(
                                'No products match the current filter.',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...visibleProducts.map(
                          (product) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildProductRow(product),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _panelDecoration(color: _panelColor),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Recent Inventory Activity',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _openInventoryHistoryScreen(),
                            child: const Text('View all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_recentMovements.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _panelAlt,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Text(
                            'No recent stock or price activity yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        ..._recentMovements.map(
                          (movement) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildMovementTile(movement),
                          ),
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

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}



