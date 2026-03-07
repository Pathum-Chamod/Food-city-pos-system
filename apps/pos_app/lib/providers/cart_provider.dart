import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get total => product.price * quantity;
}

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];
  bool _isRefundMode = false;

  List<CartItem> get items => _items;
  bool get isRefundMode => _isRefundMode;

  double get cartTotal {
    return _items.fold(0, (sum, item) => sum + (item.product.price * item.quantity));
  }

  // Toggle refund mode and clear the cart to prevent mixing sales & returns
  void toggleRefundMode(bool value) {
    _isRefundMode = value;
    _items.clear();
    notifyListeners();
  }

  void addToCart(Product product) {
    final index = _items.indexWhere((item) => item.product.barcode == product.barcode);

    // Add -1 if refunding, +1 if selling
    final qtyToAdd = _isRefundMode ? -1 : 1;

    if (index >= 0) {
      _items[index].quantity += qtyToAdd;
      // If quantity hits 0 (e.g., they cancel the item), remove it from the cart
      if (_items[index].quantity == 0) {
        _items.removeAt(index);
      }
    } else {
      _items.add(CartItem(product: product, quantity: qtyToAdd));
    }
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _isRefundMode = false; // Reset to standard sale after checkout
    notifyListeners();
  }

  List<Map<String, dynamic>> getCartItemsAsMap() {
    return _items.map((item) => {
      'product': item.product.toMap(),
      'quantity': item.quantity,
      'line_total': item.total,
    }).toList();
  }
}
