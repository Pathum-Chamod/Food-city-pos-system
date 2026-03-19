import 'package:flutter/material.dart';
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_item.dart';
import '../services/database_helper.dart';
import '../services/purchase_order_service.dart';

class PurchaseOrderEditorScreen extends StatefulWidget {
  const PurchaseOrderEditorScreen({
    super.key,
    required this.cashierName,
    this.purchaseOrderId,
    this.initialSupplier,
  });

  final String cashierName;
  final int? purchaseOrderId;
  final PosSupplier? initialSupplier;

  @override
  State<PurchaseOrderEditorScreen> createState() =>
      _PurchaseOrderEditorScreenState();
}

class _PurchaseOrderEditorScreenState extends State<PurchaseOrderEditorScreen> {
  final PurchaseOrderService _service = PurchaseOrderService();
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final TextEditingController _orderNumberController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  List<PosSupplier> _suppliers = const [];
  List<Product> _products = const [];
  List<PurchaseOrderItem> _items = <PurchaseOrderItem>[];

  PosSupplier? _selectedSupplier;
  String _status = 'draft';
  PurchaseOrder? _existingOrder;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _orderNumberController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    final suppliers = await _service.getSuppliers(refreshFromBackend: false);
    final products = await _databaseHelper.getProducts();

    PurchaseOrder? order;
    List<PurchaseOrderItem> items = const [];

    if (widget.purchaseOrderId != null) {
      order = await _service.getOrder(widget.purchaseOrderId!);
      items = await _service.getOrderItems(widget.purchaseOrderId!);
    }

    PosSupplier? resolvedSupplier = widget.initialSupplier;

    if (order != null) {
      for (final supplier in suppliers) {
        if (supplier.id == order.supplierId) {
          resolvedSupplier = supplier;
          break;
        }
      }
    } else if (resolvedSupplier != null) {
      final initialSupplier = resolvedSupplier;
      bool found = false;

      for (final supplier in suppliers) {
        if (supplier.id == initialSupplier.id) {
          resolvedSupplier = supplier;
          found = true;
          break;
        }
      }

      if (!found && suppliers.isNotEmpty) {
        resolvedSupplier = suppliers.first;
      }
    } else if (suppliers.isNotEmpty) {
      resolvedSupplier = suppliers.first;
    }

    if (!mounted) return;

    setState(() {
      _suppliers = suppliers;
      _products = products;
      _existingOrder = order;
      _items = List<PurchaseOrderItem>.from(items);
      _selectedSupplier = resolvedSupplier;
      _status = order?.status ?? 'draft';
      _orderNumberController.text =
          order?.orderNumber ?? _service.generateOrderNumber();
      _referenceController.text = order?.referenceNote ?? '';
      _isLoading = false;
    });
  }

  int get _totalUnits =>
      _items.fold<int>(0, (sum, item) => sum + item.quantity);

  double get _totalCost =>
      _items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  String _statusLabel(String value) {
    switch (value) {
      case 'draft':
        return 'Draft';
      case 'ordered':
        return 'Ordered';
      case 'partially_received':
        return 'Partially Received';
      case 'received':
        return 'Received';
      case 'cancelled':
        return 'Cancelled';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'ordered':
        return Colors.blue;
      case 'partially_received':
        return Colors.orange;
      case 'received':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'draft':
      default:
        return Colors.deepPurple;
    }
  }

  Future<void> _pickProductToAdd() async {
    final selected = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final searchController = TextEditingController();
        List<Product> visibleProducts = List<Product>.from(_products);

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: 540,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Product to Purchase Order',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        onChanged: (value) {
                          final query = value.trim().toLowerCase();
                          setSheetState(() {
                            visibleProducts = _products.where((product) {
                              return query.isEmpty ||
                                  product.name.toLowerCase().contains(query) ||
                                  product.barcode.toLowerCase().contains(query);
                            }).toList();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search name or barcode',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    searchController.clear();
                                    setSheetState(() {
                                      visibleProducts = List<Product>.from(
                                        _products,
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visibleProducts.isEmpty
                            ? const Center(child: Text('No products found.'))
                            : ListView.separated(
                                itemCount: visibleProducts.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final product = visibleProducts[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    tileColor: Colors.grey.shade50,
                                    title: Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Barcode: ${product.barcode} • Stock: ${product.stock}',
                                    ),
                                    trailing: const Icon(
                                      Icons.add_circle_outline,
                                    ),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, product),
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

    if (selected != null) {
      await _showLineDialog(product: selected);
    }
  }

  Future<void> _showLineDialog({
    required Product product,
    PurchaseOrderItem? existingItem,
  }) async {
    final qtyController = TextEditingController(
      text: existingItem?.quantity.toString() ?? '1',
    );
    final costController = TextEditingController(
      text: existingItem?.unitCost.toStringAsFixed(2) ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existingItem == null
              ? 'Add Item\n${product.name}'
              : 'Edit Item\n${product.name}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('Barcode: ${product.barcode}'),
                    const SizedBox(height: 4),
                    Text('Current stock: ${product.stock}'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Order Quantity',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Unit Cost (Rs.)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existingItem != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _items.removeWhere(
                    (item) => item.barcode == existingItem.barcode,
                  );
                });
                Navigator.pop(dialogContext);
              },
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text.trim()) ?? 0;
              final unitCost =
                  double.tryParse(costController.text.trim()) ?? -1;

              if (qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Quantity must be greater than 0.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (unitCost < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid unit cost.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final item = PurchaseOrderItem(
                id: existingItem?.id,
                purchaseOrderId: existingItem?.purchaseOrderId,
                barcode: product.barcode,
                productName: product.name,
                quantity: qty,
                receivedQuantity: existingItem?.receivedQuantity ?? 0,
                unitCost: unitCost,
                createdAt:
                    existingItem?.createdAt ?? DateTime.now().toIso8601String(),
              );

              setState(() {
                final existingIndex = _items.indexWhere(
                  (line) => line.barcode == product.barcode,
                );
                if (existingIndex >= 0) {
                  _items[existingIndex] = item;
                } else {
                  _items.add(item);
                }
              });

              Navigator.pop(dialogContext);
            },
            child: const Text('Save Item'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveOrder() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a supplier.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one product to the PO.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final orderId = await _service.saveOrder(
        purchaseOrderId: widget.purchaseOrderId,
        orderNumber: _orderNumberController.text.trim().isEmpty
            ? _service.generateOrderNumber()
            : _orderNumberController.text.trim(),
        supplier: _selectedSupplier!,
        status: _status,
        referenceNote: _referenceController.text.trim(),
        items: _items,
        createdBy: widget.cashierName,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        widget.purchaseOrderId == null ? 'created' : 'updated',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save purchase order.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteOrder() async {
    if (widget.purchaseOrderId == null) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete Purchase Order?'),
            content: const Text(
              'This will remove the purchase order and all local line items from POS.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _service.deleteOrder(widget.purchaseOrderId!);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withOpacity(0.14),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(_status);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.purchaseOrderId == null
              ? 'Create Purchase Order'
              : 'Edit Purchase Order',
        ),
        actions: [
          if (widget.purchaseOrderId != null)
            IconButton(
              tooltip: 'Delete order',
              onPressed: _deleteOrder,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Purchase Order Header',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _orderNumberController,
                            decoration: const InputDecoration(
                              labelText: 'PO Number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<PosSupplier>(
                            value: _selectedSupplier,
                            items: _suppliers
                                .map(
                                  (supplier) => DropdownMenuItem<PosSupplier>(
                                    value: supplier,
                                    child: Text(supplier.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedSupplier = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Supplier',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _status,
                            items: PurchaseOrderService.statuses
                                .map(
                                  (status) => DropdownMenuItem<String>(
                                    value: status,
                                    child: Text(_statusLabel(status)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _status = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _referenceController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Reference Note',
                              hintText:
                                  'Invoice draft note, supplier remark, delivery note',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(_status),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.cashierName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildSummaryCard(
                        label: 'Lines',
                        value: _items.length.toString(),
                        color: Colors.blue,
                        icon: Icons.list_alt,
                      ),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                        label: 'Units',
                        value: _totalUnits.toString(),
                        color: Colors.orange,
                        icon: Icons.inventory_2_outlined,
                      ),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                        label: 'Total',
                        value: 'Rs. ${_totalCost.toStringAsFixed(2)}',
                        color: Colors.green,
                        icon: Icons.payments_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickProductToAdd,
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          label: const Text('Add Product'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No items added yet.')),
                      ),
                    )
                  else
                    ..._items.map((item) {
                      Product? product;
                      for (final p in _products) {
                        if (p.barcode == item.barcode) {
                          product = p;
                          break;
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          title: Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _pill('Qty: ${item.quantity}'),
                                _pill(
                                  'Unit: Rs. ${item.unitCost.toStringAsFixed(2)}',
                                ),
                                _pill(
                                  'Line: Rs. ${item.lineTotal.toStringAsFixed(2)}',
                                ),
                                if (item.receivedQuantity > 0)
                                  _pill('Received: ${item.receivedQuantity}'),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            onPressed: product == null
                                ? null
                                : () => _showLineDialog(
                                    product: product!,
                                    existingItem: item,
                                  ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _status = 'draft';
                          });
                          _saveOrder();
                        },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          if (_status == 'draft') {
                            setState(() {
                              _status = 'ordered';
                            });
                          }
                          _saveOrder();
                        },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.purchaseOrderId == null
                              ? 'Create PO'
                              : 'Save Changes',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
