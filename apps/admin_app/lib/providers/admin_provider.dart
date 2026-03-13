import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

import '../models/inventory_history_item.dart';
import '../models/stock_adjustment_request.dart';
import '../models/supplier.dart';

class AdminProvider with ChangeNotifier {
  // Product inventory fetched from backend
  List<Product> _products = [];

  // Shared loading state for admin screens
  bool _isLoading = false;

  // Dashboard analytics
  double _todayTotalSales = 0.0;
  List<dynamic> _cashierBreakdown = [];

  // Strongly typed suppliers list
  List<Supplier> _suppliers = [];

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  double get todayTotalSales => _todayTotalSales;
  List<dynamic> get cashierBreakdown => _cashierBreakdown;
  List<Supplier> get suppliers => _suppliers;

  // Local Python backend for Android emulator
  final String apiUrl = "http://10.0.2.2:8080/api/pos_sync.php";

  // If you run admin_app on Windows desktop instead, use this:
  // final String apiUrl = "http://127.0.0.1:8080/api/pos_sync.php";

  // Fetch product master list
  Future<void> fetchProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse('$apiUrl?action=get_products'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _products = data.map((json) => Product.fromMap(json)).toList();
      }
    } catch (e) {
      debugPrint("Network error: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  // Fetch dashboard summary data
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

  // Fetch supplier list and map into Supplier model objects
  Future<void> fetchSuppliers() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl?action=get_suppliers'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _suppliers = data
            .map((item) => Supplier.fromMap(item as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching suppliers: $e");
    }
  }

  // Update a product selling price
  Future<bool> updateProductPrice(String barcode, double newPrice) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=update_price'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "barcode": barcode,
          "new_price": newPrice,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['status'] == 'success') {
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

  // Submit stock receiving data
  Future<bool> receiveStock(
    String barcode,
    int quantity,
    int supplierId,
    double cost,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=add_stock'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "barcode": barcode,
          "quantity": quantity,
          "supplier_id": supplierId,
          "cost": cost,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['status'] == 'success') {
          await fetchProducts();
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint("Stock update error: $e");
      return false;
    }
  }

  // Submit manual stock adjustment
  Future<bool> adjustStock(StockAdjustmentRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=adjust_stock'),
        headers: {"Content-Type": "application/json"},
        body: json.encode(request.toMap()),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['status'] == 'success') {
          await fetchProducts();
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint("Adjust stock error: $e");
      return false;
    }
  }

  // Fetch real inventory history for a product
  Future<List<InventoryHistoryItem>> fetchInventoryHistory(
    String barcode,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=get_inventory_history&barcode=$barcode'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          final List<dynamic> history = data['history'] ?? [];

          return history
              .map(
                (item) => _mapHistoryItem(item as Map<String, dynamic>),
              )
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Inventory history fetch error: $e");
    }

    return [];
  }

  InventoryHistoryItem _mapHistoryItem(Map<String, dynamic> item) {
    final String movementType = item['movement_type']?.toString() ?? '';
    final int quantity = int.tryParse(item['quantity'].toString()) ?? 0;
    final String reason = item['reason']?.toString() ?? '';
    final String createdAt = item['created_at']?.toString() ?? '';

    return InventoryHistoryItem(
      type: movementType,
      title: _historyTitle(movementType),
      subtitle: _historySubtitle(movementType, reason, quantity),
      quantityText: _historyQuantityText(movementType, quantity),
      dateText: _formatHistoryDate(createdAt),
      icon: _historyIcon(movementType),
      color: _historyColor(movementType),
    );
  }

  String _historyTitle(String movementType) {
    switch (movementType) {
      case 'sale':
        return 'Sale';
      case 'refund':
        return 'Refund';
      case 'stock_in':
        return 'Stock Received';
      case 'adjustment':
        return 'Manual Adjustment';
      case 'price_update':
        return 'Price Update';
      default:
        return 'Inventory Activity';
    }
  }

  String _historySubtitle(String movementType, String reason, int quantity) {
    if (reason.isNotEmpty) {
      return reason;
    }

    switch (movementType) {
      case 'sale':
        return 'Item sold through POS';
      case 'refund':
        return 'Item returned to stock';
      case 'stock_in':
        return 'Stock received from supplier';
      case 'adjustment':
        return quantity >= 0
            ? 'Manual stock increase'
            : 'Manual stock decrease';
      case 'price_update':
        return 'Selling price changed';
      default:
        return 'Inventory activity';
    }
  }

  String _historyQuantityText(String movementType, int quantity) {
    if (movementType == 'price_update') {
      return '—';
    }

    if (quantity > 0) {
      return '+$quantity';
    }

    return quantity.toString();
  }

  String _formatHistoryDate(String rawDate) {
    try {
      final dateTime = DateTime.parse(rawDate);

      String twoDigits(int value) => value.toString().padLeft(2, '0');

      final day = twoDigits(dateTime.day);
      final month = twoDigits(dateTime.month);
      final year = dateTime.year;
      final hour = twoDigits(dateTime.hour);
      final minute = twoDigits(dateTime.minute);

      return '$day/$month/$year  $hour:$minute';
    } catch (_) {
      return rawDate;
    }
  }

  IconData _historyIcon(String movementType) {
    switch (movementType) {
      case 'sale':
        return Icons.point_of_sale;
      case 'refund':
        return Icons.assignment_return;
      case 'stock_in':
        return Icons.local_shipping;
      case 'adjustment':
        return Icons.tune;
      case 'price_update':
        return Icons.edit;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Color _historyColor(String movementType) {
    switch (movementType) {
      case 'sale':
        return Colors.red;
      case 'refund':
        return Colors.deepPurple;
      case 'stock_in':
        return Colors.green;
      case 'adjustment':
        return Colors.orange;
      case 'price_update':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}