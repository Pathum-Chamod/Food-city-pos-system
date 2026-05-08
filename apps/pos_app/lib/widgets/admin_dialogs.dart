import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import 'app_snackbar.dart';
import 'premium_dialog.dart';

class AdminDialogs {
  static Future<bool> showPinDialog(
    BuildContext context,
    FutureOr<void> Function()? onSuccess, {
    String title = 'Manager Approval Required',
    String message = 'Enter an active manager or full-access PIN to continue.',
    int? requesterUserId,
    String? requesterUserName,
    String? approvalDescription,
    bool requireDifferentManager = false,
  }) async {
    final TextEditingController pinController = TextEditingController();
    String? errorText;
    bool isVerifying = false;
    bool approved = false;

    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    final canBypassWithCurrentUser =
        auth.hasManagementAccess && currentUser?.id != null;

    if (canBypassWithCurrentUser) {
      final bypassedSelfApproval = requireDifferentManager &&
          requesterUserId != null &&
          requesterUserId == currentUser!.id;

      if (!bypassedSelfApproval) {
        final description = _buildApprovalDescription(
          title: title,
          message: message,
          requesterUserName: requesterUserName,
          explicitDescription: approvalDescription,
        );

        await DatabaseHelper.instance.logManagerApproval(
          actorUserId: currentUser!.id!,
          actorName: currentUser.name,
          targetUserId: requesterUserId,
          targetUserName: requesterUserName,
          description: description,
        );

        await onSuccess?.call();
        return true;
      }
    }

    final palette = _DialogPalette.of(context);

    await showPremiumDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> verify() async {
              if (isVerifying) return;

              final pin = pinController.text.trim();
              if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
                setState(() {
                  errorText = 'Enter a valid 4-digit approval PIN.';
                });
                return;
              }

              setState(() {
                isVerifying = true;
                errorText = null;
              });

              try {
                final user = await DatabaseHelper.instance.findUserByPin(pin);

                if (user == null) {
                  setState(() {
                    errorText = 'Incorrect approval PIN.';
                    isVerifying = false;
                  });
                  return;
                }

                final userId = ((user['id'] as num?) ?? 0).toInt();
                final userName = (user['name'] ?? 'Unknown').toString();
                final role = (user['role'] ?? '').toString().toLowerCase();
                final isActive = ((user['is_active'] as num?) ?? 1).toInt() == 1;
                final hasFullAccess =
                    ((user['has_full_access'] as num?) ?? 0).toInt() == 1 ||
                    (user['has_full_access'] == true);
                final canApprove = role == 'manager' || hasFullAccess;

                if (!isActive) {
                  setState(() {
                    errorText = 'This approver account is inactive.';
                    isVerifying = false;
                  });
                  return;
                }

                if (!canApprove) {
                  setState(() {
                    errorText =
                        'Only an active manager or full-access user can approve this action.';
                    isVerifying = false;
                  });
                  return;
                }

                if (requireDifferentManager &&
                    requesterUserId != null &&
                    requesterUserId == userId) {
                  setState(() {
                    errorText = 'Another manager must approve this action.';
                    isVerifying = false;
                  });
                  return;
                }

                final description = _buildApprovalDescription(
                  title: title,
                  message: message,
                  requesterUserName: requesterUserName,
                  explicitDescription: approvalDescription,
                );

                await DatabaseHelper.instance.logManagerApproval(
                  actorUserId: userId,
                  actorName: userName,
                  targetUserId: requesterUserId,
                  targetUserName: requesterUserName,
                  description: description,
                );

                approved = true;
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }

                await onSuccess?.call();
              } catch (_) {
                if (context.mounted) {
                  setState(() {
                    errorText = 'Approval failed. Please try again.';
                    isVerifying = false;
                  });
                }
              }
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: palette.border),
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadow,
                          blurRadius: 28,
                          offset: const Offset(0, 16),
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
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: palette.brandSoft,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.admin_panel_settings_rounded,
                                  color: palette.brand,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message,
                                      style: TextStyle(
                                        color: palette.textSecondary,
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
                            controller: pinController,
                            obscureText: true,
                            autofocus: true,
                            maxLength: 4,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => verify(),
                            decoration: InputDecoration(
                              labelText: 'Approval PIN',
                              counterText: '',
                              errorText: errorText,
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                color: palette.brand,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isVerifying
                                      ? null
                                      : () => Navigator.of(dialogContext).pop(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isVerifying ? null : verify,
                                  child: isVerifying
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Verify'),
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
    );

    pinController.dispose();
    return approved;
  }

  static Future<void> showEditPriceDialog(
    BuildContext context,
    String barcode,
    String currentName,
    double currentPrice,
    VoidCallback onComplete,
  ) async {
    // Keep the TextEditingController owned by the dialog widget itself.
    // Do not create/dispose the controller in this outer async method, because
    // showGeneralDialog can still build the dialog during its closing animation.
    // Disposing the controller here can crash with:
    // "A TextEditingController was used after being disposed."
    await showPremiumDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _EditPriceDialogContent(
        rootContext: context,
        barcode: barcode,
        currentName: currentName,
        currentPrice: currentPrice,
        onComplete: onComplete,
      ),
    );
  }

  static String _buildApprovalDescription({
    required String title,
    required String message,
    String? requesterUserName,
    String? explicitDescription,
  }) {
    final custom = explicitDescription?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }

    final cleanTitle = title.trim();
    final cleanMessage = message.trim();
    final requester = requesterUserName?.trim();

    final genericMessages = <String>{
      'Enter an active manager PIN to continue.',
      'Enter manager PIN to continue.',
      'Enter manager PIN to approve.',
      'Manager approval is required to continue.',
      'Enter an active manager or full-access PIN to continue.',
    };

    if (cleanTitle.isNotEmpty && cleanTitle != 'Manager Approval Required') {
      if (requester != null && requester.isNotEmpty) {
        return '$cleanTitle approved for $requester';
      }
      return cleanTitle;
    }

    if (cleanMessage.isNotEmpty && !genericMessages.contains(cleanMessage)) {
      if (requester != null &&
          requester.isNotEmpty &&
          !cleanMessage.toLowerCase().contains(requester.toLowerCase())) {
        return '$cleanMessage (requested by $requester)';
      }
      return cleanMessage;
    }

    if (requester != null && requester.isNotEmpty) {
      return 'Manager approval granted for $requester';
    }

    return 'Manager approval granted';
  }
}


class _EditPriceDialogContent extends StatefulWidget {
  const _EditPriceDialogContent({
    required this.rootContext,
    required this.barcode,
    required this.currentName,
    required this.currentPrice,
    required this.onComplete,
  });

  final BuildContext rootContext;
  final String barcode;
  final String currentName;
  final double currentPrice;
  final VoidCallback onComplete;

  @override
  State<_EditPriceDialogContent> createState() => _EditPriceDialogContentState();
}

class _EditPriceDialogContentState extends State<_EditPriceDialogContent> {
  late final TextEditingController _priceController;
  late final FocusNode _priceFocusNode;
  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: _formatInitialPrice(widget.currentPrice),
    );
    _priceFocusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _priceFocusNode.requestFocus();
      _priceController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _priceController.text.length,
      );
    });
  }

  String _formatInitialPrice(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.round().toString();
    }

    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    _priceFocusNode.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final cleanedPriceText = _priceController.text
        .trim()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.]'), '');
    final newPrice = double.tryParse(cleanedPriceText);
    if (newPrice == null || newPrice <= 0) {
      setState(() {
        _errorText = 'Enter a valid price greater than zero.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      await DatabaseHelper.instance.updateProductPriceLocal(
        widget.barcode,
        newPrice,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      widget.onComplete();

      final rootContext = widget.rootContext;
      if (rootContext.mounted) {
        AppSnackBar.show(
          rootContext,
          message: 'Price updated locally and queued for sync!',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = 'Could not update price: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _DialogPalette.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 28,
                  offset: const Offset(0, 16),
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: palette.warningSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.sell_outlined,
                          color: palette.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Price',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.currentName,
                              style: TextStyle(
                                color: palette.textSecondary,
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
                    controller: _priceController,
                    focusNode: _priceFocusNode,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'New Price (Rs.)',
                      hintText: 'Enter new price',
                      prefixIcon: Icon(
                        Icons.currency_rupee_rounded,
                        color: palette.brand,
                      ),
                      errorText: _errorText,
                    ),
                    onTap: () {
                      _priceController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _priceController.text.length,
                      );
                    },
                    onChanged: (_) {
                      if (_errorText == null) return;
                      setState(() {
                        _errorText = null;
                      });
                    },
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.warning,
                          ),
                          onPressed: _isSaving ? null : _save,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save Price'),
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
  }
}

class _DialogPalette {
  const _DialogPalette({required this.isDark});

  final bool isDark;

  static _DialogPalette of(BuildContext context) {
    return _DialogPalette(
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  Color get surfaceAlt =>
      isDark ? const Color(0xFF0A1627) : const Color(0xFFFBFCFE);
  Color get border =>
      isDark ? const Color(0xFF23344D) : const Color(0xFFD9E3EE);
  Color get textPrimary =>
      isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
  Color get textSecondary =>
      isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);
  Color get brand => const Color(0xFF2AAA8A);
  Color get brandSoft => brand.withOpacity(isDark ? 0.16 : 0.10);
  Color get warning => const Color(0xFFFFB65C);
  Color get warningSoft => warning.withOpacity(isDark ? 0.18 : 0.10);
  Color get shadow => Colors.black.withOpacity(isDark ? 0.26 : 0.05);
}
