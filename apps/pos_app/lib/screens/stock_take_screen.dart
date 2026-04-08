
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/models/product.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';

enum StockTakeFilter {
  all,
  counted,
  discrepancies,
  uncounted,
}

class _StockTakeApprovalResult {
  const _StockTakeApprovalResult({
    required this.approverId,
    required this.approverName,
  });

  final int approverId;
  final String approverName;
}

class StockTakeScreen extends StatefulWidget {
  const StockTakeScreen({
    super.key,
    this.initialBarcode,
    this.performedByLabel,
  });

  final String? initialBarcode;
  final String? performedByLabel;

  @override
  State<StockTakeScreen> createState() => _StockTakeScreenState();
}

class _StockTakeScreenState extends State<StockTakeScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _sessionNameController = TextEditingController();

  bool _isLoading = true;
  bool _isApplying = false;
  int? _sessionId;
  String _startedAt = '';
  String _searchQuery = '';
  StockTakeFilter _selectedFilter = StockTakeFilter.all;

  List<Product> _products = [];
  Map<String, int> _countedQuantities = {};

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _page => _isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
  Color get _pageAlt => _isDark ? const Color(0xFF0B1729) : const Color(0xFFFFFFFF);
  Color get _surface => _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get _surfaceSoft => _isDark ? const Color(0xFF14243C) : const Color(0xFFF8FAFD);
  Color get _surfaceAlt => _isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get _inputFill => _isDark ? const Color(0xFF0B1628) : const Color(0xFFF7F9FC);
  Color get _border => _isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get _borderStrong => _isDark ? const Color(0xFF31445E) : const Color(0xFFCED9E5);
  Color get _textPrimary => _isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get _textSecondary => _isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get _textMuted => _isDark ? const Color(0xFF7F92AC) : const Color(0xFF778BA4);
  Color get _brand => const Color(0xFF2AAA8A);
  Color get _brandSoft => _brand.withOpacity(_isDark ? 0.16 : 0.10);
  Color get _blue => const Color(0xFF4B8DFF);
  Color get _blueSoft => _blue.withOpacity(_isDark ? 0.18 : 0.10);
  Color get _success => const Color(0xFF1FCF9A);
  Color get _successSoft => _success.withOpacity(_isDark ? 0.18 : 0.12);
  Color get _warning => const Color(0xFFFFB65C);
  Color get _warningSoft => _warning.withOpacity(_isDark ? 0.20 : 0.14);
  Color get _danger => const Color(0xFFFF6B7A);
  Color get _dangerSoft => _danger.withOpacity(_isDark ? 0.20 : 0.12);
  Color get _shadowColor => Colors.black.withOpacity(_isDark ? 0.24 : 0.0);

  @override
  void initState() {
    super.initState();
    _loadSession(showLoader: true);
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _searchController.dispose();
    _sessionNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSession({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final products = await DatabaseHelper.instance.getProducts();
      final session = await DatabaseHelper.instance.getOrCreateOpenStockTakeSession();
      final sessionId = (session['id'] as num).toInt();
      final items = await DatabaseHelper.instance.getStockTakeSessionItems(sessionId);

      final counted = <String, int>{};
      for (final item in items) {
        counted[(item['barcode'] ?? '').toString()] =
            (item['counted_stock'] as num?)?.toInt() ?? 0;
      }

      if (!mounted) return;

      setState(() {
        _products = products;
        _sessionId = sessionId;
        _sessionNameController.text =
            (session['session_name'] ?? 'Main Store Count').toString();
        _startedAt = (session['started_at'] ?? '').toString();
        _countedQuantities = counted;
        _isLoading = false;
      });

      if (widget.initialBarcode != null && widget.initialBarcode!.trim().isNotEmpty) {
        _barcodeController.text = widget.initialBarcode!.trim();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage('Could not load stock take session.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _danger : _surfaceSoft,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  BoxDecoration _panelDecoration({Color? color, double radius = 24}) {
    return BoxDecoration(
      color: color ?? _surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: _shadowColor,
          blurRadius: 26,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  BoxDecoration _softDecoration({Color? color, double radius = 18}) {
    return BoxDecoration(
      color: color ?? _surfaceSoft,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _border),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? labelText,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _textMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
      labelStyle: TextStyle(color: _textSecondary, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: _textSecondary.withOpacity(0.84), fontWeight: FontWeight.w500),
    );
  }

  Future<bool> _showDecisionDialog({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
    IconData icon = Icons.help_outline_rounded,
    Color? tone,
  }) async {
    final actionTone = tone ?? (destructive ? _danger : _brand);

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierLabel: title,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(_isDark ? 0.34 : 0.22),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
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
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: actionTone.withOpacity(_isDark ? 0.18 : 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: actionTone.withOpacity(0.24)),
                            ),
                            child: Icon(icon, color: actionTone, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: _softDecoration(color: _surfaceSoft),
                        child: Text(
                          message,
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
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textPrimary,
                                side: BorderSide(color: _borderStrong),
                                minimumSize: const Size.fromHeight(52),
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
                              onPressed: () => Navigator.pop(dialogContext, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: actionTone,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(confirmText),
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
  }

  String? _validateCount(String rawValue, {bool allowZero = true}) {
    final value = int.tryParse(rawValue.trim());
    if (value == null) return 'Enter a valid counted quantity.';
    if (allowZero) {
      if (value < 0) return 'Counted quantity cannot be negative.';
    } else if (value <= 0) {
      return 'Counted quantity must be greater than 0.';
    }
    return null;
  }

  Map<String, dynamic>? get _currentUserMap {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return null;
    return {
      'id': user.id,
      'name': user.name,
      'role': user.role,
      'has_full_access': user.hasFullAccess,
    };
  }

  int? get _currentUserId => _currentUserMap?['id'] as int?;

  String get _currentUserName {
    final raw = (_currentUserMap?['name'] ?? '').toString().trim();
    return raw.isEmpty ? 'Unknown User' : raw;
  }

  bool get _currentUserHasManagementAccess {
    return context.read<AuthProvider>().hasManagementAccess;
  }

  String _buildPerformedByLabel(String? approverName) {
    if (_currentUserHasManagementAccess) return _currentUserName;
    if (approverName == null || approverName.trim().isEmpty) {
      return _currentUserName;
    }
    return '$_currentUserName (approved by ${approverName.trim()})';
  }

  Future<_StockTakeApprovalResult?> _requireManagerApproval({
    required String actionLabel,
    required String description,
  }) async {
    if (_currentUserHasManagementAccess) {
      return _StockTakeApprovalResult(
        approverId: _currentUserId ?? 0,
        approverName: _currentUserName,
      );
    }

    final pinController = TextEditingController();
    String? errorText;
    bool isVerifying = false;

    final approver = await showGeneralDialog<_StockTakeApprovalResult?>(
      context: context,
      barrierLabel: 'Approval required',
      barrierDismissible: !isVerifying,
      barrierColor: Colors.black.withOpacity(_isDark ? 0.34 : 0.22),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> verify() async {
              final pin = pinController.text.trim();
              if (pin.isEmpty) {
                setDialogState(() {
                  errorText = 'Enter manager or full-access PIN.';
                });
                return;
              }

              setDialogState(() {
                isVerifying = true;
                errorText = null;
              });

              try {
                final user = await DatabaseHelper.instance.findUserByPin(pin);

                if (!dialogContext.mounted) return;

                if (user == null) {
                  setDialogState(() {
                    isVerifying = false;
                    errorText = 'Invalid PIN.';
                  });
                  return;
                }

                final userId = ((user['id'] as num?) ?? 0).toInt();
                final userName = (user['name'] ?? 'Manager').toString();
                final role = (user['role'] ?? '').toString().toLowerCase();
                final isActive = ((user['is_active'] as num?) ?? 1).toInt() == 1;
                final hasFullAccess = ((user['has_full_access'] as num?) ?? 0).toInt() == 1;
                final hasManagementAccess = role == 'manager' || hasFullAccess;

                if (!isActive) {
                  setDialogState(() {
                    isVerifying = false;
                    errorText = 'This approver account is inactive.';
                  });
                  return;
                }

                if (!hasManagementAccess) {
                  setDialogState(() {
                    isVerifying = false;
                    errorText = 'PIN does not belong to a manager or full-access user.';
                  });
                  return;
                }

                await DatabaseHelper.instance.logManagerApproval(
                  actorUserId: userId,
                  actorName: userName,
                  targetUserId: _currentUserId,
                  targetUserName: _currentUserName,
                  description: description,
                );

                if (!dialogContext.mounted) return;
                Navigator.pop(
                  dialogContext,
                  _StockTakeApprovalResult(
                    approverId: userId,
                    approverName: userName,
                  ),
                );
              } catch (_) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isVerifying = false;
                  errorText = 'Approval failed. Please try again.';
                });
              }
            }

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
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
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: _warningSoft,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _warning.withOpacity(0.24)),
                                ),
                                child: Icon(Icons.verified_user_outlined, color: _warning, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Approval Required',
                                      style: TextStyle(
                                        color: _textPrimary,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Enter manager or full-access PIN to $actionLabel.',
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
                          TextField(
                            controller: pinController,
                            obscureText: true,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            decoration: _fieldDecoration(
                              hintText: 'Approver PIN',
                              labelText: 'Approver PIN',
                              icon: Icons.pin_outlined,
                            ).copyWith(errorText: errorText),
                            onSubmitted: (_) {
                              if (!isVerifying) {
                                verify();
                              }
                            },
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isVerifying
                                      ? null
                                      : () => Navigator.pop(dialogContext, null),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _textPrimary,
                                    side: BorderSide(color: _borderStrong),
                                    minimumSize: const Size.fromHeight(52),
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
                                  onPressed: isVerifying ? null : verify,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _warning,
                                    foregroundColor: _surfaceAlt,
                                    elevation: 0,
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: isVerifying
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Approve'),
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

    pinController.dispose();

    if (approver == null && mounted) {
      _showMessage('Approval is required to continue.', isError: true);
    }

    return approver;
  }

  List<Product> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();

    return _products.where((product) {
      final countedQty = _countedQuantities[product.barcode];
      final hasCount = countedQty != null;
      final hasDiscrepancy = hasCount && countedQty != product.stock;

      final matchesSearch = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);

      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case StockTakeFilter.counted:
          return hasCount;
        case StockTakeFilter.discrepancies:
          return hasDiscrepancy;
        case StockTakeFilter.uncounted:
          return !hasCount;
        case StockTakeFilter.all:
          return true;
      }
    }).toList();
  }

  int get _countedItems => _countedQuantities.length;
  int get _discrepancyItems => _products.where((product) {
        final countedQty = _countedQuantities[product.barcode];
        return countedQty != null && countedQty != product.stock;
      }).length;
  int get _matchedItems => _products.where((product) {
        final countedQty = _countedQuantities[product.barcode];
        return countedQty != null && countedQty == product.stock;
      }).length;
  int get _uncountedItems => _products.length - _countedItems;

  Future<void> _renameSession() async {
    if (_sessionId == null) return;
    final controller = TextEditingController(text: _sessionNameController.text);

    final saved = await showGeneralDialog<bool>(
          context: context,
          barrierLabel: 'Rename session',
          barrierDismissible: true,
          barrierColor: Colors.black.withOpacity(_isDark ? 0.34 : 0.22),
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (dialogContext, animation, secondaryAnimation) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
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
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: _brandSoft,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _brand.withOpacity(0.24)),
                                ),
                                child: Icon(Icons.edit_note_rounded, color: _brand, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Session Name',
                                      style: TextStyle(
                                        color: _textPrimary,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Rename this stock take session.',
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
                          TextField(
                            controller: controller,
                            autofocus: true,
                            decoration: _fieldDecoration(
                              hintText: 'Session Name',
                              labelText: 'Session Name',
                              icon: Icons.drive_file_rename_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(dialogContext, false),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _textPrimary,
                                    side: BorderSide(color: _borderStrong),
                                    minimumSize: const Size.fromHeight(52),
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
                                  onPressed: () {
                                    if (controller.text.trim().isEmpty) {
                                      _showMessage('Session name cannot be empty.', isError: true);
                                      return;
                                    }
                                    Navigator.pop(dialogContext, true);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _brand,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text('Save'),
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
        ) ??
        false;

    if (!saved) return;

    final newName = controller.text.trim().isEmpty
        ? 'Main Store Count'
        : controller.text.trim();
    final ok = await DatabaseHelper.instance.renameStockTakeSession(
      _sessionId!,
      newName,
    );

    if (!mounted) return;

    if (ok) {
      setState(() {
        _sessionNameController.text = newName;
      });
      _showMessage('Session name updated.');
    } else {
      _showMessage('Could not update session name.', isError: true);
    }
  }

  Future<void> _saveCount(Product product, int countedQty) async {
    if (_sessionId == null) return;

    final success = await DatabaseHelper.instance.saveStockTakeCount(
      sessionId: _sessionId!,
      product: product,
      countedQty: countedQty,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _countedQuantities[product.barcode] = countedQty;
      });
    } else {
      _showMessage('Could not save count for ${product.name}.', isError: true);
    }
  }

  Future<void> _clearCount(Product product) async {
    if (_sessionId == null) return;

    final confirmed = await _showDecisionDialog(
      title: 'Clear Count?',
      message: 'Remove the counted quantity for ${product.name}?',
      confirmText: 'Clear',
      destructive: true,
      icon: Icons.clear_rounded,
      tone: _danger,
    );
    if (!confirmed) return;

    final success = await DatabaseHelper.instance.removeStockTakeCount(
      sessionId: _sessionId!,
      barcode: product.barcode,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _countedQuantities.remove(product.barcode);
      });
      _showMessage('Removed counted quantity for ${product.name}.');
    } else {
      _showMessage('Could not remove count.', isError: true);
    }
  }

  Future<void> _incrementByBarcode() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) return;

    Product? matched;
    for (final product in _products) {
      if (product.barcode == barcode) {
        matched = product;
        break;
      }
    }

    if (matched == null) {
      _showMessage('Barcode not found.', isError: true);
      _barcodeController.clear();
      return;
    }

    final nextQty = (_countedQuantities[matched.barcode] ?? 0) + 1;
    await _saveCount(matched, nextQty);
    if (!mounted) return;
    _barcodeController.clear();
    _showMessage('Counted 1 x ${matched.name}');
  }

  Future<void> _setCountDialog(Product product) async {
    final controller = TextEditingController(
      text: _countedQuantities[product.barcode]?.toString() ?? '',
    );

    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Set count',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(_isDark ? 0.34 : 0.22),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
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
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _blueSoft,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _blue.withOpacity(0.24)),
                            ),
                            child: Icon(Icons.edit_outlined, color: _blue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Set Count',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  product.name,
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
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          hintText: 'Counted Quantity',
                          labelText: 'Counted Quantity',
                          icon: Icons.numbers_rounded,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                Navigator.pop(dialogContext);
                                await _clearCount(product);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _danger,
                                side: BorderSide(color: _danger.withOpacity(0.28)),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textPrimary,
                                side: BorderSide(color: _borderStrong),
                                minimumSize: const Size.fromHeight(52),
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
                              onPressed: () async {
                                final error = _validateCount(controller.text);
                                if (error != null) {
                                  _showMessage(error, isError: true);
                                  return;
                                }
                                final qty = int.parse(controller.text.trim());
                                final confirmed = await _showDecisionDialog(
                                  title: 'Save Count?',
                                  message: 'Set counted quantity for ${product.name} to $qty?',
                                  confirmText: 'Save',
                                  icon: Icons.done_rounded,
                                  tone: _brand,
                                );
                                if (!confirmed) return;
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                await _saveCount(product, qty);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brand,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text('Save'),
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
  }

  Future<void> _discardDraft() async {
    if (_sessionId == null) return;
    final approval = await _requireManagerApproval(
      actionLabel: 'discard this stock take draft',
      description: 'Approved stock take draft discard for ${_sessionNameController.text.trim()} requested by $_currentUserName',
    );
    if (approval == null) return;

    final confirmed = await _showDecisionDialog(
      title: 'Discard Current Draft?',
      message: 'This will remove the current stock take draft and all counted quantities in it.',
      confirmText: 'Discard',
      destructive: true,
      icon: Icons.delete_outline_rounded,
      tone: _danger,
    );

    if (!confirmed) return;

    final ok = await DatabaseHelper.instance.discardOpenStockTakeSession(_sessionId!);
    if (!mounted) return;

    if (ok) {
      _showMessage('Stock take draft discarded.');
      await _loadSession(showLoader: true);
    } else {
      _showMessage('Could not discard stock take draft.', isError: true);
    }
  }

  Future<void> _openHistorySheet() async {
    final sessions = await DatabaseHelper.instance.getCompletedStockTakeSessions();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(color: _border),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
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
                  Text(
                    'Stock Take History',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Completed stock count sessions.',
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: sessions.isEmpty
                        ? Center(
                            child: Text(
                              'No completed stock take sessions yet.',
                              style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
                            ),
                          )
                        : ListView.separated(
                            itemCount: sessions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final session = sessions[index];
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: _softDecoration(color: _surfaceSoft),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (session['session_name'] ?? 'Stock Take Session').toString(),
                                      style: TextStyle(
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Started • ${_formatDateTime(session['started_at']?.toString())}',
                                      style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Completed • ${_formatDateTime(session['completed_at']?.toString())}',
                                      style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _buildMiniChip('${session['counted_items'] ?? 0} counted', _blue),
                                        _buildMiniChip('${session['discrepancy_items'] ?? 0} discrepancies', _warning),
                                        _buildMiniChip('${session['applied_items'] ?? 0} applied', _success),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyReconciliation() async {
    if (_sessionId == null || _isApplying) return;
    if (_discrepancyItems == 0) {
      _showMessage('No discrepancies to apply.');
      return;
    }

    final approval = await _requireManagerApproval(
      actionLabel: 'apply this stock take reconciliation',
      description: 'Approved stock take reconciliation for ${_sessionNameController.text.trim()} requested by $_currentUserName',
    );
    if (approval == null) return;

    final confirmed = await _showDecisionDialog(
      title: 'Apply Stock Take',
      message:
          'Session: ${_sessionNameController.text.trim()}\n\nDiscrepancy items: $_discrepancyItems\n\nThis will update each counted item to the exact counted quantity using stock adjustment. Uncounted items will not be changed.',
      confirmText: 'Apply',
      icon: Icons.done_all_rounded,
      tone: _brand,
    );

    if (!confirmed) return;

    setState(() {
      _isApplying = true;
    });

    final result = await DatabaseHelper.instance.applyStockTakeSession(
      sessionId: _sessionId!,
      performedBy: _buildPerformedByLabel(approval.approverName),
    );

    if (!mounted) return;

    setState(() {
      _isApplying = false;
    });

    if (result['success'] == true) {
      _showMessage((result['message'] ?? 'Stock take applied.').toString());
      await _loadSession(showLoader: true);
    } else {
      _showMessage(
        (result['message'] ?? 'Could not apply stock take.').toString(),
        isError: true,
      );
      await _loadSession(showLoader: false);
    }
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(_isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildFilterPill(String label, StockTakeFilter filter) {
    final selected = _selectedFilter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _brandSoft : _surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? _brand.withOpacity(0.26) : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _brand : _textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softDecoration(color: _surfaceSoft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _headerIconButton(
          tooltip: 'Rename session',
          icon: Icons.edit_note_rounded,
          onTap: _renameSession,
        ),
        _headerIconButton(
          tooltip: 'History',
          icon: Icons.history_rounded,
          onTap: _openHistorySheet,
        ),
        _headerIconButton(
          tooltip: 'Discard draft',
          icon: Icons.delete_outline_rounded,
          onTap: _discardDraft,
          iconColor: _danger,
        ),
      ],
    );
  }

  Widget _headerIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 44,
          height: 44,
          decoration: _softDecoration(color: _surfaceSoft, radius: 14),
          child: Icon(icon, color: iconColor ?? _textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      decoration: _panelDecoration(color: _surface),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 940;

              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_brandSoft, _blueSoft],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _border),
                        ),
                        child: Icon(Icons.fact_check_outlined, color: _brand, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _sessionNameController.text,
                              style: TextStyle(
                                color: _textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Started ${_formatDateTime(_startedAt)}',
                              style: TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    left,
                    const SizedBox(height: 14),
                    _headerIconButton(
                      tooltip: 'Refresh session',
                      icon: Icons.refresh_rounded,
                      onTap: () => _loadSession(showLoader: false),
                    ),
                    const SizedBox(height: 12),
                    _buildHeaderActions(),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 12),
                  _headerIconButton(
                    tooltip: 'Refresh session',
                    icon: Icons.refresh_rounded,
                    onTap: () => _loadSession(showLoader: false),
                  ),
                  const SizedBox(width: 10),
                  _buildHeaderActions(),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 920;
              final rightButton = SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _incrementByBarcode,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Count +1'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              );

              if (compact) {
                return Column(
                  children: [
                    TextField(
                      controller: _barcodeController,
                      decoration: _fieldDecoration(
                        hintText: 'Scan or enter barcode to count +1',
                        labelText: 'Quick Count',
                        icon: Icons.qr_code_scanner_rounded,
                      ),
                      onSubmitted: (_) => _incrementByBarcode(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: rightButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeController,
                      decoration: _fieldDecoration(
                        hintText: 'Scan or enter barcode to count +1',
                        labelText: 'Quick Count',
                        icon: Icons.qr_code_scanner_rounded,
                      ),
                      onSubmitted: (_) => _incrementByBarcode(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  rightButton,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 12.0;
              final columns = constraints.maxWidth >= 1000
                  ? 4
                  : constraints.maxWidth >= 560
                      ? 2
                      : 1;
              final itemWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildStatTile(
                      label: 'Counted',
                      value: _countedItems.toString(),
                      tone: _blue,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildStatTile(
                      label: 'Matched',
                      value: _matchedItems.toString(),
                      tone: _success,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildStatTile(
                      label: 'Discrepancies',
                      value: _discrepancyItems.toString(),
                      tone: _warning,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildStatTile(
                      label: 'Uncounted',
                      value: _uncountedItems.toString(),
                      tone: _textMuted,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      decoration: _panelDecoration(color: _surface),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final applyButton = SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _applyReconciliation,
                  icon: _isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(_isApplying ? 'Applying...' : 'Apply'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              );

              if (compact) {
                return Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: _fieldDecoration(
                        hintText: 'Search by name, barcode, or category',
                        labelText: 'Search Products',
                        icon: Icons.search_rounded,
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                                icon: Icon(Icons.close_rounded, color: _textMuted),
                              ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: applyButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: _fieldDecoration(
                        hintText: 'Search by name, barcode, or category',
                        labelText: 'Search Products',
                        icon: Icons.search_rounded,
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                                icon: Icon(Icons.close_rounded, color: _textMuted),
                              ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  applyButton,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill('All', StockTakeFilter.all),
                const SizedBox(width: 8),
                _buildFilterPill('Counted', StockTakeFilter.counted),
                const SizedBox(width: 8),
                _buildFilterPill('Discrepancies', StockTakeFilter.discrepancies),
                const SizedBox(width: 8),
                _buildFilterPill('Uncounted', StockTakeFilter.uncounted),
              ],
            ),
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

  Widget _buildProductRow(Product product) {
    final countedQty = _countedQuantities[product.barcode];
    final hasCount = countedQty != null;
    final difference = hasCount ? countedQty - product.stock : null;
    final isMatch = hasCount && difference == 0;
    final isDiscrepancy = hasCount && difference != 0;

    Color accent = _textMuted;
    String stateLabel = 'Uncounted';
    if (isMatch) {
      accent = _success;
      stateLabel = 'Matched';
    } else if (isDiscrepancy) {
      accent = _warning;
      stateLabel = 'Discrepancy';
    } else if (hasCount) {
      accent = _blue;
      stateLabel = 'Counted';
    }

    final diffText = difference == null
        ? null
        : difference == 0
            ? 'Diff 0'
            : difference > 0
                ? 'Diff +$difference'
                : 'Diff $difference';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(color: _surface, radius: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(_isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.inventory_2_outlined, color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${product.barcode} • ${product.category}',
                          style: TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(_isDark ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withOpacity(0.24)),
                    ),
                    child: Text(
                      stateLabel,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _inlineMeta('System ${product.stock}', _textSecondary),
                  _buildMetaDot(),
                  _inlineMeta(
                    hasCount ? 'Counted $countedQty' : 'Count not set',
                    hasCount ? _blue : _textMuted,
                  ),
                  if (diffText != null) ...[
                    _buildMetaDot(),
                    _inlineMeta(diffText, difference == 0 ? _success : _warning),
                  ],
                ],
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final nextQty = (countedQty ?? 0) + 1;
                  await _saveCount(product, nextQty);
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Count +1'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _setCountDialog(product),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Set Count'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textPrimary,
                  side: BorderSide(color: _borderStrong),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (hasCount)
                OutlinedButton.icon(
                  onPressed: () => _clearCount(product),
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _danger,
                    side: BorderSide(color: _danger.withOpacity(0.24)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 14),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 16),
              SizedBox(
                width: 370,
                child: Align(
                  alignment: Alignment.topRight,
                  child: actions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _inlineMeta(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '-';
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return isoString;
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: _panelDecoration(color: _surface),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: _softDecoration(color: _surfaceSoft, radius: 24),
            child: Icon(
              Icons.inventory_2_outlined,
              color: _textMuted,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No products match the current filter.',
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
    final visibleProducts = _filteredProducts;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _page,
        foregroundColor: _textPrimary,
        title: const Text('Stock Take'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _brand))
          : RefreshIndicator(
              onRefresh: () => _loadSession(showLoader: false),
              color: _brand,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_page, _pageAlt],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  children: [
                    _buildTopPanel(),
                    const SizedBox(height: 16),
                    _buildControlPanel(),
                    const SizedBox(height: 16),
                    if (visibleProducts.isEmpty)
                      _buildEmptyState()
                    else
                      ...visibleProducts.map(
                        (product) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildProductRow(product),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
