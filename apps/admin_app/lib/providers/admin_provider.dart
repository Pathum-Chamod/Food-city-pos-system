
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

import '../models/inventory_history_item.dart';
import '../models/stock_adjustment_request.dart';
import '../models/supplier.dart';

class AdminProvider with ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;

  double _todayTotalSales = 0.0;
  List<dynamic> _cashierBreakdown = [];

  List<Supplier> _suppliers = [];

  bool _isOwnerShellLoading = false;
  Map<String, dynamic> _ownerDashboardSummary = {};
  List<Map<String, dynamic>> _ownerSalesTrend = [];
  List<Map<String, dynamic>> _ownerTopProducts = [];
  List<Map<String, dynamic>> _ownerAlerts = [];

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  double get todayTotalSales => _todayTotalSales;
  List<dynamic> get cashierBreakdown => _cashierBreakdown;
  List<Supplier> get suppliers => _suppliers;

  bool get isOwnerShellLoading => _isOwnerShellLoading;
  Map<String, dynamic> get ownerDashboardSummary => _ownerDashboardSummary;
  List<Map<String, dynamic>> get ownerSalesTrend => _ownerSalesTrend;
  List<Map<String, dynamic>> get ownerTopProducts => _ownerTopProducts;
  List<Map<String, dynamic>> get ownerAlerts => _ownerAlerts;

  List<Map<String, dynamic>> get topAlertsPreview => _ownerAlerts.take(3).toList();

  int get transactionCount {
    return _cashierBreakdown.fold<int>(
      0,
      (sum, cashier) =>
          sum + (int.tryParse('${cashier['transaction_count'] ?? 0}') ?? 0),
    );
  }

  double get averageSale {
    if (transactionCount <= 0) return 0.0;
    return _todayTotalSales / transactionCount;
  }

  int get totalProducts => _products.length;
  int get outOfStockCount => _products.where((p) => p.stock <= 0).length;
  int get lowStockCount => _products
      .where(
        (p) => p.stock > 0 && p.stock <= (p.minStockLevel > 0 ? p.minStockLevel : 10),
      )
      .length;

  final String apiUrl = "http://10.0.2.2:8080/api/pos_sync.php";
  // final String apiUrl = "http://127.0.0.1:8080/api/pos_sync.php";

  Future<void> loadOwnerShellData({bool forceRefresh = false}) async {
    if (_isOwnerShellLoading && !forceRefresh) return;

    _isOwnerShellLoading = true;
    notifyListeners();

    try {
      await fetchProducts();
      await fetchDashboardStats();
      await fetchOwnerDashboard();
      await fetchOwnerAlerts();
    } finally {
      _isOwnerShellLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshOwnerDashboard() async {
    await fetchProducts();
    await fetchDashboardStats();
    await fetchOwnerDashboard();
    await fetchOwnerAlerts();
  }

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

  Future<void> fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse('$apiUrl?action=get_sales'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          _todayTotalSales = (data['grand_total'] as num?)?.toDouble() ?? 0.0;
          _cashierBreakdown = (data['cashier_sales'] as List?) ?? [];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Error fetching sales stats: $e");
    }
  }

  Future<void> fetchOwnerDashboard() async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=get_owner_dashboard'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          _ownerDashboardSummary = Map<String, dynamic>.from(
            (data['summary'] as Map?) ?? <String, dynamic>{},
          );
          _ownerSalesTrend = ((data['trend'] as List?) ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          _ownerTopProducts = ((data['top_products'] as List?) ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint("Owner dashboard fetch error: $e");
    }

    _ownerDashboardSummary = _buildFallbackOwnerSummary();
    _ownerSalesTrend = [];
    _ownerTopProducts = [];
    notifyListeners();
  }

  Future<void> fetchOwnerAlerts() async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=get_owner_alerts'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          _ownerAlerts = ((data['alerts'] as List?) ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint("Owner alerts fetch error: $e");
    }

    _ownerAlerts = _buildFallbackAlertsFromProducts();
    notifyListeners();
  }

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

  Future<bool> updateProductPrice(
    String barcode,
    double newPrice, {
    String priceType = 'selling',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=update_price'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "barcode": barcode,
          "new_price": newPrice,
          "price_type": priceType,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['status'] == 'success') {
          await fetchProducts();
          await fetchOwnerAlerts();
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint("Update error: $e");
      return false;
    }
  }

  Future<bool> updateMinStockLevel(String barcode, int minStockLevel) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=update_min_stock'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "barcode": barcode,
          "min_stock_level": minStockLevel,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['status'] == 'success') {
          await fetchProducts();
          await fetchOwnerAlerts();
          return true;
        }
      }
    } catch (e) {
      debugPrint("Min stock update error: $e");
    }
    return false;
  }

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
          await fetchOwnerAlerts();
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint("Stock update error: $e");
      return false;
    }
  }

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
          await fetchOwnerAlerts();
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint("Adjust stock error: $e");
      return false;
    }
  }

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

  Map<String, dynamic> _buildFallbackOwnerSummary() {
    final transactions = transactionCount;
    return {
      'today_sales': _todayTotalSales,
      'transaction_count': transactions,
      'average_sale': transactions > 0 ? _todayTotalSales / transactions : 0.0,
      'items_sold': 0,
    };
  }

  List<Map<String, dynamic>> _buildFallbackAlertsFromProducts() {
    final alerts = <Map<String, dynamic>>[];

    final outOfStock = _products.where((p) => p.stock <= 0).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final lowStock = _products
        .where(
          (p) =>
              p.stock > 0 &&
              p.stock <= (p.minStockLevel > 0 ? p.minStockLevel : 10),
        )
        .toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    for (final product in outOfStock.take(5)) {
      alerts.add({
        'type': 'out_of_stock',
        'severity': 'critical',
        'title': '${product.name} is out of stock',
        'subtitle': 'Barcode ${product.barcode} • stock 0',
        'barcode': product.barcode,
      });
    }

    for (final product in lowStock.take(5)) {
      alerts.add({
        'type': 'low_stock',
        'severity': 'warning',
        'title': '${product.name} is low in stock',
        'subtitle':
            'Barcode ${product.barcode} • stock ${product.stock} • min ${product.minStockLevel}',
        'barcode': product.barcode,
      });
    }

    if ((_todayTotalSales) <= 0) {
      alerts.add({
        'type': 'weak_sales',
        'severity': 'warning',
        'title': 'No sales recorded today',
        'subtitle': 'Check store activity and cashier flow.',
      });
    }

    return alerts;
  }

  String _historyTitle(String movementType) {
    switch (movementType) {
      case 'sale':
        return 'Sale';
      case 'refund':
        return 'Refund';
      case 'stock_in':
      case 'stock_receive':
        return 'Stock Received';
      case 'adjustment':
      case 'stock_adjust_add':
      case 'stock_adjust_remove':
      case 'stock_adjust_set':
        return 'Manual Adjustment';
      case 'price_update':
      case 'price_change_selling':
      case 'price_change_wholesale':
      case 'price_change_sale':
      case 'price_change_cost':
        return 'Price Update';
      case 'min_stock_change':
        return 'Minimum Stock Updated';
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
      case 'stock_receive':
        return 'Stock received from supplier';
      case 'adjustment':
      case 'stock_adjust_add':
      case 'stock_adjust_remove':
      case 'stock_adjust_set':
        return quantity >= 0
            ? 'Manual stock increase'
            : 'Manual stock decrease';
      case 'price_update':
      case 'price_change_selling':
      case 'price_change_wholesale':
      case 'price_change_sale':
      case 'price_change_cost':
        return 'Price changed';
      case 'min_stock_change':
        return 'Minimum stock level changed';
      default:
        return 'Inventory activity';
    }
  }

  String _historyQuantityText(String movementType, int quantity) {
    if (movementType.startsWith('price_') || movementType == 'min_stock_change') {
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
      case 'stock_receive':
        return Icons.local_shipping;
      case 'adjustment':
      case 'stock_adjust_add':
      case 'stock_adjust_remove':
      case 'stock_adjust_set':
        return Icons.tune;
      case 'price_update':
      case 'price_change_selling':
      case 'price_change_wholesale':
      case 'price_change_sale':
      case 'price_change_cost':
        return Icons.edit;
      case 'min_stock_change':
        return Icons.vertical_align_center;
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
      case 'stock_receive':
        return Colors.green;
      case 'adjustment':
      case 'stock_adjust_add':
      case 'stock_adjust_remove':
      case 'stock_adjust_set':
        return Colors.orange;
      case 'price_update':
      case 'price_change_selling':
      case 'price_change_wholesale':
      case 'price_change_sale':
      case 'price_change_cost':
        return Colors.blue;
      case 'min_stock_change':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
}
