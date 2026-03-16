import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });

  double get total => product.price * quantity;
}

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];
  bool _isRefundMode = false;

  UnmodifiableListView<CartItem> get items => UnmodifiableListView(_items);
  bool get isRefundMode => _isRefundMode;
  bool get isSaleMode => !_isRefundMode;
  String get transactionType => _isRefundMode ? 'refund' : 'sale';

  double get cartTotal {
    return _items.fold(0.0, (sum, item) => sum + item.total);
  }

  void toggleRefundMode(bool value) {
    if (_isRefundMode == value) return;

    _isRefundMode = value;
    _items.clear(); // prevent mixing sale + refund lines
    notifyListeners();
  }

  void addToCart(Product product) {
    final index = _items.indexWhere(
      (item) => item.product.barcode == product.barcode,
    );

    if (index >= 0) {
      _items[index].quantity += 1;
    } else {
      _items.add(CartItem(product: product));
    }

    notifyListeners();
  }

  void increaseQuantity(String barcode) {
    final index = _items.indexWhere((item) => item.product.barcode == barcode);
    if (index == -1) return;

    _items[index].quantity += 1;
    notifyListeners();
  }

  void decreaseQuantity(String barcode) {
    final index = _items.indexWhere((item) => item.product.barcode == barcode);
    if (index == -1) return;

    if (_items[index].quantity <= 1) {
      _items.removeAt(index);
    } else {
      _items[index].quantity -= 1;
    }

    notifyListeners();
  }

  void removeItem(String barcode) {
    _items.removeWhere((item) => item.product.barcode == barcode);
    notifyListeners();
  }

  int getQuantityFor(String barcode) {
    final index = _items.indexWhere((item) => item.product.barcode == barcode);
    if (index == -1) return 0;
    return _items[index].quantity;
  }

  void clearCart() {
    _items.clear();
    _isRefundMode = false;
    notifyListeners();
  }

  List<Map<String, dynamic>> getCartItemsAsMap() {
    return _items
        .map(
          (item) => {
            'product': item.product.toMap(),
            'quantity': item.quantity,
            'line_total': item.total,
          },
        )
        .toList();
  }
}