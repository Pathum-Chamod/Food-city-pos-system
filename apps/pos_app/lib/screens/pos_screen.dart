import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../config/pos_feature_flags.dart';
import '../navigation/pos_route_names.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/app_theme_provider.dart';
import '../services/database_helper.dart';
import '../services/customer_service.dart';
import '../services/customer_credit_service.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../services/sync_service.dart';
import '../widgets/admin_dialogs.dart';
import '../widgets/premium_dialog.dart';
import '../widgets/app_snackbar.dart';
import 'cart_discount_dialog.dart';
import 'cashier_summary_screen.dart';
import 'checkout_payment_dialog.dart';
import 'customer_picker_dialog.dart';
import 'customer_management_screen.dart';
import 'expiry_alerts_screen.dart';
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
  static const double _catalogRailWidth = 410;
  static const double _checkoutRailWidth = 340;
  static const Duration _priceModeDoubleTapWindow = Duration(milliseconds: 650);
  static const Duration _cartSelectionVisibleDuration = Duration(seconds: 2);
  List<Product> _products = [];
  bool _isLoadingProducts = true;
  bool _isProcessingCheckout = false;
  bool _isPaymentDialogOpen = false;
  bool _isRefreshingProducts = false;
  bool _isLookupOpen = false;
  int _activeModalCount = 0;
  bool _showWelcomeOverlay = false;
  bool _renderWelcomeOverlay = false;
  Timer? _productRefreshTimer;
  Timer? _barcodeScannerSubmitTimer;
  Timer? _welcomeOverlayTimer;
  Timer? _welcomeOverlayCleanupTimer;
  Timer? _cartSelectionHideTimer;
  DateTime? _barcodeInputStartedAt;
  DateTime? _lastBarcodeInputAt;
  String _lastBarcodeInputValue = '';
  int _rapidBarcodeInputSteps = 0;
  ProductPriceType? _lastPriceModeTapType;
  ProductPriceType? _lastPriceModePreviousType;
  DateTime? _lastPriceModeTapAt;
  bool _isPriceModePromptOpen = false;
  final Set<String> _expiryWarningShownBarcodes = <String>{};

  final ScrollController _cartScrollController = ScrollController();
  int _lastCartItemCount = 0;
  int? _selectedCartIndex;
  bool _isCartSelectionVisible = false;

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
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyboardEvent);
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
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyboardEvent);
    _productRefreshTimer?.cancel();
    _barcodeScannerSubmitTimer?.cancel();
    _cartSelectionHideTimer?.cancel();
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

  bool _handleHardwareKeyboardEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final keyboard = HardwareKeyboard.instance;
    final hasModifier =
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;

    final cart = context.read<CartProvider>();
    if (_activeModalCount == 0 &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyB) {
        unawaited(_openCustomerPicker(cart));
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyD) {
        _clearSelectedItemDiscount(cart);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.keyL) {
        unawaited(_confirmClearCart(cart));
        return true;
      }
    }

    if (hasModifier) return false;

    if (_activeModalCount == 0) {
      if (event.logicalKey == LogicalKeyboardKey.home) {
        _focusBarcodeField();
        return true;
      }

      ProductPriceType? shortcutPriceType;
      if (event.logicalKey == LogicalKeyboardKey.f1) {
        shortcutPriceType = ProductPriceType.selling;
      } else if (event.logicalKey == LogicalKeyboardKey.f2) {
        shortcutPriceType = ProductPriceType.wholesale;
      } else if (event.logicalKey == LogicalKeyboardKey.f3) {
        shortcutPriceType = ProductPriceType.sale;
      }

      if (shortcutPriceType != null) {
        unawaited(_handlePriceTypeSelection(cart, shortcutPriceType));
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.f4) {
        if (cart.items.isEmpty) {
          _showInfoMessage(
            'Add items before holding the cart.',
            backgroundColor: _warningColor,
          );
        } else {
          unawaited(_holdCurrentCart(cart));
        }
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.f5) {
        unawaited(_openHeldCarts(cart));
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.f6) {
        unawaited(_applyDiscount(cart));
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.f7) {
        _toggleItemLookup();
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveCartSelection(cart, -1);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveCartSelection(cart, 1);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.pageUp) {
        _jumpCartSelection(cart, toBottom: false);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.pageDown) {
        _jumpCartSelection(cart, toBottom: true);
        return true;
      }

      final character = event.character;
      final isPlusKey =
          character == '+' || event.logicalKey == LogicalKeyboardKey.numpadAdd;
      final isMinusKey =
          character == '-' ||
          event.logicalKey == LogicalKeyboardKey.minus ||
          event.logicalKey == LogicalKeyboardKey.numpadSubtract;
      final canUseLetterCartShortcut =
          !_searchFocusNode.hasFocus && _barcodeController.text.trim().isEmpty;

      if (isPlusKey && !_searchFocusNode.hasFocus) {
        unawaited(_increaseSelectedCartItem(cart));
        return true;
      }

      if (isMinusKey && !_searchFocusNode.hasFocus) {
        unawaited(_decreaseSelectedCartItem(cart));
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.delete &&
          !_searchFocusNode.hasFocus &&
          _barcodeController.text.trim().isEmpty) {
        unawaited(_confirmRemoveSelectedCartItem(cart));
        return true;
      }

      if (canUseLetterCartShortcut &&
          event.logicalKey == LogicalKeyboardKey.keyQ) {
        unawaited(_editSelectedCartItemQuantity(cart));
        return true;
      }

      if (canUseLetterCartShortcut &&
          event.logicalKey == LogicalKeyboardKey.keyD) {
        unawaited(_applyDiscountToSelectedCartItem(cart));
        return true;
      }

      if (canUseLetterCartShortcut &&
          event.logicalKey == LogicalKeyboardKey.keyP) {
        unawaited(_applyLabelPriceToSelectedCartItem(cart));
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_searchFocusNode.hasFocus) {
          if (_searchController.text.isNotEmpty) {
            _searchController.clear();
            setState(() {
              _searchQuery = '';
            });
          }
          _focusBarcodeField();
          return true;
        }

        if (_barcodeController.text.isNotEmpty) {
          _barcodeController.clear();
          _resetBarcodeScannerTracking();
          return true;
        }

        _focusBarcodeField();
        return true;
      }
    }

    final isEnterKey =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnterKey &&
        _activeModalCount == 0 &&
        !_searchFocusNode.hasFocus &&
        _barcodeController.text.trim().isEmpty &&
        cart.items.isNotEmpty &&
        !_isProcessingCheckout &&
        !_isPaymentDialogOpen) {
      unawaited(_handleCheckout(cart));
      return true;
    }

    return false;
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

      Future<void>.delayed(const Duration(milliseconds: 16), () {
        if (!mounted) return;
        setState(() {
          _showWelcomeOverlay = true;
        });
      });

      _welcomeOverlayTimer = Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        setState(() {
          _showWelcomeOverlay = false;
        });

        _welcomeOverlayCleanupTimer = Timer(
          const Duration(milliseconds: 220),
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
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: _showWelcomeOverlay
                  ? Offset.zero
                  : const Offset(0, -0.08),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                scale: _showWelcomeOverlay ? 1 : 0.98,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: _showWelcomeOverlay ? 1 : 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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

  void _scrollCartToIndex(int index, {bool animated = true}) {
    if (!_cartScrollController.hasClients) return;

    final maxScroll = _cartScrollController.position.maxScrollExtent;
    final target = (index * 112.0).clamp(0.0, maxScroll);

    if (animated) {
      _cartScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      _cartScrollController.jumpTo(target);
    }
  }

  void _showTemporaryCartSelection({int? selectedIndex}) {
    _cartSelectionHideTimer?.cancel();
    if (mounted) {
      setState(() {
        if (selectedIndex != null) {
          _selectedCartIndex = selectedIndex;
        }
        _isCartSelectionVisible = true;
      });
    } else {
      if (selectedIndex != null) {
        _selectedCartIndex = selectedIndex;
      }
      _isCartSelectionVisible = true;
    }

    _cartSelectionHideTimer = Timer(_cartSelectionVisibleDuration, () {
      if (!mounted) return;
      if (!_isCartSelectionVisible) return;
      setState(() {
        _isCartSelectionVisible = false;
      });
    });
  }

  void _hideCartSelection() {
    _cartSelectionHideTimer?.cancel();
    _cartSelectionHideTimer = null;
    _isCartSelectionVisible = false;
  }

  void _toggleItemLookup() {
    setState(() {
      _isLookupOpen = !_isLookupOpen;
    });

    if (_isLookupOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isLookupOpen) return;
        _searchFocusNode.requestFocus();
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
      });
    } else {
      _focusBarcodeField();
    }
  }

  void _syncCartAutoScroll(CartProvider cart) {
    final currentCount = cart.items.length;

    if (currentCount == 0) {
      _lastCartItemCount = 0;
      _selectedCartIndex = null;
      _hideCartSelection();
      return;
    }

    if (currentCount > _lastCartItemCount) {
      _selectedCartIndex = currentCount - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollCartToLatest();
      });
    } else if (_selectedCartIndex == null) {
      _selectedCartIndex = currentCount - 1;
    } else if (_selectedCartIndex! >= currentCount) {
      _selectedCartIndex = currentCount - 1;
    } else if (_selectedCartIndex! < 0) {
      _selectedCartIndex = 0;
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


  Future<void> _openCustomerPicker(CartProvider cart) async {
    if (_activeModalCount > 0) return;

    _activeModalCount += 1;
    try {
      final result = await showCustomerPickerDialog(
        context: context,
        selectedCustomer: cart.selectedCustomer,
        actorUserId: context.read<AuthProvider>().currentUser?.id,
        allowClear: true,
      );

      if (!mounted || result == null) return;

      if (result.cleared || result.customer == null) {
        cart.clearCustomer();
        _showInfoMessage(
          'Using Walk-in Customer.',
          backgroundColor: _accentBlue,
        );
      } else {
        cart.selectCustomer(result.customer!);
        _showInfoMessage(
          'Customer selected: ${result.customer!.displayName}',
          backgroundColor: _brandColor,
        );
      }
    } finally {
      _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
      if (mounted) {
        _focusBarcodeField();
      }
    }
  }

  Future<void> _openCustomerManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: PosRouteNames.customerManagement),
        builder: (context) => const CustomerManagementScreen(),
      ),
    );

    if (!mounted) return;
    _focusBarcodeField();
  }

  Widget _buildCustomerMiniPanel(CartProvider cart) {
    final customer = cart.selectedCustomer;
    final hasCustomer = customer != null;
    final tone = hasCustomer ? _brandColor : _accentBlue;
    final toneSoft = tone.withOpacity(_isDark ? 0.16 : 0.10);

    Widget miniIconButton({
      required IconData icon,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: color),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: toneSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tone.withOpacity(0.24)),
            ),
            child: Icon(
              hasCustomer ? Icons.person_rounded : Icons.storefront_rounded,
              color: tone,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openCustomerPicker(cart),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCustomer ? customer!.displayName : 'Walk-in Customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasCustomer
                          ? cart.customerDisplaySubtitle
                          : 'Ctrl + B to search / add customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          miniIconButton(
            icon: hasCustomer
                ? Icons.swap_horiz_rounded
                : Icons.person_search_rounded,
            onPressed: () => _openCustomerPicker(cart),
          ),
          if (hasCustomer)
            miniIconButton(
              icon: Icons.close_rounded,
              color: _dangerColor,
              onPressed: () {
                cart.clearCustomer();
                _showInfoMessage(
                  'Customer removed. Using Walk-in Customer.',
                  backgroundColor: _accentBlue,
                );
                _focusBarcodeField();
              },
            ),
          miniIconButton(
            icon: Icons.manage_accounts_rounded,
            onPressed: _openCustomerManagement,
          ),
        ],
      ),
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
    final printer = ReceiptPrinterService.instance;

    final printerConnected = await printer.restoreSavedPrinter();

    if (!mounted) return;

    if (printerConnected) {
      final parts = <String>[];
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

    _barcodeScannerSubmitTimer?.cancel();

    final text = value.trim();
    final now = DateTime.now();
    if (text.isEmpty) {
      _resetBarcodeScannerTracking();
      return;
    }

    final previousValue = _lastBarcodeInputValue;
    final previousAt = _lastBarcodeInputAt;
    final isGrowingInput =
        previousValue.isEmpty ||
        (value.length > previousValue.length &&
            value.startsWith(previousValue));

    if (!isGrowingInput) {
      _barcodeInputStartedAt = now;
      _rapidBarcodeInputSteps = value.length;
    } else if (previousAt == null) {
      _barcodeInputStartedAt = now;
      _rapidBarcodeInputSteps = value.length;
    } else {
      final gapMs = now.difference(previousAt).inMilliseconds;
      final addedChars = value.length - previousValue.length;
      if (gapMs <= 45) {
        _rapidBarcodeInputSteps += addedChars > 0 ? addedChars : 1;
      } else {
        _barcodeInputStartedAt = now;
        _rapidBarcodeInputSteps = addedChars > 0 ? addedChars : 1;
      }
    }

    _lastBarcodeInputAt = now;
    _lastBarcodeInputValue = value;

    if (text.length < 6) return;

    _barcodeScannerSubmitTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted) return;
      if (_barcodeController.text.trim() != text) return;
      if (_searchFocusNode.hasFocus) return;
      if (_findProductByBarcode(text) == null) return;

      final startedAt = _barcodeInputStartedAt;
      if (startedAt == null) return;

      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final maxScannerMs = text.length <= 8 ? 300 : 520;
      final minScannerSteps = text.length < 6 ? text.length : 6;
      final looksLikeScanner =
          _rapidBarcodeInputSteps >= minScannerSteps &&
          elapsedMs <= maxScannerMs;

      if (!looksLikeScanner) return;

      _handleBarcodeSubmit(cart);
    });
  }

  void _resetBarcodeScannerTracking() {
    _barcodeScannerSubmitTimer?.cancel();
    _barcodeInputStartedAt = null;
    _lastBarcodeInputAt = null;
    _lastBarcodeInputValue = '';
    _rapidBarcodeInputSteps = 0;
  }

  Future<void> _showHardwareSetupDialog() async {
    final printer = ReceiptPrinterService.instance;

    final initialPrinters = await printer.getInstalledPrinters();

    if (!mounted) return;

    _activeModalCount += 1;
    try {
      await showPremiumDialog<void>(
        context: context,
        builder: (context) {
          var printers = List<String>.from(initialPrinters);
          var isBusy = false;

          Future<void> refreshLists(StateSetter setState) async {
            setState(() {
              isBusy = true;
            });

            final nextPrinters = await printer.getInstalledPrinters();

            if (!context.mounted) return;

            setState(() {
              printers = nextPrinters;
              isBusy = false;
            });
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
              backgroundColor: response.isSuccess
                  ? _successColor
                  : _dangerColor,
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
              backgroundColor: response.isSuccess
                  ? _successColor
                  : _dangerColor,
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
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                  ),
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
    } finally {
      _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
    }

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

  void _showInfoMessage(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: backgroundColor ?? _panelSoft,
      duration: duration,
    );
  }

  TextEditingController _selectedTextController(String text) {
    return TextEditingController.fromValue(
      TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      ),
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

  String _formatStockTextWithCartUnit(Product product, num quantity) {
    if (product.isWeighted) {
      return _formatQuantityWithUnit(quantity, product.unitLabel);
    }
    return '${_formatQuantity(quantity)} pcs';
  }

  CartItem? _selectedCartItem(CartProvider cart, {bool showMessage = true}) {
    if (cart.items.isEmpty) {
      if (showMessage) {
        _showInfoMessage('Cart is empty.', backgroundColor: _warningColor);
      }
      return null;
    }

    final index =
        ((_selectedCartIndex ?? cart.items.length - 1).clamp(
              0,
              cart.items.length - 1,
            ))
            as int;
    _selectedCartIndex = index;
    _showTemporaryCartSelection();
    return cart.items[index];
  }

  void _moveCartSelection(CartProvider cart, int delta) {
    if (cart.items.isEmpty) {
      _selectedCartIndex = null;
      _hideCartSelection();
      _focusBarcodeField();
      return;
    }

    final current = _selectedCartIndex ?? cart.items.length - 1;
    final next = ((current + delta).clamp(0, cart.items.length - 1)) as int;

    _showTemporaryCartSelection(selectedIndex: next);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedCartIndex == null) return;
      _scrollCartToIndex(_selectedCartIndex!);
    });
    _focusBarcodeField();
  }

  void _jumpCartSelection(CartProvider cart, {required bool toBottom}) {
    if (cart.items.isEmpty) {
      _selectedCartIndex = null;
      _hideCartSelection();
      _focusBarcodeField();
      return;
    }

    final next = toBottom ? cart.items.length - 1 : 0;
    _showTemporaryCartSelection(selectedIndex: next);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cartScrollController.hasClients) return;
      if (toBottom) {
        _scrollCartToLatest();
      } else {
        _cartScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
    _focusBarcodeField();
  }

  double? _maxQuantityForCartItem(CartProvider cart, CartItem item) {
    if (cart.isRefundMode) return null;

    final currentStock = _getCurrentStock(
      item.product.barcode,
      fallback: item.product.stock,
    );
    final otherQtyInCart = _sanitizeQuantity(
      _getQuantityInCart(cart, item.product.barcode) - item.quantity,
    );
    return _sanitizeQuantity(currentStock - otherQtyInCart);
  }

  Future<void> _editCartItemQuantity(CartProvider cart, CartItem item) async {
    final maxQuantity = _maxQuantityForCartItem(cart, item);

    if (!cart.isRefundMode &&
        maxQuantity != null &&
        maxQuantity <= _quantityEpsilon) {
      _showInfoMessage(
        'No stock is available to increase ${item.product.name}.',
        backgroundColor: _dangerColor,
      );
      _focusBarcodeField();
      return;
    }

    final updatedQuantity = item.product.isWeighted
        ? await _promptWeightedQuantity(
            product: item.product,
            title: 'Edit ${item.product.unitLabel} quantity',
            confirmLabel: 'Update',
            initialQuantity: item.quantity,
            unitPrice: item.unitPrice,
            maxQuantity: maxQuantity,
          )
        : await _promptUnitQuantity(
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
    _showTemporaryCartSelection();
    _focusBarcodeField();
  }

  Future<void> _editSelectedCartItemQuantity(CartProvider cart) async {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    await _editCartItemQuantity(cart, item);
  }

  Future<void> _increaseSelectedCartItem(CartProvider cart) async {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    if (item.product.isWeighted) {
      await _editCartItemQuantity(cart, item);
      return;
    }

    final maxQuantity = _maxQuantityForCartItem(cart, item);
    if (maxQuantity != null &&
        _quantityExceeds(item.quantity + 1.0, maxQuantity)) {
      _showInfoMessage(
        'Cannot exceed available stock for ${item.product.name}.',
        backgroundColor: _dangerColor,
      );
      _focusBarcodeField();
      return;
    }

    cart.increaseQuantity(item);
    _showTemporaryCartSelection();
    _focusBarcodeField();
  }

  Future<void> _decreaseSelectedCartItem(CartProvider cart) async {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    if (item.product.isWeighted) {
      await _editCartItemQuantity(cart, item);
      return;
    }

    final willRemove = item.quantity <= 1 + _quantityEpsilon;
    final currentIndex = _selectedCartIndex ?? cart.items.indexOf(item);
    cart.decreaseQuantity(item);

    if (willRemove) {
      setState(() {
        _selectedCartIndex = cart.items.isEmpty
            ? null
            : (currentIndex.clamp(0, cart.items.length - 1)) as int;
      });
      if (cart.items.isEmpty) {
        _hideCartSelection();
      } else {
        _showTemporaryCartSelection();
      }
      _showInfoMessage(
        'Item removed from cart.',
        backgroundColor: _warningColor,
      );
    } else {
      _showTemporaryCartSelection();
    }

    _focusBarcodeField();
  }

  Future<bool> _showKeyboardConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    Color? confirmColor,
  }) async {
    _activeModalCount += 1;

    try {
      final tone = confirmColor ?? _brandColor;
      final toneSoft = tone.withOpacity(_isDark ? 0.18 : 0.12);
      final result = await showPremiumDialog<bool>(
        context: context,
        builder: (dialogContext) {
          void close(bool value) {
            Navigator.of(dialogContext).pop(value);
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final isEnterKey =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;

              if (isEnterKey) {
                close(true);
                return KeyEventResult.handled;
              }

              if (event.logicalKey == LogicalKeyboardKey.escape) {
                close(false);
                return KeyEventResult.handled;
              }

              return KeyEventResult.ignored;
            },
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
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
                          child: Icon(icon, color: tone, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
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
                              backgroundColor: tone,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(46),
                            ),
                            child: Text(confirmLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      return result ?? false;
    } finally {
      _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
    }
  }

  Future<void> _confirmRemoveSelectedCartItem(CartProvider cart) async {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    final confirmed = await _showKeyboardConfirmDialog(
      title: 'Remove Selected Item?',
      message: 'Remove ${item.product.name} from the current cart?',
      confirmLabel: 'Remove',
      icon: Icons.delete_outline_rounded,
      confirmColor: _dangerColor,
    );

    if (!mounted || !confirmed) {
      _focusBarcodeField();
      return;
    }

    final currentIndex = _selectedCartIndex ?? cart.items.indexOf(item);
    cart.removeItem(item);
    setState(() {
      _selectedCartIndex = cart.items.isEmpty
          ? null
          : (currentIndex.clamp(0, cart.items.length - 1)) as int;
    });
    if (cart.items.isEmpty) {
      _hideCartSelection();
    } else {
      _showTemporaryCartSelection();
    }
    _focusBarcodeField();
  }

  Future<void> _applyDiscountToSelectedCartItem(CartProvider cart) async {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    await _applyItemDiscount(cart, item);
  }


  Future<void> _applyLabelPriceToSelectedCartItem(CartProvider cart) async {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    await _applyLabelPrice(cart, item);
  }

  Future<void> _applyLabelPrice(CartProvider cart, CartItem item) async {
    if (cart.isRefundMode) {
      _showInfoMessage(
        'Label price changes are not available in refund mode.',
        backgroundColor: _warningColor,
      );
      _focusBarcodeField();
      return;
    }

    final labelPrices = await DatabaseHelper.instance.getActiveLabelPricesForProduct(
      item.product.barcode,
    );

    if (!mounted) return;

    final result = await _showLabelPriceDialog(
      item: item,
      labelPrices: labelPrices,
    );

    if (!mounted || result == null) {
      _focusBarcodeField();
      return;
    }

    final type = (result['type'] ?? '').toString();
    if (type == 'current') {
      cart.clearPriceOverride(item);
      _showTemporaryCartSelection();
      _showInfoMessage('Current product price restored.', backgroundColor: _brandColor);
      _focusBarcodeField();
      return;
    }

    final overridePrice = ((result['price'] as num?) ?? item.unitPrice).toDouble();
    final reason = (result['reason'] ?? '').toString().trim();
    final historyId = (result['price_history_id'] as num?)?.toInt();

    if (type == 'manual') {
      var approved = false;
      await _runProtectedManagerAction(() async {
        approved = true;
      });

      if (!mounted || !approved) {
        _focusBarcodeField();
        return;
      }

      cart.applyPriceOverride(
        item,
        overridePrice: overridePrice,
        overrideType: 'manual',
        reason: reason.isEmpty ? 'Manual price override' : reason,
        approvedBy: context.read<AuthProvider>().currentUser?.name,
      );
      _showTemporaryCartSelection();
      _showInfoMessage(
        'Manual price applied: Rs. ${overridePrice.toStringAsFixed(2)}',
        backgroundColor: _warningColor,
      );
      _focusBarcodeField();
      return;
    }

    if (type == 'old_label') {
      cart.applyPriceOverride(
        item,
        overridePrice: overridePrice,
        overrideType: 'old_label',
        reason: reason.isEmpty ? 'Old label price / shelf mismatch' : reason,
        priceHistoryId: historyId,
      );
      _showTemporaryCartSelection();
      _showInfoMessage(
        'Old label price applied: Rs. ${overridePrice.toStringAsFixed(2)}',
        backgroundColor: _brandColor,
      );
      _focusBarcodeField();
      return;
    }

    _focusBarcodeField();
  }

  Future<Map<String, dynamic>?> _showLabelPriceDialog({
    required CartItem item,
    required List<Map<String, dynamic>> labelPrices,
  }) async {
    final manualPriceController = TextEditingController();
    final reasonController = TextEditingController(
      text: item.priceOverrideReason.isNotEmpty
          ? item.priceOverrideReason
          : 'Old label price / shelf mismatch',
    );

    _activeModalCount += 1;

    try {
      final result = await showPremiumDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          final currentPrice = item.systemUnitPrice;
          final activeLabelPrices = labelPrices.where((row) {
            final labelPrice = ((row['label_price'] as num?) ?? 0).toDouble();
            return labelPrice > 0 &&
                (labelPrice - currentPrice).abs() > 0.000001;
          }).take(2).toList();

          void closeWithCurrentPrice() {
            Navigator.of(dialogContext).pop({
              'type': 'current',
              'price': currentPrice,
              'reason': '',
            });
          }

          void closeWithOldLabelPrice(Map<String, dynamic> row) {
            final labelPrice = ((row['label_price'] as num?) ?? 0).toDouble();
            Navigator.of(dialogContext).pop({
              'type': 'old_label',
              'price': labelPrice,
              'reason': reasonController.text.trim(),
              'price_history_id': row['id'],
            });
          }

          void closeWithManualPrice() {
            final manualPrice = double.tryParse(
              manualPriceController.text.trim(),
            );

            if (manualPrice == null || manualPrice <= 0) {
              AppSnackBar.show(
                dialogContext,
                message: 'Enter a valid manual price.',
                backgroundColor: _warningColor,
              );
              return;
            }

            Navigator.of(dialogContext).pop({
              'type': 'manual',
              'price': manualPrice,
              'reason': reasonController.text.trim().isEmpty
                  ? 'Manual price override'
                  : reasonController.text.trim(),
            });
          }

          Widget priceOption({
            required String title,
            required String subtitle,
            required double price,
            required IconData icon,
            required Color color,
            required VoidCallback onTap,
          }) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onTap,
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(_isDark ? 0.14 : 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color.withOpacity(0.28)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withOpacity(_isDark ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Rs. ${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(22),
              decoration: _panelDecoration(color: _panelColor),
              child: SingleChildScrollView(
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
                            color: _brandSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _brandColor.withOpacity(0.24),
                            ),
                          ),
                          child: Icon(
                            Icons.price_check_rounded,
                            color: _brandColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Label Price / Old Price',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.product.name} • ${item.product.barcode}',
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
                    priceOption(
                      title: 'Current system price',
                      subtitle: 'Use the latest selling price from product master.',
                      price: currentPrice,
                      icon: Icons.sell_rounded,
                      color: _accentBlue,
                      onTap: closeWithCurrentPrice,
                    ),
                    if (activeLabelPrices.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final row in activeLabelPrices) ...[
                        priceOption(
                          title: 'Old label price',
                          subtitle: 'Allowed previous shelf/item label price.',
                          price: ((row['label_price'] as num?) ?? 0).toDouble(),
                          icon: Icons.local_offer_outlined,
                          color: _brandColor,
                          onTap: () => closeWithOldLabelPrice(row),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ] else ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: _softDecoration(color: _panelSoft),
                        child: Text(
                          'No old label prices are saved for this product yet. You can enter a manual price with manager approval.',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Example: Old label price / shelf mismatch',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: manualPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Manual price',
                        hintText: 'Requires manager approval',
                      ),
                      onSubmitted: (_) => closeWithManualPrice(),
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
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: closeWithManualPrice,
                            icon: const Icon(Icons.admin_panel_settings_rounded),
                            label: const Text('Apply Manual'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      return result;
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
        manualPriceController.dispose();
        reasonController.dispose();
      });
    }
  }

  void _clearSelectedItemDiscount(CartProvider cart) {
    final item = _selectedCartItem(cart);
    if (item == null) return;

    if (item.discountAmount <= 0) {
      _showInfoMessage(
        'Selected item has no discount.',
        backgroundColor: _warningColor,
      );
      _focusBarcodeField();
      return;
    }

    cart.clearItemDiscount(item);
    _showTemporaryCartSelection();
    _focusBarcodeField();
  }

  Future<void> _confirmClearCart(CartProvider cart) async {
    if (cart.items.isEmpty) {
      _showInfoMessage(
        'Cart is already empty.',
        backgroundColor: _warningColor,
      );
      _focusBarcodeField();
      return;
    }

    final confirmed = await _showKeyboardConfirmDialog(
      title: 'Clear Whole Cart?',
      message: 'Remove every item from the current cart?',
      confirmLabel: 'Clear Cart',
      icon: Icons.delete_sweep_rounded,
      confirmColor: _dangerColor,
    );

    if (!mounted || !confirmed) {
      _focusBarcodeField();
      return;
    }

    cart.clearCart();
    setState(() {
      _selectedCartIndex = null;
      _isCartSelectionVisible = false;
    });
    _cartSelectionHideTimer?.cancel();
    _cartSelectionHideTimer = null;
    _focusBarcodeField();
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
    if (cart.isRefundMode) return;

    final now = DateTime.now();
    final previousType = cart.selectedPriceType;
    final isDoubleTap =
        _lastPriceModeTapType == newType &&
        _lastPriceModeTapAt != null &&
        now.difference(_lastPriceModeTapAt!) <= _priceModeDoubleTapWindow;

    _lastPriceModeTapType = newType;
    _lastPriceModeTapAt = now;

    if (isDoubleTap && cart.items.isNotEmpty) {
      final typeBeforeFirstTap = _lastPriceModePreviousType;
      _lastPriceModeTapType = null;
      _lastPriceModePreviousType = null;
      _lastPriceModeTapAt = null;

      final confirmed = await _confirmApplyPriceTypeToCart(newType);
      if (!mounted) return;

      if (confirmed) {
        cart.setPriceType(newType, applyToExistingItems: true);
        _showInfoMessage(
          'Whole cart switched to ${_priceTypeTitle(newType)}.',
          backgroundColor: _priceTypeColor(newType),
        );
      } else if (typeBeforeFirstTap != null &&
          typeBeforeFirstTap != cart.selectedPriceType) {
        cart.setPriceType(typeBeforeFirstTap);
      }

      _focusBarcodeField();
      return;
    }

    _lastPriceModePreviousType = previousType;

    if (cart.selectedPriceType == newType) {
      _focusBarcodeField();
      return;
    }

    cart.setPriceType(newType);

    _showInfoMessage(
      '${_priceTypeTitle(newType)} selected for new items.',
      backgroundColor: _priceTypeColor(newType),
    );
    _focusBarcodeField();
  }

  Future<bool> _confirmApplyPriceTypeToCart(ProductPriceType newType) async {
    if (_isPriceModePromptOpen) return false;

    _isPriceModePromptOpen = true;
    _activeModalCount += 1;

    var didChoose = false;

    void choose(BuildContext dialogContext, bool value) {
      if (didChoose) return;
      didChoose = true;
      Navigator.pop(dialogContext, value);
    }

    try {
      final color = _priceTypeColor(newType);
      final confirmed = await showPremiumDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final isEnterKey =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;
              if (!isEnterKey) return KeyEventResult.ignored;
              choose(dialogContext, true);
              return KeyEventResult.handled;
            },
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
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
                            color: color.withOpacity(_isDark ? 0.18 : 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: color.withOpacity(0.28)),
                          ),
                          child: Icon(
                            Icons.price_change_rounded,
                            color: color,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Switch Whole Cart?',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Apply ${_priceTypeTitle(newType)} to every item already in the cart.',
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
                          onTap: () => choose(dialogContext, false),
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
                        'This will recalculate the unit price of current cart items using ${_priceTypeTitle(newType)}. New items will also use this mode.',
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
                            onPressed: () => choose(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => choose(dialogContext, true),
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 16,
                            ),
                            label: const Text('Switch Cart'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      return confirmed ?? false;
    } finally {
      _isPriceModePromptOpen = false;
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
      });
    }
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
    _resetBarcodeScannerTracking();
    final barcode = _barcodeController.text.trim();

    if (barcode.isEmpty) {
      if (cart.items.isNotEmpty && !_isProcessingCheckout) {
        await _handleCheckout(cart);
        return;
      }

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
    final controller = _selectedTextController(
      _formatQuantity(
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

            return Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(dialogContext).pop();
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: Dialog(
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
                            textInputAction: TextInputAction.done,
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
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                  ),
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
    final controller = _selectedTextController(
      _formatQuantity(safeInitial, maxDecimals: 0),
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

            return Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(dialogContext).pop();
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: Dialog(
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
                            textInputAction: TextInputAction.done,
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
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                  ),
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

    if (!cart.isRefundMode &&
        !_expiryWarningShownBarcodes.contains(product.barcode) &&
        await DatabaseHelper.instance.hasExpiredBatchForBarcode(
          product.barcode,
        )) {
      _expiryWarningShownBarcodes.add(product.barcode);
      _showInfoMessage(
        '${product.name} has expired stock recorded. Check the shelf item before selling.',
        backgroundColor: _warningColor,
        duration: const Duration(seconds: 4),
      );
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
      _activeModalCount += 1;
      Map<String, dynamic>? result;

      try {
        result = await showCartDiscountDialog(
          context,
          subtotal: cart.discountedSubtotal,
          currentDiscountType: cart.discountType,
          currentDiscountValue: cart.discountValue,
          title: 'Apply Cart Discount',
          amountLabel: 'Discountable Total',
          totalLabel: 'Cart Total',
        );
      } finally {
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
      }

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
      _activeModalCount += 1;
      Map<String, dynamic>? result;

      try {
        result = await showCartDiscountDialog(
          context,
          subtotal: item.baseTotal,
          currentDiscountType: item.discountType,
          currentDiscountValue: item.discountValue,
          title: 'Apply Item Discount',
          amountLabel: 'Item Total',
          totalLabel: 'Line Total',
        );
      } finally {
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
      }

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
    if (cart.items.isEmpty || _isProcessingCheckout || _isPaymentDialogOpen) {
      return;
    }

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
    bool isCreditSale = false;
    String? creditApprovedBy;

    if (!isRefund) {
      _isPaymentDialogOpen = true;
      _activeModalCount += 1;
      final Map<String, dynamic>? paymentResult;
      try {
        paymentResult = await showCheckoutPaymentDialog(
          context,
          totalAmount: displayTotal,
          selectedCustomer: cart.selectedCustomer,
        );
      } finally {
        _isPaymentDialogOpen = false;
        _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
      }

      if (paymentResult == null) {
        _focusBarcodeField();
        return;
      }

      paymentMethod = paymentResult['payment_method']?.toString();
      amountTendered = (paymentResult['amount_tendered'] as num?)?.toDouble();
      changeAmount = (paymentResult['change_amount'] as num?)?.toDouble();
      isCreditSale = (paymentResult['is_credit_sale'] as bool?) ?? false;
      creditApprovedBy = paymentResult['credit_approved_by']?.toString();
    }

    setState(() {
      _isProcessingCheckout = true;
    });

    BuildContext? processingDialogContext;

    try {
      processingDialogContext = await _showCheckoutProcessingOverlay(
        isRefund: isRefund,
      );

      // DatabaseHelper currently validates only the normal tender methods
      // used by the base sale save flow. For customer credit, save the base
      // transaction through the safe card path first, then postCreditSale()
      // immediately updates the saved sale to payment_method = customer_credit
      // and creates the ledger entry.
      final baseSalePaymentMethod = isCreditSale ? 'card' : paymentMethod;

      final saleId = await DatabaseHelper.instance.processTransaction(
        subtotalAmount: subtotal,
        totalAmount: displayTotal,
        cartItems: itemsMap,
        cashierName: cashierName,
        isRefund: isRefund,
        paymentMethod: baseSalePaymentMethod,
        amountTendered: amountTendered,
        changeAmount: changeAmount,
        discountType: cart.discountType,
        discountValue: cart.discountValue,
        discountAmount: discountAmount,
      );

      await CustomerService.instance.attachCustomerToSale(
        saleId: saleId,
        customer: cart.selectedCustomer,
      );

      if (isCreditSale) {
        final selectedCustomer = cart.selectedCustomer;
        if (selectedCustomer == null || selectedCustomer.id == null) {
          throw Exception('Select a customer to use Customer Credit.');
        }

        await CustomerCreditService.instance.postCreditSale(
          customerId: selectedCustomer.id!,
          saleId: saleId,
          amount: displayTotal,
          cashierName: cashierName,
          approvedBy: creditApprovedBy,
          managerApproved: creditApprovedBy != null &&
              creditApprovedBy.trim().isNotEmpty,
        );
      }

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
        _focusBarcodeField();
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
    final tone = isRefund ? _dangerColor : _brandColor;
    final toneSoft = isRefund ? _dangerSoft : _brandSoft;
    var successDismissed = false;

    void dismissSuccess(BuildContext successContext, String action) {
      if (successDismissed) return;
      successDismissed = true;
      Navigator.of(successContext).pop(action);
    }

    final result = await showPremiumDialog<String>(
      context: dialogContext,
      barrierDismissible: false,
      includeBackdrop: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      builder: (successContext) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final isEnterKey =
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter;
          if (event is KeyDownEvent && isEnterKey) {
            dismissSuccess(successContext, 'next');
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
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
                        onPressed: () => dismissSuccess(successContext, 'next'),
                        child: const Text('Next Customer'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            dismissSuccess(successContext, 'receipt'),
                        child: const Text('View Receipt'),
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
      MaterialPageRoute(
        settings: const RouteSettings(name: PosRouteNames.userManagement),
        builder: (context) => const UserManagementScreen(),
      ),
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
          settings: const RouteSettings(name: PosRouteNames.supplierManagement),
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
        settings: const RouteSettings(name: PosRouteNames.shiftManagement),
        builder: (context) => ShiftManagementScreen(cashierName: cashierName),
      ),
    );

    await _loadShiftSummary();
    _focusBarcodeField();
  }

  Future<void> _holdCurrentCart(CartProvider cart) async {
    if (cart.items.isEmpty) return;

    final selectedCustomer = cart.selectedCustomer;
    final defaultCartName = selectedCustomer == null
        ? ''
        : selectedCustomer.displayName.trim();

    final controller = TextEditingController(text: defaultCartName);
    _activeModalCount += 1;

    String? cartName;
    try {
      cartName = await showPremiumDialog<String>(
        context: context,
        builder: (dialogContext) {
          return Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;

              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.pop(dialogContext);
                return KeyEventResult.handled;
              }

              return KeyEventResult.ignored;
            },
            child: Dialog(
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
                                  hintText:
                                      selectedCustomer == null
                                          ? 'Example: Customer 1 / Counter Hold'
                                          : 'Customer name is already filled. Press Enter or edit if needed.',
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
            ),
          );
        },
      );
    } finally {
      _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
    }

    Future<void>.delayed(const Duration(milliseconds: 320), controller.dispose);

    if (cartName == null) {
      _focusBarcodeField();
      return;
    }

    final cashierName =
        context.read<AuthProvider>().currentUser?.name ?? 'Unknown';

    try {
      final resolvedCartName = cartName.trim().isEmpty
          ? (cart.selectedCustomer?.displayName.trim().isNotEmpty == true
              ? cart.selectedCustomer!.displayName.trim()
              : 'Held Cart')
          : cartName.trim();

      await DatabaseHelper.instance.saveHeldCart(
        cartName: resolvedCartName,
        cashierName: cashierName,
        isRefundMode: cart.isRefundMode,
        discountType: cart.discountType,
        discountValue: cart.discountValue,
        items: cart.getCartItemsAsMap(),
        selectedPriceType: cart.selectedPriceType.dbValue,
      );

      await CustomerService.instance.saveCustomerSnapshotToLatestHeldCart(
        cartName: resolvedCartName,
        cashierName: cashierName,
        customer: cart.selectedCustomer,
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
    _activeModalCount += 1;
    var didChoose = false;

    void choose(BuildContext dialogContext, bool value) {
      if (didChoose) return;
      didChoose = true;
      Navigator.of(dialogContext, rootNavigator: true).pop(value);
    }

    try {
      final confirmed = await showPremiumDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final isEnterKey =
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter;
              if (!isEnterKey) return KeyEventResult.ignored;
              choose(dialogContext, true);
              return KeyEventResult.handled;
            },
            child: Dialog(
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
                          onTap: () => choose(dialogContext, false),
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
                            onPressed: () => choose(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => choose(dialogContext, true),
                            icon: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 16,
                            ),
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
            ),
          );
        },
      );

      return confirmed ?? false;
    } finally {
      _activeModalCount = ((_activeModalCount - 1).clamp(0, 999999)) as int;
    }
  }

  List<Map<String, dynamic>> _prepareResumedCartItems(
    List<Map<String, dynamic>> rawItems, {
    String fallbackPriceType = 'selling',
  }) {
    return rawItems.expand<Map<String, dynamic>>((raw) {
      final item = Map<String, dynamic>.from(raw);
      final rawProduct = item['product'];
      if (rawProduct is! Map) {
        return const <Map<String, dynamic>>[];
      }
      final productMap = Map<String, dynamic>.from(rawProduct);
      final barcode = productMap['barcode']?.toString() ?? '';
      final name = productMap['name']?.toString().trim() ?? '';
      if (barcode.trim().isEmpty || name.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final safeQuantity = quantity <= _quantityEpsilon ? 1.0 : quantity;

      final latestProduct = _getCurrentProduct(barcode);
      final resolvedProductMap = latestProduct?.toMap() ?? productMap;
      Product? resolvedProduct = latestProduct;
      if (resolvedProduct == null) {
        try {
          resolvedProduct = Product.fromMap(resolvedProductMap);
        } catch (_) {
          return const <Map<String, dynamic>>[];
        }
      }

      final priceTypeUsed = (item['price_type_used'] ?? fallbackPriceType)
          .toString();
      final resolvedUnitPrice =
          (item['unit_price_used'] as num?)?.toDouble() ??
          resolvedProduct!.resolvePrice(
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

      return [
        {
          'product': resolvedProductMap,
          'quantity': safeQuantity,
          'unit_price_used': resolvedUnitPrice,
          'price_type_used': priceTypeUsed,
          'base_line_total': baseLineTotal,
          'item_discount_type': itemDiscountType,
          'item_discount_value': itemDiscountValue,
          'item_discount_amount': itemDiscountAmount,
          'line_total': resolvedLineTotal < 0 ? 0.0 : resolvedLineTotal,
        },
      ];
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
        settings: const RouteSettings(name: PosRouteNames.heldCarts),
        builder: (context) => HeldCartsScreen(cashierName: cashierName),
      ),
    );

    if (!mounted || restored == null) {
      _focusBarcodeField();
      return;
    }

    final resumeError = (restored['resume_error'] ?? '').toString().trim();
    if (resumeError.isNotEmpty) {
      _showInfoMessage(resumeError, backgroundColor: _dangerColor);
      _focusBarcodeField();
      return;
    }

    final restoredRawItems = restored['items'];
    final restoredItems = restoredRawItems is List
        ? restoredRawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    final restoredSelectedPriceType =
        (restored['selected_price_type'] ?? 'selling').toString();

    final preparedItems = _prepareResumedCartItems(
      restoredItems,
      fallbackPriceType: restoredSelectedPriceType,
    );

    if (preparedItems.isEmpty) {
      _showInfoMessage(
        'Held cart could not be restored because its saved items are invalid.',
        backgroundColor: _dangerColor,
      );
      _focusBarcodeField();
      return;
    }

    final restoredCustomer =
        CustomerService.instance.customerFromHeldCartRow(restored);

    cart.loadHeldCart(
      items: preparedItems,
      isRefundMode: (restored['is_refund_mode'] ?? false) == true,
      discountType: (restored['discount_type'] ?? 'none').toString(),
      discountValue: ((restored['discount_value'] as num?) ?? 0).toDouble(),
      selectedPriceType: restoredSelectedPriceType,
      selectedCustomer: restoredCustomer,
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
            settings: const RouteSettings(name: PosRouteNames.cashierSummary),
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
          MaterialPageRoute(
            settings: const RouteSettings(name: PosRouteNames.inventory),
            builder: (context) => const InventoryScreen(),
          ),
        );
        break;
      case 'expiry_alerts':
        await Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: PosRouteNames.expiryAlerts),
            builder: (context) => const ExpiryAlertsScreen(),
          ),
        );
        break;
      case 'supplier_ops':
        await _openSupplierOperations();
        break;
      case 'transaction_history':
        await Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(
              name: PosRouteNames.transactionHistory,
            ),
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
          MaterialPageRoute(
            settings: const RouteSettings(name: PosRouteNames.salesReport),
            builder: (context) => const SalesReportScreen(),
          ),
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
        return Icons.print_rounded;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'expiry_alerts':
        return Icons.event_busy_outlined;
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
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: IconButton(
                            tooltip: 'Clear barcode',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: _panelSoft,
                              foregroundColor: _mutedIcon,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              _resetBarcodeScannerTracking();
                              _barcodeController.clear();
                              setState(() {});
                              _focusBarcodeField();
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 42,
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
                const MapEntry('expiry_alerts', 'Expiry Alerts'),
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
                MaterialPageRoute(
                  settings: const RouteSettings(name: PosRouteNames.login),
                  builder: (context) => const LoginScreen(),
                ),
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
                      'Item Lookup',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Search, scan, or tap products.',
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
                  tooltip: 'Hide item lookup (F7)',
                  icon: Icons.keyboard_double_arrow_left_rounded,
                  onPressed: _toggleItemLookup,
                  iconColor: _brandColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.done,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onSubmitted: (_) {
                final cart = context.read<CartProvider>();
                final matches = List<Product>.from(_filteredProducts);
                if (matches.length == 1) {
                  unawaited(() async {
                    await _handleProductTap(matches.first, cart);
                    if (!mounted) return;
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                    _focusBarcodeField();
                  }());
                  return;
                }
                _focusBarcodeField();
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
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: IconButton(
                            tooltip: 'Clear search',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 34,
                              height: 34,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: _panelSoft,
                              foregroundColor: _mutedIcon,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                              _focusBarcodeField();
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 42,
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

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _filteredProducts.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, thickness: 1, color: _borderColor),
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        return _buildProductCard(product, cart);
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: toneSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isOutOfStock
                              ? Icons.remove_shopping_cart_rounded
                              : Icons.inventory_2_rounded,
                          color: tone,
                          size: 18,
                        ),
                      ),
                    ),
                    if (cartQty > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _brandColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _panelAlt, width: 1.4),
                          ),
                          child: Text(
                            _formatQuantity(cartQty),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        height: 1.16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRect(
                            child: Text(
                              product.barcode,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 9.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 68,
                          child: Text(
                            isOutOfStock
                                ? 'Out'
                                : (isLowStock
                                      ? 'Low ${_formatStockText(product, product.stock)}'
                                      : _formatStockText(
                                          product,
                                          product.stock,
                                        )),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: tone,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 104,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                product.isWeighted
                                    ? 'Rs. ${displayPrice.toStringAsFixed(2)} / ${product.unitLabel}'
                                    : 'Rs. ${displayPrice.toStringAsFixed(2)}',
                                maxLines: 1,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: isOutOfStock
                                      ? _textSecondary
                                      : _brandColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.add_rounded,
                color: isOutOfStock ? _mutedIcon : tone,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel(CartProvider cart, {bool includeSummary = true}) {
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
                        cart.isRefundMode ? 'Refund Bill' : 'Current Bill',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cart.items.length} ${cart.items.length == 1 ? 'line' : 'lines'} ready for checkout',
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
              margin: EdgeInsets.fromLTRB(12, 0, 12, includeSummary ? 0 : 12),
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
                        return _buildCartItemRow(
                          cart,
                          item,
                          index: index,
                          isSelected:
                              _isCartSelectionVisible &&
                              _selectedCartIndex == index,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemCount: cart.items.length,
                    ),
            ),
          ),
          if (includeSummary)
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

  Widget _buildCartItemRow(
    CartProvider cart,
    CartItem item, {
    required int index,
    required bool isSelected,
  }) {
    final currentStock = _getCurrentStock(
      item.product.barcode,
      fallback: item.product.stock,
    );

    final selectedColor = cart.isRefundMode ? _dangerColor : _brandColor;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        _showTemporaryCartSelection(selectedIndex: index);
        _focusBarcodeField();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withOpacity(_isDark ? 0.18 : 0.10)
              : _panelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? selectedColor : _borderColor,
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withOpacity(_isDark ? 0.16 : 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
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
                  tooltip: item.hasPriceOverride
                      ? 'Edit label price'
                      : 'Apply label price',
                  onPressed: cart.isRefundMode
                      ? null
                      : () => _applyLabelPrice(cart, item),
                  icon: Icon(
                    Icons.price_change_outlined,
                    color: item.hasPriceOverride
                        ? _brandColor
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
            if (item.hasPriceOverride) ...[
              const SizedBox(height: 3),
              Text(
                item.priceOverrideType == 'old_label'
                    ? 'Old label price • System Rs. ${item.systemUnitPrice.toStringAsFixed(2)}'
                    : 'Manual price • System Rs. ${item.systemUnitPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  color: _brandColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.8,
                ),
              ),
            ],
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
            value: 'Rs. ${cart.discountedSubtotal.toStringAsFixed(2)}',
          ),
          _buildSummaryLine(
            label: 'Discount',
            value: 'Rs. ${cart.cartLevelDiscountAmount.toStringAsFixed(2)}',
            valueColor: cart.cartLevelDiscountAmount > 0
                ? _dangerColor
                : _textPrimary,
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
            OutlinedButton.icon(
              onPressed: cart.items.isEmpty ? null : () => _applyDiscount(cart),
              icon: const Icon(Icons.percent_rounded, size: 14),
              label: Text(
                cart.cartLevelDiscountAmount > 0
                    ? 'Edit Discount'
                    : 'Apply Discount',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(34),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: cart.cartLevelDiscountAmount > 0
                  ? () {
                      cart.clearDiscount();
                      _focusBarcodeField();
                    }
                  : null,
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('Clear Discount'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(34),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          OutlinedButton.icon(
            onPressed: cart.items.isEmpty ? null : () => _holdCurrentCart(cart),
            icon: const Icon(Icons.pause_circle_outline_rounded, size: 14),
            label: const Text('Hold Cart'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(34),
              padding: const EdgeInsets.symmetric(vertical: 8),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _openHeldCarts(cart),
            icon: const Icon(Icons.shopping_bag_outlined, size: 14),
            label: const Text('Held Carts'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(34),
              padding: const EdgeInsets.symmetric(vertical: 8),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
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
              minimumSize: const Size.fromHeight(34),
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

  Widget _buildCheckoutRail(CartProvider cart) {
    final modeColor = cart.isRefundMode ? _dangerColor : _brandColor;
    final modeSoft = cart.isRefundMode ? _dangerSoft : _brandSoft;

    return Container(
      decoration: _panelDecoration(color: _panelColor),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: modeSoft,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: modeColor.withOpacity(0.20)),
                  ),
                  child: Icon(
                    cart.isRefundMode
                        ? Icons.restart_alt_rounded
                        : Icons.point_of_sale_rounded,
                    color: modeColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checkout',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cart.isRefundMode
                            ? 'Review refund and complete.'
                            : 'Tender, hold, discount, and pay.',
                        style: TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCustomerMiniPanel(cart),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _panelAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  _buildCheckoutStat(
                    label: 'Lines',
                    value: cart.items.length.toString(),
                  ),
                  Container(width: 1, height: 32, color: _borderColor),
                  _buildCheckoutStat(
                    label: 'Items',
                    value: _formatQuantity(
                      cart.items.fold<double>(
                        0,
                        (sum, item) => sum + item.quantity,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(child: _buildSummarySection(cart)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutStat({required String label, required String value}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: _isLookupOpen ? _catalogRailWidth : 0,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: _catalogRailWidth,
                      maxWidth: _catalogRailWidth,
                      child: SizedBox(
                        width: _catalogRailWidth,
                        child: _buildCatalogPanel(cart),
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: _isLookupOpen ? 14 : 0,
                ),
                Expanded(child: _buildCartPanel(cart, includeSummary: false)),
                const SizedBox(width: 14),
                SizedBox(
                  width: _checkoutRailWidth,
                  child: _buildCheckoutRail(cart),
                ),
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
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _focusBarcodeField,
            child: SafeArea(
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
      ),
    );
  }
}
