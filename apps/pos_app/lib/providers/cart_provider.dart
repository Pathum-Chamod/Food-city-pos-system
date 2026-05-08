import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class CartItem {
  final Product product;
  double quantity;
  double unitPrice;
  double systemUnitPrice;
  ProductPriceType priceType;
  String discountType;
  double discountValue;
  String priceOverrideType;
  String priceOverrideReason;
  double priceOverrideOriginalPrice;
  int? priceHistoryId;
  String? priceOverrideApprovedBy;

  CartItem({
    required this.product,
    required this.unitPrice,
    required this.priceType,
    double? systemUnitPrice,
    this.quantity = 1.0,
    this.discountType = 'none',
    this.discountValue = 0.0,
    this.priceOverrideType = 'none',
    this.priceOverrideReason = '',
    double? priceOverrideOriginalPrice,
    this.priceHistoryId,
    this.priceOverrideApprovedBy,
  })  : systemUnitPrice = systemUnitPrice ?? unitPrice,
        priceOverrideOriginalPrice = priceOverrideOriginalPrice ?? unitPrice;

  bool get hasPriceOverride => priceOverrideType != 'none';

  double get priceOverrideDifference {
    return unitPrice - systemUnitPrice;
  }

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
  static const double _quantityEpsilon = 0.000001;
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
    bool applyToExistingItems = false,
  }) {
    if (_selectedPriceType == value && !applyToExistingItems) return;

    _selectedPriceType = value;

    if (applyToExistingItems) {
      for (final item in _items) {
        item.priceType = value;
        item.unitPrice = item.product.resolvePrice(value);
        item.systemUnitPrice = item.unitPrice;
        item.priceOverrideType = 'none';
        item.priceOverrideReason = '';
        item.priceOverrideOriginalPrice = item.unitPrice;
        item.priceHistoryId = null;
        item.priceOverrideApprovedBy = null;
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

  void applyPriceOverride(
    CartItem target, {
    required double overridePrice,
    required String overrideType,
    required String reason,
    int? priceHistoryId,
    String? approvedBy,
  }) {
    if (_isRefundMode) return;

    final index = _items.indexOf(target);
    if (index == -1) return;

    final safePrice = overridePrice < 0 ? 0.0 : overridePrice;
    final normalizedType = _normalizePriceOverrideType(overrideType);

    _items[index].priceOverrideOriginalPrice = _items[index].systemUnitPrice;
    _items[index].unitPrice = safePrice;
    _items[index].priceOverrideType = normalizedType;
    _items[index].priceOverrideReason = reason.trim();
    _items[index].priceHistoryId = priceHistoryId;
    _items[index].priceOverrideApprovedBy = approvedBy?.trim();
    notifyListeners();
  }

  void clearPriceOverride(CartItem target) {
    final index = _items.indexOf(target);
    if (index == -1) return;

    _items[index].unitPrice = _items[index].systemUnitPrice;
    _items[index].priceOverrideType = 'none';
    _items[index].priceOverrideReason = '';
    _items[index].priceOverrideOriginalPrice = _items[index].systemUnitPrice;
    _items[index].priceHistoryId = null;
    _items[index].priceOverrideApprovedBy = null;
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

  String _normalizePriceOverrideType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'old_label') return 'old_label';
    if (normalized == 'manual') return 'manual';
    return 'none';
  }

  void addToCart(Product product, {double quantity = 1.0}) {
    final safeQuantity = quantity <= _quantityEpsilon ? 0.0 : quantity;
    if (safeQuantity <= 0) return;

    final index = _items.indexWhere(
      (item) =>
          item.product.barcode == product.barcode &&
          item.priceType == _selectedPriceType &&
          !item.hasPriceOverride,
    );

    if (index >= 0) {
      _items[index].quantity += safeQuantity;
    } else {
      _items.add(
        CartItem(
          product: product,
          quantity: safeQuantity,
          unitPrice: product.resolvePrice(_selectedPriceType),
          priceType: _selectedPriceType,
        ),
      );
    }

    notifyListeners();
  }

  void increaseQuantity(CartItem target, {double delta = 1.0}) {
    final safeDelta = delta <= _quantityEpsilon ? 0.0 : delta;
    if (safeDelta <= 0) return;

    final index = _items.indexOf(target);
    if (index == -1) return;

    _items[index].quantity += safeDelta;
    notifyListeners();
  }

  void decreaseQuantity(CartItem target, {double delta = 1.0}) {
    final safeDelta = delta <= _quantityEpsilon ? 0.0 : delta;
    if (safeDelta <= 0) return;

    final index = _items.indexOf(target);
    if (index == -1) return;

    _items[index].quantity -= safeDelta;

    if (_items[index].quantity <= _quantityEpsilon) {
      _items.removeAt(index);
    }

    if (_items.isEmpty) {
      _discountType = 'none';
      _discountValue = 0.0;
    }

    notifyListeners();
  }

  void updateQuantity(CartItem target, double quantity) {
    final index = _items.indexOf(target);
    if (index == -1) return;

    if (quantity <= _quantityEpsilon) {
      _items.removeAt(index);
    } else {
      _items[index].quantity = quantity;
    }

    if (_items.isEmpty) {
      _discountType = 'none';
      _discountValue = 0.0;
    }

    notifyListeners();
  }

  void removeItem(CartItem target) {
    _items.remove(target);

    if (_items.isEmpty) {
      _discountType = 'none';
      _discountValue = 0.0;
    }

    notifyListeners();
  }

  double getQuantityFor(String barcode) {
    return _items
        .where((item) => item.product.barcode == barcode)
        .fold<double>(0.0, (sum, item) => sum + item.quantity);
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
      final rawProduct = item['product'];
      if (rawProduct is! Map) continue;
      final productMap = Map<String, dynamic>.from(rawProduct);
      final barcode = (productMap['barcode'] ?? '').toString().trim();
      final name = (productMap['name'] ?? '').toString().trim();
      if (barcode.isEmpty || name.isEmpty) continue;

      Product product;
      try {
        product = Product.fromMap(productMap);
      } catch (_) {
        continue;
      }
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;

      if (quantity <= _quantityEpsilon) continue;

      final itemPriceType = ProductPriceTypeX.fromDb(
        item['price_type_used']?.toString(),
      );

      final systemUnitPrice =
          (item['system_unit_price'] as num?)?.toDouble() ??
          product.resolvePrice(itemPriceType);
      final unitPriceUsed =
          (item['unit_price_used'] as num?)?.toDouble() ?? systemUnitPrice;

      _items.add(
        CartItem(
          product: product,
          quantity: quantity,
          unitPrice: unitPriceUsed,
          systemUnitPrice: systemUnitPrice,
          priceType: itemPriceType,
          priceOverrideType: isRefundMode
              ? 'none'
              : _normalizePriceOverrideType(
                  item['price_override_type']?.toString() ?? 'none',
                ),
          priceOverrideReason: isRefundMode
              ? ''
              : (item['price_override_reason'] ?? '').toString(),
          priceOverrideOriginalPrice: isRefundMode
              ? systemUnitPrice
              : ((item['price_override_original_price'] as num?)?.toDouble() ??
                    systemUnitPrice),
          priceHistoryId: isRefundMode
              ? null
              : (item['price_history_id'] as num?)?.toInt(),
          priceOverrideApprovedBy: isRefundMode
              ? null
              : item['price_override_approved_by']?.toString(),
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
            'system_unit_price': item.systemUnitPrice,
            'price_override_type': item.priceOverrideType,
            'price_override_reason': item.priceOverrideReason,
            'price_override_original_price': item.priceOverrideOriginalPrice,
            'price_override_difference': item.priceOverrideDifference,
            'price_history_id': item.priceHistoryId,
            'price_override_approved_by': item.priceOverrideApprovedBy,
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
