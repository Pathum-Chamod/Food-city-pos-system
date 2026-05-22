import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/backup_restore_service.dart';
import 'services/database_helper.dart';
import 'services/permission_service.dart';
import 'services/sync_service.dart';
import 'providers/cart_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/app_theme_provider.dart';
import 'navigation/pos_route_names.dart';
import 'navigation/route_search_focus_registry.dart';
import 'screens/cashier_summary_screen.dart';
import 'screens/customer_management_screen.dart';
import 'screens/expiry_alerts_screen.dart';
import 'screens/held_carts_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/login_screen.dart';
import 'screens/presentation_transaction_history_screen.dart';
import 'screens/presentation_settings_screen.dart';
import 'screens/presentation_cashier_summary_screen.dart';
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

  unawaited(
    BackupRestoreService.instance.runAutoBackupIfDue(createdBy: 'POS Startup'),
  );

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
  bool _isShortcutLegendOpen = false;
  bool _isShortcutLegendClosing = false;
  bool _isLogoutConfirmOpen = false;
  BuildContext? _shortcutLegendDialogContext;

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
    if (_isLogoutConfirmOpen) return false;

    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    if (_isShortcutLegendOpen) {
      if (key == LogicalKeyboardKey.escape) {
        _closeShortcutLegend();
      }
      return true;
    }

    if (_isHandlingGlobalShortcut) return false;

    final navigatorContext = AppSnackBar.navigatorKey.currentContext;
    if (navigatorContext == null) return false;

    final auth = navigatorContext.read<AuthProvider>();
    if (!auth.isLoggedIn) return false;

    final keyboard = HardwareKeyboard.instance;
    final hasControl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final hasShift = keyboard.isShiftPressed;
    final hasAlt = keyboard.isAltPressed;

    if (hasShift &&
        !hasControl &&
        !hasAlt &&
        key == LogicalKeyboardKey.escape) {
      _runGlobalShortcut(_showLogoutConfirmation);
      return true;
    }

    if (hasControl && !hasAlt && key == LogicalKeyboardKey.slash) {
      _runGlobalShortcut(_showShortcutLegend);
      return true;
    }

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
      if (!hasShift && key == LogicalKeyboardKey.keyE) {
        _runGlobalShortcut(_openExpiryAlerts);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyU) {
        _runGlobalShortcut(_openUserManagement);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyB) {
        _runGlobalShortcut(_openCustomerManagement);
        return true;
      }
      if (hasShift && key == LogicalKeyboardKey.keyP) {
        _runGlobalShortcut(_openPresentationSettings);
        return true;
      }
      if (!hasShift && key == LogicalKeyboardKey.keyS) {
        _runGlobalShortcut(_openCashierSummary);
        return true;
      }
    }

    return false;
  }

  Future<void> _showLogoutConfirmation() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    final navigator = AppSnackBar.navigatorKey.currentState;
    if (context == null || navigator == null || _isLogoutConfirmOpen) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;

    _isLogoutConfirmOpen = true;
    try {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final bg = isDark ? const Color(0xFF0F1C31) : Colors.white;
      final surface = isDark
          ? const Color(0xFF14243C)
          : const Color(0xFFF8FAFD);
      final border = isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
      final textPrimary = isDark ? Colors.white : const Color(0xFF14263B);
      final textSecondary = isDark
          ? const Color(0xFF9DB0C8)
          : const Color(0xFF667A92);
      const danger = Color(0xFFFF6B7A);
      final userName = auth.currentUser?.name ?? 'current user';

      final confirmed = await showGeneralDialog<bool>(
        context: context,
        barrierLabel: 'Logout confirmation',
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(isDark ? 0.34 : 0.24),
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          var isClosing = false;
          var isWaitingForEscapeRelease = HardwareKeyboard.instance
              .isLogicalKeyPressed(LogicalKeyboardKey.escape);

          void close(bool value) {
            if (isClosing) return;
            isClosing = true;
            Navigator.of(dialogContext).pop(value);
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (event is KeyUpEvent) {
                  isWaitingForEscapeRelease = false;
                  return KeyEventResult.handled;
                }

                if (event is KeyDownEvent) {
                  if (isWaitingForEscapeRelease) {
                    return KeyEventResult.handled;
                  }
                  close(false);
                  return KeyEventResult.handled;
                }
              }

              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final isEnterKey =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;

              if (isEnterKey) {
                close(true);
                return KeyEventResult.handled;
              }

              return KeyEventResult.ignored;
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.34 : 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: danger.withOpacity(isDark ? 0.18 : 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: danger.withOpacity(0.24),
                              ),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: danger,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Logout?',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          'End the current session for $userName and return to login?',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => close(false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => close(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: danger,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                              ),
                              child: const Text('Logout'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      if (confirmed == true) {
        await _performLogout();
      }
    } finally {
      _isLogoutConfirmOpen = false;
    }
  }

  Future<void> _performLogout() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    final navigator = AppSnackBar.navigatorKey.currentState;
    if (context == null || navigator == null) return;

    await context.read<AuthProvider>().logout();
    context.read<CartProvider>().clearCart();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: PosRouteNames.login),
        builder: (context) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  void _closeShortcutLegend() {
    if (_isShortcutLegendClosing) return;

    final dialogContext = _shortcutLegendDialogContext;
    if (dialogContext == null || !dialogContext.mounted) return;

    final route = ModalRoute.of(dialogContext);
    if (route == null || !route.isCurrent) return;

    _isShortcutLegendClosing = true;
    Navigator.of(dialogContext, rootNavigator: true).pop();
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
    if (_isHandlingGlobalShortcut || _isShortcutLegendOpen) return;
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
    if (navigator == null) return;
    if (_currentRouteName == routeName) {
      RouteSearchFocusRegistry.focus(routeName);
      return;
    }

    var foundRoute = false;
    navigator.popUntil((route) {
      if (route.settings.name == routeName) {
        foundRoute = true;
        return true;
      }

      return route.settings.name == PosRouteNames.pos || route.isFirst;
    });

    if (foundRoute) {
      RouteSearchFocusRegistry.focus(routeName);
      return;
    }

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
    Future<void> Function() action, {
    String permission = PosPermission.settingsManage,
    String title = 'Manager Approval Required',
    String message = 'Enter a manager PIN to continue.',
  }) async {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return;

    final auth = context.read<AuthProvider>();
    if (auth.isPresentationLogin) {
      AppSnackBar.show(
        context,
        message: 'This module is not available in Presentation Login.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    if (auth.can(permission)) {
      await action();
      return;
    }

    if (!PermissionService.requiresManagerApproval(
      auth.currentUser,
      permission,
    )) {
      AppSnackBar.show(
        context,
        message: 'You do not have permission to open this module.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    await AdminDialogs.showPinDialog(
      context,
      action,
      title: title,
      message: message,
      requesterUserId: auth.currentUser?.id,
      requesterUserName: auth.currentUser?.name,
      approvalDescription: title,
    );
  }

  Future<void> _openInventory() {
    return _runProtectedManagerAction(
      () {
        return _pushOrRevealRoute(
          routeName: PosRouteNames.inventory,
          builder: (context) => const InventoryScreen(),
        );
      },
      permission: PosPermission.inventoryAdjust,
      title: 'Open Inventory',
    );
  }

  Future<void> _openTransactionHistory() {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context != null && context.read<AuthProvider>().isPresentationLogin) {
      return _pushOrRevealRoute(
        routeName: PosRouteNames.transactionHistory,
        builder: (context) => const PresentationTransactionHistoryScreen(),
      );
    }

    return _pushOrRevealRoute(
      routeName: PosRouteNames.transactionHistory,
      builder: (context) => const TransactionHistoryScreen(),
    );
  }

  Future<void> _openCashierSummary() {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return Future<void>.value();

    if (context.read<AuthProvider>().isPresentationLogin) {
      return _pushOrRevealRoute(
        routeName: PosRouteNames.cashierSummary,
        builder: (context) => const PresentationCashierSummaryScreen(),
      );
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
    return _pushOrRevealRoute(
      routeName: PosRouteNames.cashierSummary,
      builder: (context) => CashierSummaryScreen(cashierName: cashierName),
    );
  }

  Future<void> _openSalesReport() {
    return _runProtectedManagerAction(
      () {
        return _pushOrRevealRoute(
          routeName: PosRouteNames.salesReport,
          builder: (context) => const SalesReportScreen(),
        );
      },
      permission: PosPermission.reportsView,
      title: 'Open Sales Report',
    );
  }

  Future<void> _openExpiryAlerts() {
    return _runProtectedManagerAction(
      () {
        return _pushOrRevealRoute(
          routeName: PosRouteNames.expiryAlerts,
          builder: (context) => const ExpiryAlertsScreen(),
        );
      },
      permission: PosPermission.inventoryAdjust,
      title: 'Open Expiry Alerts',
    );
  }

  Future<void> _openUserManagement() {
    return _runProtectedManagerAction(
      () async {
        final context = AppSnackBar.navigatorKey.currentContext;
        await _pushOrRevealRoute(
          routeName: PosRouteNames.userManagement,
          builder: (context) => const UserManagementScreen(),
        );

        if (context == null) return;
        await context.read<AuthProvider>().refreshCurrentUser();
      },
      permission: PosPermission.usersManage,
      title: 'Open User Management',
    );
  }

  Future<void> _openPresentationSettings() {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return Future<void>.value();

    final auth = context.read<AuthProvider>();
    if (!auth.hasFullAccess && !auth.hasManagementAccess) {
      AppSnackBar.show(
        context,
        message: 'Only owner/full-access login can open Presentation Settings.',
        backgroundColor: Colors.orange,
      );
      return Future<void>.value();
    }

    return _pushOrRevealRoute(
      routeName: PosRouteNames.presentationSettings,
      builder: (context) => const PresentationSettingsScreen(),
    );
  }

  Future<void> _openSupplierManagement() {
    return _runProtectedManagerAction(
      () {
        final context = AppSnackBar.navigatorKey.currentContext;
        if (context == null) return Future<void>.value();

        final cashierName =
            context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
        return _pushOrRevealRoute(
          routeName: PosRouteNames.supplierManagement,
          builder: (context) =>
              SupplierManagementScreen(cashierName: cashierName),
        );
      },
      permission: PosPermission.inventoryAdjust,
      title: 'Open Supplier Operations',
    );
  }

  Future<void> _openHardwareSetup() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null) return;

    await showHardwareSetupDialog(context);
  }

  Future<void> _openCustomerManagement() {
    return _runProtectedManagerAction(
      () {
        return _pushOrRevealRoute(
          routeName: PosRouteNames.customerManagement,
          builder: (context) => const CustomerManagementScreen(),
        );
      },
      permission: PosPermission.customersView,
      title: 'Open Customer Management',
    );
  }

  Future<void> _showShortcutLegend() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    if (context == null || _isShortcutLegendOpen) return;

    _isShortcutLegendOpen = true;
    _isShortcutLegendClosing = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          _shortcutLegendDialogContext = dialogContext;
          final theme = Theme.of(dialogContext);
          final isDark = theme.brightness == Brightness.dark;
          const brand = Color(0xFF2AAA8A);
          final bg = isDark ? const Color(0xFF081221) : Colors.white;
          final surface = isDark
              ? const Color(0xFF0F1B2D)
              : const Color(0xFFF6F9FC);
          final surfaceAlt = isDark
              ? const Color(0xFF14233A)
              : const Color(0xFFEFF4FB);
          final border = isDark
              ? const Color(0xFF23344E)
              : const Color(0xFFD9E3F0);
          final textPrimary = isDark ? Colors.white : const Color(0xFF122033);
          final textSecondary = isDark
              ? const Color(0xFFAAB8CB)
              : const Color(0xFF607089);
          final screenSize = MediaQuery.of(dialogContext).size;
          final dialogWidth = screenSize.width >= 1240
              ? 1180.0
              : screenSize.width - 48;

          Widget keyChip(String label) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            );
          }

          Widget shortcutRow(String keys, String action) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: keys.split(' + ').map(keyChip).toList(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      action,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          Widget section(String title, List<Widget> rows) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: brand,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...rows,
                ],
              ),
            );
          }

          final posFlowSection = section('POS Flow', [
            shortcutRow('Barcode + Enter', 'Add item to cart'),
            shortcutRow(
              'Enter',
              'Checkout when input is empty and cart has items',
            ),
            shortcutRow('Esc', 'Return to barcode/search flow'),
            shortcutRow('Home', 'Return to POS screen/barcode flow'),
          ]);
          final priceModesSection = section('Price Modes', [
            shortcutRow('F1', 'Selling price mode'),
            shortcutRow('F2', 'Wholesale price mode'),
            shortcutRow('F3', 'Sale price mode'),
            shortcutRow(
              'Double F1/F2/F3',
              'Switch whole cart to that price mode',
            ),
          ]);
          final cartActionsSection = section('Cart Actions', [
            shortcutRow('Up / Down', 'Select cart item'),
            shortcutRow('Page Up', 'Select top cart item'),
            shortcutRow('Page Down', 'Select bottom cart item'),
            shortcutRow('+ / -', 'Increase or decrease selected item quantity'),
            shortcutRow('Delete', 'Remove selected item'),
            shortcutRow('Q', 'Edit selected item quantity'),
            shortcutRow('D', 'Apply discount to selected item'),
            shortcutRow('Ctrl + D', 'Clear selected item discount'),
            shortcutRow('Ctrl + L', 'Clear whole cart'),
          ]);
          final posActionsSection = section('POS Actions', [
            shortcutRow('F4', 'Hold current cart'),
            shortcutRow('F5', 'Open held carts'),
            shortcutRow('F6', 'Apply cart discount'),
            shortcutRow('F7', 'Focus product search'),
            shortcutRow('Shift + Esc', 'Open logout confirmation'),
          ]);
          final heldBillsSection = section('Held Bills', [
            shortcutRow('1 - 9', 'Select visible held bill'),
            shortcutRow('Double 1 - 9', 'Resume selected held bill to cart'),
            shortcutRow('Up / Down', 'Move held bill selection'),
            shortcutRow('Page Up', 'Select top held bill'),
            shortcutRow('Page Down', 'Select bottom held bill'),
            shortcutRow('Enter', 'Resume selected held bill'),
            shortcutRow('Delete', 'Delete selected held bill'),
          ]);
          final modulesSection = section('Modules', [
            shortcutRow('F8', 'Transaction history'),
            shortcutRow('F9', 'Inventory'),
            shortcutRow('F11', 'Supplier operations'),
            shortcutRow('F12', 'Store sales report'),
            shortcutRow('Ctrl + I', 'Inventory'),
            shortcutRow('Ctrl + E', 'Expiry alerts'),
            shortcutRow('Ctrl + H', 'Held carts'),
            shortcutRow('Ctrl + R', 'Sales report'),
            shortcutRow('Ctrl + U', 'User management'),
            shortcutRow('Ctrl + B', 'Customer management'),
            shortcutRow('Ctrl + S', 'Cashier summary'),
            shortcutRow('Ctrl + Shift + P', 'Presentation settings'),
            shortcutRow('Ctrl + Shift + H', 'Hardware setup'),
            shortcutRow('Ctrl + ?', 'Open this shortcut legend'),
          ]);
          final popupRulesSection = section('Popup Rules', [
            shortcutRow('Tab', 'Move to next field'),
            shortcutRow('Shift + Tab', 'Move to previous field'),
            shortcutRow('Enter', 'Submit the current step'),
            shortcutRow('Esc', 'Close or cancel the current popup'),
          ]);

          final landscapeColumns = <List<Widget>>[
            [posFlowSection, posActionsSection, heldBillsSection],
            [priceModesSection, modulesSection],
            [cartActionsSection, popupRulesSection],
          ];
          final mediumColumns = <List<Widget>>[
            [
              posFlowSection,
              posActionsSection,
              heldBillsSection,
              popupRulesSection,
            ],
            [priceModesSection, cartActionsSection, modulesSection],
          ];
          final allSections = <Widget>[
            posFlowSection,
            priceModesSection,
            cartActionsSection,
            posActionsSection,
            heldBillsSection,
            modulesSection,
            popupRulesSection,
          ];

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                _closeShortcutLegend();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: const SizedBox.expand(),
                  ),
                ),
                Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Container(
                    width: dialogWidth,
                    constraints: BoxConstraints(
                      maxWidth: 1180,
                      maxHeight: screenSize.height - 64,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.34 : 0.12),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: brand.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.keyboard_rounded,
                                  color: brand,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Keyboard Shortcuts',
                                      style: TextStyle(
                                        color: textPrimary,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Fast POS actions grouped by workflow.',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: _closeShortcutLegend,
                                style: IconButton.styleFrom(
                                  backgroundColor: surfaceAlt,
                                  foregroundColor: textSecondary,
                                ),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Flexible(
                            child: SingleChildScrollView(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  Widget sectionColumn(List<Widget> column) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (
                                          var i = 0;
                                          i < column.length;
                                          i++
                                        ) ...[
                                          if (i > 0) const SizedBox(height: 12),
                                          column[i],
                                        ],
                                      ],
                                    );
                                  }

                                  final columns = constraints.maxWidth >= 1040
                                      ? landscapeColumns
                                      : constraints.maxWidth >= 720
                                      ? mediumColumns
                                      : <List<Widget>>[allSections];

                                  if (columns.length == 1) {
                                    return sectionColumn(columns.first);
                                  }

                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (
                                        var i = 0;
                                        i < columns.length;
                                        i++
                                      ) ...[
                                        if (i > 0) const SizedBox(width: 12),
                                        Expanded(
                                          child: sectionColumn(columns[i]),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _isShortcutLegendOpen = false;
      _isShortcutLegendClosing = false;
      _shortcutLegendDialogContext = null;
    }
  }

  Future<void> _openHeldCarts() async {
    final context = AppSnackBar.navigatorKey.currentContext;
    final navigator = AppSnackBar.navigatorKey.currentState;
    if (context == null || navigator == null) return;
    if (_currentRouteName == PosRouteNames.heldCarts) return;

    final cart = context.read<CartProvider>();
    final canReplaceCart = await _confirmReplaceCurrentCartIfNeeded(cart);
    if (!canReplaceCart) return;

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

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
        message:
            'Held cart could not be restored because its saved items are invalid.',
        backgroundColor: const Color(0xFFFF6B7A),
      );
      return;
    }

    cart.loadHeldCart(
      items: items,
      isRefundMode: (restored['is_refund_mode'] ?? false) == true,
      discountType: (restored['discount_type'] ?? 'none').toString(),
      discountValue: ((restored['discount_value'] as num?) ?? 0).toDouble(),
      selectedPriceType: (restored['selected_price_type'] ?? 'selling')
          .toString(),
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

    final scheme =
        ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
          primary: brand,
          secondary: const Color(0xFF4B8DFF),
          error: const Color(0xFFFF6B7A),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF07111F)
          : const Color(0xFFF4F7FB),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF0F1C31) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
            const SingleActivator(LogicalKeyboardKey.keyE, control: true): () {
              _runGlobalShortcutFromIntent(_openExpiryAlerts);
            },
            const SingleActivator(LogicalKeyboardKey.keyU, control: true): () {
              _runGlobalShortcutFromIntent(_openUserManagement);
            },
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
              _runGlobalShortcutFromIntent(_openCustomerManagement);
            },
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
              _runGlobalShortcutFromIntent(_openCashierSummary);
            },
            const SingleActivator(
              LogicalKeyboardKey.keyP,
              control: true,
              shift: true,
            ): () {
              _runGlobalShortcutFromIntent(_openPresentationSettings);
            },
            const SingleActivator(
              LogicalKeyboardKey.keyH,
              control: true,
              shift: true,
            ): () {
              _runGlobalShortcutFromIntent(_openHardwareSetup);
            },
            const SingleActivator(LogicalKeyboardKey.slash, control: true): () {
              _runGlobalShortcutFromIntent(_showShortcutLegend);
            },
            const SingleActivator(
              LogicalKeyboardKey.slash,
              control: true,
              shift: true,
            ): () {
              _runGlobalShortcutFromIntent(_showShortcutLegend);
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
