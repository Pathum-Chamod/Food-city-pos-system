import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/database_helper.dart';
import 'services/sync_service.dart';
import 'providers/cart_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/app_theme_provider.dart';
import 'navigation/pos_route_names.dart';
import 'screens/cashier_summary_screen.dart';
import 'screens/held_carts_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/login_screen.dart';
import 'screens/sales_report_screen.dart';
import 'screens/supplier_management_screen.dart';
import 'screens/transaction_history_screen.dart';
import 'screens/user_management_screen.dart';
import 'widgets/app_snackbar.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/hardware_setup_dialog.dart';

void main() async {
  // Ensure Flutter bindings are initialized before calling native code
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the local SQLite DB and inject mock data
  await DatabaseHelper.instance.database;
  await DatabaseHelper.instance.insertMockDataIfEmpty();

  // Start the background sync worker (checks every 30 seconds)
  SyncService().startSyncWorker();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AppThemeProvider()),
      ],
      child: const PosApp(),
    ),
  );
}

class _ShortcutRouteObserver extends NavigatorObserver {
  _ShortcutRouteObserver(this.onRouteChanged);

  final ValueChanged<String?> onRouteChanged;

  void _update(Route<dynamic>? route) {
    onRouteChanged(route?.settings.name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _update(newRoute);
  }
}

class PosApp extends StatefulWidget {
  const PosApp({super.key});

  @override
  State<PosApp> createState() => _PosAppState();
}

class _PosAppState extends State<PosApp> {
  late final _ShortcutRouteObserver _routeObserver;
  String? _currentRouteName;
  bool _isHandlingGlobalShortcut = false;

  @override
  void initState() {
    super.initState();
    _routeObserver = _ShortcutRouteObserver((routeName) {
      _currentRouteName = routeName;
    });
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyboardEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyboardEvent);
    super.dispose();
  }

  bool _handleGlobalKeyboardEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _isHandlingGlobalShortcut) return false;

    final navigatorContext = AppSnackBar.navigatorKey.currentContext;
    if (navigatorContext == null) return false;

    final auth = navigatorContext.read<AuthProvider>();
    if (!auth.isLoggedIn) return false;

    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final hasControl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final hasShift = keyboard.isShiftPressed;
    final hasAlt = keyboard.isAltPressed;

    if (key == LogicalKeyboardKey.home) {
      final navigator = AppSnackBar.navigatorKey.currentState;
      if (navigator == null || !navigator.canPop()) return false;
      _runGlobalShortcut(_goHome);
      return true;
    }

    if (hasAlt) return false;

    if (!hasControl && !hasShift) {
      if (key == LogicalKeyboardKey.f8) {
        _runGlobalShortcut(_openTransactionHistory);
        return true;
      }
      if (key == LogicalKeyboardKey.f9) {
        _runGlobalShortcut(_openInventory);
        return true;
      }
      if (key == LogicalKeyboardKey.f11) {
        _runGlobalShortcut(_openSupplierManagement);
        return true;
      }
      if (key == LogicalKeyboardKey.f12) {
        _runGlobalShortcut(_openSalesReport);
        return true;
      }
    }

    if (hasControl && !hasAlt) {
      if (hasShift && key == LogicalKeyboardKey.keyH) {
        _runGlobalShortcut(_openHardwareSetup);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyI) {
        _runGlobalShortcut(_openInventory);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyH) {
        _runGlobalShortcut(_openHeldCarts);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyR) {
        _runGlobalShortcut(_openSalesReport);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyU) {
        _runGlobalShortcut(_openUserManagement);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyS) {
        _runGlobalShortcut(_openCashierSummary);
        return true;
      }
    }

    return false;
  }

  void _runGlobalShortcut(Future<void> Function() action) {
    _isHandlingGlobalShortcut = true;
    unawaited(
      (() async {
        try {
          unawaited(action());
        } finally {
          await Future<void>.delayed(const Duration(milliseconds: 180));
          _isHandlingGlobalShortcut = false;
        }
      })(),
    );
  }

  void _runGlobalShortcutFromIntent(Future<void> Function() action) {
    if (_isHandlingGlobalShortcut) return;
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return;
    if (!context.read<AuthProvider>().isLoggedIn) return;
    _runGlobalShortcut(action);
  }

  Future<void> _goHome() async {
    final navigator = AppSnackBar.navigatorKey.currentState;
    if (navigator == null) return;

    navigator.popUntil(
      (route) => route.settings.name == PosRouteNames.pos || route.isFirst,
    );
  }

  Future<void> _pushOrRevealRoute({
    required String routeName,
    required WidgetBuilder builder,
  }) async {
    final navigator = AppSnackBar.navigatorKey.currentState;
    if (navigator == null || _currentRouteName == routeName) return;

    var foundRoute = false;
    navigator.popUntil((route) {
      if (route.settings.name == routeName) {
        foundRoute = true;
        return true;
      }

      return route.settings.name == PosRouteNames.pos || route.isFirst;
    });

    if (foundRoute) return;

    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: routeName),
          builder: builder,
        ),
      ),
    );
  }

  Future<void> _runProtectedManagerAction(
    Future<void> Function() action,
  ) async {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return;

    final auth = context.read<AuthProvider>();
    if (auth.hasManagementAccess) {
      await action();
      return;
    }

    await AdminDialogs.showPinDialog(context, action);
  }

  Future<void> _openInventory() {
    return _runProtectedManagerAction(() {
      return _pushOrRevealRoute(
        routeName: PosRouteNames.inventory,
        builder: (context) => const InventoryScreen(),
      );
    });
  }

  Future<void> _openTransactionHistory() {
    return _pushOrRevealRoute(
      routeName: PosRouteNames.transactionHistory,
      builder: (context) => const TransactionHistoryScreen(),
    );
  }

  Future<void> _openCashierSummary() {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return Future<void>.value();

    final cashierName = context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
    return _pushOrRevealRoute(
      routeName: PosRouteNames.cashierSummary,
      builder: (context) => CashierSummaryScreen(cashierName: cashierName),
    );
  }

  Future<void> _openSalesReport() {
    return _runProtectedManagerAction(() {
      return _pushOrRevealRoute(
        routeName: PosRouteNames.salesReport,
        builder: (context) => const SalesReportScreen(),
      );
    });
  }

  Future<void> _openUserManagement() {
    return _runProtectedManagerAction(() async {
      final context = AppSnackBar.navigatorKey.currentContext;
      await _pushOrRevealRoute(
        routeName: PosRouteNames.userManagement,
        builder: (context) => const UserManagementScreen(),
      );

      if (context == null) return;
      await context.read<AuthProvider>().refreshCurrentUser();
    });
  }

  Future<void> _openSupplierManagement() {
    return _runProtectedManagerAction(() {
      final context = AppSnackBar.navigatorKey.currentContext;
      if (context == null) return Future<void>.value();

      final cashierName =
          context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
      return _pushOrRevealRoute(
        routeName: PosRouteNames.supplierManagement,
        builder: (context) => SupplierManagementScreen(cashierName: cashierName),
      );
    });
  }

  Future<void> _openHardwareSetup() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return;

    await showHardwareSetupDialog(context);
  }

  Future<void> _openHeldCarts() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    final navigator = AppSnackBar.navigatorKey.currentState;
    if (context == null || navigator == null) return;
    if (_currentRouteName == PosRouteNames.heldCarts) return;

    final cart = context.read<CartProvider>();
    final canReplaceCart = await _confirmReplaceCurrentCartIfNeeded(cart);
    if (!canReplaceCart) return;

    final cashierName = context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    var foundRoute = false;
    navigator.popUntil((route) {
      if (route.settings.name == PosRouteNames.heldCarts) {
        foundRoute = true;
        return true;
      }

      return route.settings.name == PosRouteNames.pos || route.isFirst;
    });

    if (foundRoute) return;

    final restored = await navigator.push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        settings: const RouteSettings(name: PosRouteNames.heldCarts),
        builder: (context) => HeldCartsScreen(cashierName: cashierName),
      ),
    );

    if (restored == null) return;

    await _restoreHeldCart(restored, cart);
  }

  Future<bool> _confirmReplaceCurrentCartIfNeeded(CartProvider cart) async {
    if (cart.items.isEmpty) return true;

    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace Current Cart?'),
        content: const Text(
          'Opening a held bill will replace the current cart. Hold or finish the current cart first if you want to keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _restoreHeldCart(
    Map<String, dynamic> restored,
    CartProvider cart,
  ) async {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return;

    final resumeError = (restored['resume_error'] ?? '').toString().trim();
    if (resumeError.isNotEmpty) {
      AppSnackBar.show(
        context,
        message: resumeError,
        backgroundColor: const Color(0xFFFF6B7A),
      );
      return;
    }

    final rawItems = restored['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];

    if (items.isEmpty) {
      AppSnackBar.show(
        context,
        message: 'Held cart could not be restored because its saved items are invalid.',
        backgroundColor: const Color(0xFFFF6B7A),
      );
      return;
    }

    cart.loadHeldCart(
      items: items,
      isRefundMode: (restored['is_refund_mode'] ?? false) == true,
      discountType: (restored['discount_type'] ?? 'none').toString(),
      discountValue: ((restored['discount_value'] as num?) ?? 0).toDouble(),
      selectedPriceType: (restored['selected_price_type'] ?? 'selling').toString(),
    );

    await _goHome();

    AppSnackBar.show(
      context,
      message: 'Held cart resumed.',
      backgroundColor: const Color(0xFF1FCF9A),
    );
  }

  ThemeData _buildBaseTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    const brand = Color(0xFF2AAA8A);

    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    ).copyWith(
      primary: brand,
      secondary: const Color(0xFF4B8DFF),
      error: const Color(0xFFFF6B7A),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF0F1C31) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: brand, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppThemeProvider>();

    return MaterialApp(
      title: 'Food City POS',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppSnackBar.navigatorKey,
      navigatorObservers: [_routeObserver],
      builder: (context, child) {
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.home): () {
              final navigator = AppSnackBar.navigatorKey.currentState;
              if (navigator == null || !navigator.canPop()) return;
              _runGlobalShortcutFromIntent(_goHome);
            },
            const SingleActivator(LogicalKeyboardKey.f8): () {
              _runGlobalShortcutFromIntent(_openTransactionHistory);
            },
            const SingleActivator(LogicalKeyboardKey.f9): () {
              _runGlobalShortcutFromIntent(_openInventory);
            },
            const SingleActivator(LogicalKeyboardKey.f11): () {
              _runGlobalShortcutFromIntent(_openSupplierManagement);
            },
            const SingleActivator(LogicalKeyboardKey.f12): () {
              _runGlobalShortcutFromIntent(_openSalesReport);
            },
            const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
              _runGlobalShortcutFromIntent(_openInventory);
            },
            const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
              _runGlobalShortcutFromIntent(_openHeldCarts);
            },
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
              _runGlobalShortcutFromIntent(_openSalesReport);
            },
            const SingleActivator(LogicalKeyboardKey.keyU, control: true): () {
              _runGlobalShortcutFromIntent(_openUserManagement);
            },
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
              _runGlobalShortcutFromIntent(_openCashierSummary);
            },
            const SingleActivator(
              LogicalKeyboardKey.keyH,
              control: true,
              shift: true,
            ): () {
              _runGlobalShortcutFromIntent(_openHardwareSetup);
            },
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: _buildBaseTheme(Brightness.light),
      darkTheme: _buildBaseTheme(Brightness.dark),
      themeMode: appTheme.themeMode,
      home: const LoginScreen(),
    );
  }
}
