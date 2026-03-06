import 'package:shared/shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Product toMap and fromMap roundtrip', () {
    final product = Product(
      id: 1,
      barcode: '1234567890',
      name: 'Test Product',
      price: 9.99,
      stock: 50,
      updatedAt: '2026-03-07T00:00:00',
    );

    final map = product.toMap();
    final restored = Product.fromMap(map);

    expect(restored.barcode, product.barcode);
    expect(restored.name, product.name);
    expect(restored.price, product.price);
    expect(restored.stock, product.stock);
  });
}
