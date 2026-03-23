enum ProductPriceType {
  selling,
  wholesale,
  sale,
}

extension ProductPriceTypeX on ProductPriceType {
  String get dbValue {
    switch (this) {
      case ProductPriceType.selling:
        return 'selling';
      case ProductPriceType.wholesale:
        return 'wholesale';
      case ProductPriceType.sale:
        return 'sale';
    }
  }

  String get label {
    switch (this) {
      case ProductPriceType.selling:
        return 'Selling Price';
      case ProductPriceType.wholesale:
        return 'Wholesale Price';
      case ProductPriceType.sale:
        return 'Sale Price';
    }
  }

  static ProductPriceType fromDb(String? value) {
    switch (value) {
      case 'wholesale':
        return ProductPriceType.wholesale;
      case 'sale':
        return ProductPriceType.sale;
      case 'selling':
      default:
        return ProductPriceType.selling;
    }
  }
}

class Product {
  final int? id;
  final String barcode;
  final String name;

  final String category;

  final double costPrice;
  final double sellingPrice;
  final double wholesalePrice;
  final double? salePrice;
  final bool saleEnabled;

  final int stock;
  final int minStockLevel;
  final bool isActive;

  final String updatedAt;
  final String? lastPriceUpdatedAt;

  const Product({
    this.id,
    required this.barcode,
    required this.name,
    this.category = 'General',
    this.costPrice = 0.0,
    required this.sellingPrice,
    double? wholesalePrice,
    this.salePrice,
    this.saleEnabled = false,
    required this.stock,
    this.minStockLevel = 0,
    this.isActive = true,
    required this.updatedAt,
    this.lastPriceUpdatedAt,
  }) : wholesalePrice = wholesalePrice ?? sellingPrice;

  /// Legacy compatibility for current POS screens that still call product.price
  double get price => sellingPrice;

  bool get hasSalePrice => saleEnabled && salePrice != null && salePrice! > 0;

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock => !isOutOfStock && stock <= minStockLevel;

  double resolvePrice(ProductPriceType type) {
    switch (type) {
      case ProductPriceType.wholesale:
        return wholesalePrice > 0 ? wholesalePrice : sellingPrice;
      case ProductPriceType.sale:
        if (hasSalePrice) return salePrice!;
        return sellingPrice;
      case ProductPriceType.selling:
        return sellingPrice;
    }
  }

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    String? category,
    double? costPrice,
    double? sellingPrice,
    double? wholesalePrice,
    double? salePrice,
    bool? saleEnabled,
    int? stock,
    int? minStockLevel,
    bool? isActive,
    String? updatedAt,
    String? lastPriceUpdatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      category: category ?? this.category,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      salePrice: salePrice ?? this.salePrice,
      saleEnabled: saleEnabled ?? this.saleEnabled,
      stock: stock ?? this.stock,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPriceUpdatedAt: lastPriceUpdatedAt ?? this.lastPriceUpdatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'category': category,

      // legacy + new
      'price': sellingPrice,
      'selling_price': sellingPrice,
      'cost_price': costPrice,
      'wholesale_price': wholesalePrice,
      'sale_price': salePrice,
      'sale_enabled': saleEnabled ? 1 : 0,

      'stock': stock,
      'min_stock_level': minStockLevel,
      'is_active': isActive ? 1 : 0,
      'updated_at': updatedAt,
      'last_price_updated_at': lastPriceUpdatedAt,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawSelling = map['selling_price'] ?? map['price'] ?? 0;
    final rawWholesale = map['wholesale_price'] ?? rawSelling;
    final rawSale = map['sale_price'];

    return Product(
      id: (map['id'] as num?)?.toInt(),
      barcode: (map['barcode'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      category: (map['category'] ?? 'General').toString(),
      costPrice: ((map['cost_price'] ?? 0) as num).toDouble(),
      sellingPrice: (rawSelling as num).toDouble(),
      wholesalePrice: (rawWholesale as num).toDouble(),
      salePrice: rawSale == null ? null : (rawSale as num).toDouble(),
      saleEnabled: _readBool(
        map['sale_enabled'],
        fallback: rawSale != null,
      ),
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      minStockLevel: (map['min_stock_level'] as num?)?.toInt() ?? 0,
      isActive: _readBool(
        map['is_active'],
        fallback: true,
      ),
      updatedAt: (map['updated_at'] ?? DateTime.now().toIso8601String())
          .toString(),
      lastPriceUpdatedAt: map['last_price_updated_at']?.toString(),
    );
  }

  static bool _readBool(dynamic value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }
    return fallback;
  }
}