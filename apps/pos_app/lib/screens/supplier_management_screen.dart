import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../models/stock_receipt_record.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../services/supplier_service.dart';
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
  bool _isSaving = false;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDateTime(String raw) {
    if (raw.trim().isEmpty) return 'No activity yet';
    try {
      final date = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
    } catch (_) {
      return raw;
    }
  }

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
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade700, width: 1.4),
      ),
      isDense: true,
    );
  }

  Future<void> _showSupplierFormBottomSheet({PosSupplier? supplier}) async {
    final isEdit = supplier != null;
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD5DCE7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEdit ? 'Edit Supplier' : 'Add Supplier',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isEdit
                                        ? 'Update supplier contact details.'
                                        : 'Create a supplier record for product linking and history.',
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isSubmitting ? null : () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: nameController,
                          enabled: !isSubmitting,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            hintText: 'Enter supplier name',
                            labelText: 'Supplier Name',
                            icon: Icons.local_shipping_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: phoneController,
                          enabled: !isSubmitting,
                          keyboardType: TextInputType.phone,
                          decoration: _fieldDecoration(
                            hintText: 'Phone number',
                            labelText: 'Phone',
                            icon: Icons.phone_outlined,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
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

                                    setSheetState(() {
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

                                      if (sheetContext.mounted) {
                                        Navigator.pop(sheetContext);
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
                                      if (sheetContext.mounted) {
                                        setSheetState(() {
                                          isSubmitting = false;
                                        });
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    isEdit ? 'SAVE CHANGES' : 'CREATE SUPPLIER',
                                  ),
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final visibleProducts = products.where((product) {
              if (query.isEmpty) return true;
              return product.name.toLowerCase().contains(query) ||
                  product.barcode.toLowerCase().contains(query) ||
                  product.category.toLowerCase().contains(query);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.82,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Products • ${supplier.name}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set this supplier as the preferred supplier for selected products.',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        decoration: _fieldDecoration(
                          hintText: 'Search by name, barcode, or category',
                          icon: Icons.search,
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: visibleProducts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final product = visibleProducts[index];
                            final mapping = currentMappings[product.barcode];
                            final isAssigned = mapping != null;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE3E9F2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${product.barcode} • ${product.category} • Stock ${product.stock}',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (isAssigned)
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        if (mapping?.id == null) return;
                                        await _supplierService
                                            .deleteSupplierProductMapping(
                                          mapping!.id!,
                                        );
                                        currentMappings.remove(product.barcode);
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(Icons.link_off),
                                      label: const Text('Assigned'),
                                    )
                                  else
                                    FilledButton.icon(
                                      onPressed: () async {
                                        await _supplierService
                                            .assignProductToSupplier(
                                          supplier: supplier,
                                          product: product,
                                          isPreferred: true,
                                          defaultUnitCost: product.costPrice,
                                        );
                                        final refreshed = await _supplierService
                                            .getPreferredSupplierMapping(
                                          product.barcode,
                                        );
                                        if (refreshed != null) {
                                          currentMappings[product.barcode] =
                                              refreshed;
                                        }
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(Icons.link),
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linked Products • ${supplier.name}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Products currently assigned to this supplier.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('No linked products yet.'),
                          )
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE3E9F2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (row['product_name'] ?? 'Product')
                                                .toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${row['barcode']} • ${row['category']} • Stock ${(row['stock'] ?? 0)}',
                                            style: TextStyle(
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (((row['is_preferred'] as num?) ?? 0)
                                            .toInt() ==
                                        1)
                                      _buildPill(
                                        label: 'Primary',
                                        color: Colors.blue,
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

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
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

  Widget _buildSupplierCard(PosSupplier supplier) {
    final linkedCount = _linkedCounts[supplier.id] ?? 0;
    final lastReceipt = _lastReceiptForSupplier(supplier.id);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          supplier.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: Color(0xFF1552C4),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    supplier.phone.trim().isEmpty
                        ? 'Phone not available'
                        : supplier.phone.trim(),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildMiniDetailCard('Products', linkedCount.toString()),
                      _buildMiniDetailCard(
                        'Last Received',
                        lastReceipt == null
                            ? 'No activity'
                            : _formatDateTime(lastReceipt.createdAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Assign products',
                  onPressed: () => _openAssignProductsSheet(supplier),
                  icon: const Icon(Icons.link),
                ),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: 'Linked products',
                  onPressed: () => _openLinkedProductsSheet(supplier),
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: 'Edit supplier',
                  onPressed: _hasManagementAccess
                      ? () => _showSupplierFormBottomSheet(supplier: supplier)
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ],
        ),
      );
    
  }

  Widget _buildMiniDetailCard(String title, String value) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _supplierSearchController,
                  decoration: _fieldDecoration(
                    hintText: 'Search supplier by name, phone, or id',
                    icon: Icons.search,
                    suffixIcon: _supplierSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _supplierSearchController.clear();
                              setState(() {});
                              _loadAll(refreshFromBackend: false);
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadAll(refreshFromBackend: false),
                ),
              ),
              const SizedBox(width: 12),
              _buildQuickActionButton(
                title: 'Refresh',
                icon: Icons.refresh,
                onTap: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildQuickActionButton(
                title: 'Add Supplier',
                icon: Icons.add_business_outlined,
                onTap: _hasManagementAccess
                    ? () => _showSupplierFormBottomSheet()
                    : () => _showMessage(
                          'Only management users can add suppliers.',
                          isError: true,
                        ),
              ),
              _buildQuickActionButton(
                title: 'History',
                icon: Icons.history,
                onTap: () => _openSupplierHistory(null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Center(
        child: Text('No suppliers match the current search.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalLinkedProducts =
        _linkedCounts.values.fold<int>(0, (sum, count) => sum + count);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Supplier Module'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh suppliers',
            onPressed: _isRefreshing ? null : _refresh,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Suppliers',
                        value: _suppliers.length.toString(),
                        icon: Icons.local_shipping_outlined,
                        accent: Colors.blue,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Products Linked',
                        value: totalLinkedProducts.toString(),
                        icon: Icons.link_outlined,
                        accent: Colors.deepPurple,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Receipts Logged',
                        value: (((_historySummary['receipt_count'] as num?) ??
                                    0)
                                .toInt())
                            .toString(),
                        icon: Icons.receipt_long_outlined,
                        accent: Colors.green,
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: _buildSummaryCard(
                        title: 'Supplier Spend',
                        value:
                            'Rs. ${(((_historySummary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                        icon: Icons.payments_outlined,
                        accent: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildToolbarCard(),
                const SizedBox(height: 18),
                Text(
                  'Suppliers (${_suppliers.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (_suppliers.isEmpty)
                  _buildEmptyState()
                else
                  ..._suppliers.map(
                    (supplier) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSupplierCard(supplier),
                    ),
                  ),
              ],
            ),
    );
  }
}
