import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pos_supplier.dart';
import '../models/stock_receipt_record.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/supplier_service.dart';
import '../widgets/app_snackbar.dart';
import 'supplier_receive_history_screen.dart';

class SupplierManagementScreen extends StatefulWidget {
  const SupplierManagementScreen({
    super.key,
    required this.cashierName,
  });

  final String cashierName;

  @override
  State<SupplierManagementScreen> createState() =>
      _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  final SupplierService _supplierService = SupplierService();
  final TextEditingController _supplierSearchController =
      TextEditingController();

  bool _isLoading = true;
  bool _isRefreshing = false;

  List<PosSupplier> _suppliers = const [];
  List<StockReceiptRecord> _history = const [];
  Map<String, dynamic> _historySummary = const {};
  Map<int, int> _linkedCounts = const {};

  @override
  void initState() {
    super.initState();
    _loadAll(refreshFromBackend: false);
  }

  @override
  void dispose() {
    _supplierSearchController.dispose();
    super.dispose();
  }

  SupplierModulePalette get _ui => SupplierModulePalette.of(context);

  bool get _hasManagementAccess =>
      context.read<AuthProvider>().hasManagementAccess;

  Future<void> _loadAll({bool refreshFromBackend = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final suppliers = await _supplierService.getSuppliers(
        refreshFromBackend: refreshFromBackend,
        search: _supplierSearchController.text.trim(),
      );
      final linkedCounts =
          await _supplierService.getLinkedProductCountsBySupplier();
      final history = await _supplierService.getReceiveHistory();
      final historySummary = await _supplierService.getReceiveSummary();

      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _linkedCounts = linkedCounts;
        _history = history;
        _historySummary = historySummary;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadAll(refreshFromBackend: false);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: isError ? _ui.danger : _ui.brand,
    );
  }

  String _formatDateTime(String raw) {
    if (raw.trim().isEmpty) return 'No activity yet';
    try {
      final date = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
      final suffix = date.hour >= 12 ? 'PM' : 'AM';
      return '${two(date.day)}/${two(date.month)}/${date.year}  $hour:${two(date.minute)} $suffix';
    } catch (_) {
      return raw;
    }
  }

  String _formatCurrency(num value) =>
      'Rs. ${value.toDouble().toStringAsFixed(2)}';

  StockReceiptRecord? _lastReceiptForSupplier(int supplierId) {
    for (final receipt in _history) {
      if (receipt.supplierId == supplierId) {
        return receipt;
      }
    }
    return null;
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? labelText,
    IconData? icon,
    Widget? suffixIcon,
    SupplierModulePalette? palette,
  }) {
    final ui = palette ?? _ui;
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: ui.textMuted),
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
      labelStyle: TextStyle(color: ui.textSecondary),
      hintStyle: TextStyle(color: ui.textMuted),
      isDense: true,
    );
  }

  Future<void> _showSupplierFormDialog({PosSupplier? supplier}) async {
    final isEdit = supplier != null;
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final ui = SupplierModulePalette.of(dialogContext);
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  decoration: BoxDecoration(
                    color: ui.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: ui.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(ui.isDark ? 0.34 : 0.08),
                        blurRadius: 36,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: ui.borderStrong,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: ui.brandSoft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                isEdit
                                    ? Icons.edit_outlined
                                    : Icons.add_business_outlined,
                                color: ui.brand,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEdit ? 'Edit Supplier' : 'Add Supplier',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: ui.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isEdit
                                        ? 'Update supplier contact details and identity.'
                                        : 'Create a supplier record for product linking and receive history.',
                                    style: TextStyle(
                                      color: ui.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              icon: Icon(Icons.close_rounded, color: ui.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: nameController,
                          enabled: !isSubmitting,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            hintText: 'Enter supplier name',
                            labelText: 'Supplier Name',
                            icon: Icons.local_shipping_outlined,
                            palette: ui,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: phoneController,
                          enabled: !isSubmitting,
                          keyboardType: TextInputType.phone,
                          decoration: _fieldDecoration(
                            hintText: 'Phone number',
                            labelText: 'Phone',
                            icon: Icons.phone_outlined,
                            palette: ui,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ui.surfaceSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: ui.border),
                          ),
                          child: Text(
                            'Tip: keeping supplier names clean and phone numbers consistent helps product linking and stock receive history stay easy to track.',
                            style: TextStyle(
                              color: ui.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ui.textPrimary,
                                  side: BorderSide(color: ui.borderStrong),
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        final name = nameController.text.trim();
                                        final phone = phoneController.text.trim();
                                        if (name.isEmpty) {
                                          _showMessage(
                                            'Supplier name is required.',
                                            isError: true,
                                          );
                                          return;
                                        }

                                        setDialogState(() {
                                          isSubmitting = true;
                                        });

                                        try {
                                          if (isEdit) {
                                            await _supplierService.updateSupplier(
                                              supplierId: supplier.id,
                                              name: name,
                                              phone: phone,
                                            );
                                          } else {
                                            await _supplierService.createSupplier(
                                              name: name,
                                              phone: phone,
                                            );
                                          }

                                          if (dialogContext.mounted) {
                                            Navigator.of(dialogContext).pop();
                                          }
                                          if (!mounted) return;
                                          await _loadAll(refreshFromBackend: false);
                                          _showMessage(
                                            isEdit
                                                ? 'Supplier updated successfully.'
                                                : 'Supplier created successfully.',
                                          );
                                        } catch (e) {
                                          if (mounted) {
                                            _showMessage(
                                              e.toString().replaceFirst('Exception: ', ''),
                                              isError: true,
                                            );
                                          }
                                        } finally {
                                          if (dialogContext.mounted) {
                                            setDialogState(() {
                                              isSubmitting = false;
                                            });
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ui.brand,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: isSubmitting
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        isEdit ? 'Save Changes' : 'Create Supplier',
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
      },
    );
  }

  Future<void> _openAssignProductsSheet(PosSupplier supplier) async {
    final products = await DatabaseHelper.instance.getProducts();
    final mappings = await _supplierService.getSupplierProductMappings(
      supplierId: supplier.id,
      limit: 5000,
    );

    if (!mounted) return;

    final currentMappings = {
      for (final mapping in mappings) mapping.barcode: mapping,
    };
    final searchController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ui = SupplierModulePalette.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchController.text.trim().toLowerCase();
            final visibleProducts = products.where((product) {
              if (query.isEmpty) return true;
              return product.name.toLowerCase().contains(query) ||
                  product.barcode.toLowerCase().contains(query) ||
                  product.category.toLowerCase().contains(query);
            }).toList();

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
                child: Container(
                  decoration: BoxDecoration(
                    color: ui.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: ui.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(ui.isDark ? 0.34 : 0.08),
                        blurRadius: 36,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: ui.borderStrong,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: ui.blueSoft,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(Icons.link_rounded, color: ui.blue),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Assign Products',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: ui.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Set ${supplier.name} as the preferred supplier for selected products.',
                                  style: TextStyle(
                                    color: ui.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: searchController,
                        decoration: _fieldDecoration(
                          hintText: 'Search by name, barcode, or category',
                          icon: Icons.search_rounded,
                          palette: ui,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: visibleProducts.isEmpty
                            ? Center(
                                child: Text(
                                  'No matching products found.',
                                  style: TextStyle(
                                    color: ui.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: visibleProducts.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: ui.border),
                                itemBuilder: (context, index) {
                                  final product = visibleProducts[index];
                                  final mapping = currentMappings[product.barcode];
                                  final isAssigned = mapping != null;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                product.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: ui.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    product.barcode,
                                                    style: TextStyle(
                                                      color: ui.textSecondary,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  _buildMetaDivider(ui),
                                                  Text(
                                                    product.category,
                                                    style: TextStyle(
                                                      color: ui.textSecondary,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  _buildMetaDivider(ui),
                                                  Text(
                                                    'Stock ${product.stock}',
                                                    style: TextStyle(
                                                      color: ui.textSecondary,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        if (isAssigned)
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              if (mapping.id == null) return;
                                              await _supplierService.deleteSupplierProductMapping(
                                                mapping.id!,
                                              );
                                              currentMappings.remove(product.barcode);
                                              setDialogState(() {});
                                            },
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: ui.warning,
                                              side: BorderSide(color: ui.warning.withOpacity(0.35)),
                                            ),
                                            icon: const Icon(Icons.link_off_rounded),
                                            label: const Text('Assigned'),
                                          )
                                        else
                                          ElevatedButton.icon(
                                            onPressed: () async {
                                              await _supplierService.assignProductToSupplier(
                                                supplier: supplier,
                                                product: product,
                                                isPreferred: true,
                                                defaultUnitCost: product.costPrice,
                                              );
                                              final refreshed =
                                                  await _supplierService.getPreferredSupplierMapping(
                                                product.barcode,
                                              );
                                              if (refreshed != null) {
                                                currentMappings[product.barcode] = refreshed;
                                              }
                                              setDialogState(() {});
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: ui.brand,
                                              foregroundColor: Colors.white,
                                            ),
                                            icon: const Icon(Icons.link_rounded),
                                            label: const Text('Assign'),
                                          ),
                                      ],
                                    ),
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

    searchController.dispose();
    await _loadAll(refreshFromBackend: false);
  }

  Future<void> _openLinkedProductsSheet(PosSupplier supplier) async {
    final rows = await _supplierService.getLinkedProductsForSupplier(supplier.id);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ui = SupplierModulePalette.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
            child: Container(
              decoration: BoxDecoration(
                color: ui.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: ui.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(ui.isDark ? 0.34 : 0.08),
                    blurRadius: 36,
                    offset: const Offset(0, 22),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ui.borderStrong,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: ui.purpleSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.inventory_2_outlined, color: ui.purple),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Linked Products',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: ui.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Products currently assigned to ${supplier.name}.',
                              style: TextStyle(
                                color: ui.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: rows.isEmpty
                        ? Center(
                            child: Text(
                              'No linked products yet.',
                              style: TextStyle(
                                color: ui.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: ui.border),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final isPrimary = (((row['is_preferred'] as num?) ?? 0).toInt() == 1);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (row['product_name'] ?? 'Product').toString(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: ui.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                (row['barcode'] ?? '').toString(),
                                                style: TextStyle(
                                                  color: ui.textSecondary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              _buildMetaDivider(ui),
                                              Text(
                                                (row['category'] ?? '').toString(),
                                                style: TextStyle(
                                                  color: ui.textSecondary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              _buildMetaDivider(ui),
                                              Text(
                                                'Stock ${(row['stock'] ?? 0)}',
                                                style: TextStyle(
                                                  color: ui.textSecondary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isPrimary)
                                      _buildPill(
                                        label: 'Primary',
                                        color: ui.blue,
                                        soft: ui.blueSoft,
                                      ),
                                  ],
                                ),
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
  }

  Future<void> _openSupplierHistory(PosSupplier? supplier) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierReceiveHistoryScreen(supplier: supplier),
      ),
    );

    if (!mounted) return;
    await _loadAll(refreshFromBackend: false);
  }

  Widget _buildPageHeader() {
    final ui = _ui;
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
              final compact = constraints.maxWidth < 940;
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
                    child: Icon(Icons.local_shipping_outlined, color: ui.brand),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supplier Workspace',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: ui.textPrimary,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Manage supplier contacts, product links, and receive history from one place.',
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

              final right = OutlinedButton.icon(
                onPressed: _isRefreshing ? null : _refresh,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ui.textPrimary,
                  side: BorderSide(color: ui.borderStrong),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                label: const Text('Refresh'),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [left, const SizedBox(height: 18), right],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: left), const SizedBox(width: 16), right],
              );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 12.0;
              final columns = constraints.maxWidth >= 1180
                  ? 4
                  : constraints.maxWidth >= 700
                      ? 2
                      : 1;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              final totalLinkedProducts =
                  _linkedCounts.values.fold<int>(0, (sum, count) => sum + count);

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Suppliers',
                      value: _suppliers.length.toString(),
                      subtitle: 'Available supplier records',
                      icon: Icons.local_shipping_outlined,
                      color: ui.blue,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Products Linked',
                      value: totalLinkedProducts.toString(),
                      subtitle: 'Mapped to preferred suppliers',
                      icon: Icons.link_outlined,
                      color: ui.purple,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Receipts Logged',
                      value: (((_historySummary['receipt_count'] as num?) ?? 0).toInt()).toString(),
                      subtitle: 'Supplier receive entries saved',
                      icon: Icons.receipt_long_outlined,
                      color: ui.success,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Supplier Spend',
                      value: _formatCurrency(((_historySummary['total_cost'] as num?) ?? 0)),
                      subtitle: 'Recorded total receive cost',
                      icon: Icons.payments_outlined,
                      color: ui.warning,
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
                    fontSize: 22,
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

  Widget _buildToolbarRow() {
    final ui = _ui;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ui.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;
          final searchWidth = compact ? constraints.maxWidth : constraints.maxWidth * 0.42;
          final buttonWidth = compact ? (constraints.maxWidth - 10) / 2 : null;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: _supplierSearchController,
                  decoration: _fieldDecoration(
                    hintText: 'Search supplier by name, phone, or id',
                    icon: Icons.search_rounded,
                    suffixIcon: _supplierSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _supplierSearchController.clear();
                              setState(() {});
                              _loadAll(refreshFromBackend: false);
                            },
                            icon: Icon(Icons.close_rounded, color: ui.textMuted),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadAll(refreshFromBackend: false),
                ),
              ),
              SizedBox(
                width: compact ? buttonWidth : 190,
                child: OutlinedButton.icon(
                  onPressed: () => _openSupplierHistory(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ui.textPrimary,
                    side: BorderSide(color: ui.borderStrong),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Receive History'),
                ),
              ),
              SizedBox(
                width: compact ? buttonWidth : 180,
                child: ElevatedButton.icon(
                  onPressed: _hasManagementAccess
                      ? () => _showSupplierFormDialog()
                      : () => _showMessage(
                            'Only management users can add suppliers.',
                            isError: true,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ui.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_business_outlined, size: 18),
                  label: const Text('Add Supplier'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSupplierWorkspace() {
    final ui = _ui;
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
                        'Supplier Directory',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ui.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage supplier details, preferred product links, and recent receiving activity.',
                        style: TextStyle(
                          color: ui.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_suppliers.length} suppliers',
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: ui.border),
          Expanded(
            child: _suppliers.isEmpty
                ? _buildEmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No suppliers found',
                    subtitle: 'Try another search or add a new supplier record.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    itemCount: _suppliers.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: ui.border),
                    itemBuilder: (context, index) => _buildSupplierRow(_suppliers[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierRow(PosSupplier supplier) {
    final ui = _ui;
    final linkedCount = _linkedCounts[supplier.id] ?? 0;
    final lastReceipt = _lastReceiptForSupplier(supplier.id);
    final phone = supplier.phone.trim().isEmpty ? 'Phone not available' : supplier.phone.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supplier.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: ui.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildInlineMeta(
                  icon: Icons.phone_outlined,
                  text: phone,
                  color: ui.textSecondary,
                ),
                _buildMetaDivider(ui),
                _buildInlineMeta(
                  icon: Icons.link_rounded,
                  text: '$linkedCount linked products',
                  color: ui.brand,
                ),
                _buildMetaDivider(ui),
                Text(
                  lastReceipt == null
                      ? 'No receive activity yet'
                      : 'Last received ${_formatDateTime(lastReceipt.createdAt)}',
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            _actionButton(
              icon: Icons.link_rounded,
              tooltip: 'Assign products',
              onTap: () => _openAssignProductsSheet(supplier),
            ),
            _actionButton(
              icon: Icons.inventory_2_outlined,
              tooltip: 'Linked products',
              onTap: () => _openLinkedProductsSheet(supplier),
            ),
            _actionButton(
              icon: Icons.history_rounded,
              tooltip: 'Supplier history',
              onTap: () => _openSupplierHistory(supplier),
            ),
            _actionButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit supplier',
              onTap: _hasManagementAccess
                  ? () => _showSupplierFormDialog(supplier: supplier)
                  : () => _showMessage(
                        'Only management users can edit suppliers.',
                        isError: true,
                      ),
            ),
          ],
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: ui.brandSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.local_shipping_outlined,
                        color: ui.brand,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: content),
                  ],
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: ui.brandSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.local_shipping_outlined,
                  color: ui.brand,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: content),
              const SizedBox(width: 16),
              actions,
            ],
          ),
        );
      },
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

  Widget _buildMetaDivider(SupplierModulePalette ui) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: ui.textMuted.withOpacity(0.75),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required Color color,
    required Color soft,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final ui = _ui;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: ui.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ui.border),
          ),
          child: Icon(icon, size: 18, color: ui.textSecondary),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final ui = _ui;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              child: Icon(icon, size: 36, color: ui.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ui.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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

    return Scaffold(
      backgroundColor: ui.page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ui.page,
        foregroundColor: ui.textPrimary,
        title: const Text('Supplier Management'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              _buildPageHeader(),
              const SizedBox(height: 16),
              _buildToolbarRow(),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: ui.brand),
                      )
                    : _buildSupplierWorkspace(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SupplierModulePalette {
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
  final Color purpleSoft;

  const SupplierModulePalette({
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
    required this.purpleSoft,
  });

  factory SupplierModulePalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brand = Color(0xFF2AAA8A);
    const blue = Color(0xFF4B8DFF);
    const success = Color(0xFF1FCF9A);
    const warning = Color(0xFFFFB65C);
    const danger = Color(0xFFFF6B7A);
    const purple = Color(0xFF8B5CF6);

    if (isDark) {
      return const SupplierModulePalette(
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
        purpleSoft: Color(0x188B5CF6),
      );
    }

    return const SupplierModulePalette(
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
      purpleSoft: Color(0x148B5CF6),
    );
  }
}
