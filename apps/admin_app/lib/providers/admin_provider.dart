
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

  bool _isOwnerSalesLoading = false;
  Map<String, dynamic> _ownerSalesReport = {};

  bool _isOwnerUsersLoading = false;
  Map<String, dynamic> _ownerUsersSummary = {};
  List<Map<String, dynamic>> _ownerUsers = [];
  List<Map<String, dynamic>> _ownerActivityLogs = [];

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

  bool get isOwnerSalesLoading => _isOwnerSalesLoading;
  Map<String, dynamic> get ownerSalesReport => _ownerSalesReport;
  Map<String, dynamic> get ownerSalesSummary => Map<String, dynamic>.from((_ownerSalesReport['summary'] as Map?) ?? <String, dynamic>{});
  List<Map<String, dynamic>> get ownerSalesTrendReport => ((_ownerSalesReport['trend'] as List?) ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  List<Map<String, dynamic>> get ownerSalesCashiers => ((_ownerSalesReport['cashier_summary'] as List?) ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  List<Map<String, dynamic>> get ownerSalesTopProducts => ((_ownerSalesReport['top_products'] as List?) ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  List<Map<String, dynamic>> get ownerSalesSlowMovers => ((_ownerSalesReport['slow_movers'] as List?) ?? []).map((item) => Map<String, dynamic>.from(item as Map)).toList();

  bool get isOwnerUsersLoading => _isOwnerUsersLoading;
  Map<String, dynamic> get ownerUsersSummary => _ownerUsersSummary;
  List<Map<String, dynamic>> get ownerUsers => _ownerUsers;
  List<Map<String, dynamic>> get ownerActivityLogs => _ownerActivityLogs;

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

  Future<void> fetchOwnerSalesReport({
    String range = 'today',
    DateTime? specificDate,
    DateTimeRange? dateRange,
  }) async {
    _isOwnerSalesLoading = true;
    notifyListeners();

    try {
      final query = <String, String>{'action': 'get_owner_sales_report'};

      switch (range) {
        case 'last7':
          query['range'] = '7d';
          break;
        case 'last30':
          query['range'] = '30d';
          break;
        case 'specific':
          query['range'] = 'specific';
          query['date'] = _formatDateOnly(specificDate ?? DateTime.now());
          break;
        case 'custom':
          final start = dateRange?.start ?? DateTime.now();
          final end = dateRange?.end ?? DateTime.now();
          query['range'] = 'custom';
          query['start_date'] = _formatDateOnly(start);
          query['end_date'] = _formatDateOnly(end);
          break;
        case 'today':
        default:
          query['range'] = 'today';
      }

      final uri = Uri.parse(apiUrl).replace(queryParameters: query);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          _ownerSalesReport = Map<String, dynamic>.from(data as Map);
          _isOwnerSalesLoading = false;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Owner sales report fetch error: $e');
    }

    _ownerSalesReport = _buildFallbackOwnerSalesReport(
      range: range,
      specificDate: specificDate,
      dateRange: dateRange,
    );
    _isOwnerSalesLoading = false;
    notifyListeners();
  }

  Map<String, dynamic> _buildFallbackOwnerSalesReport({
    required String range,
    DateTime? specificDate,
    DateTimeRange? dateRange,
  }) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    String label;

    switch (range) {
      case 'last7':
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
        end = DateTime(now.year, now.month, now.day);
        label = 'Last 7 Days';
        break;
      case 'last30':
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
        end = DateTime(now.year, now.month, now.day);
        label = 'Last 30 Days';
        break;
      case 'specific':
        final picked = specificDate ?? now;
        start = DateTime(picked.year, picked.month, picked.day);
        end = start;
        label = _formatDateOnly(start);
        break;
      case 'custom':
        start = DateTime(
          (dateRange?.start ?? now).year,
          (dateRange?.start ?? now).month,
          (dateRange?.start ?? now).day,
        );
        end = DateTime(
          (dateRange?.end ?? now).year,
          (dateRange?.end ?? now).month,
          (dateRange?.end ?? now).day,
        );
        label = '${_formatDateOnly(start)} to ${_formatDateOnly(end)}';
        break;
      case 'today':
      default:
        start = DateTime(now.year, now.month, now.day);
        end = start;
        label = 'Today';
    }

    return {
      'window': {
        'range_key': range,
        'label': label,
        'start_date': _formatDateOnly(start),
        'end_date': _formatDateOnly(end),
      },
      'summary': {
        'gross_sales': _todayTotalSales,
        'net_sales': _todayTotalSales,
        'discounts': 0.0,
        'refunds': 0.0,
        'cash_sales': 0.0,
        'card_sales': 0.0,
        'transaction_count': transactionCount,
        'items_sold': 0,
        'average_sale': averageSale,
        'gross_profit': 0.0,
        'margin_percent': 0.0,
      },
      'trend': <Map<String, dynamic>>[],
      'cashier_summary': _cashierBreakdown
          .map((item) => {
                'cashier_name': (item['cashier_name'] ?? 'Unknown').toString(),
                'transaction_count': int.tryParse('${item['transaction_count'] ?? 0}') ?? 0,
                'items_sold': 0,
                'net_sales': double.tryParse('${item['total_sales'] ?? 0}') ?? 0.0,
                'refund_total': 0.0,
                'gross_profit': 0.0,
                'average_sale': 0.0,
              })
          .toList(),
      'top_products': <Map<String, dynamic>>[],
      'slow_movers': <Map<String, dynamic>>[],
    };
  }


  Future<void> fetchOwnerUsersActivity({
    String userSearch = '',
    String role = 'all',
    String status = 'all',
    String activitySearch = '',
    String activityFilter = 'all',
    int activityLimit = 30,
  }) async {
    _isOwnerUsersLoading = true;
    notifyListeners();

    try {
      final summaryUri = Uri.parse(apiUrl).replace(
        queryParameters: const {'action': 'get_owner_user_summary'},
      );
      final usersUri = Uri.parse(apiUrl).replace(
        queryParameters: {
          'action': 'get_owner_users',
          'search': userSearch,
          'role': role,
          'status': status,
        },
      );
      final logsUri = Uri.parse(apiUrl).replace(
        queryParameters: {
          'action': 'get_owner_activity_logs',
          'search': activitySearch,
          'filter': activityFilter,
          'limit': '$activityLimit',
        },
      );

      final summaryResponse = await http.get(summaryUri);
      final usersResponse = await http.get(usersUri);
      final logsResponse = await http.get(logsUri);

      if (summaryResponse.statusCode == 200) {
        final data = json.decode(summaryResponse.body);
        if (data['status'] == 'success') {
          _ownerUsersSummary = Map<String, dynamic>.from(
            (data['summary'] as Map?) ?? <String, dynamic>{},
          );
        }
      }

      if (usersResponse.statusCode == 200) {
        final data = json.decode(usersResponse.body);
        if (data['status'] == 'success') {
          _ownerUsers = ((data['users'] as List?) ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }

      if (logsResponse.statusCode == 200) {
        final data = json.decode(logsResponse.body);
        if (data['status'] == 'success') {
          _ownerActivityLogs = ((data['logs'] as List?) ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Owner users/activity fetch error: $e');
      _ownerUsersSummary = {};
      _ownerUsers = [];
      _ownerActivityLogs = [];
    }

    _isOwnerUsersLoading = false;
    notifyListeners();
  }



  Future<String?> _postOwnerUserAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=$action'),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return null;
        }
        return (data['message'] ?? 'Request failed').toString();
      }

      try {
        final data = json.decode(response.body);
        return (data['message'] ?? 'Request failed').toString();
      } catch (_) {
        return 'Request failed';
      }
    } catch (e) {
      debugPrint('Owner user action error ($action): $e');
      return 'Network error';
    }
  }

  Future<String?> createOwnerUser({
    required String name,
    required String role,
    required String pin,
  }) async {
    final message = await _postOwnerUserAction(
      'create_owner_user',
      {
        'name': name,
        'role': role,
        'pin': pin,
        'actor_name': 'Admin Mobile',
      },
    );
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> updateOwnerUserProfile({
    required int userId,
    required String name,
    required String role,
  }) async {
    final message = await _postOwnerUserAction(
      'update_owner_user',
      {
        'user_id': userId,
        'name': name,
        'role': role,
        'actor_name': 'Admin Mobile',
      },
    );
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> resetOwnerUserPin({
    required int userId,
    required String newPin,
  }) async {
    final message = await _postOwnerUserAction(
      'reset_owner_user_pin',
      {
        'user_id': userId,
        'new_pin': newPin,
        'actor_name': 'Admin Mobile',
      },
    );
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> setOwnerUserActiveStatus({
    required int userId,
    required bool isActive,
  }) async {
    final message = await _postOwnerUserAction(
      'set_owner_user_active_status',
      {
        'user_id': userId,
        'is_active': isActive,
        'actor_name': 'Admin Mobile',
      },
    );
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> setOwnerUserFullAccess({
    required int userId,
    required bool hasFullAccess,
  }) async {
    final message = await _postOwnerUserAction(
      'set_owner_user_full_access',
      {
        'user_id': userId,
        'has_full_access': hasFullAccess,
        'actor_name': 'Admin Mobile',
      },
    );
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
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


  String _formatDateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
