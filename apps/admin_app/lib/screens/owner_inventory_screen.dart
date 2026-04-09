import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/inventory_history_item.dart';
import '../providers/admin_provider.dart';
import '../widgets/app_snackbar.dart';
import 'inventory_history_screen.dart';

class OwnerInventoryScreen extends StatefulWidget {
  const OwnerInventoryScreen({super.key});

  @override
  State<OwnerInventoryScreen> createState() => _OwnerInventoryScreenState();
}

class _OwnerInventoryScreenState extends State<OwnerInventoryScreen> {
  String _search = '';
  String _filter = 'all';

  String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  String _formatCompactMoney(num value) {
    final abs = value.abs().toDouble();
    if (abs >= 1000000) return 'Rs. ${(value / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return 'Rs. ${(value / 1000).toStringAsFixed(1)}K';
    return 'Rs. ${value.toStringAsFixed(0)}';
  }

  List<Product> _filterProducts(List<Product> products) {
    final query = _search.trim().toLowerCase();

    return products.where((product) {
      final matchesSearch =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);

      final threshold = product.minStockLevel > 0 ? product.minStockLevel : 10;
      final matchesFilter = switch (_filter) {
        'low' => product.stock > 0 && product.stock <= threshold,
        'out' => product.stock <= 0,
        _ => true,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final filteredProducts = _filterProducts(provider.products);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: provider.refreshOwnerDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _HeaderCard(),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by product name or barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        onPressed: () => setState(() => _search = ''),
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF2F6FE4)),
                ),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            _FilterBar(
              value: _filter,
              onChanged: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 14),
            if (provider.isLoading && provider.products.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredProducts.isEmpty)
              const _EmptyInventoryState()
            else
              ...filteredProducts.map(
                (product) => _ProductCard(
                  product: product,
                  formatMoney: _formatMoney,
                  formatCompactMoney: _formatCompactMoney,
                  onTap: () => _showProductSheet(context, provider, product),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductSheet(
    BuildContext context,
    AdminProvider provider,
    Product product,
  ) async {
    final minStockController = TextEditingController(
      text: product.minStockLevel.toString(),
    );
    final sellingController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );
    final wholesaleController = TextEditingController(
      text: product.wholesalePrice.toStringAsFixed(2),
    );
    final saleController = TextEditingController(
      text: (product.salePrice ?? 0).toStringAsFixed(2),
    );
    final supplierInfo = await provider.fetchProductSupplierContact(product.barcode);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        final threshold = product.minStockLevel > 0 ? product.minStockLevel : 10;
        final supplierName = (supplierInfo['supplier_name'] ?? '').toString().trim();
        final supplierPhone = (supplierInfo['supplier_phone'] ?? '').toString().trim();
        final hasSupplierInfo = supplierName.isNotEmpty || supplierPhone.isNotEmpty;
        final statusColor = product.stock <= 0
            ? const Color(0xFFD92D20)
            : product.stock <= threshold
                ? const Color(0xFFF79009)
                : const Color(0xFF147A5A);
        final statusText = product.stock <= 0
            ? 'Out of Stock'
            : product.stock <= threshold
                ? 'Low Stock'
                : 'In Stock';

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172433),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Barcode: ${product.barcode}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (supplierName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Supplier: $supplierName',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      label: statusText,
                      color: statusColor,
                      background: statusColor.withOpacity(0.12),
                    ),
                    _InfoChip(
                      label: 'Stock ${product.stock}',
                      color: const Color(0xFF0F3D91),
                      background: const Color(0xFFE7F0FF),
                    ),
                    _InfoChip(
                      label: 'Min ${product.minStockLevel}',
                      color: const Color(0xFF7A5C00),
                      background: const Color(0xFFFFF4D6),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _PriceBox(
                        label: 'Selling',
                        value: _formatMoney(product.sellingPrice),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PriceBox(
                        label: 'Wholesale',
                        value: _formatMoney(product.wholesalePrice),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PriceBox(
                        label: 'Sale',
                        value: product.hasSalePrice
                            ? _formatMoney(product.salePrice!)
                            : '—',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172433),
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<InventoryHistoryItem>>(
                  future: provider.fetchInventoryHistory(product.barcode),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _RecentActivityLoading();
                    }

                    final history = snapshot.data ?? const <InventoryHistoryItem>[];
                    if (history.isEmpty) {
                      return const _RecentActivityEmpty();
                    }

                    final latest = history.first;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE3E9F3)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: latest.color.withOpacity(0.12),
                            child: Icon(latest.icon, color: latest.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  latest.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF172433),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  latest.subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  latest.dateText,
                                  style: const TextStyle(
                                    color: Color(0xFF98A2B3),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            latest.quantityText,
                            style: TextStyle(
                              color: latest.color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF172433),
                  ),
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.history,
                  color: const Color(0xFF0F3D91),
                  title: 'View inventory history',
                  subtitle: 'Open full movement timeline',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InventoryHistoryScreen(product: product),
                      ),
                    );
                  },
                ),
                _ActionTile(
                  icon: Icons.sell_outlined,
                  color: const Color(0xFF147A5A),
                  title: 'Update selling price',
                  subtitle: 'Edit main selling price',
                  onTap: () async {
                    final ok = await _showPriceEditor(
                      context: context,
                      provider: provider,
                      controller: sellingController,
                      product: product,
                      title: 'Selling Price',
                      priceType: 'selling',
                    );
                    if (ok && mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
                _ActionTile(
                  icon: Icons.storefront_outlined,
                  color: const Color(0xFF7A5C00),
                  title: 'Update wholesale price',
                  subtitle: 'Edit bulk/wholesale price',
                  onTap: () async {
                    final ok = await _showPriceEditor(
                      context: context,
                      provider: provider,
                      controller: wholesaleController,
                      product: product,
                      title: 'Wholesale Price',
                      priceType: 'wholesale',
                    );
                    if (ok && mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
                _ActionTile(
                  icon: Icons.local_offer_outlined,
                  color: const Color(0xFF7A1CAC),
                  title: 'Update sale price',
                  subtitle: 'Edit active sale price',
                  onTap: () async {
                    final ok = await _showPriceEditor(
                      context: context,
                      provider: provider,
                      controller: saleController,
                      product: product,
                      title: 'Sale Price',
                      priceType: 'sale',
                    );
                    if (ok && mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
                _ActionTile(
                  icon: Icons.flag_outlined,
                  color: const Color(0xFFF79009),
                  title: 'Update minimum stock level',
                  subtitle: 'Control low-stock alert threshold',
                  onTap: () async {
                    final ok = await _showMinStockEditor(
                      context: context,
                      provider: provider,
                      controller: minStockController,
                      product: product,
                    );
                    if (ok && mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
                if (hasSupplierInfo)
                  _ActionTile(
                    icon: Icons.local_shipping_outlined,
                    color: const Color(0xFF0F3D91),
                    title: 'View Supplier Info',
                    subtitle: 'See supplier name and telephone number',
                    onTap: () => _showSupplierInfoSheet(
                      context,
                      supplierName: supplierName,
                      supplierPhone: supplierPhone,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSupplierInfoSheet(
    BuildContext context, {
    required String supplierName,
    required String supplierPhone,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECF3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE7F0FF),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: Color(0xFF0F3D91),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Supplier Info',
                          style: TextStyle(
                            color: Color(0xFF172433),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Relevant supplier for this product.',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE7ECF3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Supplier Name',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      supplierName.isEmpty ? 'Not available' : supplierName,
                      style: const TextStyle(
                        color: Color(0xFF172433),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Telephone Number',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (supplierPhone.isNotEmpty)
                      InkWell(
                        onTap: () => _callSupplier(context, supplierPhone),
                        borderRadius: BorderRadius.circular(12),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F0FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.call_rounded, color: Color(0xFF0F3D91), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  supplierPhone,
                                  style: const TextStyle(
                                    color: Color(0xFF0F3D91),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const Text(
                                'Call',
                                style: TextStyle(
                                  color: Color(0xFF0F3D91),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Text(
                        'Not available',
                        style: TextStyle(
                          color: Color(0xFF172433),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callSupplier(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      AppSnackBar.show(
        context,
        message: 'Unable to open the phone dialer.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<bool> _showPriceEditor({
    required BuildContext context,
    required AdminProvider provider,
    required TextEditingController controller,
    required Product product,
    required String title,
    required String priceType,
  }) async {
    return _showValueEditorSheet(
      context: context,
      title: title,
      productName: product.name,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      fieldLabel: title,
      accentColor: _accentForPriceType(priceType),
      hintText: 'Enter ${title.toLowerCase()}',
      helperText: 'This change updates the owner inventory view and POS-linked pricing.',
      onSave: (rawValue) async {
        final value = double.tryParse(rawValue.trim());
        if (value == null || value <= 0) {
          AppSnackBar.show(
            context,
            message: 'Enter a valid ${title.toLowerCase()}.',
            backgroundColor: Colors.red,
          );
          return false;
        }

        final updated = await provider.updateProductPrice(
          product.barcode,
          value,
          priceType: priceType,
        );

        if (!context.mounted) return false;

        if (updated) {
          AppSnackBar.show(
            context,
            message: '$title updated.',
            backgroundColor: Colors.green,
          );
          return true;
        }

        AppSnackBar.show(
          context,
          message: 'Failed to update ${title.toLowerCase()}.',
          backgroundColor: Colors.red,
        );
        return false;
      },
    );
  }

  Future<bool> _showMinStockEditor({
    required BuildContext context,
    required AdminProvider provider,
    required TextEditingController controller,
    required Product product,
  }) async {
    return _showValueEditorSheet(
      context: context,
      title: 'Minimum Stock',
      productName: product.name,
      controller: controller,
      keyboardType: TextInputType.number,
      fieldLabel: 'Minimum stock level',
      accentColor: const Color(0xFFF79009),
      hintText: 'Enter minimum stock level',
      helperText: 'This controls when low-stock alerts appear for the owner.',
      onSave: (rawValue) async {
        final value = int.tryParse(rawValue.trim());
        if (value == null || value < 0) {
          AppSnackBar.show(
            context,
            message: 'Enter a valid minimum stock level.',
            backgroundColor: Colors.red,
          );
          return false;
        }

        final updated = await provider.updateMinStockLevel(
          product.barcode,
          value,
        );

        if (!context.mounted) return false;

        if (updated) {
          AppSnackBar.show(
            context,
            message: 'Minimum stock level updated.',
            backgroundColor: Colors.green,
          );
          return true;
        }

        AppSnackBar.show(
          context,
          message: 'Failed to update minimum stock level.',
          backgroundColor: Colors.red,
        );
        return false;
      },
    );
  }

  Color _accentForPriceType(String priceType) {
    switch (priceType) {
      case 'wholesale':
        return const Color(0xFF7A5C00);
      case 'sale':
        return const Color(0xFF7A1CAC);
      case 'selling':
      default:
        return const Color(0xFF147A5A);
    }
  }

  Future<bool> _showValueEditorSheet({
    required BuildContext context,
    required String title,
    required String productName,
    required TextEditingController controller,
    required TextInputType keyboardType,
    required String fieldLabel,
    required Color accentColor,
    required String hintText,
    required String helperText,
    required Future<bool> Function(String rawValue) onSave,
  }) async {
    bool saved = false;
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 6,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: accentColor.withOpacity(0.12),
                          child: Icon(Icons.edit_outlined, color: accentColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF172433),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                productName,
                                style: const TextStyle(
                                  color: Color(0xFF667085),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFD),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE3E9F3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fieldLabel,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: controller,
                            keyboardType: keyboardType,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: hintText,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: Color(0xFFE3E9F3)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: accentColor, width: 1.4),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            helperText,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting ? null : () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              side: const BorderSide(color: Color(0xFFD6DCE8)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    setSheetState(() => isSubmitting = true);
                                    final ok = await onSave(controller.text);
                                    if (!sheetContext.mounted) return;
                                    if (ok) {
                                      saved = true;
                                      Navigator.pop(sheetContext);
                                    } else {
                                      setSheetState(() => isSubmitting = false);
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: accentColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return saved;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF094067), Color(0xFF3E7CB1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x1FFFFFFF),
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Icon(Icons.inventory_2_outlined, color: Colors.white, size: 28),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Inventory',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Quick product check for the owner.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: 'All',
            selected: value == 'all',
            onTap: () => onChanged('all'),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Low Stock',
            selected: value == 'low',
            onTap: () => onChanged('low'),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Out of Stock',
            selected: value == 'out',
            onTap: () => onChanged('out'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF163D8F) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFF163D8F)
                  : const Color(0xFFD6DCE8),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.formatMoney,
    required this.formatCompactMoney,
    required this.onTap,
  });

  final Product product;
  final String Function(num value) formatMoney;
  final String Function(num value) formatCompactMoney;
  final VoidCallback onTap;

  Color get _statusColor {
    final threshold = product.minStockLevel > 0 ? product.minStockLevel : 10;
    if (product.stock <= 0) return const Color(0xFFD92D20);
    if (product.stock <= threshold) return const Color(0xFFF79009);
    return const Color(0xFF12B76A);
  }

  String get _statusText {
    final threshold = product.minStockLevel > 0 ? product.minStockLevel : 10;
    if (product.stock <= 0) return 'Out of Stock';
    if (product.stock <= threshold) return 'Low Stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE7F0FF),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFF0F3D91),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF172433),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Barcode: ${product.barcode}',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF98A2B3),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: _statusText,
                    color: _statusColor,
                    background: _statusColor.withOpacity(0.12),
                  ),
                  _InfoChip(
                    label: 'Stock ${product.stock}',
                    color: const Color(0xFF0F3D91),
                    background: const Color(0xFFE7F0FF),
                  ),
                  _InfoChip(
                    label: 'Min ${product.minStockLevel}',
                    color: const Color(0xFF7A5C00),
                    background: const Color(0xFFFFF4D6),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PriceChip(label: 'Sell', value: formatCompactMoney(product.sellingPrice)),
                  _PriceChip(label: 'Wholesale', value: formatCompactMoney(product.wholesalePrice)),
                  _PriceChip(
                    label: 'Sale',
                    value: product.hasSalePrice
                        ? formatCompactMoney(product.salePrice!)
                        : '—',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
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
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Color(0xFF172433),
            fontFamily: 'Roboto',
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7482),
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _PriceBox extends StatelessWidget {
  const _PriceBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7482),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF172433),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _RecentActivityLoading extends StatelessWidget {
  const _RecentActivityLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Loading recent activity...',
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityEmpty extends StatelessWidget {
  const _RecentActivityEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: const Text(
        'No inventory activity found yet for this product.',
        style: TextStyle(
          color: Color(0xFF667085),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: Color(0xFF98A2B3),
          ),
          SizedBox(height: 12),
          Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Try changing the search or filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
