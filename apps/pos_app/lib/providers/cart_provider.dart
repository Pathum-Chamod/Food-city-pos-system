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

  List<CartItem> get items => _items;
  bool get isRefundMode => _isRefundMode;

  double get cartTotal {
    return _items.fold(0, (sum, item) => sum + item.total);
  }

  void toggleRefundMode(bool value) {
    _isRefundMode = value;
    _items.clear();
    notifyListeners();
  }

  void addToCart(Product product) {
    final index =
        _items.indexWhere((item) => item.product.barcode == product.barcode);

    if (index >= 0) {
      _items[index].quantity += 1;
    } else {
      _items.add(CartItem(product: product, quantity: 1));
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

    _items[index].quantity -= 1;

    if (_items[index].quantity <= 0) {
      _items.removeAt(index);
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

  void loadHeldCart({
    required List<Map<String, dynamic>> items,
    required bool isRefundMode,
  }) {
    _items.clear();
    _isRefundMode = isRefundMode;

    for (final rawItem in items) {
      final item = Map<String, dynamic>.from(rawItem);
      final productMap = Map<String, dynamic>.from(item['product'] as Map);
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;

      if (quantity <= 0) continue;

      _items.add(
        CartItem(
          product: Product.fromMap(productMap),
          quantity: quantity,
        ),
      );
    }

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