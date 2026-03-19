import 'package:flutter/material.dart';
import 'package:shared/models/product.dart';

import '../models/pos_supplier.dart';
import '../models/supplier_product_mapping.dart';
import '../services/database_helper.dart';
import '../services/supplier_service.dart';

class SupplierProductMappingScreen extends StatefulWidget {
  const SupplierProductMappingScreen({
    super.key,
    this.initialSupplier,
  });

  final PosSupplier? initialSupplier;

  @override
  State<SupplierProductMappingScreen> createState() =>
      _SupplierProductMappingScreenState();
}

class _SupplierProductMappingScreenState extends State<SupplierProductMappingScreen> {
  final SupplierService _supplierService = SupplierService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<Product> _products = const [];
  List<PosSupplier> _suppliers = const [];
  List<SupplierProductMapping> _mappings = const [];
  Map<String, dynamic> _summary = const {};
  PosSupplier? _selectedSupplier;
  bool _mappedOnly = false;

  @override
  void initState() {
    super.initState();
    _selectedSupplier = widget.initialSupplier;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final suppliers = await _supplierService.getSuppliers(refreshFromBackend: false);
    final products = await DatabaseHelper.instance.getProducts();
    final mappings = await _supplierService.getSupplierProductMappings(
      supplierId: _selectedSupplier?.id,
      search: _searchController.text.trim(),
    );
    final summary = await _supplierService.getSupplierProductMappingSummary(
      supplierId: _selectedSupplier?.id,
    );

    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      _products = products;
      _mappings = mappings;
      _summary = summary;
      _isLoading = false;
    });
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    final mappedBarcodes = _mappings.map((e) => e.barcode).toSet();

    return _products.where((product) {
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
      if (!matchesQuery) return false;
      if (_mappedOnly && !mappedBarcodes.contains(product.barcode)) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<SupplierProductMapping> _mappingsForBarcode(String barcode) {
    final list = _mappings.where((e) => e.barcode == barcode).toList();
    list.sort((a, b) {
      if (a.isPreferred == b.isPreferred) {
        return a.supplierName.toLowerCase().compareTo(b.supplierName.toLowerCase());
      }
      return a.isPreferred ? -1 : 1;
    });
    return list;
  }

  Future<void> _editMapping(Product product) async {
    final existing = _mappingsForBarcode(product.barcode).firstWhere(
      (m) => _selectedSupplier == null || m.supplierId == _selectedSupplier!.id,
      orElse: () => SupplierProductMapping(
        barcode: product.barcode,
        productName: product.name,
        supplierId: _selectedSupplier?.id ?? (_suppliers.isNotEmpty ? _suppliers.first.id : 0),
        supplierName: _selectedSupplier?.name ?? (_suppliers.isNotEmpty ? _suppliers.first.name : ''),
        isPreferred: _selectedSupplier != null,
        defaultUnitCost: 0,
        minimumOrderQuantity: 1,
        packSize: 1,
        leadTimeDays: 0,
        note: '',
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );

    if (_suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No suppliers available.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    PosSupplier selectedSupplier = _suppliers.firstWhere(
      (s) => s.id == existing.supplierId,
      orElse: () => _selectedSupplier ?? _suppliers.first,
    );
    final costController = TextEditingController(
      text: existing.defaultUnitCost > 0 ? existing.defaultUnitCost.toStringAsFixed(2) : '',
    );
    final minQtyController = TextEditingController(
      text: existing.minimumOrderQuantity.toString(),
    );
    final packSizeController = TextEditingController(
      text: existing.packSize.toString(),
    );
    final leadTimeController = TextEditingController(
      text: existing.leadTimeDays.toString(),
    );
    final noteController = TextEditingController(text: existing.note);
    bool isPreferred = existing.isPreferred;
    bool deleteRequested = false;

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text('Supplier Mapping\n${product.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedSupplier.id,
                      decoration: const InputDecoration(
                        labelText: 'Supplier',
                        border: OutlineInputBorder(),
                      ),
                      items: _suppliers
                          .map(
                            (supplier) => DropdownMenuItem<int>(
                              value: supplier.id,
                              child: Text(supplier.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedSupplier = _suppliers.firstWhere((s) => s.id == value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: costController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Default Unit Cost',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: minQtyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min Order Qty',
                              border: OutlineInputBorder(),
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
                            controller: packSizeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Pack Size',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: leadTimeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Lead Days',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: isPreferred,
                      onChanged: (value) => setDialogState(() => isPreferred = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Preferred Supplier'),
                    ),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (existing.id != null)
                  TextButton(
                    onPressed: () {
                      deleteRequested = true;
                      Navigator.pop(dialogContext, true);
                    },
                    child: const Text('Delete'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!saved) return;

    if (deleteRequested) {
      if (existing.id != null) {
        await _supplierService.deleteSupplierProductMapping(existing.id!);
      }
      await _loadData();
      return;
    }

    final cost = double.tryParse(costController.text.trim()) ?? 0;
    final minQty = int.tryParse(minQtyController.text.trim()) ?? 1;
    final packSize = int.tryParse(packSizeController.text.trim()) ?? 1;
    final leadDays = int.tryParse(leadTimeController.text.trim()) ?? 0;

    final mapping = SupplierProductMapping(
      id: existing.id,
      barcode: product.barcode,
      productName: product.name,
      supplierId: selectedSupplier.id,
      supplierName: selectedSupplier.name,
      isPreferred: isPreferred,
      defaultUnitCost: cost < 0 ? 0 : cost,
      minimumOrderQuantity: minQty <= 0 ? 1 : minQty,
      packSize: packSize <= 0 ? 1 : packSize,
      leadTimeDays: leadDays < 0 ? 0 : leadDays,
      note: noteController.text.trim(),
      updatedAt: DateTime.now().toIso8601String(),
    );

    await _supplierService.saveSupplierProductMapping(mapping);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Supplier mapping saved.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.14),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialSupplier == null ? 'Supplier Product Mapping' : '${widget.initialSupplier!.name} Mapping'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                if (widget.initialSupplier == null) ...[
                  DropdownButtonFormField<int?>(
                    value: _selectedSupplier?.id,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Supplier',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All Suppliers')),
                      ..._suppliers.map(
                        (supplier) => DropdownMenuItem<int?>(
                          value: supplier.id,
                          child: Text(supplier.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSupplier = value == null ? null : _suppliers.firstWhere((s) => s.id == value);
                      });
                      _loadData();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search product or barcode',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _loadData();
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (_) => _loadData(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilterChip(
                        selected: !_mappedOnly,
                        label: const Text('All Products'),
                        onSelected: (_) => setState(() => _mappedOnly = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterChip(
                        selected: _mappedOnly,
                        label: const Text('Mapped Only'),
                        onSelected: (_) => setState(() => _mappedOnly = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _summaryCard(
                        label: 'Mappings',
                        value: ((_summary['mapping_count'] as num?) ?? 0).toInt().toString(),
                        color: Colors.blue,
                        icon: Icons.link,
                      ),
                      const SizedBox(width: 10),
                      _summaryCard(
                        label: 'Preferred',
                        value: ((_summary['preferred_count'] as num?) ?? 0).toInt().toString(),
                        color: Colors.green,
                        icon: Icons.star_border,
                      ),
                      const SizedBox(width: 10),
                      _summaryCard(
                        label: 'Avg Cost',
                        value: 'Rs. ${(((_summary['avg_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                        color: Colors.deepPurple,
                        icon: Icons.payments_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? const Center(child: Text('No products found for mapping.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final mappings = _mappingsForBarcode(product.barcode);
                          final preferred = mappings.isEmpty ? null : mappings.first;

                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
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
                                            Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            const SizedBox(height: 4),
                                            Text('Barcode: ${product.barcode}', style: TextStyle(color: Colors.grey[700])),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () => _editMapping(product),
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        label: const Text('Map'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (preferred == null)
                                    Text('No supplier mapping yet.', style: TextStyle(color: Colors.grey[700]))
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _pill('Preferred: ${preferred.supplierName}', Colors.indigo),
                                        _pill('Cost: Rs. ${preferred.defaultUnitCost.toStringAsFixed(2)}', Colors.green),
                                        _pill('MOQ: ${preferred.minimumOrderQuantity}', Colors.orange),
                                        _pill('Pack: ${preferred.packSize}', Colors.blueGrey),
                                        _pill('Lead: ${preferred.leadTimeDays}d', Colors.deepPurple),
                                      ],
                                    ),
                                  if (mappings.length > 1) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Also mapped to: ${mappings.skip(1).map((e) => e.supplierName).join(', ')}',
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
