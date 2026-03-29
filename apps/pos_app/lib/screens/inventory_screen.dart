
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../models/supplier_product_mapping.dart';
import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import 'inventory_history_screen.dart';
import 'stock_take_screen.dart';
import 'supplier_receive_history_screen.dart';

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

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String confirmText = 'Confirm',
    bool isDestructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmText),
          ),
        ],
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

    final approver = await showDialog<_InventoryApprovalResult?>(
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

            return AlertDialog(
              title: const Text('Manager Approval Required'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter manager or full-access PIN to $actionLabel.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Approval PIN',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onSubmitted: (_) {
                      if (!isVerifying) {
                        verify();
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () => Navigator.pop(dialogContext, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isVerifying ? null : verify,
                  child: isVerifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve'),
                ),
              ],
            );
          },
        );
      },
    );

    pinController.dispose();

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
    );
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
    bool saleEnabled = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
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
                        'Add Product',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Create a new product with opening stock and price setup.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Product name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: barcodeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Barcode',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoryController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: costPriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Cost price',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: sellingPriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Selling price',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
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
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Wholesale price (optional)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: salePriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Sale price (optional)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: saleEnabled,
                        title: const Text('Sale price active'),
                        subtitle: const Text(
                          'If on, billing can use this product\'s sale price in Sale mode.',
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            saleEnabled = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: openingStockController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Opening stock',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: minStockController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Min stock',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            final barcode = barcodeController.text.trim();
                            final category = categoryController.text.trim();

                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enter a product name.')),
                              );
                              return;
                            }
                            if (barcode.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enter a barcode.')),
                              );
                              return;
                            }
                            final barcodeExists = _products.any(
                              (item) => item.barcode.trim().toLowerCase() == barcode.toLowerCase(),
                            );
                            if (barcodeExists) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('A product with this barcode already exists.')),
                              );
                              return;
                            }

                            final costError = _validateNonNegativeMoney(
                              costPriceController.text,
                              label: 'cost price',
                            );
                            if (costError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(costError)),
                              );
                              return;
                            }

                            final sellingError = _validateNonNegativeMoney(
                              sellingPriceController.text,
                              label: 'selling price',
                            );
                            if (sellingError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(sellingError)),
                              );
                              return;
                            }

                            final openingStockError = _validatePositiveInt(
                              openingStockController.text,
                              label: 'opening stock',
                              allowZero: true,
                            );
                            if (openingStockError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(openingStockError)),
                              );
                              return;
                            }

                            final minStockError = _validatePositiveInt(
                              minStockController.text,
                              label: 'minimum stock level',
                              allowZero: true,
                            );
                            if (minStockError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(minStockError)),
                              );
                              return;
                            }

                            final rawWholesale = wholesalePriceController.text.trim();
                            if (rawWholesale.isNotEmpty) {
                              final wholesaleError = _validateNonNegativeMoney(
                                rawWholesale,
                                label: 'wholesale price',
                              );
                              if (wholesaleError != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(wholesaleError)),
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(saleError)),
                                );
                                return;
                              }
                            }

                            final sellingPrice = double.parse(sellingPriceController.text.trim());
                            if (sellingPrice <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Selling price must be greater than 0.')),
                              );
                              return;
                            }

                            final costPrice = double.parse(costPriceController.text.trim());
                            final wholesalePrice = rawWholesale.isEmpty
                                ? sellingPrice
                                : double.parse(rawWholesale);
                            final salePrice = rawSale.isEmpty ? null : double.parse(rawSale);
                            final openingStock = int.parse(openingStockController.text.trim());
                            final minStock = int.parse(minStockController.text.trim());

                            if (saleEnabled && (salePrice == null || salePrice <= 0)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Enter a valid sale price before activating sale mode.')),
                              );
                              return;
                            }

                            final confirmed = await _confirmAction(
                              title: 'Confirm Add Product',
                              message: 'Create $name with opening stock of $openingStock?',
                              confirmText: 'Create',
                            );
                            if (!confirmed) return;

                            final success = await DatabaseHelper.instance.createProductLocal(
                              barcode: barcode,
                              name: name,
                              category: category.isEmpty ? 'General' : category,
                              costPrice: costPrice,
                              sellingPrice: sellingPrice,
                              wholesalePrice: wholesalePrice,
                              salePrice: salePrice,
                              saleEnabled: saleEnabled,
                              openingStock: openingStock,
                              minStockLevel: minStock,
                              changedBy: changedBy,
                            );

                            if (!context.mounted) return;
                            Navigator.pop(context, success);
                          },
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text('Create Product'),
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

    nameController.dispose();
    barcodeController.dispose();
    categoryController.dispose();
    costPriceController.dispose();
    sellingPriceController.dispose();
    wholesalePriceController.dispose();
    salePriceController.dispose();
    openingStockController.dispose();
    minStockController.dispose();

    if (saved == true) {
      await _loadData(showLoader: false);
      _showMessage('Product added successfully.');
    } else if (saved == false) {
      _showMessage('Could not create product.', isError: true);
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

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        int? selectedSupplierId = preferredMapping.supplierId;
        bool setAsPrimary = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final selectedSupplier = selectedSupplierId == null
                ? null
                : suppliers
                    .where((supplier) => supplier.id == selectedSupplierId)
                    .cast<PosSupplier?>()
                    .firstOrNull;
            final selectedMapping = selectedSupplierId == null
                ? null
                : mappingBySupplierId[selectedSupplierId];

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
                      'Receive Stock',
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
                    DropdownButtonFormField<int>(
                      value: selectedSupplierId,
                      decoration: InputDecoration(
                        labelText: 'Supplier',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                        setModalState(() {
                          selectedSupplierId = value;
                          setAsPrimary = value != preferredMapping.supplierId;
                          final mappedCost = mapping?.defaultUnitCost ?? 0;
                          final resolvedCost = mappedCost > 0
                              ? mappedCost
                              : product.costPrice;
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
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (selectedSupplier != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F9FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE3E9F2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedSupplier.phone.trim().isEmpty
                                  ? 'Phone not available'
                                  : 'Phone • ${selectedSupplier.phone.trim()}',
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (selectedMapping != null &&
                                selectedMapping.defaultUnitCost > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Mapped cost • Rs. ${selectedMapping.defaultUnitCost.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: setAsPrimary,
                      title: const Text('Set as primary supplier for this product'),
                      subtitle: Text(
                        selectedSupplierId == preferredMapping.supplierId
                            ? 'This supplier is already the primary supplier for this product.'
                            : 'This supplier will be auto-selected next time you receive stock for this product.',
                      ),
                      onChanged: selectedSupplierId == null ||
                              selectedSupplierId == preferredMapping.supplierId
                          ? null
                          : (value) {
                              setModalState(() {
                                setAsPrimary = value;
                              });
                            },
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
                          if (selectedSupplierId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Select a mapped supplier first.'),
                              ),
                            );
                            return;
                          }

                          final qtyError = _validatePositiveInt(
                            qtyController.text,
                            label: 'quantity',
                          );
                          if (qtyError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(qtyError)),
                            );
                            return;
                          }

                          final rawCost = costController.text.trim();
                          if (rawCost.isNotEmpty) {
                            final costError = _validateNonNegativeMoney(
                              rawCost,
                              label: 'unit cost',
                            );
                            if (costError != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(costError)),
                              );
                              return;
                            }
                          }

                          final supplier = suppliers.firstWhere(
                            (item) => item.id == selectedSupplierId,
                          );
                          final selectedMapping = mappingBySupplierId[selectedSupplierId];
                          if (selectedMapping == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'This supplier is not linked to the selected product.',
                                ),
                              ),
                            );
                            return;
                          }

                          final qty = int.parse(qtyController.text.trim());
                          final unitCost = rawCost.isEmpty
                              ? null
                              : double.parse(rawCost);
                          final resolvedCost = unitCost ??
                              (selectedMapping.defaultUnitCost > 0
                                  ? selectedMapping.defaultUnitCost
                                  : product.costPrice);

                          final confirmed = await _confirmAction(
                            title: 'Confirm Stock Receive',
                            message:
                                'Receive $qty units of ${product.name} from ${supplier.name}? This will increase stock immediately.',
                            confirmText: 'Receive',
                          );
                          if (!confirmed) return;

                          final success = await DatabaseHelper.instance.receiveStockLocal(
                            product.barcode,
                            qty,
                            unitCost: unitCost,
                            performedBy: changedBy,
                            reason: noteController.text.trim(),
                          );

                          if (!success) {
                            if (!context.mounted) return;
                            Navigator.pop(context, false);
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

                          if (!context.mounted) return;
                          Navigator.pop(context, true);
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.60,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Supplier Info',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${product.name} • ${product.barcode}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  if (currentSupplier == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No supplier assigned yet.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Assign a preferred supplier so receiving stock becomes faster and supplier history stays linked to this product.',
                            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSupplier.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            currentSupplier.phone.trim().isEmpty
                                ? 'Phone not available'
                                : 'Phone • ${currentSupplier.phone.trim()}',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildPriceAvailabilityChip('Primary Supplier', Colors.blue),
                              if (preferredMapping != null &&
                                  preferredMapping.defaultUnitCost > 0)
                                _buildPriceAvailabilityChip(
                                  'Default Cost Rs. ${preferredMapping.defaultUnitCost.toStringAsFixed(2)}',
                                  Colors.deepPurple,
                                ),
                            ],
                          ),
                          if (lastReceipt != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Last received • ${_formatDateTime((lastReceipt.createdAt ?? '').toString())}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Last cost • Rs. ${(((lastReceipt.cost as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(const Duration(milliseconds: 120));
                          if (!mounted) return;
                          await _openReceiveFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.inventory_2),
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
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.link_outlined),
                        label: Text(
                          currentSupplier == null ? 'Assign Supplier' : 'Change Supplier',
                        ),
                      ),
                      if (currentSupplier != null)
                        OutlinedButton.icon(
                          onPressed: () async {
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
            ),
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
      description: 'Approved stock adjustment for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

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
                          final qtyError = _validatePositiveInt(
                            qtyController.text,
                            label: adjustmentType == 'set'
                                ? 'final stock quantity'
                                : 'quantity',
                            allowZero: adjustmentType == 'set',
                          );
                          if (qtyError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(qtyError)),
                            );
                            return;
                          }

                          final qty = int.parse(qtyController.text.trim());
                          int resultingStock;
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Resulting stock cannot be negative.'),
                              ),
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
                                'This will $actionLabel for ${product.name}. Final stock will be $resultingStock.',
                            confirmText: 'Apply',
                          );
                          if (!confirmed) return;

                          final success = await DatabaseHelper.instance.adjustStockLocal(
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
    final approval = await _requireManagerApproval(
      actionLabel: 'update minimum stock for ${product.name}',
      description: 'Approved minimum stock update for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

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
            decoration: const InputDecoration(
              labelText: 'Minimum stock level',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
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

                final success =
                    await DatabaseHelper.instance.updateProductMinStockLevelLocal(
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
    final product = initialProduct ??
        await _pickProduct(title: 'Select a product to change price');
    if (product == null || !mounted) return;

    final approval = await _requireManagerApproval(
      actionLabel: 'change prices for ${product.name}',
      description: 'Approved price change for ${product.name} (${product.barcode}) requested by $_currentUserName',
    );
    if (approval == null || !mounted) return;
    final changedBy = _buildPerformedByLabel(approval.approverName);

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
                          final priceError = _validateNonNegativeMoney(
                            valueController.text,
                            label: 'price',
                          );
                          if (priceError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(priceError)),
                            );
                            return;
                          }

                          final newPrice = double.parse(valueController.text.trim());
                          if (priceType == 'sale' && saleEnabled && newPrice <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Active sale price must be greater than 0.'),
                              ),
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

                          final success =
                              await DatabaseHelper.instance.updateProductPriceLocal(
                            product.barcode,
                            newPrice,
                            priceType: priceType,
                            changedBy: changedBy,
                            reason: noteController.text.trim(),
                            saleEnabled: priceType == 'sale' ? saleEnabled : null,
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
                      _buildDetailCard('Current Stock', product.stock.toString()),
                      _buildDetailCard('Min Stock', product.minStockLevel.toString()),
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
                          await Future.delayed(const Duration(milliseconds: 120));
                          if (!mounted) return;
                          await _openReceiveFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.inventory_2),
                        label: const Text('Receive'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(const Duration(milliseconds: 120));
                          if (!mounted) return;
                          await _openAdjustFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.tune),
                        label: const Text('Adjust'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(const Duration(milliseconds: 120));
                          if (!mounted) return;
                          await _openPriceChangeFlow(initialProduct: product);
                        },
                        icon: const Icon(Icons.sell),
                        label: const Text('Change Price'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(const Duration(milliseconds: 120));
                          if (!mounted) return;
                          await _openStockTakeScreen(barcode: product.barcode);
                        },
                        icon: const Icon(Icons.playlist_add_check_circle),
                        label: const Text('Count'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Future.delayed(const Duration(milliseconds: 120));
                          if (!mounted) return;
                          await _openMinStockDialog(product);
                        },
                        icon: const Icon(Icons.warning_amber_rounded),
                        label: const Text('Min Stock'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
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
                            _openInventoryHistoryScreen(barcode: product.barcode);
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
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
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
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
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
      case 'product_created':
        return 'Product Created';
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
                              title: 'Add Product',
                              icon: Icons.add_box_outlined,
                              onTap: () => _openAddProductFlow(),
                            ),
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
                              title: 'History',
                              icon: Icons.history,
                              onTap: () => _openInventoryHistoryScreen(),
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                              onPressed: () => _openInventoryHistoryScreen(),
                              child: const Text('View all'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_recentMovements.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text('No recent stock or price activity yet.'),
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

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
