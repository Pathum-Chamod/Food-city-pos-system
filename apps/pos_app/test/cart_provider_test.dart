import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/providers/cart_provider.dart';
import 'package:shared/shared.dart';

void main() {
  Product testProduct() {
    return Product(
      barcode: 'ITEM-1',
      name: 'Test Item',
      sellingPrice: 100,
      wholesalePrice: 80,
      salePrice: 60,
      saleEnabled: true,
      stock: 10,
      updatedAt: '2026-05-02T00:00:00.000',
    );
  }

  test('changing price type only affects newly added cart lines', () {
    final cart = CartProvider();
    final product = testProduct();

    cart.addToCart(product);
    expect(cart.items, hasLength(1));
    expect(cart.items[0].priceType, ProductPriceType.selling);
    expect(cart.items[0].unitPrice, 100);

    cart.setPriceType(ProductPriceType.wholesale);
    expect(cart.items[0].priceType, ProductPriceType.selling);
    expect(cart.items[0].unitPrice, 100);

    cart.addToCart(product);
    expect(cart.items, hasLength(2));
    expect(cart.items[1].priceType, ProductPriceType.wholesale);
    expect(cart.items[1].unitPrice, 80);

    cart.setPriceType(ProductPriceType.sale);
    cart.addToCart(product);
    expect(cart.items, hasLength(3));
    expect(cart.items[2].priceType, ProductPriceType.sale);
    expect(cart.items[2].unitPrice, 60);

    expect(cart.subtotal, 240);
  });

  test('existing cart lines can still be intentionally repriced', () {
    final cart = CartProvider();
    final product = testProduct();

    cart.addToCart(product, quantity: 2);
    cart.setPriceType(
      ProductPriceType.wholesale,
      applyToExistingItems: true,
    );

    expect(cart.items, hasLength(1));
    expect(cart.items[0].priceType, ProductPriceType.wholesale);
    expect(cart.items[0].unitPrice, 80);
    expect(cart.subtotal, 160);
  });
}
