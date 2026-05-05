
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/database_helper.dart';
import '../widgets/app_snackbar.dart';

class HeldCartsScreen extends StatefulWidget {
  final String cashierName;

  const HeldCartsScreen({
    super.key,
    required this.cashierName,
  });

  @override
  State<HeldCartsScreen> createState() => _HeldCartsScreenState();
}

class _HeldCartsScreenState extends State<HeldCartsScreen> {
  static const double _quantityEpsilon = 0.000001;
  static const Duration _heldCartDoubleTapWindow = Duration(milliseconds: 650);
  static const Duration _heldSelectionVisibleDuration = Duration(seconds: 2);
  static final Map<LogicalKeyboardKey, int> _numberKeys = {
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _heldSelectionHideTimer;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isResumingHeldCart = false;
  bool _isDeleteDialogOpen = false;
  int? _selectedCartIndex;
  bool _isHeldSelectionVisible = false;
  int? _lastNumberShortcut;
  DateTime? _lastNumberShortcutAt;
  List<Map<String, dynamic>> _heldCarts = [];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page => _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _surface => _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get _surfaceSoft => _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _inputFill => _isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC);
  Color get _border => _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _textPrimary => _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary => _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _textMuted => _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _brand => const Color(0xFF2AAA8A);
  Color get _brandSoft => _brand.withOpacity(_isDark ? 0.16 : 0.10);
  Color get _danger => const Color(0xFFFF6B7A);
  Color get _dangerSoft => _danger.withOpacity(_isDark ? 0.20 : 0.12);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyboardEvent);
    _loadHeldCarts();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyboardEvent);
    _heldSelectionHideTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _handleHardwareKeyboardEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !mounted ||
        _isLoading ||
        _isResumingHeldCart ||
        _isDeleteDialogOpen) {
      return false;
    }

    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final keyboard = HardwareKeyboard.instance;
    if (_searchFocusNode.hasFocus) return false;

    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    final selectedNumber = _numberKeys[event.logicalKey];
    if (selectedNumber != null) {
      final carts = _filteredCarts;
      final index = selectedNumber - 1;
      if (index < 0 || index >= carts.length) return true;

      final now = DateTime.now();
      final wasAlreadySelected = _selectedCartIndex == index;
      final isDoubleTap = _lastNumberShortcut == selectedNumber &&
          wasAlreadySelected &&
          _lastNumberShortcutAt != null &&
          now.difference(_lastNumberShortcutAt!) <= _heldCartDoubleTapWindow;

      _lastNumberShortcut = selectedNumber;
      _lastNumberShortcutAt = now;
      _selectHeldCart(index);

      if (isDoubleTap) {
        _lastNumberShortcut = null;
        _lastNumberShortcutAt = null;
        _resumeHeldCart((carts[index]['id'] as num).toInt());
      }

      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHeldCartSelection(-1);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHeldCartSelection(1);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _selectHeldCart(0);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      final carts = _filteredCarts;
      if (carts.isNotEmpty) _selectHeldCart(carts.length - 1);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _resumeSelectedHeldCart();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _deleteSelectedHeldCart();
      return true;
    }

    return false;
  }

  void _syncSelectedCartIndex() {
    final carts = _filteredCarts;
    if (carts.isEmpty) {
      _selectedCartIndex = null;
      _hideHeldSelection();
      return;
    }

    final current = _selectedCartIndex ?? 0;
    _selectedCartIndex = (current.clamp(0, carts.length - 1)) as int;
  }

  void _showTemporaryHeldSelection({int? selectedIndex}) {
    _heldSelectionHideTimer?.cancel();
    if (mounted) {
      setState(() {
        if (selectedIndex != null) {
          _selectedCartIndex = selectedIndex;
        }
        _isHeldSelectionVisible = true;
      });
    } else {
      if (selectedIndex != null) {
        _selectedCartIndex = selectedIndex;
      }
      _isHeldSelectionVisible = true;
    }

    _heldSelectionHideTimer = Timer(_heldSelectionVisibleDuration, () {
      if (!mounted) return;
      if (!_isHeldSelectionVisible) return;
      setState(() {
        _isHeldSelectionVisible = false;
      });
    });
  }

  void _hideHeldSelection() {
    _heldSelectionHideTimer?.cancel();
    _heldSelectionHideTimer = null;
    _isHeldSelectionVisible = false;
  }

  void _selectHeldCart(int index, {bool showSelection = true}) {
    final carts = _filteredCarts;
    if (carts.isEmpty) return;

    final next = (index.clamp(0, carts.length - 1)) as int;
    if (showSelection) {
      _showTemporaryHeldSelection(selectedIndex: next);
    } else {
      _selectedCartIndex = next;
    }
  }

  void _moveHeldCartSelection(int delta) {
    final carts = _filteredCarts;
    if (carts.isEmpty) return;

    final current = _selectedCartIndex ?? 0;
    _selectHeldCart(current + delta);
  }

  Map<String, dynamic>? _selectedHeldCart() {
    final carts = _filteredCarts;
    if (carts.isEmpty) return null;

    final index = ((_selectedCartIndex ?? 0).clamp(0, carts.length - 1)) as int;
    _showTemporaryHeldSelection(selectedIndex: index);
    return carts[index];
  }

  void _resumeSelectedHeldCart() {
    final cart = _selectedHeldCart();
    if (cart == null) return;

    _resumeHeldCart((cart['id'] as num).toInt());
  }

  void _deleteSelectedHeldCart() {
    final cart = _selectedHeldCart();
    if (cart == null) return;

    _deleteHeldCart(
      (cart['id'] as num).toInt(),
      (cart['cart_name'] ?? 'Held Cart').toString(),
    );
  }

  Future<void> _loadHeldCarts() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    final carts =
        await DatabaseHelper.instance.getHeldCartsForCashier(widget.cashierName);

    if (!mounted) return;

    setState(() {
      _heldCarts = carts;
      _isLoading = false;
      _syncSelectedCartIndex();
    });
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      await _loadHeldCarts();
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCarts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _heldCarts;

    return _heldCarts.where((cart) {
      final cartName = (cart['cart_name'] ?? 'Held Cart').toString().toLowerCase();
      final type = ((cart['is_refund_mode'] ?? false) == true ? 'refund' : 'sale');
      final itemCount = _formatQuantity((cart['item_count'] as num?) ?? 0);
      final totalAmount = ((cart['total_amount'] as num?) ?? 0).toDouble();
      final totalText = totalAmount.toStringAsFixed(2);
      final updatedAt = _formatDateTime((cart['updated_at'] ?? '').toString()).toLowerCase();

      return cartName.contains(query) ||
          type.contains(query) ||
          itemCount.contains(query) ||
          totalText.contains(query) ||
          updatedAt.contains(query);
    }).toList();
  }

  String _formatDateTime(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d  $h:$min';
    } catch (_) {
      return raw;
    }
  }

  String _formatQuantity(num value, {int maxDecimals = 3}) {
    final safeValue =
        value.toDouble().abs() < _quantityEpsilon ? 0.0 : value.toDouble();
    return safeValue.toStringAsFixed(maxDecimals).replaceFirst(
      RegExp(r'\.?0+$'),
      '',
    );
  }

  BoxDecoration _panelDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? _surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(_isDark ? 0.22 : 0.04),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: 'Search held bill by name, type, amount, or saved date',
      prefixIcon: Icon(Icons.search_rounded, color: _textMuted, size: 20),
      suffixIcon: _searchController.text.isEmpty
          ? null
          : IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _syncSelectedCartIndex();
                });
              },
              icon: Icon(Icons.close_rounded, color: _textMuted),
            ),
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _brand, width: 1.4),
      ),
      hintStyle: TextStyle(
        color: _textSecondary.withOpacity(0.85),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Future<void> _resumeHeldCart(int heldCartId) async {
    if (_isResumingHeldCart) return;

    setState(() {
      _isResumingHeldCart = true;
    });

    final Map<String, dynamic>? restored;
    try {
      restored = await DatabaseHelper.instance.resumeHeldCart(
        heldCartId,
        cashierName: widget.cashierName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResumingHeldCart = false;
      });
      AppSnackBar.show(
        context,
        message: e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _danger,
      );
      return;
    }

    if (!mounted) return;

    if (restored == null) {
      setState(() {
        _isResumingHeldCart = false;
      });
      AppSnackBar.show(
        context,
        message: 'Held bill not found.',
        backgroundColor: _danger,
      );
      return;
    }

    Navigator.pop(context, restored);
  }

  Future<bool> _showDeleteDialog(String cartName) async {
    _isDeleteDialogOpen = true;
    try {
      final result = await showGeneralDialog<bool>(
        context: context,
        barrierLabel: 'Delete held bill',
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(_isDark ? 0.34 : 0.24),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          var isClosing = false;

          void close(bool value) {
            if (isClosing) return;
            isClosing = true;
            Navigator.of(dialogContext).pop(value);
          }

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final isEnterKey = event.logicalKey == LogicalKeyboardKey.enter ||
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
            child: StatefulBuilder(
              builder: (context, setState) {
                return BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 440),
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          decoration: _panelDecoration(color: _surface),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 46,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: _border,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: _dangerSoft,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _danger.withOpacity(0.24),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      color: _danger,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Delete Held Bill',
                                          style: TextStyle(
                                            color: _textPrimary,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This will permanently remove this held bill.',
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
                                ],
                              ),
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _surfaceSoft,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: _border),
                                ),
                                child: Text(
                                  cartName,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => close(false),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _textPrimary,
                                        side: BorderSide(color: _border),
                                        padding: const EdgeInsets.symmetric(vertical: 15),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => close(true),
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        backgroundColor: _danger,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 15),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Text('Delete Bill'),
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
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );

      return result ?? false;
    } finally {
      _isDeleteDialogOpen = false;
    }
  }

  Future<void> _deleteHeldCart(int heldCartId, String cartName) async {
    final confirmed = await _showDeleteDialog(cartName);
    if (!confirmed) return;

    await DatabaseHelper.instance.deleteHeldCart(
      heldCartId,
      cashierName: widget.cashierName,
    );

    if (!mounted) return;

    AppSnackBar.show(
      context,
      message: 'Held bill deleted.',
      backgroundColor: _brand,
    );

    await _loadHeldCarts();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(color: _surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Held Bills',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: _searchDecoration(),
            onChanged: (_) => setState(() {
              _syncSelectedCartIndex();
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${_filteredCarts.length} held ${_filteredCarts.length == 1 ? 'bill' : 'bills'}',
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (_isRefreshing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brand,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaDot() {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: _textMuted.withOpacity(0.75),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _buildCartRow(
    Map<String, dynamic> cart, {
    int? shortcutNumber,
    required bool isSelected,
  }) {
    final id = (cart['id'] as num).toInt();
    final cartName = (cart['cart_name'] ?? 'Held Cart').toString();
    final isRefundMode = (cart['is_refund_mode'] ?? false) == true;
    final itemCount = _formatQuantity((cart['item_count'] as num?) ?? 0);
    final totalAmount = ((cart['total_amount'] as num?) ?? 0).toDouble();
    final updatedAt = (cart['updated_at'] ?? '').toString();

    final modeColor = isRefundMode ? _danger : _brand;
    final modeSoft = isRefundMode ? _dangerSoft : _brandSoft;
    final selectedColor = isRefundMode ? _danger : _brand;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _resumeHeldCart(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor.withOpacity(_isDark ? 0.16 : 0.08) : _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected ? selectedColor : _border,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: selectedColor.withOpacity(_isDark ? 0.14 : 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: modeSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isRefundMode ? Icons.restart_alt_rounded : Icons.receipt_long_rounded,
                      color: modeColor,
                      size: 22,
                    ),
                  ),
                  if (shortcutNumber != null)
                    Positioned(
                      top: -7,
                      left: -7,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _brand,
                          shape: BoxShape.circle,
                          border: Border.all(color: _surface, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '$shortcutNumber',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cartName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: modeSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: modeColor.withOpacity(0.22)),
                          ),
                          child: Text(
                            isRefundMode ? 'Refund' : 'Sale',
                            style: TextStyle(
                              color: modeColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _deleteHeldCart(id, cartName),
                          child: Ink(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _surfaceSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border),
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: _danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$itemCount ${itemCount == '1' ? 'item' : 'items'}',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        _buildMetaDot(),
                        Text(
                          'Rs. ${totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        _buildMetaDot(),
                        Text(
                          'Saved ${_formatDateTime(updatedAt)}',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      shortcutNumber == null
                          ? 'Enter resumes selected bill. Delete removes it.'
                          : 'Press $shortcutNumber to select. Press twice to resume.',
                      style: TextStyle(
                        color: _textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
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

  Widget _buildEmptyState({required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: _panelDecoration(color: _surface),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              color: _textMuted,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _page,
        foregroundColor: _textPrimary,
        title: const Text('Held Bills'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _brand))
          : RefreshIndicator(
              onRefresh: _refresh,
              color: _brand,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  if (_heldCarts.isEmpty)
                    _buildEmptyState(message: 'No held bills found.')
                  else if (_filteredCarts.isEmpty)
                    _buildEmptyState(message: 'No held bills match your search.')
                  else
                    ..._filteredCarts.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCartRow(
                          entry.value,
                          shortcutNumber: entry.key < 9 ? entry.key + 1 : null,
                          isSelected:
                              _isHeldSelectionVisible && _selectedCartIndex == entry.key,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
