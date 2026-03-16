import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../config/pos_feature_flags.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../widgets/admin_dialogs.dart';
import 'cart_discount_dialog.dart';
import 'checkout_payment_dialog.dart';
import 'held_carts_screen.dart';
import 'login_screen.dart';
import 'shift_management_screen.dart';
import 'transaction_history_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Product> _products = [];
  bool _isLoadingProducts = true;
  bool _isProcessingCheckout = false;
  bool _isRefreshingProducts = false;
  Timer? _productRefreshTimer;

  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = '';
  Map<String, dynamic>? _currentShiftSummary;

  @override
  void initState() {
    super.initState();
    _loadProducts(showLoader: true);
    _refreshProductsFromBackendAndReload(silentOnFailure: true);
    _startAutoRefresh();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusBarcodeField();
      if (PosFeatureFlags.enableShiftManagement) {
        _loadShiftSummary();
      }
    });
  }

  @override
  void dispose() {
    _productRefreshTimer?.cancel();
    _barcodeController.dispose();
    _searchController.dispose();
    _barcodeFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadShiftSummary() async {
    if (!PosFeatureFlags.enableShiftManagement) {
      if (!mounted) return;
      setState(() {
        _currentShiftSummary = null;
      });
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
    final summary =
        await DatabaseHelper.instance.getOpenShiftSummaryForCashier(cashierName);

    if (!mounted) return;

    setState(() {
      _currentShiftSummary = summary;
    });
  }

  void _focusBarcodeField() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      _barcodeFocusNode.requestFocus();
    });
  }

  void _startAutoRefresh() {
    _productRefreshTimer?.cancel();
    _productRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshProductsFromBackendAndReload(silentOnFailure: true);
      if (PosFeatureFlags.enableShiftManagement) {
        _loadShiftSummary();
      }
    });
  }

  Future<void> _loadProducts({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoadingProducts = true;
      });
    }

    final products = await DatabaseHelper.instance.getProducts();

    if (!mounted) return;

    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
  }

  Future<bool> _refreshProductsFromBackendAndReload({
    bool showSuccessMessage = false,
    bool silentOnFailure = false,
  }) async {
    if (_isRefreshingProducts) return false;

    setState(() {
      _isRefreshingProducts = true;
    });

    try {
      final success = await SyncService().refreshProductsFromBackend();

      await _loadProducts(showLoader: false);

      if (!mounted) return success;

      if (success && showSuccessMessage) {
        _showInfoMessage(
          'Products refreshed from backend.',
          backgroundColor: Colors.green,
        );
      } else if (!success && !silentOnFailure) {
        _showInfoMessage(
          'Could not refresh products from backend.',
          backgroundColor: Colors.orange,
        );
      }

      return success;
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingProducts = false;
        });
      }
    }
  }

  void _showInfoMessage(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Product? _findProductByBarcode(String barcode) {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    try {
      return _products.firstWhere((product) => product.barcode == trimmed);
    } catch (_) {
      return null;
    }
  }

  Product? _getCurrentProduct(String barcode) {
    try {
      return _products.firstWhere((product) => product.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  int _getCurrentStock(String barcode, {int fallback = 0}) {
    return _getCurrentProduct(barcode)?.stock ?? fallback;
  }

  List<Product> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) return _products;

    return _products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
    }).toList();
  }

  void _handleBarcodeSubmit(CartProvider cart) {
    final barcode = _barcodeController.text.trim();

    if (barcode.isEmpty) {
      _focusBarcodeField();
      return;
    }

    final product = _findProductByBarcode(barcode);

    if (product == null) {
      _barcodeController.clear();
      _showInfoMessage(
        'Product not found for barcode: $barcode',
        backgroundColor: Colors.red,
      );
      _focusBarcodeField();
      return;
    }

    _handleProductTap(product, cart);
    _barcodeController.clear();
    _focusBarcodeField();
  }

  void _handleProductTap(Product product, CartProvider cart) {
    if (!cart.isRefundMode && product.stock <= 0) {
      _showInfoMessage(
        'This item is out of stock.',
        backgroundColor: Colors.red,
      );
      return;
    }

    final currentQtyInCart = cart.getQuantityFor(product.barcode);

    if (!cart.isRefundMode && currentQtyInCart >= product.stock) {
      _showInfoMessage(
        'Cannot add more than available stock for ${product.name}.',
        backgroundColor: Colors.red,
      );
      return;
    }

    cart.addToCart(product);
    _focusBarcodeField();
  }

  Future<void> _showReceiptForTransaction(int saleId) async {
    await TransactionHistoryScreen.showReceiptDialogForTransaction(
      context,
      saleId,
    );
    _focusBarcodeField();
  }

  Future<void> _applyDiscount(CartProvider cart) async {
    if (cart.items.isEmpty) {
      _showInfoMessage(
        'Add items before applying a discount.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    if (cart.isRefundMode) {
      _showInfoMessage(
        'Discounts are not available in refund mode.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    AdminDialogs.showPinDialog(context, () async {
      final result = await showCartDiscountDialog(
        context,
        subtotal: cart.subtotal,
        currentDiscountType: cart.discountType,
        currentDiscountValue: cart.discountValue,
      );

      if (!mounted || result == null) return;

      cart.setDiscount(
        discountType: (result['discount_type'] ?? 'none').toString(),
        discountValue: ((result['discount_value'] as num?) ?? 0).toDouble(),
      );

      _focusBarcodeField();
    });
  }

  Future<void> _handleCheckout(CartProvider cart) async {
    if (cart.items.isEmpty || _isProcessingCheckout) return;

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    if (PosFeatureFlags.enableShiftManagement) {
      final openShift =
          await DatabaseHelper.instance.getOpenShiftSummaryForCashier(
        cashierName,
      );

      if (openShift == null) {
        if (!mounted) return;
        _showInfoMessage(
          'Open a shift before processing transactions.',
          backgroundColor: Colors.red,
        );
        return;
      }

      setState(() {
        _currentShiftSummary = openShift;
      });
    }

    final isRefund = cart.isRefundMode;
    final subtotal = cart.subtotal;
    final displayTotal = cart.cartTotal;
    final itemsMap = cart.getCartItemsAsMap();

    String? paymentMethod;
    double? amountTendered;
    double? changeAmount;

    if (!isRefund) {
      final paymentResult = await showCheckoutPaymentDialog(
        context,
        totalAmount: displayTotal,
      );

      if (paymentResult == null) {
        _focusBarcodeField();
        return;
      }

      paymentMethod = paymentResult['payment_method']?.toString();
      amountTendered = (paymentResult['amount_tendered'] as num?)?.toDouble();
      changeAmount = (paymentResult['change_amount'] as num?)?.toDouble();
    }

    setState(() {
      _isProcessingCheckout = true;
    });

    try {
      final saleId = await DatabaseHelper.instance.processTransaction(
        subtotalAmount: subtotal,
        totalAmount: displayTotal,
        cartItems: itemsMap,
        cashierName: cashierName,
        isRefund: isRefund,
        paymentMethod: paymentMethod,
        amountTendered: amountTendered,
        changeAmount: changeAmount,
        discountType: cart.discountType,
        discountValue: cart.discountValue,
        discountAmount: cart.discountAmount,
      );

      cart.clearCart();

      await SyncService().syncNow();
      await _refreshProductsFromBackendAndReload(silentOnFailure: true);
      if (PosFeatureFlags.enableShiftManagement) {
        await _loadShiftSummary();
      }

      if (!mounted) return;

      final title = isRefund ? '✅ Refund Completed' : '✅ Payment Successful';
      final amountLabel = isRefund ? 'Refund Amount' : 'Total Paid';

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(
            '$amountLabel: Rs. ${displayTotal.toStringAsFixed(2)}\n\n'
            'Transaction #$saleId was saved locally. Sync was attempted now and the product list has been refreshed from backend.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _focusBarcodeField();
              },
              child: const Text('Next Customer'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _showReceiptForTransaction(saleId);
              },
              child: const Text('View Receipt'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().replaceFirst('Exception: ', '');

      _showInfoMessage(
        message.isEmpty ? 'Error processing checkout.' : message,
        backgroundColor: Colors.red,
      );
      _focusBarcodeField();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingCheckout = false;
        });
      }
    }
  }

  Future<void> _openShiftManagement() async {
    if (!PosFeatureFlags.enableShiftManagement) return;

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftManagementScreen(cashierName: cashierName),
      ),
    );

    await _loadShiftSummary();
    _focusBarcodeField();
  }

  Future<void> _holdCurrentCart(CartProvider cart) async {
    if (cart.items.isEmpty) return;

    final controller = TextEditingController();

    final cartName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hold Cart'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Cart Name',
            hintText: 'Example: Customer 1 / Counter Hold',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Hold'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (cartName == null) {
      _focusBarcodeField();
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    try {
      await DatabaseHelper.instance.saveHeldCart(
        cartName: cartName,
        cashierName: cashierName,
        isRefundMode: cart.isRefundMode,
        discountType: cart.discountType,
        discountValue: cart.discountValue,
        items: cart.getCartItemsAsMap(),
      );

      cart.clearCart();

      if (!mounted) return;

      _showInfoMessage(
        'Cart held successfully.',
        backgroundColor: Colors.green,
      );
      _focusBarcodeField();
    } catch (e) {
      if (!mounted) return;

      _showInfoMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: Colors.red,
      );
      _focusBarcodeField();
    }
  }

  Future<bool> _confirmReplaceCurrentCartIfNeeded(CartProvider cart) async {
    if (cart.items.isEmpty) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace Current Cart?'),
        content: const Text(
          'Resuming a held cart will replace the current cart. Hold or clear the current cart first if you want to keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  List<Map<String, dynamic>> _prepareResumedCartItems(
    List<Map<String, dynamic>> rawItems,
  ) {
    return rawItems.map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final productMap = Map<String, dynamic>.from(item['product'] as Map);
      final barcode = productMap['barcode']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;

      final latestProduct = _getCurrentProduct(barcode);
      final resolvedProduct = latestProduct?.toMap() ?? productMap;
      final resolvedPrice =
          ((resolvedProduct['price'] as num?) ?? 0).toDouble();

      return {
        'product': resolvedProduct,
        'quantity': quantity <= 0 ? 1 : quantity,
        'line_total': resolvedPrice * (quantity <= 0 ? 1 : quantity),
      };
    }).toList();
  }

  Future<void> _openHeldCarts(CartProvider cart) async {
    final canProceed = await _confirmReplaceCurrentCartIfNeeded(cart);
    if (!canProceed) {
      _focusBarcodeField();
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    final restored = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => HeldCartsScreen(cashierName: cashierName),
      ),
    );

    if (!mounted || restored == null) {
      _focusBarcodeField();
      return;
    }

    final restoredItems = (restored['items'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final preparedItems = _prepareResumedCartItems(restoredItems);

    cart.loadHeldCart(
      items: preparedItems,
      isRefundMode: (restored['is_refund_mode'] ?? false) == true,
      discountType: (restored['discount_type'] ?? 'none').toString(),
      discountValue: ((restored['discount_value'] as num?) ?? 0).toDouble(),
    );

    _showInfoMessage(
      'Held cart resumed.',
      backgroundColor: Colors.green,
    );
    _focusBarcodeField();
  }

  Widget _buildShiftStatusChip() {
    final shift = _currentShiftSummary;
    final isOpen = shift != null;

    return Container(
      margin: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isOpen ? Colors.green[100] : Colors.orange[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isOpen ? Colors.green : Colors.orange),
      ),
      child: Row(
        children: [
          Icon(
            isOpen ? Icons.badge : Icons.badge_outlined,
            color: isOpen ? Colors.green[700] : Colors.orange[800],
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isOpen ? 'SHIFT OPEN' : 'SHIFT CLOSED',
            style: TextStyle(
              color: isOpen ? Colors.green[900] : Colors.orange[900],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _barcodeController,
                  focusNode: _barcodeFocusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleBarcodeSubmit(cart),
                  decoration: InputDecoration(
                    labelText: 'Scan / Enter Barcode',
                    hintText: 'Example: 4791044000123',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    suffixIcon: _barcodeController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear barcode',
                            onPressed: () {
                              _barcodeController.clear();
                              setState(() {});
                              _focusBarcodeField();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _handleBarcodeSubmit(cart),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Search Products',
                    hintText: 'Search by name or barcode',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                              _focusBarcodeField();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Showing ${_filteredProducts.length} of ${_products.length} products',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_searchQuery.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Filter: "${_searchQuery.trim()}"',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, CartProvider cart) {
    final isOutOfStock = product.stock <= 0 && !cart.isRefundMode;
    final cartQty = cart.getQuantityFor(product.barcode);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleProductTap(product, cart),
        onLongPress: () {
          AdminDialogs.showPinDialog(context, () {
            AdminDialogs.showEditPriceDialog(
              context,
              product.barcode,
              product.name,
              product.price,
              () async {
                await _refreshProductsFromBackendAndReload(
                  silentOnFailure: true,
                );
              },
            );
          });
        },
        child: Container(
          color: isOutOfStock ? Colors.grey[200] : Colors.white,
          padding: const EdgeInsets.all(12.0),
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        product.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              isOutOfStock ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rs. ${product.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isOutOfStock ? Colors.grey : Colors.green,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.barcode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOutOfStock ? Colors.red[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isOutOfStock ? 'Out of Stock' : 'Stock: ${product.stock}',
                        style: TextStyle(
                          color:
                              isOutOfStock ? Colors.red[700] : Colors.blue[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (cartQty > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[700],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'In Cart: $cartQty',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartItemRow(CartProvider cart, CartItem item) {
    final currentStock = _getCurrentStock(
      item.product.barcode,
      fallback: item.product.stock,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item',
                  onPressed: () {
                    cart.removeItem(item.product.barcode);
                    _focusBarcodeField();
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Rs. ${item.product.price.toStringAsFixed(2)} each',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    cart.decreaseQuantity(item.product.barcode);
                    _focusBarcodeField();
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '${item.quantity}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    if (!cart.isRefundMode && item.quantity >= currentStock) {
                      _showInfoMessage(
                        'Cannot exceed available stock for ${item.product.name}.',
                        backgroundColor: Colors.red,
                      );
                      return;
                    }

                    cart.increaseQuantity(item.product.barcode);
                    _focusBarcodeField();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Available Stock: $currentStock',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Line Total: Rs. ${item.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Supermarket POS — ${auth.currentUser?.name ?? 'Not Logged In'}',
        ),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<List<ConnectivityResult>>(
            stream: Connectivity().onConnectivityChanged,
            builder: (context, snapshot) {
              final hasNoInternet =
                  snapshot.data?.contains(ConnectivityResult.none) ?? false;

              return Container(
                margin: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: hasNoInternet ? Colors.orange[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasNoInternet ? Colors.orange : Colors.green,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasNoInternet ? Icons.wifi_off : Icons.wifi,
                      color: hasNoInternet
                          ? Colors.orange[800]
                          : Colors.green[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasNoInternet ? 'NO INTERNET' : 'NETWORK READY',
                      style: TextStyle(
                        color: hasNoInternet
                            ? Colors.orange[900]
                            : Colors.green[900],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (PosFeatureFlags.enableShiftManagement) _buildShiftStatusChip(),
          if (PosFeatureFlags.enableShiftManagement)
            IconButton(
              tooltip: 'Shift management',
              onPressed: _openShiftManagement,
              icon: const Icon(Icons.point_of_sale, color: Colors.white),
            ),
          IconButton(
            tooltip: 'Transaction history',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TransactionHistoryScreen(),
                ),
              );
              if (PosFeatureFlags.enableShiftManagement) {
                await _loadShiftSummary();
              }
              _focusBarcodeField();
            },
            icon: const Icon(Icons.receipt_long, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Refresh products from backend',
            onPressed: _isRefreshingProducts
                ? null
                : () {
                    _refreshProductsFromBackendAndReload(
                      showSuccessMessage: true,
                    );
                    if (PosFeatureFlags.enableShiftManagement) {
                      _loadShiftSummary();
                    }
                  },
            icon: _isRefreshingProducts
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () {
              context.read<AuthProvider>().logout();
              context.read<CartProvider>().clearCart();

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildTopToolbar(cart),
                  Expanded(
                    child: _isLoadingProducts
                        ? const Center(child: CircularProgressIndicator())
                        : _products.isEmpty
                            ? const Center(
                                child: Text(
                                  'No products available in local POS DB',
                                ),
                              )
                            : _filteredProducts.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No products match your search',
                                    ),
                                  )
                                : GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 4 / 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: _filteredProducts.length,
                                    itemBuilder: (context, index) {
                                      final product = _filteredProducts[index];
                                      return _buildProductCard(product, cart);
                                    },
                                  ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 390,
            color: Colors.white,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Current Order',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (PosFeatureFlags.enableShiftManagement &&
                    _currentShiftSummary == null)
                  Container(
                    width: double.infinity,
                    color: Colors.orange[50],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      'Open a shift to process transactions.',
                      style: TextStyle(
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (PosFeatureFlags.enableShiftManagement &&
                    _currentShiftSummary != null)
                  Container(
                    width: double.infinity,
                    color: Colors.green[50],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      'Expected Cash: Rs. ${((((_currentShiftSummary!['expected_cash'] as num?) ?? 0).toDouble())).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.green[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Divider(height: 1),
                Container(
                  color: cart.isRefundMode ? Colors.red[50] : Colors.grey[200],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cart.isRefundMode
                            ? '🔴 REFUND MODE'
                            : '🛒 STANDARD SALE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: cart.isRefundMode
                              ? Colors.red[800]
                              : Colors.black87,
                        ),
                      ),
                      Switch(
                        value: cart.isRefundMode,
                        activeThumbColor: Colors.red,
                        onChanged: (value) {
                          if (value) {
                            AdminDialogs.showPinDialog(context, () {
                              context
                                  .read<CartProvider>()
                                  .toggleRefundMode(true);
                              _focusBarcodeField();
                            });
                          } else {
                            context.read<CartProvider>().toggleRefundMode(false);
                            _focusBarcodeField();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: cart.items.isEmpty
                      ? Center(
                          child: Text(
                            cart.isRefundMode
                                ? 'Refund cart is empty'
                                : 'Cart is empty',
                          ),
                        )
                      : ListView.builder(
                          itemCount: cart.items.length,
                          itemBuilder: (context, index) {
                            final item = cart.items[index];
                            return _buildCartItemRow(cart, item);
                          },
                        ),
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: cart.isRefundMode ? Colors.red[50] : Colors.blue[50],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Subtotal: Rs. ${cart.subtotal.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Discount: Rs. ${cart.discountAmount.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cart.discountAmount > 0
                              ? Colors.red
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cart.isRefundMode
                            ? 'Refund Total: Rs. ${cart.cartTotal.toStringAsFixed(2)}'
                            : 'Total: Rs. ${cart.cartTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 12),
                      if (!cart.isRefundMode)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: cart.items.isEmpty
                                    ? null
                                    : () => _applyDiscount(cart),
                                child: Text(
                                  cart.discountAmount > 0
                                      ? 'EDIT DISCOUNT'
                                      : 'APPLY DISCOUNT',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: cart.discountAmount > 0
                                    ? () {
                                        cart.clearDiscount();
                                        _focusBarcodeField();
                                      }
                                    : null,
                                child: const Text('CLEAR DISCOUNT'),
                              ),
                            ),
                          ],
                        ),
                      if (!cart.isRefundMode) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: cart.items.isEmpty
                                  ? null
                                  : () => _holdCurrentCart(cart),
                              child: const Text('HOLD CART'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _openHeldCarts(cart),
                              child: const Text('HELD CARTS'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: cart.items.isEmpty
                            ? null
                            : () {
                                context.read<CartProvider>().clearCart();
                                _focusBarcodeField();
                              },
                        child: const Text('CLEAR CART'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor:
                              cart.isRefundMode ? Colors.red : Colors.green,
                        ),
                        onPressed: cart.items.isEmpty || _isProcessingCheckout
                            ? null
                            : () => _handleCheckout(cart),
                        child: Text(
                          _isProcessingCheckout
                              ? 'PROCESSING...'
                              : (cart.isRefundMode
                                  ? 'PROCESS REFUND'
                                  : 'PAY NOW'),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
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