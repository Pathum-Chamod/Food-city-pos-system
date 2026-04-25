import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../config/pos_feature_flags.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/app_theme_provider.dart';
import '../services/card_terminal_service.dart';
import '../services/database_helper.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../services/sync_service.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/premium_dialog.dart';
import '../widgets/app_snackbar.dart';
import 'cart_discount_dialog.dart';
import 'cashier_summary_screen.dart';
import 'checkout_payment_dialog.dart';
import 'held_carts_screen.dart';
import 'inventory_screen.dart';
import 'login_screen.dart';
import 'sales_report_screen.dart';
import 'supplier_management_screen.dart';
import 'shift_management_screen.dart';
import 'transaction_history_screen.dart';
import 'user_management_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    this.showWelcomeAnimation = false,
    this.welcomeUserName,
  });

  final bool showWelcomeAnimation;
  final String? welcomeUserName;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _DecimalQuantityInputFormatter extends TextInputFormatter {
  _DecimalQuantityInputFormatter({this.maxDecimals = 3});

  final int maxDecimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    final decimalPattern = RegExp('^\\d*(?:\\.\\d{0,$maxDecimals})?\$');
    if (!decimalPattern.hasMatch(text)) {
      return oldValue;
    }

    return newValue;
  }
}

class _PosScreenState extends State<PosScreen> {
  static const double _quantityEpsilon = 0.000001;
  static const double _minSupportedWidth = 1180;
  static const double _minSupportedHeight = 680;
  static const double _cartPanelWidth = 430;
  static const double _productTileExtent = 218;
  List<Product> _products = [];
  bool _isLoadingProducts = true;
  bool _isProcessingCheckout = false;
  bool _isRefreshingProducts = false;
  int _activeModalCount = 0;
  bool _showWelcomeOverlay = false;
  bool _renderWelcomeOverlay = false;
  Timer? _productRefreshTimer;
  Timer? _barcodeInputTimer;
  Timer? _welcomeOverlayTimer;
  Timer? _welcomeOverlayCleanupTimer;

  final ScrollController _cartScrollController = ScrollController();
  int _lastCartItemCount = 0;

  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardListenerFocusNode = FocusNode();

  String _searchQuery = '';
  Map<String, dynamic>? _currentShiftSummary;

  bool get _isDark => context.read<AppThemeProvider>().isDarkMode;
  Color get _screenBackground =>
      _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _screenBackgroundAlt =>
      _isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get _panelColor =>
      _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get _panelSoft =>
      _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _panelAlt =>
      _isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get _borderColor =>
      _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary =>
      _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _mutedIcon =>
      _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _brandColor => const Color(0xFF2AAA8A);
  Color get _brandSoft => _brandColor.withOpacity(_isDark ? 0.16 : 0.10);
  Color get _accentBlue => const Color(0xFF4B8DFF);
  Color get _accentBlueSoft => _accentBlue.withOpacity(_isDark ? 0.18 : 0.10);
  Color get _successColor => const Color(0xFF1FCF9A);
  Color get _successSoft => _successColor.withOpacity(_isDark ? 0.18 : 0.12);
  Color get _warningColor => const Color(0xFFFFB65C);
  Color get _warningSoft => _warningColor.withOpacity(_isDark ? 0.20 : 0.14);
  Color get _dangerColor => const Color(0xFFFF6B7A);
  Color get _dangerSoft => _dangerColor.withOpacity(_isDark ? 0.20 : 0.12);
  Color get _inputFill =>
      _isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC);
  Color get _shadowColor => Colors.black.withOpacity(_isDark ? 0.26 : 0.0);

  @override
  void initState() {
    super.initState();
    _loadProducts(showLoader: true);
    _refreshProductsFromBackendAndReload(silentOnFailure: true);
    _startAutoRefresh();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreHardwareConnections();
      _focusBarcodeField();
      if (PosFeatureFlags.enableShiftManagement) {
        _loadShiftSummary();
      }
    });

    _scheduleWelcomeOverlay();
  }

  @override
  void dispose() {
    _productRefreshTimer?.cancel();
    _barcodeInputTimer?.cancel();
    _welcomeOverlayTimer?.cancel();
    _welcomeOverlayCleanupTimer?.cancel();
    _barcodeController.dispose();
    _searchController.dispose();
    _cartScrollController.dispose();
    _barcodeFocusNode.dispose();
    _searchFocusNode.dispose();
    _keyboardListenerFocusNode.dispose();
    super.dispose();
  }

  void _scheduleWelcomeOverlay() {
    final name = widget.welcomeUserName?.trim();
    if (!widget.showWelcomeAnimation && (name == null || name.isEmpty)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _renderWelcomeOverlay = true;
      });

      Future<void>.delayed(const Duration(milliseconds: 30), () {
        if (!mounted) return;
        setState(() {
          _showWelcomeOverlay = true;
        });
      });

      _welcomeOverlayTimer = Timer(const Duration(milliseconds: 2300), () {
        if (!mounted) return;
        setState(() {
          _showWelcomeOverlay = false;
        });

        _welcomeOverlayCleanupTimer = Timer(
          const Duration(milliseconds: 420),
          () {
            if (!mounted) return;
            setState(() {
              _renderWelcomeOverlay = false;
            });
          },
        );
      });
    });
  }

  String _resolveWelcomeName(AuthProvider auth) {
    final explicit = widget.welcomeUserName?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    final authName = auth.currentUser?.name.trim();
    if (authName != null && authName.isNotEmpty) {
      return authName;
    }

    return 'Cashier';
  }

  Widget _buildWelcomeOverlay(AuthProvider auth) {
    final userName = _resolveWelcomeName(auth);

    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              offset: _showWelcomeOverlay
                  ? Offset.zero
                  : const Offset(0, -0.18),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 480),
                curve: Curves.easeOutBack,
                scale: _showWelcomeOverlay ? 1 : 0.94,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOut,
                  opacity: _showWelcomeOverlay ? 1 : 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _brandColor.withOpacity(_isDark ? 0.18 : 0.14),
                              _accentBlue.withOpacity(_isDark ? 0.14 : 0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(
                              _isDark ? 0.14 : 0.52,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                _isDark ? 0.26 : 0.08,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(
                                  _isDark ? 0.10 : 0.72,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                Icons.waving_hand_rounded,
                                color: _brandColor,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome, $userName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Your register is ready for this shift.',
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scrollCartToLatest({bool animated = true}) {
    if (!_cartScrollController.hasClients) return;

    final target = _cartScrollController.position.maxScrollExtent;

    if (animated) {
      _cartScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _cartScrollController.jumpTo(target);
    }
  }

  void _syncCartAutoScroll(CartProvider cart) {
    final currentCount = cart.items.length;

    if (currentCount == 0) {
      _lastCartItemCount = 0;
      return;
    }

    if (currentCount > _lastCartItemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollCartToLatest();
      });
    }

    _lastCartItemCount = currentCount;
  }

  ThemeData _buildPosTheme() {
    final brightness = _isDark ? Brightness.dark : Brightness.light;
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: _brandColor,
          brightness: brightness,
        ).copyWith(
          primary: _brandColor,
          secondary: _accentBlue,
          surface: _panelColor,
          onSurface: _textPrimary,
          outline: _borderColor,
          error: _dangerColor,
        );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: _screenBackground,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        bodyColor: _textPrimary,
        displayColor: _textPrimary,
      ),
      cardColor: _panelColor,
      dividerColor: _borderColor,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _panelSoft,
        contentTextStyle: TextStyle(
          color: _textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _borderColor),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _panelColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: _borderColor),
        ),
        titleTextStyle: TextStyle(
          color: _textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: _textSecondary,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: _panelColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _borderColor),
        ),
        textStyle: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _inputFill,
        hintStyle: TextStyle(
          color: _textSecondary.withOpacity(0.82),
          fontWeight: FontWeight.w500,
        ),
        labelStyle: TextStyle(
          color: _textSecondary,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: _mutedIcon,
        suffixIconColor: _mutedIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _brandColor, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: _brandColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _textPrimary,
          side: BorderSide(color: _borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _textPrimary,
          backgroundColor: _panelSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return _textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _dangerColor;
          }
          return _borderColor;
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(_borderColor),
        radius: const Radius.circular(999),
      ),
    );
  }

  BoxDecoration _panelDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? _panelColor,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: _borderColor),
      boxShadow: [
        BoxShadow(
          color: _shadowColor,
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  BoxDecoration _softDecoration({Color? color, BorderRadius? radius}) {
    return BoxDecoration(
      color: color ?? _panelSoft,
      borderRadius: radius ?? BorderRadius.circular(20),
      border: Border.all(color: _borderColor),
    );
  }

  Future<void> _loadShiftSummary() async {
    if (!PosFeatureFlags.enableShiftManagement) {
      if (!mounted) return;
      setState(() {
        _currentShiftSummary = null;
      });
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
    final summary = await DatabaseHelper.instance.getOpenShiftSummaryForCashier(
      cashierName,
    );

    if (!mounted) return;

    setState(() {
      _currentShiftSummary = summary;
    });
  }

  void _focusBarcodeField() {
    if (!mounted || _activeModalCount > 0) return;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted || _activeModalCount > 0) return;
      _barcodeFocusNode.requestFocus();
    });
  }

  Future<void> _restoreHardwareConnections() async {
    final cardTerminal = CardTerminalService.instance;
    final printer = ReceiptPrinterService.instance;

    final cardConnected = await cardTerminal.restoreSavedConnection();
    final printerConnected = await printer.restoreSavedPrinter();

    if (!mounted) return;

    if (cardConnected || printerConnected) {
      final parts = <String>[];
      if (cardConnected && cardTerminal.connectedPortName != null) {
        parts.add('Card terminal: ${cardTerminal.connectedPortName}');
      }
      if (printerConnected && printer.connectedPrinterName != null) {
        parts.add('Printer: ${printer.connectedPrinterName}');
      }

      if (parts.isNotEmpty) {
        _showInfoMessage(parts.join(' • '), backgroundColor: _successColor);
      }
    }
  }

  void _handleGlobalKeyboardEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    final isModifierOnly =
        event.isAltPressed || event.isControlPressed || event.isMetaPressed;
    if (isModifierOnly) return;

    if (!_barcodeFocusNode.hasFocus && !_searchFocusNode.hasFocus) {
      _barcodeFocusNode.requestFocus();
    }
  }

  void _handleBarcodeChanged(CartProvider cart, String value) {
    setState(() {});
    _barcodeInputTimer?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 6) {
      return;
    }

    _barcodeInputTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (_barcodeController.text.trim() != trimmed) return;
      if (_searchFocusNode.hasFocus) return;
      _handleBarcodeSubmit(cart);
    });
  }

  Future<void> _showHardwareSetupDialog() async {
    final cardTerminal = CardTerminalService.instance;
    final printer = ReceiptPrinterService.instance;

    final initialPorts = cardTerminal.getAvailablePorts();
    final initialPrinters = await printer.getInstalledPrinters();

    if (!mounted) return;

    await showPremiumDialog<void>(
      context: context,
      builder: (context) {
        var ports = List<String>.from(initialPorts);
        var printers = List<String>.from(initialPrinters);
        var selectedBaudRate = cardTerminal.baudRate;
        var isBusy = false;

        Future<void> refreshLists(StateSetter setState) async {
          setState(() {
            isBusy = true;
          });

          final nextPrinters = await printer.getInstalledPrinters();

          if (!context.mounted) return;

          setState(() {
            ports = cardTerminal.getAvailablePorts();
            printers = nextPrinters;
            isBusy = false;
          });
        }

        Future<void> connectCardPort(String port, StateSetter setState) async {
          setState(() {
            isBusy = true;
          });

          final ok = await cardTerminal.connect(
            port,
            baudRate: selectedBaudRate,
          );

          if (!context.mounted) return;

          setState(() {
            isBusy = false;
          });

          _showInfoMessage(
            ok
                ? 'Connected card terminal on $port'
                : 'Failed to connect card terminal on $port',
            backgroundColor: ok ? _successColor : _dangerColor,
          );
        }

        Future<void> selectPrinter(
          String printerName,
          StateSetter setState,
        ) async {
          setState(() {
            isBusy = true;
          });

          final ok = await printer.selectPrinter(printerName);

          if (!context.mounted) return;

          setState(() {
            isBusy = false;
          });

          _showInfoMessage(
            ok
                ? 'Receipt printer set to $printerName'
                : 'Could not set printer $printerName',
            backgroundColor: ok ? _successColor : _dangerColor,
          );
        }

        Future<void> runTestPrint(StateSetter setState) async {
          setState(() {
            isBusy = true;
          });

          final response = await printer.printTestSlip();

          if (!context.mounted) return;

          setState(() {
            isBusy = false;
          });

          _showInfoMessage(
            response.message,
            backgroundColor: response.isSuccess ? _successColor : _dangerColor,
          );
        }

        Future<void> saveTestPdf(StateSetter setState) async {
          setState(() {
            isBusy = true;
          });

          final response = await ReceiptPdfService.instance.saveReceiptPdf(
            transactionId: 0,
            cashierName: 'Hardware Test',
            paymentMethod: 'cash',
            items: const [
              {
                'name': 'Printer Test Item',
                'qty': 1,
                'unitPrice': 0.0,
                'lineTotal': 0.0,
              },
            ],
            subtotal: 0.0,
            discountAmount: 0.0,
            total: 0.0,
            storeName: 'FOOD CITY',
            storeAddress: 'Windows PDF Test',
            storePhone: '',
            footerNote: 'If you can read this, PDF receipt export works.',
          );

          if (!context.mounted) return;

          setState(() {
            isBusy = false;
          });

          _showInfoMessage(
            response.message,
            backgroundColor: response.isSuccess ? _successColor : _dangerColor,
          );
        }

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Hardware Setup'),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Card Terminal',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (cardTerminal.isConnected)
                            Chip(
                              label: Text(
                                cardTerminal.connectedPortName ?? 'Connected',
                              ),
                              backgroundColor: _successSoft,
                              side: BorderSide(color: _successColor),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'Baud rate:',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<int>(
                            value: selectedBaudRate,
                            items: const [9600, 19200, 38400, 57600, 115200]
                                .map(
                                  (value) => DropdownMenuItem<int>(
                                    value: value,
                                    child: Text('$value'),
                                  ),
                                )
                                .toList(),
                            onChanged: isBusy
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      selectedBaudRate = value;
                                    });
                                  },
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: isBusy
                                ? null
                                : () => refreshLists(setState),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (ports.isEmpty)
                        Text(
                          'No COM ports found. Connect the terminal, then refresh.',
                          style: TextStyle(color: _dangerColor),
                        )
                      else
                        ...ports.map(
                          (port) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(port),
                            subtitle: Text(
                              port == cardTerminal.connectedPortName
                                  ? 'Currently connected'
                                  : 'Available serial port',
                            ),
                            trailing: port == cardTerminal.connectedPortName
                                ? OutlinedButton(
                                    onPressed: isBusy
                                        ? null
                                        : () async {
                                            setState(() {
                                              isBusy = true;
                                            });
                                            await cardTerminal.disconnect(
                                              clearSaved: true,
                                            );
                                            if (!context.mounted) return;
                                            setState(() {
                                              isBusy = false;
                                            });
                                            _showInfoMessage(
                                              'Card terminal disconnected.',
                                              backgroundColor: _warningColor,
                                            );
                                          },
                                    child: const Text('Disconnect'),
                                  )
                                : ElevatedButton(
                                    onPressed: isBusy
                                        ? null
                                        : () => connectCardPort(port, setState),
                                    child: const Text('Connect'),
                                  ),
                          ),
                        ),
                      const Divider(height: 28),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Receipt Printer',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (printer.isConnected)
                            Chip(
                              label: Text(
                                printer.connectedPrinterName ?? 'Selected',
                              ),
                              backgroundColor: _successSoft,
                              side: BorderSide(color: _successColor),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (printers.isEmpty)
                        Text(
                          'No Windows printers found. Install or share the receipt printer first.',
                          style: TextStyle(color: _dangerColor),
                        )
                      else
                        ...printers.map(
                          (printerName) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(printerName),
                            subtitle: Text(
                              printerName == printer.connectedPrinterName
                                  ? 'Currently selected printer'
                                  : 'Installed Windows printer',
                            ),
                            trailing:
                                printerName == printer.connectedPrinterName
                                ? OutlinedButton(
                                    onPressed: isBusy
                                        ? null
                                        : () async {
                                            setState(() {
                                              isBusy = true;
                                            });
                                            await printer.disconnect(
                                              clearSaved: true,
                                            );
                                            if (!context.mounted) return;
                                            setState(() {
                                              isBusy = false;
                                            });
                                            _showInfoMessage(
                                              'Receipt printer cleared.',
                                              backgroundColor: _warningColor,
                                            );
                                          },
                                    child: const Text('Clear'),
                                  )
                                : ElevatedButton(
                                    onPressed: isBusy
                                        ? null
                                        : () => selectPrinter(
                                            printerName,
                                            setState,
                                          ),
                                    child: const Text('Use'),
                                  ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (printer.isConnected)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: isBusy
                                    ? null
                                    : () => runTestPrint(setState),
                                icon: const Icon(Icons.print),
                                label: const Text('Print Test Slip'),
                              ),
                              OutlinedButton.icon(
                                onPressed: isBusy
                                    ? null
                                    : () => saveTestPdf(setState),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('Save Test PDF'),
                              ),
                            ],
                          ),
                        ),
                      if (!printer.isConnected)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: isBusy
                                ? null
                                : () => saveTestPdf(setState),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Save Test PDF'),
                          ),
                        ),
                      if (isBusy) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isBusy ? null : () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );

    _focusBarcodeField();
  }

  Future<void> _runProtectedManagerAction(
    Future<void> Function() onApproved,
  ) async {
    final auth = context.read<AuthProvider>();

    if (auth.hasManagementAccess) {
      await onApproved();
      return;
    }

    await AdminDialogs.showPinDialog(context, () async {
      await onApproved();
    });
  }

  void _startAutoRefresh() {
    _productRefreshTimer?.cancel();
    _productRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshProductsFromBackendAndReload(silentOnFailure: true);
      if (PosFeatureFlags.enableShiftManagement) {
        _loadShiftSummary();
      }
    });
  }

  Future<void> _loadProducts({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoadingProducts = true;
      });
    }

    final products = await DatabaseHelper.instance.getProducts();

    if (!mounted) return;

    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
  }

  Future<bool> _refreshProductsFromBackendAndReload({
    bool showSuccessMessage = false,
    bool silentOnFailure = false,
  }) async {
    if (_isRefreshingProducts || _activeModalCount > 0) return false;

    setState(() {
      _isRefreshingProducts = true;
    });

    try {
      final success = await SyncService().refreshProductsFromBackend();

      await _loadProducts(showLoader: false);

      if (!mounted) return success;

      if (success && showSuccessMessage) {
        _showInfoMessage(
          'Products refreshed from backend.',
          backgroundColor: _successColor,
        );
      } else if (!success && !silentOnFailure) {
        _showInfoMessage(
          'Could not refresh products from backend.',
          backgroundColor: _warningColor,
        );
      }

      return success;
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingProducts = false;
        });
      }
    }
  }

  void _showInfoMessage(String message, {Color? backgroundColor}) {
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: backgroundColor ?? _panelSoft,
    );
  }

  Product? _findProductByBarcode(String barcode) {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    try {
      return _products.firstWhere((product) => product.barcode == trimmed);
    } catch (_) {
      return null;
    }
  }

  Product? _getCurrentProduct(String barcode) {
    try {
      return _products.firstWhere((product) => product.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  double _getCurrentStock(String barcode, {double fallback = 0.0}) {
    return _getCurrentProduct(barcode)?.stock ?? fallback;
  }

  double _getQuantityInCart(CartProvider cart, String barcode) {
    return cart.items
        .where((item) => item.product.barcode == barcode)
        .fold<double>(0.0, (sum, item) => sum + item.quantity);
  }

  double _sanitizeQuantity(num value) {
    final quantity = value.toDouble();
    return quantity.abs() < _quantityEpsilon ? 0.0 : quantity;
  }

  bool _quantityExceeds(num requested, num available) {
    return requested.toDouble() - available.toDouble() > _quantityEpsilon;
  }

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final sanitized = _sanitizeQuantity(value);
    return sanitized
        .toStringAsFixed(maxDecimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatQuantityWithUnit(
    num value,
    String unitLabel, {
    int maxDecimals = 3,
  }) {
    return '${_formatQuantity(value, maxDecimals: maxDecimals)} $unitLabel';
  }

  String _formatStockText(Product product, num quantity) {
    if (product.isWeighted) {
      return _formatQuantityWithUnit(quantity, product.unitLabel);
    }
    return _formatQuantity(quantity);
  }

  String _formatCartBadgeText(Product product, num quantity) {
    final label = product.isWeighted
        ? _formatQuantityWithUnit(quantity, product.unitLabel)
        : _formatQuantity(quantity);
    return '$label in cart';
  }

  String _formatStockTextWithCartUnit(Product product, num quantity) {
    if (product.isWeighted) {
      return _formatQuantityWithUnit(quantity, product.unitLabel);
    }
    return '${_formatQuantity(quantity)} pcs';
  }

  String _formatPriceCaption(Product product, double unitPrice) {
    final suffix = product.isWeighted ? 'per ${product.unitLabel}' : 'each';
    return 'Rs. ${unitPrice.toStringAsFixed(2)} $suffix';
  }

  double _getDisplayPrice(Product product, CartProvider cart) {
    if (cart.isRefundMode) {
      return product.sellingPrice;
    }

    return product.resolvePrice(cart.selectedPriceType);
  }

  String _priceTypeTitle(ProductPriceType type) {
    switch (type) {
      case ProductPriceType.selling:
        return 'Selling Price';
      case ProductPriceType.wholesale:
        return 'Wholesale Price';
      case ProductPriceType.sale:
        return 'Sale Price';
    }
  }

  String _priceTypeShortLabel(ProductPriceType type) {
    switch (type) {
      case ProductPriceType.selling:
        return 'SELL';
      case ProductPriceType.wholesale:
        return 'WHSL';
      case ProductPriceType.sale:
        return 'SALE';
    }
  }

  Color _priceTypeColor(ProductPriceType type) {
    switch (type) {
      case ProductPriceType.selling:
        return _accentBlue;
      case ProductPriceType.wholesale:
        return const Color(0xFF8B5CF6);
      case ProductPriceType.sale:
        return _warningColor;
    }
  }

  // ignore: unused_element
  String _priceModeDescription(ProductPriceType type) {
    switch (type) {
      case ProductPriceType.selling:
        return 'Standard retail billing using the product selling price.';
      case ProductPriceType.wholesale:
        return 'Uses wholesale price. If missing, it falls back to selling price.';
      case ProductPriceType.sale:
        return 'Uses sale price only for products with active sale pricing. Others use selling price.';
    }
  }

  Future<void> _handlePriceTypeSelection(
    CartProvider cart,
    ProductPriceType newType,
  ) async {
    if (cart.isRefundMode || cart.selectedPriceType == newType) return;

    if (cart.items.isNotEmpty) {
      final confirmed = await showPremiumDialog<bool>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            decoration: _panelDecoration(color: _panelColor),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _priceTypeColor(
                          newType,
                        ).withOpacity(_isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _priceTypeColor(newType).withOpacity(0.24),
                        ),
                      ),
                      child: Icon(
                        newType == ProductPriceType.wholesale
                            ? Icons.local_offer_outlined
                            : (newType == ProductPriceType.sale
                                  ? Icons.sell_outlined
                                  : Icons.price_change_outlined),
                        color: _priceTypeColor(newType),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Change Billing Price Category?',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Apply ${_priceTypeTitle(newType)} to all items currently in the cart.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(dialogContext, false),
                      child: Ink(
                        width: 42,
                        height: 42,
                        decoration: _softDecoration(color: _panelSoft),
                        child: Icon(
                          Icons.close_rounded,
                          color: _textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _panelSoft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    'This will update the billing price used for every current line in the bill.',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (confirmed != true) {
        _focusBarcodeField();
        return;
      }
    }

    cart.setPriceType(newType, applyToExistingItems: true);

    _showInfoMessage(
      '${_priceTypeTitle(newType)} selected for this bill.',
      backgroundColor: _priceTypeColor(newType),
    );
    _focusBarcodeField();
  }

  // ignore: unused_element
  bool _shouldShowCartPriceTypeBadge(CartItem item) {
    switch (item.priceType) {
      case ProductPriceType.selling:
        return false;
      case ProductPriceType.wholesale:
        return item.product.wholesalePrice > 0 &&
            item.product.wholesalePrice != item.product.sellingPrice;
      case ProductPriceType.sale:
        return item.product.saleEnabled &&
            item.product.salePrice != null &&
            item.product.salePrice! > 0;
    }
  }

  Widget _buildPriceTypeBadge(ProductPriceType type) {
    final color = _priceTypeColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        _priceTypeShortLabel(type),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<Product> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) return _products;

    return _products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
    }).toList();
  }

  // ignore: unused_element
  int get _lowStockCount => _products
      .where((product) => product.stock > 0 && product.isLowStock)
      .length;

  // ignore: unused_element
  int get _outOfStockCount =>
      _products.where((product) => product.stock <= 0).length;

  Future<void> _handleBarcodeSubmit(CartProvider cart) async {
    final barcode = _barcodeController.text.trim();

    if (barcode.isEmpty) {
      _focusBarcodeField();
      return;
    }

    final product = _findProductByBarcode(barcode);

    if (product == null) {
      _barcodeController.clear();
      _showInfoMessage(
        'Product not found for barcode: $barcode',
        backgroundColor: _dangerColor,
      );
      _focusBarcodeField();
      return;
    }

    await _handleProductTap(product, cart);
    _barcodeController.clear();
    _focusBarcodeField();
  }

  Future<double?> _promptWeightedQuantity({
    required Product product,
    required String title,
    required String confirmLabel,
    required double initialQuantity,
    required double unitPrice,
    double? maxQuantity,
  }) async {
    final boundedInitial = maxQuantity != null && maxQuantity > 0
        ? (initialQuantity > maxQuantity ? maxQuantity : initialQuantity)
        : initialQuantity;
    final controller = TextEditingController(
      text: _formatQuantity(
        boundedInitial <= _quantityEpsilon ? 1.0 : boundedInitial,
      ),
    );
    String? quantityError;
    _activeModalCount += 1;

    try {
      final result = await showPremiumDialog<double>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            String? validateQuantity(String raw) {
              final parsed = double.tryParse(raw.trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter a valid quantity.';
              }
              if (maxQuantity != null &&
                  _quantityExceeds(parsed, maxQuantity)) {
                return 'Only ${_formatStockText(product, maxQuantity)} available.';
              }
              return null;
            }

            void submit() {
              final error = validateQuantity(controller.text);
              if (error != null) {
                setLocalState(() {
                  quantityError = error;
                });
                return;
              }

              Navigator.of(
                dialogContext,
              ).pop(_sanitizeQuantity(double.parse(controller.text.trim())));
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  decoration: _panelDecoration(color: _panelColor),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _brandSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.scale_rounded,
                                color: _brandColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.name,
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _panelSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatPriceCaption(product, unitPrice),
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (maxQuantity != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Available: ${_formatStockText(product, maxQuantity)}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            _DecimalQuantityInputFormatter(maxDecimals: 3),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Quantity (${product.unitLabel})',
                            hintText: 'Enter ${product.unitLabel} amount',
                            errorText: quantityError,
                          ),
                          onChanged: (_) {
                            if (quantityError == null) return;
                            setLocalState(() {
                              quantityError = null;
                            });
                          },
                          onSubmitted: (_) => submit(),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: submit,
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: Text(confirmLabel),
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
        ),
      );

      return result == null ? null : _sanitizeQuantity(result);
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
        controller.dispose();
      });
    }
  }

  Future<double?> _promptUnitQuantity({
    required Product product,
    required String title,
    required String confirmLabel,
    required double initialQuantity,
    required double unitPrice,
    double? maxQuantity,
  }) async {
    final boundedInitial = maxQuantity != null && maxQuantity > 0
        ? (initialQuantity > maxQuantity ? maxQuantity : initialQuantity)
        : initialQuantity;
    final safeInitial = boundedInitial <= _quantityEpsilon
        ? 1.0
        : boundedInitial.floorToDouble();
    final controller = TextEditingController(
      text: _formatQuantity(safeInitial, maxDecimals: 0),
    );
    String? quantityError;
    _activeModalCount += 1;

    try {
      final result = await showPremiumDialog<double>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setLocalState) {
            String? validateQuantity(String raw) {
              final parsed = int.tryParse(raw.trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter a valid quantity.';
              }
              if (maxQuantity != null &&
                  _quantityExceeds(parsed, maxQuantity)) {
                return 'Only ${_formatStockTextWithCartUnit(product, maxQuantity)} available.';
              }
              return null;
            }

            void submit() {
              final error = validateQuantity(controller.text);
              if (error != null) {
                setLocalState(() {
                  quantityError = error;
                });
                return;
              }

              Navigator.of(
                dialogContext,
              ).pop(_sanitizeQuantity(double.parse(controller.text.trim())));
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  decoration: _panelDecoration(color: _panelColor),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _brandSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.edit_note_rounded,
                                color: _brandColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    product.name,
                                    style: TextStyle(
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _panelSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatPriceCaption(product, unitPrice),
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (maxQuantity != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Available: ${_formatStockTextWithCartUnit(product, maxQuantity)}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Quantity (pcs)',
                            hintText: 'Enter piece count',
                            errorText: quantityError,
                          ),
                          onChanged: (_) {
                            if (quantityError == null) return;
                            setLocalState(() {
                              quantityError = null;
                            });
                          },
                          onSubmitted: (_) => submit(),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: submit,
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: Text(confirmLabel),
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
        ),
      );

      return result == null ? null : _sanitizeQuantity(result);
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
        controller.dispose();
      });
    }
  }

  Future<void> _handleProductTap(Product product, CartProvider cart) async {
    if (!cart.isRefundMode && product.stock <= 0) {
      _showInfoMessage(
        'This item is out of stock.',
        backgroundColor: _dangerColor,
      );
      return;
    }

    final currentQtyInCart = _getQuantityInCart(cart, product.barcode);
    var quantityToAdd = 1.0;

    if (product.isWeighted) {
      final remainingStock = cart.isRefundMode
          ? null
          : _sanitizeQuantity(product.stock - currentQtyInCart);

      if (!cart.isRefundMode &&
          remainingStock != null &&
          remainingStock <= _quantityEpsilon) {
        _showInfoMessage(
          'Cannot add more than available stock for ${product.name}.',
          backgroundColor: _dangerColor,
        );
        return;
      }

      final defaultQuantity =
          remainingStock != null &&
              remainingStock > _quantityEpsilon &&
              remainingStock < 1
          ? remainingStock
          : 1.0;

      final enteredQuantity = await _promptWeightedQuantity(
        product: product,
        title: 'Enter ${product.unitLabel} quantity',
        confirmLabel: 'Add to cart',
        initialQuantity: defaultQuantity,
        unitPrice: product.resolvePrice(cart.selectedPriceType),
        maxQuantity: remainingStock,
      );

      if (enteredQuantity == null) {
        _focusBarcodeField();
        return;
      }

      quantityToAdd = enteredQuantity;
    }

    if (!cart.isRefundMode &&
        _quantityExceeds(currentQtyInCart + quantityToAdd, product.stock)) {
      _showInfoMessage(
        'Cannot add more than available stock for ${product.name}.',
        backgroundColor: _dangerColor,
      );
      return;
    }

    cart.addToCart(product, quantity: quantityToAdd);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollCartToLatest();
    });
    _focusBarcodeField();
  }

  Future<void> _showReceiptForTransaction(int saleId) async {
    await TransactionHistoryScreen.showReceiptDialogForTransaction(
      context,
      saleId,
    );
    _focusBarcodeField();
  }

  Future<void> _applyDiscount(CartProvider cart) async {
    if (cart.items.isEmpty) {
      _showInfoMessage(
        'Add items before applying a discount.',
        backgroundColor: _warningColor,
      );
      return;
    }

    if (cart.isRefundMode) {
      _showInfoMessage(
        'Discounts are not available in refund mode.',
        backgroundColor: _warningColor,
      );
      return;
    }

    await _runProtectedManagerAction(() async {
      final result = await showCartDiscountDialog(
        context,
        subtotal: cart.discountedSubtotal,
        currentDiscountType: cart.discountType,
        currentDiscountValue: cart.discountValue,
        title: 'Apply Cart Discount',
        amountLabel: 'Discountable Total',
        totalLabel: 'Cart Total',
      );

      if (!mounted || result == null) return;

      cart.setDiscount(
        discountType: (result['discount_type'] ?? 'none').toString(),
        discountValue: ((result['discount_value'] as num?) ?? 0).toDouble(),
      );

      _focusBarcodeField();
    });
  }

  Future<void> _applyItemDiscount(CartProvider cart, CartItem item) async {
    if (cart.isRefundMode) {
      _showInfoMessage(
        'Discounts are not available in refund mode.',
        backgroundColor: _warningColor,
      );
      return;
    }

    await _runProtectedManagerAction(() async {
      final result = await showCartDiscountDialog(
        context,
        subtotal: item.baseTotal,
        currentDiscountType: item.discountType,
        currentDiscountValue: item.discountValue,
        title: 'Apply Item Discount',
        amountLabel: 'Item Total',
        totalLabel: 'Line Total',
      );

      if (!mounted || result == null) return;

      cart.setItemDiscount(
        item,
        discountType: (result['discount_type'] ?? 'none').toString(),
        discountValue: ((result['discount_value'] as num?) ?? 0).toDouble(),
      );

      _focusBarcodeField();
    });
  }

  Future<void> _handleCheckout(CartProvider cart) async {
    if (cart.items.isEmpty || _isProcessingCheckout) return;

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    if (PosFeatureFlags.enableShiftManagement) {
      final openShift = await DatabaseHelper.instance
          .getOpenShiftSummaryForCashier(cashierName);

      if (openShift == null) {
        if (!mounted) return;
        _showInfoMessage(
          'Open a shift before processing transactions.',
          backgroundColor: _dangerColor,
        );
        return;
      }

      setState(() {
        _currentShiftSummary = openShift;
      });
    }

    final isRefund = cart.isRefundMode;
    final subtotal = cart.subtotal;
    final discountAmount = cart.discountAmount;
    final displayTotal = cart.cartTotal;
    final itemsMap = cart.getCartItemsAsMap();
    String? paymentMethod;
    double? amountTendered;
    double? changeAmount;

    if (!isRefund) {
      final paymentResult = await showCheckoutPaymentDialog(
        context,
        totalAmount: displayTotal,
        onOpenHardwareSetup: _showHardwareSetupDialog,
      );

      if (paymentResult == null) {
        _focusBarcodeField();
        return;
      }

      paymentMethod = paymentResult['payment_method']?.toString();
      amountTendered = (paymentResult['amount_tendered'] as num?)?.toDouble();
      changeAmount = (paymentResult['change_amount'] as num?)?.toDouble();
    }

    setState(() {
      _isProcessingCheckout = true;
    });

    BuildContext? processingDialogContext;

    try {
      processingDialogContext = await _showCheckoutProcessingOverlay(
        isRefund: isRefund,
      );

      final saleId = await DatabaseHelper.instance.processTransaction(
        subtotalAmount: subtotal,
        totalAmount: displayTotal,
        cartItems: itemsMap,
        cashierName: cashierName,
        isRefund: isRefund,
        paymentMethod: paymentMethod,
        amountTendered: amountTendered,
        changeAmount: changeAmount,
        discountType: cart.discountType,
        discountValue: cart.discountValue,
        discountAmount: discountAmount,
      );

      cart.clearCart();

      await SyncService().syncNow();
      await _refreshProductsFromBackendAndReload(silentOnFailure: true);
      if (PosFeatureFlags.enableShiftManagement) {
        await _loadShiftSummary();
      }

      if (!mounted) return;

      final printer = ReceiptPrinterService.instance;
      if (printer.isConnected) {
        await TransactionHistoryScreen.printReceiptForTransaction(
          context,
          saleId,
        );
      }

      final action = await _showTransactionSuccessFlow(
        overlayContext: processingDialogContext,
        isRefund: isRefund,
        displayTotal: displayTotal,
        saleId: saleId,
      );

      if (action == 'receipt') {
        await _showReceiptForTransaction(saleId);
      } else {
        _focusBarcodeField();
      }
    } catch (e) {
      if (!mounted) return;

      await _dismissProcessingOverlay(processingDialogContext);
      processingDialogContext = null;

      final message = e.toString().replaceFirst('Exception: ', '');

      _showInfoMessage(
        message.isEmpty ? 'Error processing checkout.' : message,
        backgroundColor: _dangerColor,
      );
      _focusBarcodeField();
    } finally {
      await _dismissProcessingOverlay(processingDialogContext);
      if (mounted) {
        setState(() {
          _isProcessingCheckout = false;
        });
      }
    }
  }

  Future<BuildContext?> _showCheckoutProcessingOverlay({
    required bool isRefund,
  }) async {
    if (!mounted) return null;

    final completer = Completer<BuildContext>();
    final title = isRefund ? 'Processing refund' : 'Processing payment';
    final subtitle = isRefund
        ? 'Please wait while the refund is saved and synced.'
        : 'Please wait while the payment is being finalized.';
    final tone = isRefund ? _dangerColor : _brandColor;
    final toneSoft = isRefund ? _dangerSoft : _brandSoft;

    unawaited(
      showPremiumDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(_isDark ? 0.30 : 0.22),
        transitionDuration: const Duration(milliseconds: 220),
        builder: (dialogContext) {
          if (!completer.isCompleted) {
            completer.complete(dialogContext);
          }

          return PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(24),
                decoration: _panelDecoration(color: _panelColor),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: toneSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: tone.withOpacity(0.22)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: tone,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    return completer.future;
  }

  Future<void> _dismissProcessingOverlay(BuildContext? overlayContext) async {
    if (overlayContext == null || !overlayContext.mounted) return;
    Navigator.of(overlayContext, rootNavigator: true).pop();
    await Future<void>.delayed(const Duration(milliseconds: 90));
  }

  Future<String?> _showTransactionSuccessFlow({
    required BuildContext? overlayContext,
    required bool isRefund,
    required double displayTotal,
    required int saleId,
  }) async {
    final dialogContext = overlayContext ?? context;
    final title = isRefund ? 'Refund Completed' : 'Payment Successful';
    final amountLabel = isRefund ? 'Refund Amount' : 'Total Paid';
    final tone = isRefund ? _dangerColor : _brandColor;
    final toneSoft = isRefund ? _dangerSoft : _brandSoft;

    final result = await showPremiumDialog<String>(
      context: dialogContext,
      barrierDismissible: false,
      includeBackdrop: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      builder: (successContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(24),
          decoration: _panelDecoration(color: _panelColor),
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
                      color: toneSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tone.withOpacity(0.24)),
                    ),
                    child: Icon(
                      isRefund
                          ? Icons.restart_alt_rounded
                          : Icons.check_circle_rounded,
                      color: tone,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Transaction #$saleId completed successfully.',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: toneSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: tone.withOpacity(0.22)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            amountLabel.toUpperCase(),
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Rs. ${displayTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: tone,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _panelColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Text(
                        isRefund ? 'REFUND' : 'PAID',
                        style: TextStyle(
                          color: tone,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Local save, sync attempt, and product refresh are complete for this transaction.',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(successContext).pop('next'),
                      child: const Text('Next Customer'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(successContext).pop('receipt'),
                      child: const Text('View Receipt'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return result;
  }

  Future<void> _openUserManagement() async {
    final auth = context.read<AuthProvider>();

    if (!auth.hasManagementAccess) {
      _showInfoMessage(
        'Only managers or full-access users can access User Management.',
        backgroundColor: _warningColor,
      );
      _focusBarcodeField();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserManagementScreen()),
    );

    if (!mounted) return;

    await auth.refreshCurrentUser();
    _focusBarcodeField();
  }

  Future<void> _openSupplierOperations() async {
    await _runProtectedManagerAction(() async {
      final cashierName =
          context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              SupplierManagementScreen(cashierName: cashierName),
        ),
      );

      if (!mounted) return;

      await _refreshProductsFromBackendAndReload(silentOnFailure: true);
      _focusBarcodeField();
    });
  }

  Future<void> _openShiftManagement() async {
    if (!PosFeatureFlags.enableShiftManagement) return;

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftManagementScreen(cashierName: cashierName),
      ),
    );

    await _loadShiftSummary();
    _focusBarcodeField();
  }

  Future<void> _holdCurrentCart(CartProvider cart) async {
    if (cart.items.isEmpty) return;

    final controller = TextEditingController();

    final cartName = await showPremiumDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              return Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                decoration: _panelDecoration(color: _panelColor),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _borderColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _brandSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _brandColor.withOpacity(0.24),
                            ),
                          ),
                          child: Icon(
                            Icons.pause_circle_outline_rounded,
                            color: _brandColor,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hold Cart',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Save this bill and resume it later from Held Bills.',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(dialogContext),
                          child: Ink(
                            width: 42,
                            height: 42,
                            decoration: _softDecoration(color: _panelSoft),
                            child: Icon(
                              Icons.close_rounded,
                              color: _textSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _panelSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CART NAME',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            onChanged: (_) => setLocalState(() {}),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              Navigator.pop(
                                dialogContext,
                                controller.text.trim(),
                              );
                            },
                            decoration: InputDecoration(
                              hintText: 'Example: Customer 1 / Counter Hold',
                              prefixIcon: Container(
                                margin: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _brandSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.edit_note_rounded,
                                  color: _brandColor,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(
                                dialogContext,
                                controller.text.trim(),
                              );
                            },
                            icon: const Icon(
                              Icons.pause_circle_outline_rounded,
                              size: 16,
                            ),
                            label: const Text('Hold Bill'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    controller.dispose();

    if (cartName == null) {
      _focusBarcodeField();
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    try {
      await DatabaseHelper.instance.saveHeldCart(
        cartName: cartName,
        cashierName: cashierName,
        isRefundMode: cart.isRefundMode,
        discountType: cart.discountType,
        discountValue: cart.discountValue,
        items: cart.getCartItemsAsMap(),
        selectedPriceType: cart.selectedPriceType.dbValue,
      );

      cart.clearCart();

      if (!mounted) return;

      _showInfoMessage(
        'Cart held successfully.',
        backgroundColor: _successColor,
      );
      _focusBarcodeField();
    } catch (e) {
      if (!mounted) return;

      _showInfoMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _dangerColor,
      );
      _focusBarcodeField();
    }
  }

  Future<bool> _confirmReplaceCurrentCartIfNeeded(CartProvider cart) async {
    if (cart.items.isEmpty) return true;

    final confirmed = await showPremiumDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            decoration: _panelDecoration(color: _panelColor),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _warningSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _warningColor.withOpacity(0.24),
                        ),
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: _warningColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replace Current Cart?',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Opening a held bill will replace the current cart on the register.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(dialogContext, false),
                      child: Ink(
                        width: 42,
                        height: 42,
                        decoration: _softDecoration(color: _panelSoft),
                        child: Icon(
                          Icons.close_rounded,
                          color: _textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _panelSoft,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    'Hold or clear the current cart first if you want to keep it before resuming a held bill.',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                        label: const Text('Continue'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return confirmed ?? false;
  }

  List<Map<String, dynamic>> _prepareResumedCartItems(
    List<Map<String, dynamic>> rawItems, {
    String fallbackPriceType = 'selling',
  }) {
    return rawItems.map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final productMap = Map<String, dynamic>.from(item['product'] as Map);
      final barcode = productMap['barcode']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final safeQuantity = quantity <= _quantityEpsilon ? 1.0 : quantity;

      final latestProduct = _getCurrentProduct(barcode);
      final resolvedProductMap = latestProduct?.toMap() ?? productMap;

      final priceTypeUsed = (item['price_type_used'] ?? fallbackPriceType)
          .toString();
      final resolvedUnitPrice =
          (item['unit_price_used'] as num?)?.toDouble() ??
          (latestProduct ?? Product.fromMap(resolvedProductMap)).resolvePrice(
            ProductPriceTypeX.fromDb(priceTypeUsed),
          );
      final baseLineTotal =
          (item['base_line_total'] as num?)?.toDouble() ??
          (resolvedUnitPrice * safeQuantity);
      final itemDiscountType = (item['item_discount_type'] ?? 'none')
          .toString();
      final itemDiscountValue = ((item['item_discount_value'] as num?) ?? 0)
          .toDouble();
      final itemDiscountAmount = ((item['item_discount_amount'] as num?) ?? 0)
          .toDouble();
      final resolvedLineTotal =
          (item['line_total'] as num?)?.toDouble() ??
          (baseLineTotal - itemDiscountAmount);

      return {
        'product': resolvedProductMap,
        'quantity': safeQuantity,
        'unit_price_used': resolvedUnitPrice,
        'price_type_used': priceTypeUsed,
        'base_line_total': baseLineTotal,
        'item_discount_type': itemDiscountType,
        'item_discount_value': itemDiscountValue,
        'item_discount_amount': itemDiscountAmount,
        'line_total': resolvedLineTotal < 0 ? 0.0 : resolvedLineTotal,
      };
    }).toList();
  }

  Future<void> _openHeldCarts(CartProvider cart) async {
    final canProceed = await _confirmReplaceCurrentCartIfNeeded(cart);
    if (!canProceed) {
      _focusBarcodeField();
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    final restored = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => HeldCartsScreen(cashierName: cashierName),
      ),
    );

    if (!mounted || restored == null) {
      _focusBarcodeField();
      return;
    }

    final restoredItems = (restored['items'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final restoredSelectedPriceType =
        (restored['selected_price_type'] ?? 'selling').toString();

    final preparedItems = _prepareResumedCartItems(
      restoredItems,
      fallbackPriceType: restoredSelectedPriceType,
    );

    cart.loadHeldCart(
      items: preparedItems,
      isRefundMode: (restored['is_refund_mode'] ?? false) == true,
      discountType: (restored['discount_type'] ?? 'none').toString(),
      discountValue: ((restored['discount_value'] as num?) ?? 0).toDouble(),
      selectedPriceType: restoredSelectedPriceType,
    );

    _showInfoMessage('Held cart resumed.', backgroundColor: _successColor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollCartToLatest(animated: false);
    });
    _focusBarcodeField();
  }

  Future<void> _handleHeaderMenuAction(String value, CartProvider cart) async {
    switch (value) {
      case 'cashier_summary':
        final cashierName =
            context.read<AuthProvider>().currentUser?.name ?? 'Unknown';
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CashierSummaryScreen(cashierName: cashierName),
          ),
        );
        break;
      case 'hardware_setup':
        await _showHardwareSetupDialog();
        break;
      case 'inventory':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const InventoryScreen()),
        );
        break;
      case 'supplier_ops':
        await _openSupplierOperations();
        break;
      case 'transaction_history':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TransactionHistoryScreen(),
          ),
        );
        if (PosFeatureFlags.enableShiftManagement) {
          await _loadShiftSummary();
        }
        break;
      case 'refresh_products':
        await _refreshProductsFromBackendAndReload(showSuccessMessage: true);
        if (PosFeatureFlags.enableShiftManagement) {
          await _loadShiftSummary();
        }
        break;
      case 'user_management':
        await _openUserManagement();
        break;
      case 'sales_report':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SalesReportScreen()),
        );
        break;
      case 'shift_management':
        await _openShiftManagement();
        break;
      case 'held_carts':
        await _openHeldCarts(cart);
        break;
    }

    _focusBarcodeField();
  }

  IconData _menuActionIcon(String value) {
    switch (value) {
      case 'cashier_summary':
        return Icons.bar_chart_rounded;
      case 'hardware_setup':
        return Icons.usb_rounded;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'supplier_ops':
        return Icons.local_shipping_outlined;
      case 'transaction_history':
        return Icons.receipt_long_outlined;
      case 'user_management':
        return Icons.manage_accounts_outlined;
      case 'sales_report':
        return Icons.analytics_outlined;
      case 'shift_management':
        return Icons.point_of_sale_rounded;
      case 'held_carts':
        return Icons.shopping_bag_outlined;
      default:
        return Icons.circle;
    }
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconSurfaceButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Ink(
            padding: const EdgeInsets.all(9),
            decoration: _softDecoration(color: _panelSoft),
            child: Icon(icon, size: 18, color: iconColor ?? _textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderMenu({
    required String title,
    required IconData icon,
    required List<MapEntry<String, String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: title,
      onSelected: onSelected,
      itemBuilder: (context) {
        return items
            .map(
              (entry) => PopupMenuItem<String>(
                value: entry.key,
                child: Row(
                  children: [
                    Icon(
                      _menuActionIcon(entry.key),
                      size: 17,
                      color: _textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(entry.value),
                  ],
                ),
              ),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: _softDecoration(color: _panelSoft),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: _textPrimary),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _mutedIcon,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(AuthProvider auth, CartProvider cart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_panelAlt, _panelColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 194,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_brandSoft, _accentBlueSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _brandColor.withOpacity(_isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: _brandColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'FOOD CITY',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Premium point of sale',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleBarcodeSubmit(cart),
              onChanged: (value) => _handleBarcodeChanged(cart, value),
              decoration: InputDecoration(
                labelText: 'Quick scan / barcode',
                hintText: 'Scan barcode or type product code',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: _brandColor,
                    size: 18,
                  ),
                ),
                suffixIcon: _barcodeController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear barcode',
                        onPressed: () {
                          _barcodeInputTimer?.cancel();
                          _barcodeController.clear();
                          setState(() {});
                          _focusBarcodeField();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () => _handleBarcodeSubmit(cart),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Add to Cart'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 42),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: _brandColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          StreamBuilder<List<ConnectivityResult>>(
            stream: Connectivity().onConnectivityChanged,
            builder: (context, snapshot) {
              final hasNoInternet =
                  snapshot.data?.contains(ConnectivityResult.none) ?? false;
              return _buildStatusPill(
                icon: hasNoInternet
                    ? Icons.wifi_off_rounded
                    : Icons.wifi_rounded,
                label: hasNoInternet ? 'OFFLINE' : 'ONLINE',
                color: hasNoInternet ? _warningColor : _successColor,
                background: hasNoInternet ? _warningSoft : _successSoft,
              );
            },
          ),
          if (PosFeatureFlags.enableShiftManagement) ...[
            const SizedBox(width: 10),
            _buildStatusPill(
              icon: _currentShiftSummary == null
                  ? Icons.badge_outlined
                  : Icons.badge_rounded,
              label: _currentShiftSummary == null
                  ? 'SHIFT CLOSED'
                  : 'SHIFT OPEN',
              color: _currentShiftSummary == null ? _warningColor : _brandColor,
              background: _currentShiftSummary == null
                  ? _warningSoft
                  : _brandSoft,
            ),
          ],
          const SizedBox(width: 10),
          _buildIconSurfaceButton(
            tooltip: _isDark ? 'Switch to light mode' : 'Switch to dark mode',
            icon: _isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            onPressed: () {
              context.read<AppThemeProvider>().toggleTheme();
            },
            iconColor: _brandColor,
          ),
          const SizedBox(width: 10),
          _buildHeaderMenu(
            title: 'Quick Actions',
            icon: Icons.widgets_outlined,
            items: [
              const MapEntry('cashier_summary', 'Cashier Summary'),
              const MapEntry('transaction_history', 'Transaction History'),
              const MapEntry('hardware_setup', 'Hardware Setup'),
            ],
            onSelected: (value) => _handleHeaderMenuAction(value, cart),
          ),
          if (auth.hasManagementAccess) ...[
            const SizedBox(width: 10),
            _buildHeaderMenu(
              title: 'Manager',
              icon: Icons.admin_panel_settings_outlined,
              items: [
                const MapEntry('inventory', 'Inventory'),
                const MapEntry('user_management', 'User Management'),
                const MapEntry('supplier_ops', 'Supplier Operations'),
                const MapEntry('sales_report', 'Store Sales Report'),
                if (PosFeatureFlags.enableShiftManagement)
                  const MapEntry('shift_management', 'Shift Management'),
              ],
              onSelected: (value) => _handleHeaderMenuAction(value, cart),
            ),
          ],
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: _softDecoration(color: _panelSoft),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _brandSoft,
                    child: Text(
                      (auth.currentUser?.name ?? 'U').trim().isEmpty
                          ? 'U'
                          : (auth.currentUser?.name ?? 'U')
                                .trim()[0]
                                .toUpperCase(),
                      style: TextStyle(
                        color: _brandColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          auth.currentUser?.name ?? 'Not Logged In',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          auth.hasManagementAccess ? 'manager' : 'cashier',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildIconSurfaceButton(
            tooltip: 'Logout',
            icon: Icons.logout_rounded,
            iconColor: _dangerColor,
            onPressed: () {
              context.read<AuthProvider>().logout();
              context.read<CartProvider>().clearCart();

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMetricChip({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$value ',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogPanel(CartProvider cart) {
    return Container(
      decoration: _panelDecoration(color: _panelColor),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product Catalog',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Search or scan to bill faster.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _buildIconSurfaceButton(
                  tooltip: 'Refresh products from backend',
                  icon: _isRefreshingProducts
                      ? Icons.sync_rounded
                      : Icons.refresh_rounded,
                  onPressed: _isRefreshingProducts
                      ? () {}
                      : () {
                          _refreshProductsFromBackendAndReload(
                            showSuccessMessage: true,
                          );
                          if (PosFeatureFlags.enableShiftManagement) {
                            _loadShiftSummary();
                          }
                        },
                  iconColor: _isRefreshingProducts ? _brandColor : _textPrimary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                labelText: 'Search products',
                hintText: 'Search by product name or barcode',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accentBlueSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    color: _accentBlue,
                    size: 18,
                  ),
                ),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                          _focusBarcodeField();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Showing ${_filteredProducts.length} of ${_products.length} products',
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (_searchQuery.trim().isNotEmpty)
                  Flexible(
                    child: Text(
                      'Filter: "${_searchQuery.trim()}"',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _brandColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _panelAlt,
                    border: Border.all(color: _borderColor),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: _buildProductGrid(cart),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid(CartProvider cart) {
    if (_isLoadingProducts) {
      return Center(child: CircularProgressIndicator(color: _brandColor));
    }

    if (_products.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products found',
        message: 'Your local POS database does not have products yet.',
      );
    }

    if (_filteredProducts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching products',
        message: 'Try another keyword or barcode to find the item faster.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 3;
        if (width >= 1460) {
          crossAxisCount = 6;
        } else if (width >= 1080) {
          crossAxisCount = 5;
        } else if (width >= 820) {
          crossAxisCount = 4;
        }

        return GridView.builder(
          itemCount: _filteredProducts.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: _productTileExtent,
          ),
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            return _buildProductCard(product, cart);
          },
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: _panelSoft,
              shape: BoxShape.circle,
              border: Border.all(color: _borderColor),
            ),
            child: Icon(icon, size: 34, color: _mutedIcon),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, CartProvider cart) {
    final isOutOfStock =
        _sanitizeQuantity(product.stock) <= _quantityEpsilon &&
        !cart.isRefundMode;
    final isLowStock = !isOutOfStock && product.isLowStock;
    final cartQty = _getQuantityInCart(cart, product.barcode);
    final displayPrice = _getDisplayPrice(product, cart);

    final tone = isOutOfStock
        ? _dangerColor
        : (isLowStock ? _warningColor : _brandColor);
    final toneSoft = isOutOfStock
        ? _dangerSoft
        : (isLowStock ? _warningSoft : _brandSoft);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _handleProductTap(product, cart),
        onLongPress: () async {
          await _runProtectedManagerAction(() async {
            await AdminDialogs.showEditPriceDialog(
              context,
              product.barcode,
              product.name,
              product.sellingPrice,
              () async {
                await _refreshProductsFromBackendAndReload(
                  silentOnFailure: true,
                );
              },
            );
          });
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isOutOfStock ? _panelColor.withOpacity(0.72) : _panelSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isOutOfStock
                  ? _dangerColor.withOpacity(0.35)
                  : _borderColor,
            ),
            boxShadow: _isDark
                ? [
                    BoxShadow(
                      color: _shadowColor.withOpacity(0.36),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: toneSoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      isOutOfStock
                          ? Icons.remove_shopping_cart_rounded
                          : Icons.inventory_2_rounded,
                      color: tone,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  if (cartQty > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _brandSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _brandColor.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        _formatCartBadgeText(product, cartQty),
                        style: TextStyle(
                          color: _brandColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.isWeighted
                    ? 'Rs. ${displayPrice.toStringAsFixed(2)} / ${product.unitLabel}'
                    : 'Rs. ${displayPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  color: isOutOfStock ? _textSecondary : _brandColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.05,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _screenBackgroundAlt.withOpacity(
                    _isDark ? 0.55 : 0.80,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _borderColor),
                ),
                child: Text(
                  product.barcode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: toneSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tone.withOpacity(0.28)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOutOfStock
                          ? Icons.error_outline_rounded
                          : (isLowStock
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded),
                      size: 14,
                      color: tone,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isOutOfStock
                            ? 'Out of stock'
                            : (isLowStock
                                  ? 'Low stock - ${_formatStockText(product, product.stock)}'
                                  : 'Stock - ${_formatStockText(product, product.stock)}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel(CartProvider cart) {
    final modeColor = cart.isRefundMode ? _dangerColor : _accentBlue;
    final modeSoft = cart.isRefundMode ? _dangerSoft : _accentBlueSoft;

    return Container(
      decoration: _panelDecoration(color: _panelColor),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_rounded, color: _brandColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sale Cart',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cart.items.length} ${cart.items.length == 1 ? 'line' : 'lines'} in current bill',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _toggleSaleRefundModeFromHeader(cart),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: modeSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: modeColor.withOpacity(0.28)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cart.isRefundMode
                                ? Icons.restart_alt_rounded
                                : Icons.swap_horiz_rounded,
                            size: 14,
                            color: modeColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cart.isRefundMode ? 'REFUND' : 'SALE',
                            style: TextStyle(
                              color: modeColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (PosFeatureFlags.enableShiftManagement)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _currentShiftSummary == null
                      ? _warningSoft
                      : _successSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        (_currentShiftSummary == null
                                ? _warningColor
                                : _successColor)
                            .withOpacity(0.25),
                  ),
                ),
                child: Text(
                  _currentShiftSummary == null
                      ? 'Open a shift to process transactions.'
                      : 'Expected cash: Rs. ${((((_currentShiftSummary!['expected_cash'] as num?) ?? 0).toDouble())).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: _currentShiftSummary == null
                        ? _warningColor
                        : _successColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: _buildPriceModeSelector(cart),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _panelAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _borderColor),
              ),
              child: cart.items.isEmpty
                  ? _buildCartEmptyState(cart)
                  : ListView.separated(
                      controller: _cartScrollController,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      itemBuilder: (context, index) {
                        final item = cart.items[index];
                        return _buildCartItemRow(cart, item);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemCount: cart.items.length,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: _buildSummarySection(cart),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSaleRefundModeFromHeader(CartProvider cart) async {
    if (cart.isRefundMode) {
      context.read<CartProvider>().toggleRefundMode(false);
      _showInfoMessage('Switched to sale mode.', backgroundColor: _accentBlue);
      _focusBarcodeField();
      return;
    }

    await _runProtectedManagerAction(() async {
      context.read<CartProvider>().toggleRefundMode(true);
      if (!mounted) return;
      _showInfoMessage('Refund mode enabled.', backgroundColor: _dangerColor);
      _focusBarcodeField();
    });
  }

  Widget _buildCartEmptyState(CartProvider cart) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: _panelSoft,
                shape: BoxShape.circle,
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                cart.isRefundMode
                    ? Icons.restart_alt_rounded
                    : Icons.shopping_cart_outlined,
                size: 30,
                color: _mutedIcon,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              cart.isRefundMode ? 'Refund cart is empty' : 'Cart is empty',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cart.isRefundMode
                  ? 'Find a past sale or add items to start a refund.'
                  : 'Scan a barcode or tap a product card to start billing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceModeSelector(CartProvider cart) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: ProductPriceType.values.map((type) {
          final selected = cart.selectedPriceType == type;
          final color = _priceTypeColor(type);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: type == ProductPriceType.sale ? 0 : 6,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: cart.isRefundMode
                      ? null
                      : () => _handlePriceTypeSelection(cart, type),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withOpacity(_isDark ? 0.18 : 0.12)
                          : _inputFill,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: selected ? color : _borderColor,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _priceTypeShortLabel(type),
                        style: TextStyle(
                          color: selected ? color : _textSecondary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.25,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCartItemRow(CartProvider cart, CartItem item) {
    final currentStock = _getCurrentStock(
      item.product.barcode,
      fallback: item.product.stock,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: item.discountAmount > 0
                    ? 'Edit item discount'
                    : 'Discount this item',
                onPressed: () => _applyItemDiscount(cart, item),
                icon: Icon(
                  Icons.discount_outlined,
                  color: item.discountAmount > 0
                      ? _warningColor
                      : _textSecondary,
                  size: 16,
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                tooltip: 'Remove item',
                onPressed: () {
                  cart.removeItem(item);
                  _focusBarcodeField();
                },
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: _dangerColor,
                  size: 16,
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatPriceCaption(item.product, item.unitPrice),
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
          if (item.discountAmount > 0) ...[
            const SizedBox(height: 3),
            Text(
              item.discountType == 'percent'
                  ? 'Discount: ${item.discountValue.toStringAsFixed(item.discountValue % 1 == 0 ? 0 : 2)}% (-Rs. ${item.discountAmount.toStringAsFixed(2)})'
                  : 'Discount: Rs. ${item.discountValue.toStringAsFixed(2)} (-Rs. ${item.discountAmount.toStringAsFixed(2)})',
              style: TextStyle(
                color: _dangerColor,
                fontWeight: FontWeight.w700,
                fontSize: 9.8,
              ),
            ),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              if (item.product.isWeighted)
                OutlinedButton.icon(
                  onPressed: () async {
                    final otherQtyInCart = _sanitizeQuantity(
                      _getQuantityInCart(cart, item.product.barcode) -
                          item.quantity,
                    );
                    final maxQuantity = cart.isRefundMode
                        ? null
                        : _sanitizeQuantity(currentStock - otherQtyInCart);

                    if (!cart.isRefundMode &&
                        maxQuantity != null &&
                        maxQuantity <= _quantityEpsilon) {
                      _showInfoMessage(
                        'No stock is available to increase ${item.product.name}.',
                        backgroundColor: _dangerColor,
                      );
                      return;
                    }

                    final updatedQuantity = await _promptWeightedQuantity(
                      product: item.product,
                      title: 'Edit ${item.product.unitLabel} quantity',
                      confirmLabel: 'Update',
                      initialQuantity: item.quantity,
                      unitPrice: item.unitPrice,
                      maxQuantity: maxQuantity,
                    );

                    if (updatedQuantity == null) {
                      _focusBarcodeField();
                      return;
                    }

                    cart.updateQuantity(item, updatedQuantity);
                    _focusBarcodeField();
                  },
                  icon: const Icon(Icons.scale_rounded, size: 14),
                  label: Text(
                    _formatQuantityWithUnit(
                      item.quantity,
                      item.product.unitLabel,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    foregroundColor: _textPrimary,
                    backgroundColor: _inputFill,
                    side: BorderSide(color: _borderColor),
                  ),
                )
              else
                GestureDetector(
                  onTap: () async {
                    final otherQtyInCart = _sanitizeQuantity(
                      _getQuantityInCart(cart, item.product.barcode) -
                          item.quantity,
                    );
                    final maxQuantity = cart.isRefundMode
                        ? null
                        : _sanitizeQuantity(currentStock - otherQtyInCart);

                    if (!cart.isRefundMode &&
                        maxQuantity != null &&
                        maxQuantity <= _quantityEpsilon) {
                      _showInfoMessage(
                        'No stock is available to increase ${item.product.name}.',
                        backgroundColor: _dangerColor,
                      );
                      return;
                    }

                    final updatedQuantity = await _promptUnitQuantity(
                      product: item.product,
                      title: 'Edit quantity',
                      confirmLabel: 'Update',
                      initialQuantity: item.quantity,
                      unitPrice: item.unitPrice,
                      maxQuantity: maxQuantity,
                    );

                    if (updatedQuantity == null) {
                      _focusBarcodeField();
                      return;
                    }

                    cart.updateQuantity(item, updatedQuantity);
                    _focusBarcodeField();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: _inputFill,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            cart.decreaseQuantity(item);
                            _focusBarcodeField();
                          },
                          icon: const Icon(Icons.remove_rounded, size: 14),
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            _formatQuantity(item.quantity),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            if (!cart.isRefundMode &&
                                _quantityExceeds(
                                  item.quantity + 1.0,
                                  currentStock,
                                )) {
                              _showInfoMessage(
                                'Cannot exceed available stock for ${item.product.name}.',
                                backgroundColor: _dangerColor,
                              );
                              return;
                            }

                            cart.increaseQuantity(item);
                            _focusBarcodeField();
                          },
                          icon: const Icon(Icons.add_rounded, size: 14),
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stock: ${_formatStockTextWithCartUnit(item.product, currentStock)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.discountAmount > 0)
                    Text(
                      'Rs. ${item.baseTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    'Rs. ${item.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (item.discountAmount > 0) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  cart.clearItemDiscount(item);
                  _focusBarcodeField();
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Clear Item Discount'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryLine({
    required String label,
    required String value,
    Color? valueColor,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: emphasize ? 14 : 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _textPrimary,
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
              fontSize: emphasize ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(CartProvider cart) {
    final totalTone = cart.isRefundMode ? _dangerColor : _brandColor;
    final totalToneSoft = cart.isRefundMode ? _dangerSoft : _brandSoft;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryLine(
            label: 'Subtotal',
            value: 'Rs. ${cart.subtotal.toStringAsFixed(2)}',
          ),
          _buildSummaryLine(
            label: 'Discount',
            value: 'Rs. ${cart.discountAmount.toStringAsFixed(2)}',
            valueColor: cart.discountAmount > 0 ? _dangerColor : _textPrimary,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: totalToneSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: totalTone.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                Text(
                  cart.isRefundMode ? 'REFUND TOTAL' : 'TOTAL',
                  style: TextStyle(
                    color: _isDark ? const Color(0xFFF4F8FF) : _textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    fontSize: 11.5,
                    shadows: [
                      Shadow(
                        color: totalTone.withOpacity(_isDark ? 0.18 : 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'Rs. ${cart.cartTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: totalTone,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: totalTone.withOpacity(_isDark ? 0.22 : 0.10),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!cart.isRefundMode) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: cart.items.isEmpty
                        ? null
                        : () => _applyDiscount(cart),
                    icon: const Icon(Icons.percent_rounded, size: 14),
                    label: Text(
                      cart.discountAmount > 0
                          ? 'Edit Discount'
                          : 'Apply Discount',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: cart.discountAmount > 0
                        ? () {
                            cart.clearDiscount();
                            _focusBarcodeField();
                          }
                        : null,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text('Clear Discount'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: cart.items.isEmpty
                      ? null
                      : () => _holdCurrentCart(cart),
                  icon: const Icon(
                    Icons.pause_circle_outline_rounded,
                    size: 14,
                  ),
                  label: const Text('Hold Cart'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openHeldCarts(cart),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 14),
                  label: const Text('Held Carts'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: cart.items.isEmpty
                ? null
                : () {
                    context.read<CartProvider>().clearCart();
                    _focusBarcodeField();
                  },
            icon: const Icon(Icons.delete_sweep_rounded, size: 14),
            label: const Text('Clear Cart'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: cart.items.isEmpty || _isProcessingCheckout
                ? null
                : () => _handleCheckout(cart),
            icon: Icon(
              _isProcessingCheckout
                  ? Icons.sync_rounded
                  : (cart.isRefundMode
                        ? Icons.restart_alt_rounded
                        : Icons.lock_open_rounded),
              size: 16,
            ),
            label: Text(
              _isProcessingCheckout
                  ? 'Processing...'
                  : (cart.isRefundMode ? 'Process Refund' : 'Pay Now'),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              backgroundColor: totalTone,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupportedWindow() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            decoration: _panelDecoration(color: _panelColor),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _brandSoft,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _brandColor.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.open_in_full_rounded,
                    color: _brandColor,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Maximize the screen to continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Food City POS needs a desktop workspace of at least '
                  '${_minSupportedWidth.toInt()} x ${_minSupportedHeight.toInt()}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspace(AuthProvider auth, CartProvider cart) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _buildTopHeader(auth, cart),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildCatalogPanel(cart)),
                const SizedBox(width: 14),
                SizedBox(width: _cartPanelWidth, child: _buildCartPanel(cart)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cart = context.watch<CartProvider>();
    context.watch<AppThemeProvider>();

    _syncCartAutoScroll(cart);

    return Theme(
      data: _buildPosTheme(),
      child: RawKeyboardListener(
        focusNode: _keyboardListenerFocusNode,
        autofocus: true,
        onKey: _handleGlobalKeyboardEvent,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWindowSupported =
                    constraints.maxWidth >= _minSupportedWidth &&
                    constraints.maxHeight >= _minSupportedHeight;

                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_screenBackground, _screenBackgroundAlt],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: isWindowSupported
                          ? _buildDesktopWorkspace(auth, cart)
                          : _buildUnsupportedWindow(),
                    ),
                    if (isWindowSupported && _renderWelcomeOverlay)
                      _buildWelcomeOverlay(auth),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
