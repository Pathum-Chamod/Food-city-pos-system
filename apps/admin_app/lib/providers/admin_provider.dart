import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_history_item.dart';
import '../models/stock_adjustment_request.dart';
import '../models/supplier.dart';

class AdminProvider with ChangeNotifier {
  AdminProvider() {
    _restoreSession();
  }

  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _sessionUserIdKey = 'admin_session_user_id';
  static const String _sessionUserNameKey = 'admin_session_user_name';
  static const String _sessionUserRoleKey = 'admin_session_user_role';
  static const String _sessionUserFullAccessKey =
      'admin_session_user_full_access';
  static const String _biometricEnabledKey = 'admin_biometric_enabled';

  List<Product> _products = [];
  bool _isLoading = false;

  double _todayTotalSales = 0.0;
  List<dynamic> _cashierBreakdown = [];

  List<Supplier> _suppliers = [];
  final Map<String, Map<String, dynamic>> _productSupplierContacts = {};

  bool _isOwnerShellLoading = false;
  Map<String, dynamic> _ownerDashboardSummary = {};
  List<Map<String, dynamic>> _ownerSalesTrend = [];
  List<Map<String, dynamic>> _ownerTopProducts = [];
  List<Map<String, dynamic>> _ownerAlerts = [];

  bool _isOwnerSalesLoading = false;
  Map<String, dynamic> _ownerSalesReport = {};
  List<Map<String, dynamic>> _ownerSalesHourlyTrend = [];

  bool _isOwnerUsersLoading = false;
  Map<String, dynamic> _ownerUsersSummary = {};
  List<Map<String, dynamic>> _ownerUsers = [];
  List<Map<String, dynamic>> _ownerActivityLogs = [];

  bool _isBusinessInfoLoading = false;
  Map<String, dynamic> _businessInfo = {};

  bool _isSessionReady = false;
  bool _isAuthenticating = false;
  bool _showWelcomeAnimation = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _biometricEnrolled = false;
  bool _biometricUnlockRequired = false;
  bool _manualUnlockRequested = false;
  bool _isBiometricBusy = false;
  List<BiometricType> _availableBiometrics = const [];
  Map<String, dynamic>? _currentOwnerUser;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  double get todayTotalSales => _todayTotalSales;
  List<dynamic> get cashierBreakdown => _cashierBreakdown;
  List<Supplier> get suppliers => _suppliers;
  Map<String, dynamic> supplierContactForBarcode(String barcode) =>
      Map<String, dynamic>.from(
        _productSupplierContacts[barcode] ?? const <String, dynamic>{},
      );

  bool get isOwnerShellLoading => _isOwnerShellLoading;
  Map<String, dynamic> get ownerDashboardSummary => _ownerDashboardSummary;
  List<Map<String, dynamic>> get ownerSalesTrend => _ownerSalesTrend;
  List<Map<String, dynamic>> get ownerTopProducts => _ownerTopProducts;
  List<Map<String, dynamic>> get ownerAlerts => _ownerAlerts;

  bool get isOwnerSalesLoading => _isOwnerSalesLoading;
  Map<String, dynamic> get ownerSalesReport => _ownerSalesReport;
  List<Map<String, dynamic>> get ownerSalesHourlyTrend =>
      _ownerSalesHourlyTrend;
  Map<String, dynamic> get ownerSalesSummary => Map<String, dynamic>.from(
    (_ownerSalesReport['summary'] as Map?) ?? <String, dynamic>{},
  );
  List<Map<String, dynamic>> get ownerSalesTrendReport =>
      ((_ownerSalesReport['trend'] as List?) ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  List<Map<String, dynamic>> get ownerSalesCashiers =>
      ((_ownerSalesReport['cashier_summary'] as List?) ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  List<Map<String, dynamic>> get ownerSalesTopProducts =>
      ((_ownerSalesReport['top_products'] as List?) ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                _normalizeSalesProductRow(Map<String, dynamic>.from(item)),
          )
          .toList();
  List<Map<String, dynamic>> get ownerSalesSlowMovers =>
      ((_ownerSalesReport['slow_movers'] as List?) ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                _normalizeSalesProductRow(Map<String, dynamic>.from(item)),
          )
          .toList();

  bool get isOwnerUsersLoading => _isOwnerUsersLoading;
  Map<String, dynamic> get ownerUsersSummary => _ownerUsersSummary;
  List<Map<String, dynamic>> get ownerUsers => _ownerUsers;
  List<Map<String, dynamic>> get ownerActivityLogs => _ownerActivityLogs;

  bool get isBusinessInfoLoading => _isBusinessInfoLoading;
  Map<String, dynamic> get businessInfo => _businessInfo;

  bool get isSessionReady => _isSessionReady;
  bool get isAuthenticating => _isAuthenticating;
  bool get showWelcomeAnimation => _showWelcomeAnimation;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnrolled => _biometricEnrolled;
  bool get biometricUnlockRequired => _biometricUnlockRequired;
  bool get isBiometricBusy => _isBiometricBusy;
  bool get shouldShowBiometricUnlock =>
      _currentOwnerUser != null &&
      _biometricEnabled &&
      _biometricUnlockRequired &&
      !_manualUnlockRequested;
  bool get shouldShowPinLogin =>
      _currentOwnerUser == null || _manualUnlockRequested;
  bool get isAuthenticated => _currentOwnerUser != null;
  Map<String, dynamic>? get currentOwnerUser => _currentOwnerUser == null
      ? null
      : Map<String, dynamic>.from(_currentOwnerUser!);
  String get currentOwnerName =>
      (_currentOwnerUser?['name'] ?? 'Owner').toString();
  String get currentOwnerRole => (_currentOwnerUser?['role'] ?? '').toString();
  bool get currentOwnerHasFullAccess =>
      (_currentOwnerUser?['has_full_access'] == true) ||
      (_currentOwnerUser?['has_full_access'] == 1);

  String get biometricTypeLabel {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face ID / biometrics';
    }
    if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    }
    if (_availableBiometrics.contains(BiometricType.strong) ||
        _availableBiometrics.contains(BiometricType.weak)) {
      return 'Biometrics';
    }
    return 'Biometrics';
  }

  String get biometricSettingsSubtitle {
    if (!_biometricAvailable || !_biometricEnrolled) {
      return 'Not available on this device yet. Set up fingerprint or biometrics in device settings first.';
    }
    return 'Use $biometricTypeLabel to unlock the owner app faster on this device.';
  }

  List<Map<String, dynamic>> get topAlertsPreview =>
      _ownerAlerts.take(3).toList();

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
  int get outOfStockCount => _products.where((p) => p.isOutOfStock).length;
  int get lowStockCount => _products.where((p) => p.isLowStock).length;

  final String apiUrl = "http://10.0.2.2:8080/api/pos_sync.php";
  // final String apiUrl = "http://127.0.0.1:8080/api/pos_sync.php";

  String _formatAlertQuantity(Product product, double value) {
    final safeValue = value.abs() < Product.quantityEpsilon ? 0.0 : value;
    if (!product.isWeighted) {
      return '${safeValue.round()} ${product.unitLabel}';
    }

    final text = safeValue
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return '$text ${product.unitLabel}';
  }

  Map<String, dynamic> _normalizeSalesProductRow(Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    final barcode = (normalized['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty) return normalized;

    Product? product;
    for (final candidate in _products) {
      if (candidate.barcode == barcode) {
        product = candidate;
        break;
      }
    }
    if (product == null) return normalized;

    normalized['quantity_type'] = product.quantityType.dbValue;
    normalized['unit_label'] = product.unitLabel;
    normalized['stock'] = normalized['stock'] ?? product.stock;
    return normalized;
  }

  Map<String, dynamic> _normalizeOwnerAlert(Map<String, dynamic> alert) {
    final normalized = Map<String, dynamic>.from(alert);
    final barcode = (normalized['barcode'] ?? '').toString().trim();
    if (barcode.isEmpty) return normalized;

    Product? product;
    for (final candidate in _products) {
      if (candidate.barcode == barcode) {
        product = candidate;
        break;
      }
    }
    if (product == null) return normalized;

    final type = (normalized['type'] ?? '').toString();
    final isStockAlert =
        type == 'out_of_stock' ||
        type == 'low_stock' ||
        type == 'best_seller_low_stock';
    if (!isStockAlert) return normalized;

    final stockText = _formatAlertQuantity(product, product.stock);
    if (product.isOutOfStock) {
      normalized['type'] = 'out_of_stock';
      normalized['severity'] = 'critical';
      normalized['title'] = '${product.name} is out of stock';
      normalized['subtitle'] =
          'Barcode ${product.barcode} - stock ${_formatAlertQuantity(product, 0)}';
      return normalized;
    }

    if (product.isLowStock) {
      final title = type == 'best_seller_low_stock'
          ? 'Best seller low in stock: ${product.name}'
          : '${product.name} is low in stock';
      normalized['type'] = type == 'best_seller_low_stock'
          ? 'best_seller_low_stock'
          : 'low_stock';
      normalized['severity'] = 'warning';
      normalized['title'] = title;

      final currentSubtitle = (normalized['subtitle'] ?? '').toString().trim();
      if (type == 'best_seller_low_stock' &&
          currentSubtitle.startsWith('Sold ')) {
        final parts = currentSubtitle.split(' - ');
        final salesPrefix = parts.isNotEmpty ? parts.first : currentSubtitle;
        normalized['subtitle'] = '$salesPrefix - stock $stockText';
      } else {
        normalized['subtitle'] =
            'Barcode ${product.barcode} - stock $stockText - min ${_formatAlertQuantity(product, product.minStockLevel.toDouble())}';
      }
    }

    return normalized;
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt(_sessionUserIdKey);
      final userName = prefs.getString(_sessionUserNameKey);
      final userRole = prefs.getString(_sessionUserRoleKey);
      final hasFullAccess = prefs.getBool(_sessionUserFullAccessKey) ?? false;
      _biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;

      if (userId != null && userName != null && userName.trim().isNotEmpty) {
        _currentOwnerUser = {
          'id': userId,
          'name': userName,
          'role': userRole ?? 'cashier',
          'has_full_access': hasFullAccess,
        };
      }

      await refreshBiometricAvailability(notify: false);

      if (_currentOwnerUser != null &&
          _biometricEnabled &&
          _biometricAvailable &&
          _biometricEnrolled) {
        _biometricUnlockRequired = true;
      }
    } catch (e) {
      debugPrint('Session restore error: $e');
    } finally {
      _isSessionReady = true;
      notifyListeners();
    }
  }

  Future<void> refreshBiometricAvailability({bool notify = true}) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = canCheck
          ? await _localAuth.getAvailableBiometrics()
          : <BiometricType>[];
      _availableBiometrics = available;
      _biometricAvailable = canCheck;
      _biometricEnrolled = available.isNotEmpty;
    } catch (e) {
      debugPrint('Biometric availability check error: $e');
      _availableBiometrics = const [];
      _biometricAvailable = false;
      _biometricEnrolled = false;
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<String?> enableBiometricUnlock() async {
    if (_currentOwnerUser == null) {
      return 'Sign in with your owner PIN first.';
    }

    _isBiometricBusy = true;
    notifyListeners();

    try {
      await refreshBiometricAvailability(notify: false);

      if (!_biometricAvailable) {
        return 'Biometric hardware is not available on this device.';
      }

      if (!_biometricEnrolled) {
        return 'No fingerprint or biometrics are enrolled on this device.';
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason:
            'Scan your fingerprint to enable biometric unlock for Food City Admin.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!didAuthenticate) {
        return 'Biometric setup was cancelled.';
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, true);

      _biometricEnabled = true;
      _biometricUnlockRequired = false;
      _manualUnlockRequested = false;
      return null;
    } on LocalAuthException catch (e) {
      if (e.code == LocalAuthExceptionCode.noBiometricHardware) {
        return 'Biometric hardware is not available on this device.';
      }
      if (e.code == LocalAuthExceptionCode.noBiometricsEnrolled) {
        return 'No fingerprint or biometrics are enrolled on this device.';
      }
      if (e.code == LocalAuthExceptionCode.noCredentialsSet) {
        return 'Set up a screen lock and biometrics on this device first.';
      }
      if (e.code == LocalAuthExceptionCode.temporaryLockout ||
          e.code == LocalAuthExceptionCode.biometricLockout) {
        return 'Biometrics are temporarily locked. Unlock the device and try again.';
      }
      return 'Unable to enable biometric unlock.';
    } catch (e) {
      debugPrint('Enable biometric error: $e');
      return 'Unable to enable biometric unlock.';
    } finally {
      _isBiometricBusy = false;
      notifyListeners();
    }
  }

  Future<void> disableBiometricUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, false);

    _biometricEnabled = false;
    _biometricUnlockRequired = false;
    _manualUnlockRequested = false;
    notifyListeners();
  }

  Future<String?> unlockWithBiometrics() async {
    if (_currentOwnerUser == null) {
      return 'Please sign in with your owner PIN first.';
    }

    _isBiometricBusy = true;
    notifyListeners();

    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Scan your fingerprint to unlock Food City Admin.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!didAuthenticate) {
        return 'Biometric unlock was cancelled.';
      }

      _biometricUnlockRequired = false;
      _manualUnlockRequested = false;
      return null;
    } on LocalAuthException catch (e) {
      if (e.code == LocalAuthExceptionCode.noBiometricsEnrolled) {
        return 'No fingerprint or biometrics are enrolled on this device.';
      }
      if (e.code == LocalAuthExceptionCode.noBiometricHardware) {
        return 'Biometric hardware is not available on this device.';
      }
      if (e.code == LocalAuthExceptionCode.temporaryLockout ||
          e.code == LocalAuthExceptionCode.biometricLockout) {
        return 'Biometrics are temporarily locked. Unlock the device and try again.';
      }
      return 'Unable to unlock with biometrics.';
    } catch (e) {
      debugPrint('Biometric unlock error: $e');
      return 'Unable to unlock with biometrics.';
    } finally {
      _isBiometricBusy = false;
      notifyListeners();
    }
  }

  void usePinInsteadOfBiometrics() {
    _manualUnlockRequested = true;
    notifyListeners();
  }

  Future<void> _saveSession(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionUserIdKey, (user['id'] as num?)?.toInt() ?? 0);
    await prefs.setString(_sessionUserNameKey, (user['name'] ?? '').toString());
    await prefs.setString(
      _sessionUserRoleKey,
      (user['role'] ?? 'cashier').toString(),
    );
    await prefs.setBool(
      _sessionUserFullAccessKey,
      user['has_full_access'] == true || user['has_full_access'] == 1,
    );
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionUserIdKey);
    await prefs.remove(_sessionUserNameKey);
    await prefs.remove(_sessionUserRoleKey);
    await prefs.remove(_sessionUserFullAccessKey);
  }

  Future<String?> loginOwner(String pin) async {
    final trimmedPin = pin.trim();
    if (trimmedPin.length != 4 || int.tryParse(trimmedPin) == null) {
      return 'Enter a valid 4-digit PIN.';
    }

    _isAuthenticating = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=owner_login'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({'pin': trimmedPin}),
      );

      final Map<String, dynamic> data =
          json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['status'] == 'success') {
        final user = Map<String, dynamic>.from(
          (data['user'] as Map?) ?? <String, dynamic>{},
        );
        _currentOwnerUser = user;
        _showWelcomeAnimation = true;
        _manualUnlockRequested = false;
        _biometricUnlockRequired = false;
        await _saveSession(user);
        _isAuthenticating = false;
        notifyListeners();
        return null;
      }

      _isAuthenticating = false;
      notifyListeners();
      return (data['message'] ?? 'Unable to sign in').toString();
    } catch (e) {
      debugPrint('Owner login error: $e');
      _isAuthenticating = false;
      notifyListeners();
      return 'Network error';
    }
  }

  Future<void> logout() async {
    final currentUser = _currentOwnerUser == null
        ? null
        : Map<String, dynamic>.from(_currentOwnerUser!);

    try {
      if (currentUser != null) {
        await http.post(
          Uri.parse('$apiUrl?action=owner_logout'),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            'user_id': currentUser['id'],
            'user_name': currentUser['name'],
          }),
        );
      }
    } catch (e) {
      debugPrint('Owner logout sync warning: $e');
    }

    await _clearSession();
    _currentOwnerUser = null;
    _showWelcomeAnimation = false;
    _biometricUnlockRequired = false;
    _manualUnlockRequested = false;
    notifyListeners();
  }

  void completeWelcomeAnimation() {
    if (!_showWelcomeAnimation) return;
    _showWelcomeAnimation = false;
    notifyListeners();
  }

  Future<String?> exportDataBackup() async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=export_data_backup'),
      );

      final Map<String, dynamic> data =
          json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['status'] != 'success') {
        return (data['message'] ?? 'Unable to export backup').toString();
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .replaceAll('T', '_');
      final file = File('${tempDir.path}/food_city_backup_$timestamp.json');
      final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
      await file.writeAsString(prettyJson, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Food City backup export',
        subject: 'Food City backup export',
      );

      return null;
    } catch (e) {
      debugPrint('Backup export error: $e');
      return 'Unable to export backup';
    }
  }

  Future<void> loadOwnerShellData({bool forceRefresh = false}) async {
    if (_isOwnerShellLoading && !forceRefresh) return;

    _isOwnerShellLoading = true;
    notifyListeners();

    try {
      await fetchProducts();
      await fetchDashboardStats();
      await fetchOwnerDashboard();
      await _syncDashboardTopProductsFromSalesReport();
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
    await _syncDashboardTopProductsFromSalesReport();
    await fetchOwnerAlerts();
  }

  Future<void> fetchProducts() async {
    _isLoading = true;
    _productSupplierContacts.clear();
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
              .whereType<Map>()
              .map(
                (item) =>
                    _normalizeSalesProductRow(Map<String, dynamic>.from(item)),
              )
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

  Future<Map<String, dynamic>> fetchProductSupplierContact(
    String barcode,
  ) async {
    final normalized = barcode.trim();
    if (normalized.isEmpty) return const {};

    final cached = _productSupplierContacts[normalized];
    if (cached != null && cached.isNotEmpty) {
      return Map<String, dynamic>.from(cached);
    }

    try {
      final response = await http.get(
        Uri.parse(
          '$apiUrl?action=get_product_supplier_contact&barcode=$normalized',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final contact = Map<String, dynamic>.from(
            (data['contact'] as Map?) ?? const <String, dynamic>{},
          );
          final hasVisibleDetails =
              (contact['supplier_name'] ?? '').toString().trim().isNotEmpty ||
              (contact['supplier_phone'] ?? '').toString().trim().isNotEmpty;
          if (hasVisibleDetails) {
            _productSupplierContacts[normalized] = contact;
          } else {
            _productSupplierContacts.remove(normalized);
          }
          return Map<String, dynamic>.from(contact);
        }
      }
    } catch (e) {
      debugPrint('Product supplier contact fetch error: $e');
    }

    _productSupplierContacts.remove(normalized);
    return const {};
  }

  Future<void> _syncDashboardTopProductsFromSalesReport() async {
    try {
      final uri = Uri.parse(apiUrl).replace(
        queryParameters: const {
          'action': 'get_owner_sales_report',
          'range': 'today',
        },
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      if (data['status'] != 'success') return;

      final rows = ((data['top_products'] as List?) ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                _normalizeSalesProductRow(Map<String, dynamic>.from(item)),
          )
          .toList();

      _ownerTopProducts = rows
          .map(_mapSalesReportProductToDashboardRow)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Dashboard top products sync error: $e');
    }
  }

  Map<String, dynamic> _mapSalesReportProductToDashboardRow(
    Map<String, dynamic> row,
  ) {
    final totalSales =
        ((row['net_sales_after_refunds'] ?? row['net_sales']) as num?)
            ?.toDouble() ??
        0.0;
    final quantitySold =
        ((row['net_quantity_sold'] ??
                    row['sold_quantity'] ??
                    row['quantity_sold'])
                as num?)
            ?.toDouble() ??
        0.0;

    return {...row, 'total_sales': totalSales, 'quantity_sold': quantitySold};
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
              .whereType<Map>()
              .map(
                (item) => _normalizeOwnerAlert(Map<String, dynamic>.from(item)),
              )
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
          final payload = Map<String, dynamic>.from(data as Map);
          payload['top_products'] = ((payload['top_products'] as List?) ?? [])
              .whereType<Map>()
              .map(
                (item) =>
                    _normalizeSalesProductRow(Map<String, dynamic>.from(item)),
              )
              .toList();
          payload['slow_movers'] = ((payload['slow_movers'] as List?) ?? [])
              .whereType<Map>()
              .map(
                (item) =>
                    _normalizeSalesProductRow(Map<String, dynamic>.from(item)),
              )
              .toList();
          _ownerSalesReport = payload;
          _ownerSalesHourlyTrend = await _resolveOwnerSalesHourlyTrend(
            payload: payload,
            range: range,
            specificDate: specificDate,
          );
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
    _ownerSalesHourlyTrend = const [];
    _isOwnerSalesLoading = false;
    notifyListeners();
  }

  bool _usesHourlyTrend(String range) =>
      range == 'today' || range == 'specific';

  Future<List<Map<String, dynamic>>> _resolveOwnerSalesHourlyTrend({
    required Map<String, dynamic> payload,
    required String range,
    DateTime? specificDate,
  }) async {
    if (!_usesHourlyTrend(range)) return const [];

    final embedded = _extractHourlyTrendRows(payload);
    if (embedded.isNotEmpty) {
      return embedded;
    }

    final targetDay = specificDate ?? DateTime.now();
    return _fetchOwnerHourlyTrendForDay(targetDay);
  }

  List<Map<String, dynamic>> _extractHourlyTrendRows(
    Map<String, dynamic> payload,
  ) {
    const possibleKeys = [
      'hourly_trend',
      'trend_hourly',
      'hourly_sales',
      'sales_by_hour',
      'hour_breakdown',
      'hourly',
    ];

    for (final key in possibleKeys) {
      final raw = payload[key];
      if (raw is List) {
        final rows = raw
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final normalized = _normalizeHourlyTrendRows(rows);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }

    final trend = payload['trend'];
    if (trend is List) {
      final rows = trend
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      return _normalizeHourlyTrendRows(rows);
    }

    return const [];
  }

  Future<List<Map<String, dynamic>>> _fetchOwnerHourlyTrendForDay(
    DateTime day,
  ) async {
    final formattedDay = _formatDateOnly(day);
    final attempts = <Map<String, String>>[
      {
        'action': 'get_owner_sales_report',
        'range': 'today',
        'granularity': 'hourly',
      },
      {
        'action': 'get_owner_sales_report',
        'range': 'specific',
        'date': formattedDay,
        'granularity': 'hourly',
      },
      {
        'action': 'get_owner_sales_report',
        'range': 'specific',
        'date': formattedDay,
        'view': 'hourly',
      },
      {
        'action': 'get_owner_sales_report',
        'range': 'specific',
        'date': formattedDay,
        'breakdown': 'hourly',
      },
    ];

    for (final query in attempts) {
      try {
        final uri = Uri.parse(apiUrl).replace(queryParameters: query);
        final response = await http.get(uri);
        if (response.statusCode != 200) continue;

        final data = json.decode(response.body);
        if (data['status'] != 'success') continue;

        final payload = Map<String, dynamic>.from(data as Map);
        final rows = _extractHourlyTrendRows(payload);
        if (rows.isNotEmpty) {
          return rows;
        }
      } catch (e) {
        debugPrint('Owner hourly trend fetch warning: $e');
      }
    }

    return const [];
  }

  List<Map<String, dynamic>> _normalizeHourlyTrendRows(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return const [];

    final normalized = <Map<String, dynamic>>[];
    for (final row in rows) {
      final hour = _extractHourFromTrendRow(row);
      if (hour == null) continue;

      normalized.add({
        ...row,
        'hour': hour,
        'net_after_refunds':
            ((row['net_after_refunds'] ?? row['net_sales'] ?? row['sales'])
                    as num?)
                ?.toDouble() ??
            0.0,
        'transaction_count':
            ((row['transaction_count'] ?? row['transactions']) as num?)
                ?.toInt() ??
            0,
      });
    }

    normalized.sort(
      (a, b) => ((a['hour'] as num?)?.toInt() ?? 0).compareTo(
        (b['hour'] as num?)?.toInt() ?? 0,
      ),
    );
    return normalized;
  }

  int? _extractHourFromTrendRow(Map<String, dynamic> row) {
    final directValue = row['hour'] ?? row['sales_hour'] ?? row['hour_of_day'];
    if (directValue is num) {
      final hour = directValue.toInt();
      return hour >= 0 && hour <= 23 ? hour : null;
    }

    if (directValue is String) {
      final parsed = int.tryParse(directValue.trim());
      if (parsed != null && parsed >= 0 && parsed <= 23) {
        return parsed;
      }
    }

    final textCandidates = [
      row['label'],
      row['time_label'],
      row['hour_label'],
      row['bucket'],
    ];

    for (final candidate in textCandidates) {
      final parsed = _parseHourLabel(candidate?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  int? _parseHourLabel(String raw) {
    final input = raw.trim().toLowerCase();
    if (input.isEmpty) return null;

    final twentyFourHour = RegExp(r'^(\d{1,2})[:.]?\d{0,2}$').firstMatch(input);
    if (twentyFourHour != null) {
      final hour = int.tryParse(twentyFourHour.group(1)!);
      if (hour != null && hour >= 0 && hour <= 23) {
        return hour;
      }
    }

    final meridiem = RegExp(
      r'^(\d{1,2})(?::\d{2})?\s*([ap]m)$',
    ).firstMatch(input);
    if (meridiem != null) {
      final baseHour = int.tryParse(meridiem.group(1)!);
      if (baseHour == null || baseHour < 1 || baseHour > 12) return null;
      final suffix = meridiem.group(2);
      if (suffix == 'am') {
        return baseHour == 12 ? 0 : baseHour;
      }
      return baseHour == 12 ? 12 : baseHour + 12;
    }

    final compactMeridiem = RegExp(r'^(\d{1,2})([ap])$').firstMatch(input);
    if (compactMeridiem != null) {
      final baseHour = int.tryParse(compactMeridiem.group(1)!);
      if (baseHour == null || baseHour < 1 || baseHour > 12) return null;
      final suffix = compactMeridiem.group(2);
      if (suffix == 'a') {
        return baseHour == 12 ? 0 : baseHour;
      }
      return baseHour == 12 ? 12 : baseHour + 12;
    }

    return null;
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
        start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        end = DateTime(now.year, now.month, now.day);
        label = 'Last 7 Days';
        break;
      case 'last30':
        start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));
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
        'credit_sales': 0.0,
        'loyalty_redeemed_total': 0.0,
        'transaction_count': transactionCount,
        'items_sold': 0,
        'average_sale': averageSale,
        'gross_profit': 0.0,
        'margin_percent': 0.0,
      },
      'trend': <Map<String, dynamic>>[],
      'cashier_summary': _cashierBreakdown
          .map(
            (item) => {
              'cashier_name': (item['cashier_name'] ?? 'Unknown').toString(),
              'transaction_count':
                  int.tryParse('${item['transaction_count'] ?? 0}') ?? 0,
              'items_sold': 0,
              'net_sales':
                  double.tryParse('${item['total_sales'] ?? 0}') ?? 0.0,
              'refund_total': 0.0,
              'gross_profit': 0.0,
              'average_sale': 0.0,
            },
          )
          .toList(),
      'top_products': <Map<String, dynamic>>[],
      'slow_movers': <Map<String, dynamic>>[],
    };
  }

  Future<void> fetchBusinessInfo() async {
    _isBusinessInfoLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=get_business_info'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          _businessInfo = Map<String, dynamic>.from(
            (data['business_info'] as Map?) ?? <String, dynamic>{},
          );
          _isBusinessInfoLoading = false;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Business info fetch error: $e');
    }

    _businessInfo = _buildFallbackBusinessInfo();
    _isBusinessInfoLoading = false;
    notifyListeners();
  }

  Future<String?> updateBusinessInfo({
    required String storeName,
    required String branchName,
    required String phoneNumber,
    required String email,
    required String address,
    required String businessHours,
    required String currencyCode,
    required String businessNote,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl?action=update_business_info'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'store_name': storeName,
          'branch_name': branchName,
          'phone_number': phoneNumber,
          'email': email,
          'address': address,
          'business_hours': businessHours,
          'currency_code': currencyCode,
          'business_note': businessNote,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          await fetchBusinessInfo();
          return null;
        }
        return (data['message'] ?? 'Unable to update business info').toString();
      }

      try {
        final data = json.decode(response.body);
        return (data['message'] ?? 'Unable to update business info').toString();
      } catch (_) {
        return 'Unable to update business info';
      }
    } catch (e) {
      debugPrint('Business info update error: $e');
      return 'Network error';
    }
  }

  Map<String, dynamic> _buildFallbackBusinessInfo() {
    return {
      'store_name': 'Food City',
      'branch_name': 'Main Branch',
      'phone_number': '',
      'email': '',
      'address': '',
      'business_hours': '8:00 AM - 10:00 PM',
      'currency_code': 'LKR',
      'business_note': '',
      'updated_at': DateTime.now().toIso8601String(),
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
      final summaryUri = Uri.parse(
        apiUrl,
      ).replace(queryParameters: const {'action': 'get_owner_user_summary'});
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
    final message = await _postOwnerUserAction('create_owner_user', {
      'name': name,
      'role': role,
      'pin': pin,
      'actor_name': 'Admin Mobile',
    });
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
    final message = await _postOwnerUserAction('update_owner_user', {
      'user_id': userId,
      'name': name,
      'role': role,
      'actor_name': 'Admin Mobile',
    });
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> resetOwnerUserPin({
    required int userId,
    required String newPin,
  }) async {
    final message = await _postOwnerUserAction('reset_owner_user_pin', {
      'user_id': userId,
      'new_pin': newPin,
      'actor_name': 'Admin Mobile',
    });
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> setOwnerUserActiveStatus({
    required int userId,
    required bool isActive,
  }) async {
    final message = await _postOwnerUserAction('set_owner_user_active_status', {
      'user_id': userId,
      'is_active': isActive,
      'actor_name': 'Admin Mobile',
    });
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<String?> setOwnerUserFullAccess({
    required int userId,
    required bool hasFullAccess,
  }) async {
    final message = await _postOwnerUserAction('set_owner_user_full_access', {
      'user_id': userId,
      'has_full_access': hasFullAccess,
      'actor_name': 'Admin Mobile',
    });
    if (message == null) {
      await fetchOwnerUsersActivity();
    }
    return message;
  }

  Future<void> fetchSuppliers() async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl?action=get_suppliers'),
      );

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
    num quantity,
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
    String barcode, {
    Product? product,
  }) async {
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
                (item) => _mapHistoryItem(
                  item as Map<String, dynamic>,
                  selectedProduct: product,
                ),
              )
              .toList();
        }
      }
    } catch (e) {
      debugPrint("Inventory history fetch error: $e");
    }

    return [];
  }

  InventoryHistoryItem _mapHistoryItem(
    Map<String, dynamic> item, {
    Product? selectedProduct,
  }) {
    final String movementType = item['movement_type']?.toString() ?? '';
    final double quantity = _asHistoryQuantity(item['quantity']);
    final String reason = item['reason']?.toString() ?? '';
    final String createdAt = item['created_at']?.toString() ?? '';
    final product =
        selectedProduct ??
        _products.firstWhere(
          (product) => product.barcode == (item['barcode'] ?? '').toString(),
          orElse: () => Product(
            barcode: (item['barcode'] ?? '').toString(),
            name: '',
            sellingPrice: 0,
            stock: 0,
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );

    return InventoryHistoryItem(
      type: movementType,
      title: _historyTitle(movementType),
      subtitle: _historySubtitle(movementType, reason, quantity),
      quantityText: _historyQuantityText(movementType, quantity, product),
      dateText: _formatHistoryDate(createdAt),
      icon: _historyIcon(movementType),
      color: _historyColor(movementType),
      unitLabel: product.unitLabel,
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

    final outOfStock = _products.where((p) => p.isOutOfStock).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final lowStock = _products.where((p) => p.isLowStock).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    for (final product in outOfStock.take(5)) {
      alerts.add({
        'type': 'out_of_stock',
        'severity': 'critical',
        'title': '${product.name} is out of stock',
        'subtitle':
            'Barcode ${product.barcode} - stock ${_formatAlertQuantity(product, 0)}',
        'barcode': product.barcode,
      });
    }

    for (final product in lowStock.take(5)) {
      alerts.add({
        'type': 'low_stock',
        'severity': 'warning',
        'title': '${product.name} is low in stock',
        'subtitle':
            'Barcode ${product.barcode} - stock ${_formatAlertQuantity(product, product.stock)} - min ${_formatAlertQuantity(product, product.minStockLevel.toDouble())}',
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
      case 'product_updated':
        return 'Product Updated';
      case 'product_created':
        return 'Product Added';
      case 'product_deleted':
        return 'Product Deleted';
      default:
        return 'Inventory Activity';
    }
  }

  double _asHistoryQuantity(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _formatHistoryQuantity(Product product, double value) {
    final safeValue = value.abs() < Product.quantityEpsilon ? 0.0 : value;
    if (!product.isWeighted ||
        (safeValue - safeValue.roundToDouble()).abs() <
            Product.quantityEpsilon) {
      return safeValue.round().toString();
    }

    return safeValue.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _historySubtitle(String movementType, String reason, double quantity) {
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
      case 'product_updated':
        return 'Product details updated';
      case 'product_created':
        return 'Product added to inventory';
      case 'product_deleted':
        return 'Product removed from inventory';
      default:
        return 'Inventory activity';
    }
  }

  String _historyQuantityText(
    String movementType,
    double quantity,
    Product product,
  ) {
    if (movementType.startsWith('price_') ||
        movementType == 'min_stock_change' ||
        movementType == 'product_updated' ||
        movementType == 'product_created' ||
        movementType == 'product_deleted') {
      return '—';
    }

    if (quantity > 0) {
      return '+${_formatHistoryQuantity(product, quantity)}';
    }

    if (quantity < 0) {
      return '-${_formatHistoryQuantity(product, quantity.abs())}';
    }

    return _formatHistoryQuantity(product, quantity);
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
      case 'product_updated':
        return Icons.edit_outlined;
      case 'product_created':
        return Icons.add_box_outlined;
      case 'product_deleted':
        return Icons.delete_outline;
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
      case 'product_updated':
        return Colors.blue;
      case 'product_created':
        return Colors.green;
      case 'product_deleted':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
