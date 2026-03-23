import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import 'stock_take_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

enum InventoryFilter { all, inStock, lowStock, outOfStock, inactive }

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Product> _products = [];
  List<Map<String, dynamic>> _recentMovements = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _searchQuery = '';
  InventoryFilter _selectedFilter = InventoryFilter.all;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Product> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();

    return _products.where((product) {
      final matchesSearch =
          query.isEmpty ||
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

  int get _lowStockCount =>
      _products.where((p) => p.isActive && p.isLowStock).length;
  int get _outOfStockCount =>
      _products.where((p) => p.isActive && p.isOutOfStock).length;
  int get _activeProductCount => _products.where((p) => p.isActive).length;
  double get _stockValue => _products.fold<double>(
    0,
    (sum, product) => sum + (product.costPrice * product.stock),
  );

  Future<Product?> _pickProduct({required String title}) async {
    return showModalBottomSheet<Product>(
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
                                      '${product.barcode} • ${product.category} • Stock ${product.stock}',
                                    ),
                                    trailing: Text(
                                      'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green,
                                      ),
                                    ),
                                    onTap: () =>
                                        Navigator.pop(context, product),
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

  Future<void> _openReceiveFlow({Product? initialProduct}) async {
    final product =
        initialProduct ??
        await _pickProduct(title: 'Select a product to receive');
    if (product == null || !mounted) return;

    final qtyController = TextEditingController();
    final costController = TextEditingController(
      text: product.costPrice > 0 ? product.costPrice.toStringAsFixed(2) : '',
    );
    final noteController = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receive Stock',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${product.name} • ${product.barcode}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Received quantity',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: costController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Unit cost (optional)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                      if (qty <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid quantity.'),
                          ),
                        );
                        return;
                      }

                      final rawCost = costController.text.trim();
                      final unitCost = rawCost.isEmpty
                          ? null
                          : double.tryParse(rawCost);

                      final changedBy = context
                          .read<AuthProvider>()
                          .currentUser
                          ?.name;
                      final success = await DatabaseHelper.instance
                          .receiveStockLocal(
                            product.barcode,
                            qty,
                            unitCost: unitCost,
                            performedBy: changedBy,
                            reason: noteController.text.trim(),
                          );

                      if (!context.mounted) return;
                      Navigator.pop(context, success);
                    },
                    icon: const Icon(Icons.inventory_2),
                    label: const Text('Save Receive Entry'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    qtyController.dispose();
    costController.dispose();
    noteController.dispose();

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Stock received successfully.');
    } else if (saved == false) {
      _showMessage('Could not save stock receive entry.', isError: true);
    }
  }

  Future<void> _openAdjustFlow({Product? initialProduct}) async {
    final product =
        initialProduct ??
        await _pickProduct(title: 'Select a product to adjust');
    if (product == null || !mounted) return;

    final qtyController = TextEditingController();
    final reasonController = TextEditingController();
    String adjustmentType = 'add';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stock Adjustment',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${product.name} • Current stock ${product.stock}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: adjustmentType,
                      decoration: InputDecoration(
                        labelText: 'Adjustment type',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'add',
                          child: Text('Add Stock'),
                        ),
                        DropdownMenuItem(
                          value: 'remove',
                          child: Text('Remove Stock'),
                        ),
                        DropdownMenuItem(
                          value: 'set',
                          child: Text('Set Exact Stock'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          adjustmentType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: adjustmentType == 'set'
                            ? 'Final stock quantity'
                            : 'Quantity',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final qty =
                              int.tryParse(qtyController.text.trim()) ?? -1;
                          if (qty < 0 ||
                              (adjustmentType != 'set' && qty == 0)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid quantity.'),
                              ),
                            );
                            return;
                          }

                          final changedBy = context
                              .read<AuthProvider>()
                              .currentUser
                              ?.name;
                          final success = await DatabaseHelper.instance
                              .adjustStockLocal(
                                product.barcode,
                                adjustmentType: adjustmentType,
                                quantity: qty,
                                performedBy: changedBy,
                                reason: reasonController.text.trim(),
                              );

                          if (!context.mounted) return;
                          Navigator.pop(context, success);
                        },
                        icon: const Icon(Icons.tune),
                        label: const Text('Save Adjustment'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    qtyController.dispose();
    reasonController.dispose();

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Stock adjusted successfully.');
    } else if (saved == false) {
      _showMessage('Could not save stock adjustment.', isError: true);
    }
  }

  Future<void> _openMinStockDialog(Product product) async {
    final controller = TextEditingController(
      text: product.minStockLevel.toString(),
    );

    final changed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Minimum Stock'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Minimum stock level'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final value = int.tryParse(controller.text.trim()) ?? -1;
                if (value < 0) return;
                final changedBy = context
                    .read<AuthProvider>()
                    .currentUser
                    ?.name;
                final success = await DatabaseHelper.instance
                    .updateProductMinStockLevelLocal(
                      product.barcode,
                      value,
                      changedBy: changedBy,
                    );
                if (!context.mounted) return;
                Navigator.pop(context, success);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (changed == true) {
      await _loadData(showLoader: false);
      _showMessage('Minimum stock updated.');
    } else if (changed == false) {
      _showMessage('Could not update minimum stock.', isError: true);
    }
  }

  Future<void> _openPriceChangeFlow({Product? initialProduct}) async {
    final product =
        initialProduct ??
        await _pickProduct(title: 'Select a product to change price');
    if (product == null || !mounted) return;

    final valueController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    String priceType = 'selling';
    bool saleEnabled = product.saleEnabled;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        void syncField() {
          switch (priceType) {
            case 'cost':
              valueController.text = product.costPrice.toStringAsFixed(2);
              break;
            case 'wholesale':
              valueController.text = product.wholesalePrice.toStringAsFixed(2);
              break;
            case 'sale':
              valueController.text = (product.salePrice ?? product.sellingPrice)
                  .toStringAsFixed(2);
              saleEnabled = product.saleEnabled;
              break;
            case 'selling':
            default:
              valueController.text = product.sellingPrice.toStringAsFixed(2);
              break;
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Change Price',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${product.name} • ${product.barcode}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: priceType,
                      decoration: InputDecoration(
                        labelText: 'Price field',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'selling',
                          child: Text('Selling Price'),
                        ),
                        DropdownMenuItem(
                          value: 'wholesale',
                          child: Text('Wholesale Price'),
                        ),
                        DropdownMenuItem(
                          value: 'sale',
                          child: Text('Sale Price'),
                        ),
                        DropdownMenuItem(
                          value: 'cost',
                          child: Text('Cost Price'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          priceType = value;
                          syncField();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: valueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'New price',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (priceType == 'sale') ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: saleEnabled,
                        title: const Text('Sale price active'),
                        subtitle: const Text(
                          'If off, billing will fall back to selling price.',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            saleEnabled = value;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Reason / note (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final newPrice = double.tryParse(
                            valueController.text.trim(),
                          );
                          if (newPrice == null || newPrice < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid price.'),
                              ),
                            );
                            return;
                          }

                          final changedBy = context
                              .read<AuthProvider>()
                              .currentUser
                              ?.name;
                          final success = await DatabaseHelper.instance
                              .updateProductPriceLocal(
                                product.barcode,
                                newPrice,
                                priceType: priceType,
                                changedBy: changedBy,
                                reason: noteController.text.trim(),
                                saleEnabled: priceType == 'sale'
                                    ? saleEnabled
                                    : null,
                              );

                          if (!context.mounted) return;
                          Navigator.pop(context, success);
                        },
                        icon: const Icon(Icons.sell),
                        label: const Text('Save Price Change'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    valueController.dispose();
    noteController.dispose();

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Price updated successfully.');
    } else if (saved == false) {
      _showMessage('Could not update price.', isError: true);
    }
  }

  Future<void> _openStockTakeScreen({String? barcode}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockTakeScreen(initialBarcode: barcode),
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${product.barcode} • ${product.category}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusChip(product),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildDetailCard(
                        'Current Stock',
                        product.stock.toString(),
                      ),
                      _buildDetailCard(
                        'Min Stock',
                        product.minStockLevel.toString(),
                      ),
                      _buildDetailCard(
                        'Cost Price',
                        'Rs. ${product.costPrice.toStringAsFixed(2)}',
                      ),
                      _buildDetailCard(
                        'Selling Price',
                        'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                      ),
                      _buildDetailCard(
                        'Wholesale Price',
                        'Rs. ${product.wholesalePrice.toStringAsFixed(2)}',
                      ),
                      _buildDetailCard(
                        'Sale Price',
                        product.hasSalePrice
                            ? 'Rs. ${product.salePrice!.toStringAsFixed(2)}'
                            : 'Not active',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!mounted) return;
                          await _openReceiveFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.inventory_2),
                        label: const Text('Receive'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!mounted) return;
                          await _openAdjustFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.tune),
                        label: const Text('Adjust'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!mounted) return;
                          await _openPriceChangeFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.sell),
                        label: const Text('Change Price'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!mounted) return;
                          await _openStockTakeScreen(barcode: product.barcode);
                        },
                        icon: const Icon(Icons.playlist_add_check_circle),
                        label: const Text('Count'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(
                            const Duration(milliseconds: 120),
                          );
                          if (!mounted) return;
                          await _openMinStockDialog(product);
                        },
                        icon: const Icon(Icons.warning_amber_rounded),
                        label: const Text('Min Stock'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Text(
                        'Recent activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Future.delayed(const Duration(milliseconds: 120), () {
                            if (!mounted) return;
                            _openRecentActivitySheet(barcode: product.barcode);
                          });
                        },
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: movements.isEmpty
                        ? const Center(
                            child: Text('No stock or price movement yet.'),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required InventoryFilter filter,
  }) {
    final isSelected = _selectedFilter == filter;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = filter;
        });
      },
      selectedColor: Colors.blue.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue.shade800 : Colors.grey.shade800,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: isSelected ? Colors.blue.shade200 : Colors.grey.shade300,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildStatusChip(Product product) {
    late final Color color;
    late final String label;

    if (!product.isActive) {
      color = Colors.grey;
      label = 'Inactive';
    } else if (product.isOutOfStock) {
      color = Colors.red;
      label = 'Out of stock';
    } else if (product.isLowStock) {
      color = Colors.orange;
      label = 'Low stock';
    } else {
      color = Colors.green;
      label = 'In stock';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _shadeColor(color),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPriceAvailabilityChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _shadeColor(color),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, String value) {
    return Container(
      width: 180,
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementTile(Map<String, dynamic> movement) {
    final actionType = (movement['action_type'] ?? '').toString();
    final quantityChange = movement['quantity_change'] as int?;
    final oldPrice = movement['old_price'] as num?;
    final newPrice = movement['new_price'] as num?;

    String subtitle = _movementSubtitle(movement);
    String trailing = _formatDateTime(movement['created_at']?.toString());
    Color accent = Colors.blue;
    IconData icon = Icons.history;

    if (actionType.contains('receive')) {
      accent = Colors.green;
      icon = Icons.inventory_2;
    } else if (actionType.contains('adjust')) {
      accent = Colors.orange;
      icon = Icons.tune;
    } else if (actionType.contains('price')) {
      accent = Colors.purple;
      icon = Icons.sell;
    } else if (actionType.contains('sale')) {
      accent = Colors.blue;
      icon = Icons.point_of_sale;
    } else if (actionType.contains('refund')) {
      accent = Colors.red;
      icon = Icons.undo;
    }

    if (quantityChange != null) {
      final sign = quantityChange > 0 ? '+' : '';
      trailing = '$sign$quantityChange • $trailing';
    } else if (oldPrice != null || newPrice != null) {
      trailing = 'Rs. ${newPrice?.toStringAsFixed(2) ?? '0.00'} • $trailing';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  (movement['product_name'] ?? 'Unknown product').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  String _movementTitle(String actionType) {
    switch (actionType) {
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

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Color _shadeColor(Color color) {
    if (color == Colors.red) return Colors.red.shade700;
    if (color == Colors.orange) return Colors.orange.shade800;
    if (color == Colors.green) return Colors.green.shade700;
    if (color == Colors.deepPurple) return Colors.deepPurple.shade700;
    if (color == Colors.purple) return Colors.purple.shade700;
    if (color == Colors.grey) return Colors.grey.shade700;
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

  @override
  Widget build(BuildContext context) {
    final visibleProducts = _filteredProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh inventory',
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
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Products',
                          value: _activeProductCount.toString(),
                          icon: Icons.inventory,
                          accent: Colors.blue,
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Low Stock',
                          value: _lowStockCount.toString(),
                          icon: Icons.warning_amber_rounded,
                          accent: Colors.orange,
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Out of Stock',
                          value: _outOfStockCount.toString(),
                          icon: Icons.remove_shopping_cart,
                          accent: Colors.red,
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _buildSummaryCard(
                          title: 'Stock Value',
                          value: 'Rs. ${_stockValue.toStringAsFixed(2)}',
                          icon: Icons.payments_outlined,
                          accent: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
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
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText:
                                      'Search by name, barcode, or category',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
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
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFilterChip(
                              label: 'All',
                              filter: InventoryFilter.all,
                            ),
                            _buildFilterChip(
                              label: 'In Stock',
                              filter: InventoryFilter.inStock,
                            ),
                            _buildFilterChip(
                              label: 'Low Stock',
                              filter: InventoryFilter.lowStock,
                            ),
                            _buildFilterChip(
                              label: 'Out of Stock',
                              filter: InventoryFilter.outOfStock,
                            ),
                            _buildFilterChip(
                              label: 'Inactive',
                              filter: InventoryFilter.inactive,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildQuickActionButton(
                              title: 'Receive Stock',
                              icon: Icons.inventory_2,
                              onTap: () => _openReceiveFlow(),
                            ),
                            _buildQuickActionButton(
                              title: 'Adjust Stock',
                              icon: Icons.tune,
                              onTap: () => _openAdjustFlow(),
                            ),
                            _buildQuickActionButton(
                              title: 'Change Price',
                              icon: Icons.sell,
                              onTap: () => _openPriceChangeFlow(),
                            ),
                            _buildQuickActionButton(
                              title: 'Count Stock',
                              icon: Icons.playlist_add_check_circle,
                              onTap: () => _openStockTakeScreen(),
                            ),
                            _buildQuickActionButton(
                              title: 'Activity',
                              icon: Icons.history,
                              onTap: () => _openRecentActivitySheet(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'Products (${visibleProducts.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Tap a product for details',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (visibleProducts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Center(
                        child: Text('No products match the current filter.'),
                      ),
                    )
                  else
                    ...visibleProducts.map(
                      (product) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _openProductDetail(product),
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              product.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          _buildStatusChip(product),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${product.barcode} • ${product.category}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _buildDetailCard(
                                            'Stock',
                                            product.stock.toString(),
                                          ),
                                          _buildDetailCard(
                                            'Min Stock',
                                            product.minStockLevel.toString(),
                                          ),
                                          _buildDetailCard(
                                            'Selling',
                                            'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (product.wholesalePrice > 0 &&
                                              product.wholesalePrice !=
                                                  product.sellingPrice)
                                            _buildPriceAvailabilityChip(
                                              'Wholesale active',
                                              Colors.deepPurple,
                                            ),
                                          if (product.hasSalePrice)
                                            _buildPriceAvailabilityChip(
                                              'Sale active',
                                              Colors.orange,
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
                                      tooltip: 'Receive stock',
                                      onPressed: () => _openReceiveFlow(
                                        initialProduct: product,
                                      ),
                                      icon: const Icon(Icons.inventory_2),
                                    ),
                                    const SizedBox(height: 8),
                                    IconButton.filledTonal(
                                      tooltip: 'Adjust stock',
                                      onPressed: () => _openAdjustFlow(
                                        initialProduct: product,
                                      ),
                                      icon: const Icon(Icons.tune),
                                    ),
                                    const SizedBox(height: 8),
                                    IconButton.filledTonal(
                                      tooltip: 'Change price',
                                      onPressed: () => _openPriceChangeFlow(
                                        initialProduct: product,
                                      ),
                                      icon: const Icon(Icons.sell),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
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
                            const Text(
                              'Recent Inventory Activity',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => _openRecentActivitySheet(),
                              child: const Text('View all'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_recentMovements.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'No recent stock or price activity yet.',
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
    );
  }
}
