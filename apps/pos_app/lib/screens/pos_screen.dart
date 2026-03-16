import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../widgets/admin_dialogs.dart';
import 'login_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Product> _products = [];
  bool _isLoadingProducts = true;
  bool _isProcessingCheckout = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });

    final products = await DatabaseHelper.instance.getProducts();

    if (!mounted) return;

    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
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
  }

  Future<void> _handleCheckout(CartProvider cart) async {
    if (cart.items.isEmpty || _isProcessingCheckout) return;

    setState(() {
      _isProcessingCheckout = true;
    });

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
    final isRefund = cart.isRefundMode;
    final displayTotal = cart.cartTotal;
    final itemsMap = cart.getCartItemsAsMap();

    try {
      await DatabaseHelper.instance.processTransaction(
        totalAmount: displayTotal,
        cartItems: itemsMap,
        cashierName: cashierName,
        isRefund: isRefund,
      );

      cart.clearCart();

      await SyncService().syncNow();
      await _loadProducts();

      if (!mounted) return;

      final title =
          isRefund ? '✅ Refund Completed' : '✅ Payment Successful';
      final amountLabel = isRefund ? 'Refund Amount' : 'Total Paid';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(
            '$amountLabel: Rs. ${displayTotal.toStringAsFixed(2)}\n\n'
            'Transaction saved locally. Sync was attempted now and will retry automatically if needed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Next Customer'),
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
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingCheckout = false;
        });
      }
    }
  }

  Widget _buildProductCard(Product product, CartProvider cart) {
    final isOutOfStock = product.stock <= 0 && !cart.isRefundMode;

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
              _loadProducts,
            );
          });
        },
        child: Container(
          color: isOutOfStock ? Colors.grey[200] : Colors.white,
          padding: const EdgeInsets.all(12.0),
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
                    color: isOutOfStock ? Colors.grey[600] : Colors.black87,
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
                    color: isOutOfStock ? Colors.red[700] : Colors.blue[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
                    if (!cart.isRefundMode &&
                        item.quantity >= item.product.stock) {
                      _showInfoMessage(
                        'Cannot exceed available stock for ${item.product.name}.',
                        backgroundColor: Colors.red,
                      );
                      return;
                    }

                    cart.increaseQuantity(item.product.barcode);
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
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
          IconButton(
            tooltip: 'Reload local products',
            onPressed: _loadProducts,
            icon: const Icon(Icons.refresh, color: Colors.white),
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
              child: _isLoadingProducts
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                      ? const Center(
                          child: Text('No products available in local POS DB'),
                        )
                      : GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 4 / 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            return _buildProductCard(product, cart);
                          },
                        ),
            ),
          ),
          Container(
            width: 380,
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
                            });
                          } else {
                            context.read<CartProvider>().toggleRefundMode(false);
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
                      OutlinedButton(
                        onPressed: cart.items.isEmpty
                            ? null
                            : () {
                                context.read<CartProvider>().clearCart();
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