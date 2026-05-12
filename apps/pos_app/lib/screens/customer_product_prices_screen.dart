import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

import '../services/customer_pricing_service.dart';
import '../services/database_helper.dart';
import '../widgets/app_snackbar.dart';
import 'customer_product_price_dialog.dart';

class CustomerProductPricesScreen extends StatefulWidget {
  const CustomerProductPricesScreen({super.key, required this.customer});

  final Customer customer;

  @override
  State<CustomerProductPricesScreen> createState() =>
      _CustomerProductPricesScreenState();
}

class _CustomerProductPricesScreenState
    extends State<CustomerProductPricesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<CustomerProductPrice> _prices = [];
  List<Product> _products = [];
  bool _isLoading = true;

  static const Color _brand = Color(0xFF2AAA8A);
  static const Color _warning = Color(0xFFFFB65C);
  static const Color _danger = Color(0xFFFF6B7A);
  static const Color _success = Color(0xFF1FCF9A);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _panel => _isDark ? const Color(0xFF0F1C31) : Colors.white;
  Color get _border =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customerId = widget.customer.id ?? 0;
      final results = await Future.wait([
        CustomerPricingService.instance.getProductPricesForCustomer(customerId),
        DatabaseHelper.instance.getProducts(),
      ]);

      if (!mounted) return;
      setState(() {
        _prices = results[0] as List<CustomerProductPrice>;
        _products = results[1] as List<Product>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prices = [];
        _products = [];
        _isLoading = false;
      });
      _showMessage('Could not load customer product prices.', color: _danger);
    }
  }

  void _showMessage(String message, {Color color = _brand}) {
    AppSnackBar.show(context, message: message, backgroundColor: color);
  }

  String _money(num value) {
    return 'Rs. ${value.toDouble().toStringAsFixed(2)}';
  }

  Product? _productForBarcode(String barcode) {
    for (final product in _products) {
      if (product.barcode == barcode) return product;
    }
    return null;
  }

  List<CustomerProductPrice> get _filteredPrices {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _prices;

    return _prices.where((price) {
      return price.productNameSnapshot.toLowerCase().contains(query) ||
          price.barcode.toLowerCase().contains(query) ||
          (price.note ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addPrice() async {
    final customerId = widget.customer.id ?? 0;
    if (customerId <= 0) return;

    final result = await showCustomerProductPriceDialog(
      context: context,
      products: _products,
    );
    if (result == null) return;

    try {
      await CustomerPricingService.instance.upsertProductPrice(
        customerId: customerId,
        barcode: result.product.barcode,
        productNameSnapshot: result.product.name,
        fixedPrice: result.fixedPrice,
        isActive: result.isActive,
        note: result.note,
      );
      if (!mounted) return;
      _showMessage('Customer product price saved.', color: _success);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  Future<void> _editPrice(CustomerProductPrice price) async {
    final customerId = widget.customer.id ?? 0;
    if (customerId <= 0) return;

    final result = await showCustomerProductPriceDialog(
      context: context,
      products: _products,
      existingPrice: price,
    );
    if (result == null) return;

    try {
      await CustomerPricingService.instance.upsertProductPrice(
        id: price.id,
        customerId: customerId,
        barcode: result.product.barcode,
        productNameSnapshot: result.product.name,
        fixedPrice: result.fixedPrice,
        isActive: result.isActive,
        note: result.note,
      );
      if (!mounted) return;
      _showMessage('Customer product price updated.', color: _success);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  Future<void> _toggleActive(CustomerProductPrice price) async {
    final id = price.id;
    if (id == null || id <= 0) return;

    try {
      await CustomerPricingService.instance.setProductPriceActive(
        id: id,
        isActive: !price.isActive,
      );
      if (!mounted) return;
      _showMessage(
        price.isActive ? 'Product price deactivated.' : 'Product price active.',
        color: _success,
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        color: _danger,
      );
    }
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      labelText: 'Search product prices',
      hintText: 'Product name, barcode, or note',
      prefixIcon: const Icon(Icons.search_rounded),
      filled: true,
      fillColor: _panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _prices.where((price) => price.isActive).length;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Customer Product Prices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _addPrice,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Price'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(activeCount),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      decoration: _searchDecoration(),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    if (_filteredPrices.isEmpty)
                      _emptyState()
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredPrices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _priceRow(_filteredPrices[index]);
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(int activeCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _brand.withValues(alpha: 0.24)),
            ),
            child: const Icon(
              Icons.price_change_rounded,
              color: _brand,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customer.displayName,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.customer.displayCode} - $activeCount active of ${_prices.length} product prices',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _addPrice,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Price'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Text(
        'No customer-specific product prices yet.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _priceRow(CustomerProductPrice price) {
    final product = _productForBarcode(price.barcode);
    final normalPrice = product?.sellingPrice ?? price.fixedPrice;
    final savings = normalPrice - price.fixedPrice;
    final statusColor = price.isActive ? _brand : _textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: price.isActive ? _brand.withValues(alpha: 0.22) : _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.inventory_2_rounded, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      price.productNameSnapshot,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    _statusPill(price.isActive),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${price.barcode} - Normal ${_money(normalPrice)} - Customer ${_money(price.fixedPrice)}',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if ((price.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    price.note!.trim(),
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _amountColumn(
            label: savings >= 0 ? 'Saving' : 'Higher by',
            value: _money(savings.abs()),
            color: savings >= 0 ? _brand : _warning,
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _editPrice(price),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: price.isActive ? 'Deactivate' : 'Activate',
            onPressed: () => _toggleActive(price),
            icon: Icon(
              price.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              color: price.isActive ? _brand : _textSecondary,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool isActive) {
    final color = isActive ? _brand : _textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _amountColumn({
    required String label,
    required String value,
    required Color color,
  }) {
    return SizedBox(
      width: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
