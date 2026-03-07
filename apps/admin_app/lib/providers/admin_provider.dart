import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminProvider with ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;
  double _todayTotalSales = 0.0;
  List<dynamic> _cashierBreakdown = [];

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  double get todayTotalSales => _todayTotalSales;
  List<dynamic> get cashierBreakdown => _cashierBreakdown;

  // ⚠️ YOUR LIVE SPACESHIP API URL 
  final String apiUrl = "https://alfasoft.it.com/api/pos_sync.php";

  // 0. Fetch today's sales analytics from the cloud
  Future<void> fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl?action=get_sales'));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          _todayTotalSales = (data['grand_total'] as num).toDouble();
          _cashierBreakdown = data['cashier_sales'];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Error fetching sales stats: $e");
    }
  }

  // 1. Fetch live products from your MySQL Database
  Future<void> fetchProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse('$apiUrl?action=get_products'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _products = data.map((json) => Product.fromMap(json)).toList();
      } else {
        debugPrint("Server error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Network error: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  // 2. Push price updates live to the cloud
  Future<bool> updateProductPrice(String barcode, double newPrice) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=update_price'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "barcode": barcode,
          "new_price": newPrice
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['status'] == 'success') {
          // Refresh the list to show the new price from the database
          await fetchProducts(); 
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint("Update error: $e");
      return false;
    }
  }
}
