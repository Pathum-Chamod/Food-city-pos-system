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

  String _discountType = 'none'; // none | fixed | percent
  double _discountValue = 0.0;

  List<CartItem> get items => _items;
  bool get isRefundMode => _isRefundMode;
  String get discountType => _discountType;
  double get discountValue => _discountValue;

  double get subtotal {
    return _items.fold(0, (sum, item) => sum + item.total);
  }

  double get discountAmount {
    if (_isRefundMode || subtotal <= 0) return 0.0;

    if (_discountType == 'fixed') {
      final safeValue = _discountValue < 0 ? 0.0 : _discountValue;
      return safeValue > subtotal ? subtotal : safeValue;
    }

    if (_discountType == 'percent') {
      final safeValue = _discountValue < 0 ? 0.0 : _discountValue;
      final capped = safeValue > 100 ? 100.0 : safeValue;
      return subtotal * (capped / 100);
    }

    return 0.0;
  }

  double get cartTotal {
    final total = subtotal - discountAmount;
    return total < 0 ? 0 : total;
  }

  void toggleRefundMode(bool value) {
    _isRefundMode = value;
    _items.clear();
    _discountType = 'none';
    _discountValue = 0.0;
    notifyListeners();
  }

  void setDiscount({
    required String discountType,
    required double discountValue,
  }) {
    if (_isRefundMode) return;

    _discountType = _normalizeDiscountType(discountType);
    _discountValue = discountValue < 0 ? 0.0 : discountValue;
    notifyListeners();
  }

  void clearDiscount() {
    _discountType = 'none';
    _discountValue = 0.0;
    notifyListeners();
  }

  String _normalizeDiscountType(String value) {
    if (value == 'fixed' || value == 'percent') return value;
    return 'none';
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

    if (_items.isEmpty) {
      _discountType = 'none';
      _discountValue = 0.0;
    }

    notifyListeners();
  }

  void removeItem(String barcode) {
    _items.removeWhere((item) => item.product.barcode == barcode);

    if (_items.isEmpty) {
      _discountType = 'none';
      _discountValue = 0.0;
    }

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
    _discountType = 'none';
    _discountValue = 0.0;
    notifyListeners();
  }

  void loadHeldCart({
    required List<Map<String, dynamic>> items,
    required bool isRefundMode,
    String discountType = 'none',
    double discountValue = 0.0,
  }) {
    _items.clear();
    _isRefundMode = isRefundMode;
    _discountType = isRefundMode ? 'none' : _normalizeDiscountType(discountType);
    _discountValue = isRefundMode ? 0.0 : (discountValue < 0 ? 0.0 : discountValue);

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