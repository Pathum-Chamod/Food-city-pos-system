import 'package:flutter/material.dart';

import '../models/pos_supplier.dart';
import '../services/purchase_order_service.dart';
import '../services/supplier_service.dart';
import 'purchase_order_editor_screen.dart';
import 'purchase_order_list_screen.dart';
import 'supplier_receive_history_screen.dart';
import 'supplier_workspace_screen.dart';
import 'supplier_purchase_history_screen.dart';

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
  final PurchaseOrderService _purchaseOrderService = PurchaseOrderService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<PosSupplier> _suppliers = const [];
  Map<String, dynamic> _receiveSummary = const {};
  Map<String, dynamic> _poSummary = const {};

  @override
  void initState() {
    super.initState();
    _loadData(refreshFromBackend: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool refreshFromBackend = false}) async {
    setState(() {
      _isLoading = true;
    });

    final suppliers = await _supplierService.getSuppliers(
      refreshFromBackend: refreshFromBackend,
    );
    final receiveSummary = await _supplierService.getReceiveSummary();
    final poSummary = await _purchaseOrderService.getSummary();

    if (!mounted) return;

    setState(() {
      _suppliers = suppliers;
      _receiveSummary = receiveSummary;
      _poSummary = poSummary;
      _isLoading = false;
    });
  }

  List<PosSupplier> get _filteredSuppliers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _suppliers;

    return _suppliers.where((supplier) {
      return supplier.name.toLowerCase().contains(query) ||
          supplier.phone.toLowerCase().contains(query) ||
          supplier.id.toString().contains(query);
    }).toList();
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SupplierReceiveHistoryScreen(),
      ),
    );
    await _loadData(refreshFromBackend: false);
  }

  Future<void> _openPurchaseHistory({PosSupplier? supplier}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierPurchaseHistoryScreen(supplier: supplier),
      ),
    );
    await _loadData(refreshFromBackend: false);
  }

  Future<void> _openPurchaseOrders({PosSupplier? supplier}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderListScreen(
          cashierName: widget.cashierName,
          initialSupplier: supplier,
        ),
      ),
    );
    await _loadData(refreshFromBackend: false);
  }

  Future<void> _createPurchaseOrder({PosSupplier? supplier}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderEditorScreen(
          cashierName: widget.cashierName,
          initialSupplier: supplier,
        ),
      ),
    );
    await _loadData(refreshFromBackend: false);
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 200,
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
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
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
    final filteredSuppliers = _filteredSuppliers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Operations'),
        actions: [
          IconButton(
            tooltip: 'Purchase orders',
            onPressed: () => _openPurchaseOrders(),
            icon: const Icon(Icons.description_outlined),
          ),
          IconButton(
            tooltip: 'Receive history',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Purchase history',
            onPressed: () => _openPurchaseHistory(),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: 'Refresh suppliers',
            onPressed: () => _loadData(refreshFromBackend: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPurchaseOrder(),
        icon: const Icon(Icons.add),
        label: const Text('New PO'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(refreshFromBackend: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manager Supplier Workspace',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use this area to receive stock from suppliers, create local purchase orders, and keep supplier activity on the store machine behind manager PIN.',
                      style: TextStyle(color: Colors.grey[700], height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _openPurchaseOrders(),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Open Purchase Orders'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _createPurchaseOrder(),
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Create New PO'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openHistory,
                          icon: const Icon(Icons.history),
                          label: const Text('Receive History'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openPurchaseHistory(),
                          icon: const Icon(Icons.insights_outlined),
                          label: const Text('Purchase History'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSummaryCard(
                    label: 'Suppliers',
                    value: _suppliers.length.toString(),
                    icon: Icons.local_shipping,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Receipts Logged',
                    value: ((_receiveSummary['receipt_count'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'Purchase Orders',
                    value: ((_poSummary['order_count'] as num?) ?? 0)
                        .toInt()
                        .toString(),
                    icon: Icons.description_outlined,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(width: 10),
                  _buildSummaryCard(
                    label: 'PO Value',
                    value: 'Rs. ${(((_poSummary['total_cost'] as num?) ?? 0).toDouble()).toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                    color: Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search suppliers by name or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredSuppliers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No suppliers found.')),
              )
            else
              ...filteredSuppliers.map(
                (supplier) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.orange.withOpacity(0.12),
                          child: const Icon(
                            Icons.local_shipping,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                supplier.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                supplier.phone.isEmpty
                                    ? 'Phone not available'
                                    : 'Phone: ${supplier.phone}',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _chip('Supplier ID: ${supplier.id}'),
                                  _chip('Receive + PO ready'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SupplierWorkspaceScreen(
                                            supplier: supplier,
                                            cashierName: widget.cashierName,
                                          ),
                                        ),
                                      );
                                      await _loadData(refreshFromBackend: false);
                                    },
                                    icon: const Icon(Icons.storefront_outlined),
                                    label: const Text('Open Workspace'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _createPurchaseOrder(
                                      supplier: supplier,
                                    ),
                                    icon: const Icon(Icons.add_business_outlined),
                                    label: const Text('New PO'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _openPurchaseHistory(
                                      supplier: supplier,
                                    ),
                                    icon: const Icon(Icons.insights_outlined),
                                    label: const Text('History'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
