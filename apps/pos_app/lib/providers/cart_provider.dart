import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class CartItem {
  final Product product;
  int quantity;
  double unitPrice;
  ProductPriceType priceType;
  String discountType;
  double discountValue;

  CartItem({
    required this.product,
    required this.unitPrice,
    required this.priceType,
    this.quantity = 1,
    this.discountType = 'none',
    this.discountValue = 0.0,
  });

  double get baseTotal => unitPrice * quantity;

  double get discountAmount {
    if (baseTotal <= 0) return 0.0;

    if (discountType == 'fixed') {
      final safeValue = discountValue < 0 ? 0.0 : discountValue;
      return safeValue > baseTotal ? baseTotal : safeValue;
    }

    if (discountType == 'percent') {
      final safeValue = discountValue < 0 ? 0.0 : discountValue;
      final capped = safeValue > 100 ? 100.0 : safeValue;
      return baseTotal * (capped / 100);
    }

    return 0.0;
  }

  double get total {
    final netTotal = baseTotal - discountAmount;
    return netTotal < 0 ? 0 : netTotal;
  }
}

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];

  bool _isRefundMode = false;
  String _discountType = 'none'; // none | fixed | percent
  double _discountValue = 0.0;

  ProductPriceType _selectedPriceType = ProductPriceType.selling;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isRefundMode => _isRefundMode;
  String get discountType => _discountType;
  double get discountValue => _discountValue;
  ProductPriceType get selectedPriceType => _selectedPriceType;

  double get subtotal {
    return _items.fold(0.0, (sum, item) => sum + item.baseTotal);
  }

  double get itemDiscountAmount {
    if (_isRefundMode) return 0.0;
    return _items.fold(0.0, (sum, item) => sum + item.discountAmount);
  }

  double get discountedSubtotal {
    final total = subtotal - itemDiscountAmount;
    return total < 0 ? 0 : total;
  }

  double get cartLevelDiscountAmount {
    if (_isRefundMode || discountedSubtotal <= 0) return 0.0;

    if (_discountType == 'fixed') {
      final safeValue = _discountValue < 0 ? 0.0 : _discountValue;
      return safeValue > discountedSubtotal ? discountedSubtotal : safeValue;
    }

    if (_discountType == 'percent') {
      final safeValue = _discountValue < 0 ? 0.0 : _discountValue;
      final capped = safeValue > 100 ? 100.0 : safeValue;
      return discountedSubtotal * (capped / 100);
    }

    return 0.0;
  }

  double get discountAmount {
    return itemDiscountAmount + cartLevelDiscountAmount;
  }

  double get cartTotal {
    final total = discountedSubtotal - cartLevelDiscountAmount;
    return total < 0 ? 0 : total;
  }

  void toggleRefundMode(bool value) {
    _isRefundMode = value;
    _items.clear();
    _selectedPriceType = ProductPriceType.selling;
    _discountType = 'none';
    _discountValue = 0.0;
    notifyListeners();
  }

  void setPriceType(
    ProductPriceType value, {
    bool applyToExistingItems = true,
  }) {
    if (_selectedPriceType == value) return;

    _selectedPriceType = value;

    if (applyToExistingItems) {
      for (final item in _items) {
        item.priceType = value;
        item.unitPrice = item.product.resolvePrice(value);
      }
    }

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

  void setItemDiscount(
    CartItem target, {
    required String discountType,
    required double discountValue,
  }) {
    if (_isRefundMode) return;

    final index = _items.indexOf(target);
    if (index == -1) return;

    _items[index].discountType = _normalizeDiscountType(discountType);
    _items[index].discountValue = discountValue < 0 ? 0.0 : discountValue;
    notifyListeners();
  }

  void clearItemDiscount(CartItem target) {
    final index = _items.indexOf(target);
    if (index == -1) return;

    _items[index].discountType = 'none';
    _items[index].discountValue = 0.0;
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
    final index = _items.indexWhere(
      (item) =>
          item.product.barcode == product.barcode &&
          item.priceType == _selectedPriceType,
    );

    if (index >= 0) {
      _items[index].quantity += 1;
    } else {
      _items.add(
        CartItem(
          product: product,
          quantity: 1,
          unitPrice: product.resolvePrice(_selectedPriceType),
          priceType: _selectedPriceType,
        ),
      );
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
    _selectedPriceType = ProductPriceType.selling;
    _discountType = 'none';
    _discountValue = 0.0;
    notifyListeners();
  }

  void loadHeldCart({
    required List<Map<String, dynamic>> items,
    required bool isRefundMode,
    String discountType = 'none',
    double discountValue = 0.0,
    String? selectedPriceType,
  }) {
    _items.clear();
    _isRefundMode = isRefundMode;
    _selectedPriceType = isRefundMode
        ? ProductPriceType.selling
        : ProductPriceTypeX.fromDb(selectedPriceType);

    _discountType = isRefundMode ? 'none' : _normalizeDiscountType(discountType);
    _discountValue = isRefundMode ? 0.0 : (discountValue < 0 ? 0.0 : discountValue);

    for (final rawItem in items) {
      final item = Map<String, dynamic>.from(rawItem);
      final productMap = Map<String, dynamic>.from(item['product'] as Map);

      final product = Product.fromMap(productMap);
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;

      if (quantity <= 0) continue;

      final itemPriceType = ProductPriceTypeX.fromDb(
        item['price_type_used']?.toString(),
      );

      final unitPriceUsed =
          (item['unit_price_used'] as num?)?.toDouble() ??
          product.resolvePrice(itemPriceType);

      _items.add(
        CartItem(
          product: product,
          quantity: quantity,
          unitPrice: unitPriceUsed,
          priceType: itemPriceType,
          discountType: isRefundMode
              ? 'none'
              : _normalizeDiscountType(
                  item['item_discount_type']?.toString() ?? 'none',
                ),
          discountValue: isRefundMode
              ? 0.0
              : ((item['item_discount_value'] as num?) ?? 0).toDouble(),
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
            'unit_price_used': item.unitPrice,
            'price_type_used': item.priceType.dbValue,
            'base_line_total': item.baseTotal,
            'item_discount_type': item.discountType,
            'item_discount_value': item.discountValue,
            'item_discount_amount': item.discountAmount,
            'line_total': item.total,
          },
        )
        .toList();
  }
}
