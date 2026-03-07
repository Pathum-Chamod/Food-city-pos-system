class Product {
  final int? id;
  final String barcode;
  final String name;
  final double price;
  final int stock;
  final String updatedAt;

  Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.price,
    required this.stock,
    required this.updatedAt,
  });

  // Convert a Product into a Map (for SQLite and JSON APIs)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'price': price,
      'stock': stock,
      'updated_at': updatedAt,
    };
  }

  // Create a Product from a Map (reading from SQLite or JSON)
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      barcode: map['barcode'],
      name: map['name'],
      price: (map['price'] as num).toDouble(),
      stock: map['stock'],
      updatedAt: map['updated_at'],
    );
  }
}
