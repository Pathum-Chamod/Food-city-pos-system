import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';

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
      final bypassedSelfApproval =
          requireDifferentManager && requesterUserId != null && requesterUserId == currentUser!.id;

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

    await showDialog<void>(
      context: context,
      barrierDismissible: !isVerifying,
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
                    errorText = 'Only an active manager or full-access user can approve this action.';
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

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    autofocus: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => verify(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Approval PIN',
                      counterText: '',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isVerifying ? null : verify,
                  child: Text(isVerifying ? 'Verifying...' : 'Verify'),
                ),
              ],
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
    final TextEditingController priceController =
        TextEditingController(text: currentPrice.toString());

    await showDialog(
      context: context,
      builder: (context) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        return AlertDialog(
          title: Text('Edit Price: $currentName'),
          content: TextField(
            controller: priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'New Price (Rs.)',
              prefixText: 'Rs. ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final newPrice = double.tryParse(priceController.text);
                if (newPrice != null && newPrice > 0) {
                  await DatabaseHelper.instance.updateProductPriceLocal(
                    barcode,
                    newPrice,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  onComplete();

                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Price updated locally and queued for sync!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text(
                'Save Price',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    priceController.dispose();
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
