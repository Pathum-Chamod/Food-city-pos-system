import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

class AdminProvider with ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;

  // Mocking the initial fetch from your future Spaceship API
  Future<void> fetchProducts() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay

    _products = [
      Product(barcode: '4791044000123', name: 'Munchee Super Cream Cracker 500g', price: 450.0, stock: 100, updatedAt: DateTime.now().toIso8601String()),
      Product(barcode: '4792011001234', name: 'Anchor Milk Powder 400g', price: 1100.0, stock: 50, updatedAt: DateTime.now().toIso8601String()),
    ];

    _isLoading = false;
    notifyListeners();
  }

  // Mocking the update push to your future Spaceship API
  Future<bool> updateProductPrice(String barcode, double newPrice) async {
    final index = _products.indexWhere((p) => p.barcode == barcode);
    if (index >= 0) {
      // 1. We will eventually send this to the API via http.put
      await Future.delayed(const Duration(milliseconds: 500)); 
      
      // 2. Update the local memory state
      final oldProduct = _products[index];
      _products[index] = Product(
        id: oldProduct.id,
        barcode: oldProduct.barcode,
        name: oldProduct.name,
        price: newPrice,
        stock: oldProduct.stock,
        updatedAt: DateTime.now().toIso8601String(),
      );
      notifyListeners();
      return true;
    }
    return false;
  }
}
