import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../widgets/app_snackbar.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _showLogsView = false;

  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _logSearchController = TextEditingController();

  Map<String, dynamic> _summary = const {
    'total_users': 0,
    'active_users': 0,
    'managers': 0,
    'cashiers': 0,
  };
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _logs = [];

  bool _isLoading = true;
  bool _isSaving = false;

  String _userRoleFilter = 'all';
  String _userStatusFilter = 'all';
  String _logFilter = 'all';

  int? _selectedActivityUserId;
  String? _selectedActivityUserName;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    _logSearchController.dispose();
    super.dispose();
  }

  UserModulePalette get _ui => UserModulePalette.of(context);

  int? get _actorUserId => context.read<AuthProvider>().currentUser?.id;

  String get _actorName =>
      context.read<AuthProvider>().currentUser?.name ?? 'System';

  Future<void> _loadAll({bool keepUserActivityFilter = true}) async {
    if (!mounted) return;

    final relatedUserId = keepUserActivityFilter ? _selectedActivityUserId : null;

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        DatabaseHelper.instance.getUserSummaryCounts(),
        DatabaseHelper.instance.getUsers(
          search: _userSearchController.text.trim(),
          role: _userRoleFilter,
          status: _userStatusFilter,
        ),
        DatabaseHelper.instance.getUserLogs(
          search: _logSearchController.text.trim(),
          actionFilter: _logFilter,
          relatedUserId: relatedUserId,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _summary = Map<String, dynamic>.from(results[0] as Map);
        _users = (results[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _logs = (results[2] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _isLoading = false;
        if (!keepUserActivityFilter) {
          _selectedActivityUserId = null;
          _selectedActivityUserName = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _ui.danger,
      );
    }
  }

  void _showMessage(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    AppSnackBar.show(
      context,
      message: message,
      backgroundColor: backgroundColor ?? _ui.surfaceSoft,
    );
  }

  String _formatRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'manager') return 'Manager';
    if (normalized == 'cashier') return 'Cashier';
    if (normalized.isEmpty) return 'Unknown';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _formatLastLogin(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return 'Never';

    final dateTime = DateTime.tryParse(raw);
    if (dateTime == null) return raw;

    final local = dateTime.toLocal();
    final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}  $hour:$minute $suffix';
  }

  String _formatActionLabel(String actionType) {
    switch (actionType) {
      case 'login_success':
        return 'Login';
      case 'login_failed':
        return 'Login Failed';
      case 'logout':
        return 'Logout';
      case 'user_created':
        return 'User Created';
      case 'user_updated':
        return 'User Updated';
      case 'pin_reset':
        return 'PIN Reset';
      case 'user_deactivated':
        return 'Deactivated';
      case 'user_reactivated':
        return 'Reactivated';
      case 'role_changed':
        return 'Role Changed';
      case 'full_access_granted':
        return 'Full Access Granted';
      case 'full_access_revoked':
        return 'Full Access Removed';
      case 'manager_approval':
        return 'Approval';
      default:
        return actionType
            .split('_')
            .map((part) => part.isEmpty
                ? part
                : '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
    }
  }

  String _formatLogFilterLabel(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'logins':
        return 'Logins';
      case 'user_changes':
        return 'User Changes';
      case 'pin_changes':
        return 'PIN Changes';
      case 'approvals':
        return 'Approvals';
      default:
        return filter;
    }
  }

  Color _actionColor(String actionType) {
    switch (actionType) {
      case 'login_success':
      case 'logout':
      case 'user_created':
      case 'user_reactivated':
        return _ui.success;
      case 'login_failed':
      case 'user_deactivated':
        return _ui.danger;
      case 'pin_reset':
      case 'manager_approval':
        return _ui.warning;
      case 'full_access_granted':
      case 'full_access_revoked':
      case 'role_changed':
      case 'user_updated':
        return _ui.brand;
      default:
        return _ui.textMuted;
    }
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? labelText,
    IconData? icon,
    Widget? suffixIcon,
    String? counterText,
    UserModulePalette? palette,
  }) {
    final ui = palette ?? _ui;
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      counterText: counterText,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: ui.textMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: ui.inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ui.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ui.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ui.brand, width: 1.4),
      ),
      labelStyle: TextStyle(color: ui.textSecondary),
      hintStyle: TextStyle(color: ui.textMuted),
    );
  }

  Future<void> _showUserEditor({Map<String, dynamic>? user}) async {
    final isEdit = user != null;
    final nameController = TextEditingController(
      text: (user?['name'] ?? '').toString(),
    );
    final pinController = TextEditingController();
    var role = (user?['role'] ?? 'cashier').toString().trim().toLowerCase();

    await showDialog<void>(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogContext) {
        final ui = UserModulePalette.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: StatefulBuilder(
              builder: (context, setLocalState) {
                return Container(
                  decoration: BoxDecoration(
                    color: ui.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: ui.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(ui.isDark ? 0.34 : 0.08),
                        blurRadius: 36,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            decoration: BoxDecoration(
                              color: ui.borderStrong,
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
                                color: ui.brandSoft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                isEdit
                                    ? Icons.edit_outlined
                                    : Icons.person_add_alt_1_rounded,
                                color: ui.brand,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEdit ? 'Edit User' : 'Create User',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: ui.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isEdit
                                        ? 'Update the account profile, role, and access setup.'
                                        : 'Create a new cashier or manager account for the POS team.',
                                    style: TextStyle(
                                      color: ui.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _isSaving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              icon: Icon(Icons.close_rounded, color: ui.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            hintText: 'Enter full name',
                            labelText: 'Full Name',
                            icon: Icons.person_outline_rounded,
                            palette: ui,
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: role,
                          items: const [
                            DropdownMenuItem(value: 'manager', child: Text('Manager')),
                            DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setLocalState(() {
                              role = value;
                            });
                          },
                          decoration: _fieldDecoration(
                            hintText: 'Select role',
                            labelText: 'Role',
                            icon: Icons.badge_outlined,
                            palette: ui,
                          ),
                        ),
                        if (!isEdit) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: _fieldDecoration(
                              hintText: '4-digit PIN',
                              labelText: 'PIN',
                              icon: Icons.pin_outlined,
                              counterText: '',
                              palette: ui,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ui.surfaceSoft,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: ui.border),
                          ),
                          child: Text(
                            isEdit
                                ? 'Tip: use Reset PIN from the account actions when only the PIN needs to change.'
                                : 'Tip: managers already receive full access by role. Cashiers can be upgraded later if needed.',
                            style: TextStyle(
                              color: ui.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ui.textPrimary,
                                  side: BorderSide(color: ui.borderStrong),
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
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        final name = nameController.text.trim();
                                        final pin = pinController.text.trim();

                                        if (name.isEmpty) {
                                          _showMessage(
                                            'User name is required.',
                                            backgroundColor: _ui.warning,
                                          );
                                          return;
                                        }

                                        if (!isEdit &&
                                            !RegExp(r'^\d{4}$').hasMatch(pin)) {
                                          _showMessage(
                                            'PIN must be exactly 4 digits.',
                                            backgroundColor: _ui.warning,
                                          );
                                          return;
                                        }

                                        await _saveUser(
                                          isEdit: isEdit,
                                          user: user,
                                          name: name,
                                          role: role,
                                          pin: pin,
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ui.brand,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(isEdit ? 'Save Changes' : 'Create User'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveUser({
    required bool isEdit,
    Map<String, dynamic>? user,
    required String name,
    required String role,
    String? pin,
  }) async {
    final previousRole =
        (user?['role'] ?? 'cashier').toString().trim().toLowerCase();
    final roleChanged = isEdit && previousRole != role;

    setState(() {
      _isSaving = true;
    });

    try {
      if (isEdit) {
        await DatabaseHelper.instance.updateUserProfile(
          userId: ((user?['id'] as num?) ?? 0).toInt(),
          name: name,
          role: role,
          actorUserId: _actorUserId,
          actorName: _actorName,
        );
      } else {
        await DatabaseHelper.instance.createUser(
          name: name,
          role: role,
          pin: pin ?? '',
          actorUserId: _actorUserId,
          actorName: _actorName,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      await _loadAll(keepUserActivityFilter: false);
      _showMessage(
        isEdit
            ? (roleChanged
                ? 'User role updated successfully.'
                : 'User details updated successfully.')
            : 'User created successfully.',
        backgroundColor: _ui.success,
      );
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _ui.danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<bool> _showDecisionDialog({
    required String title,
    required String message,
    required String actionLabel,
    Color? actionColor,
  }) async {
    final ui = _ui;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              decoration: BoxDecoration(
                color: ui.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: ui.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(ui.isDark ? 0.34 : 0.08),
                    blurRadius: 34,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
                          color: (actionColor ?? ui.brand).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.help_outline_rounded,
                          color: actionColor ?? ui.brand,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: ui.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: TextStyle(
                      color: ui.textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ui.textPrimary,
                            side: BorderSide(color: ui.borderStrong),
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                            backgroundColor: actionColor ?? ui.brand,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(actionLabel),
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
  }

  Future<void> _showResetPinDialog(Map<String, dynamic> user) async {
    final pinController = TextEditingController();
    final userId = ((user['id'] as num?) ?? 0).toInt();
    final userName = (user['name'] ?? 'User').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final ui = UserModulePalette.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              decoration: BoxDecoration(
                color: ui.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: ui.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(ui.isDark ? 0.34 : 0.08),
                    blurRadius: 34,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
                          color: ui.warningSoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.pin_outlined, color: ui.warning),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reset PIN',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: ui.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Set a new 4-digit PIN for $userName.',
                              style: TextStyle(
                                color: ui.textSecondary,
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
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    autofocus: true,
                    decoration: _fieldDecoration(
                      hintText: 'New PIN',
                      labelText: 'New PIN',
                      icon: Icons.pin_outlined,
                      counterText: '',
                      palette: ui,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ui.textPrimary,
                            side: BorderSide(color: ui.borderStrong),
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                            backgroundColor: ui.warning,
                            foregroundColor: ui.surfaceAlt,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Reset PIN'),
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

    if (confirmed != true) return;

    final pin = pinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _showMessage(
        'PIN must be exactly 4 digits.',
        backgroundColor: _ui.warning,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await DatabaseHelper.instance.resetUserPin(
        userId: userId,
        newPin: pin,
        actorUserId: _actorUserId,
        actorName: _actorName,
      );
      await _loadAll();
      _showMessage('PIN reset for $userName.', backgroundColor: _ui.success);
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _ui.danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final userId = ((user['id'] as num?) ?? 0).toInt();
    final userName = (user['name'] ?? 'User').toString();
    final isActive = ((user['is_active'] as num?) ?? 1).toInt() == 1;

    if (_actorUserId == userId && isActive) {
      _showMessage(
        'You cannot deactivate your own account while logged in.',
        backgroundColor: _ui.warning,
      );
      return;
    }

    final confirmed = await _showDecisionDialog(
      title: isActive ? 'Deactivate User?' : 'Reactivate User?',
      message: isActive
          ? 'This will block $userName from logging in until reactivated.'
          : 'This will allow $userName to log in again.',
      actionLabel: isActive ? 'Deactivate' : 'Reactivate',
      actionColor: isActive ? _ui.danger : _ui.success,
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await DatabaseHelper.instance.setUserActiveStatus(
        userId: userId,
        isActive: !isActive,
        actorUserId: _actorUserId,
        actorName: _actorName,
      );
      await _loadAll();
      _showMessage(
        !isActive
            ? '$userName reactivated successfully.'
            : '$userName deactivated successfully.',
        backgroundColor: _ui.success,
      );
      await context.read<AuthProvider>().refreshCurrentUser();
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _ui.danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _toggleUserFullAccess(Map<String, dynamic> user) async {
    final userId = ((user['id'] as num?) ?? 0).toInt();
    final userName = (user['name'] ?? 'User').toString();
    final role = (user['role'] ?? 'cashier').toString().trim().toLowerCase();
    final hasFullAccess = ((user['has_full_access'] as num?) ?? 0).toInt() == 1;

    if (role == 'manager') {
      _showMessage(
        'Managers already have full access by role.',
        backgroundColor: _ui.warning,
      );
      return;
    }

    final confirmed = await _showDecisionDialog(
      title: hasFullAccess ? 'Remove Full Access?' : 'Give Full Access?',
      message: hasFullAccess
          ? 'This will remove advanced access from $userName and treat the account like a standard cashier again.'
          : 'This will allow $userName to access manager-only modules and protected actions without changing the role.',
      actionLabel: hasFullAccess ? 'Remove Access' : 'Give Access',
      actionColor: hasFullAccess ? _ui.danger : _ui.brand,
    );

    if (!confirmed) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await DatabaseHelper.instance.setUserFullAccess(
        userId: userId,
        hasFullAccess: !hasFullAccess,
        actorUserId: _actorUserId,
        actorName: _actorName,
      );
      await _loadAll();
      _showMessage(
        !hasFullAccess
            ? 'Full access granted to $userName.'
            : 'Full access removed from $userName.',
        backgroundColor: _ui.success,
      );

      if (_actorUserId == userId) {
        await context.read<AuthProvider>().refreshCurrentUser();
      }
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: _ui.danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _viewUserActivity(Map<String, dynamic> user) {
    setState(() {
      _selectedActivityUserId = ((user['id'] as num?) ?? 0).toInt();
      _selectedActivityUserName = (user['name'] ?? '').toString();
      _logSearchController.clear();
      _logFilter = 'all';
      _showLogsView = true;
    });
    _loadAll();
  }

  Widget _buildPageHeader() {
    final ui = _ui;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ui.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(ui.isDark ? 0.22 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 940;
              final left = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ui.brandSoft, ui.blueSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ui.border),
                    ),
                    child: Icon(Icons.manage_accounts_rounded, color: ui.brand),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Workspace',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: ui.textPrimary,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Manage cashier and manager accounts, login access, and audit activity in one place.',
                          style: TextStyle(
                            color: ui.textSecondary,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final right = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => _loadAll(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ui.textPrimary,
                      side: BorderSide(color: ui.borderStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [left, const SizedBox(height: 18), right],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: left), const SizedBox(width: 16), right],
              );
            },
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 12.0;
              final columns = constraints.maxWidth >= 1180
                  ? 4
                  : constraints.maxWidth >= 700
                      ? 2
                      : 1;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Total Users',
                      value: ((_summary['total_users'] as num?) ?? 0).toInt().toString(),
                      subtitle: 'All POS accounts',
                      icon: Icons.group_outlined,
                      color: ui.blue,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Active Users',
                      value: ((_summary['active_users'] as num?) ?? 0).toInt().toString(),
                      subtitle: 'Can log in now',
                      icon: Icons.verified_user_outlined,
                      color: ui.success,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Managers',
                      value: ((_summary['managers'] as num?) ?? 0).toInt().toString(),
                      subtitle: 'Management access accounts',
                      icon: Icons.admin_panel_settings_outlined,
                      color: ui.purple,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildSummarySurface(
                      label: 'Cashiers',
                      value: ((_summary['cashiers'] as num?) ?? 0).toInt().toString(),
                      subtitle: 'Sales-floor users',
                      icon: Icons.point_of_sale_outlined,
                      color: ui.warning,
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

  Widget _buildSummarySurface({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final ui = _ui;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ui.surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ui.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: ui.textPrimary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: ui.textMuted,
                    fontWeight: FontWeight.w600,
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

  Widget _buildToolbarActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final ui = _ui;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );

    if (primary) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: ui.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: ui.textPrimary,
        side: BorderSide(color: ui.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: child,
    );
  }

  Widget _buildUsersInlineToolbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1220;
        final semiWide = constraints.maxWidth >= 900;

        Widget searchField() {
          return TextField(
            controller: _userSearchController,
            decoration: _fieldDecoration(
              hintText: 'Search users by name, role, or PIN',
              icon: Icons.search_rounded,
              suffixIcon: _userSearchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _userSearchController.clear();
                        setState(() {});
                        _loadAll(keepUserActivityFilter: false);
                      },
                      icon: Icon(Icons.close_rounded, color: _ui.textMuted),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _loadAll(keepUserActivityFilter: false),
          );
        }

        Widget roleField(double width) {
          return SizedBox(
            width: width,
            child: DropdownButtonFormField<String>(
              value: _userRoleFilter,
              decoration: _fieldDecoration(
                hintText: 'All Roles',
                labelText: 'Role',
                icon: Icons.badge_outlined,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Roles')),
                DropdownMenuItem(value: 'manager', child: Text('Managers')),
                DropdownMenuItem(value: 'cashier', child: Text('Cashiers')),
              ],
              onChanged: (value) {
                setState(() {
                  _userRoleFilter = value ?? 'all';
                });
                _loadAll(keepUserActivityFilter: false);
              },
            ),
          );
        }

        Widget statusField(double width) {
          return SizedBox(
            width: width,
            child: DropdownButtonFormField<String>(
              value: _userStatusFilter,
              decoration: _fieldDecoration(
                hintText: 'All Status',
                labelText: 'Status',
                icon: Icons.toggle_on_outlined,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Status')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (value) {
                setState(() {
                  _userStatusFilter = value ?? 'all';
                });
                _loadAll(keepUserActivityFilter: false);
              },
            ),
          );
        }

        if (wide) {
          return Row(
            children: [
              Expanded(child: searchField()),
              const SizedBox(width: 12),
              roleField(160),
              const SizedBox(width: 12),
              statusField(160),
              const SizedBox(width: 12),
              _buildToolbarActionButton(
                label: 'User Logs History',
                icon: Icons.history_rounded,
                onTap: () {
                  setState(() {
                    _showLogsView = true;
                  });
                },
              ),
              const SizedBox(width: 12),
              _buildToolbarActionButton(
                label: 'Add User',
                icon: Icons.person_add_alt_1_rounded,
                primary: true,
                onTap: _isSaving ? () {} : () => _showUserEditor(),
              ),
            ],
          );
        }

        if (semiWide) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: searchField()),
                  const SizedBox(width: 12),
                  roleField(170),
                  const SizedBox(width: 12),
                  statusField(170),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  _buildToolbarActionButton(
                    label: 'User Logs History',
                    icon: Icons.history_rounded,
                    onTap: () {
                      setState(() {
                        _showLogsView = true;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  _buildToolbarActionButton(
                    label: 'Add User',
                    icon: Icons.person_add_alt_1_rounded,
                    primary: true,
                    onTap: _isSaving ? () {} : () => _showUserEditor(),
                  ),
                ],
              ),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(width: double.infinity, child: searchField()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: roleField(double.infinity)),
                const SizedBox(width: 12),
                Expanded(child: statusField(double.infinity)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildToolbarActionButton(
                    label: 'User Logs History',
                    icon: Icons.history_rounded,
                    onTap: () {
                      setState(() {
                        _showLogsView = true;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildToolbarActionButton(
                    label: 'Add User',
                    icon: Icons.person_add_alt_1_rounded,
                    primary: true,
                    onTap: _isSaving ? () {} : () => _showUserEditor(),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogsInlineToolbar() {
    final ui = _ui;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1120;
            final semiWide = constraints.maxWidth >= 860;

            Widget searchField() {
              return TextField(
                controller: _logSearchController,
                decoration: _fieldDecoration(
                  hintText: 'Search activity, user, or approval details',
                  icon: Icons.search_rounded,
                  suffixIcon: (_logSearchController.text.isEmpty &&
                          _selectedActivityUserName == null)
                      ? null
                      : IconButton(
                          onPressed: () {
                            _logSearchController.clear();
                            setState(() {
                              _selectedActivityUserId = null;
                              _selectedActivityUserName = null;
                              _logFilter = 'all';
                            });
                            _loadAll(keepUserActivityFilter: false);
                          },
                          icon: Icon(Icons.close_rounded, color: ui.textMuted),
                        ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _loadAll(),
              );
            }

            Widget historyTypeField(double width) {
              return SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  value: _logFilter,
                  decoration: _fieldDecoration(
                    hintText: 'All Activity',
                    labelText: 'History Type',
                    icon: Icons.tune_rounded,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Activity')),
                    DropdownMenuItem(value: 'logins', child: Text('Logins')),
                    DropdownMenuItem(value: 'user_changes', child: Text('User Changes')),
                    DropdownMenuItem(value: 'pin_changes', child: Text('PIN Changes')),
                    DropdownMenuItem(value: 'approvals', child: Text('Approvals')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _logFilter = value ?? 'all';
                    });
                    _loadAll();
                  },
                ),
              );
            }

            Widget backButton() {
              return _buildToolbarActionButton(
                label: 'Back to Users',
                icon: Icons.arrow_back_rounded,
                onTap: () {
                  _logSearchController.clear();
                  setState(() {
                    _showLogsView = false;
                    _selectedActivityUserId = null;
                    _selectedActivityUserName = null;
                    _logFilter = 'all';
                  });
                  _loadAll(keepUserActivityFilter: false);
                },
              );
            }

            if (wide) {
              return Row(
                children: [
                  Expanded(child: searchField()),
                  const SizedBox(width: 12),
                  historyTypeField(220),
                  const SizedBox(width: 12),
                  backButton(),
                ],
              );
            }

            if (semiWide) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: searchField()),
                      const SizedBox(width: 12),
                      historyTypeField(220),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      backButton(),
                    ],
                  ),
                ],
              );
            }

            return Column(
              children: [
                SizedBox(width: double.infinity, child: searchField()),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: historyTypeField(double.infinity)),
                    const SizedBox(width: 12),
                    Expanded(child: backButton()),
                  ],
                ),
              ],
            );
          },
        ),
        if (_selectedActivityUserName != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: ui.brandSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ui.brand.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.person_search_outlined, color: ui.brand, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Viewing activity for $_selectedActivityUserName',
                    style: TextStyle(
                      color: ui.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    _logSearchController.clear();
                    setState(() {
                      _selectedActivityUserId = null;
                      _selectedActivityUserName = null;
                    });
                    _loadAll(keepUserActivityFilter: false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 18, color: ui.brand),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  
  Widget _buildUsersTab() {
    final ui = _ui;
    return Container(
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ui.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team Accounts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ui.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage roles, access, login status, and protected actions.',
                        style: TextStyle(
                          color: ui.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_users.length} users',
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: ui.border),
          if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: _buildEmptyState(
                icon: Icons.group_outlined,
                title: 'No users found',
                subtitle: 'Try changing the filters or add a new user.',
              ),
            )
          else
            ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              itemCount: _users.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => Divider(height: 1, color: ui.border),
              itemBuilder: (context, index) => _buildUserRow(_users[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user) {
    final ui = _ui;
    final name = (user['name'] ?? 'User').toString();
    final role = (user['role'] ?? 'cashier').toString().trim().toLowerCase();
    final isActive = ((user['is_active'] as num?) ?? 1).toInt() == 1;
    final initial = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    final userId = ((user['id'] as num?) ?? 0).toInt();
    final isSelf = _actorUserId == userId;
    final hasFullAccess = ((user['has_full_access'] as num?) ?? 0).toInt() == 1;
    final activeManagerCount = _users.where((entry) {
      final entryRole =
          (entry['role'] ?? 'cashier').toString().trim().toLowerCase();
      final entryActive = ((entry['is_active'] as num?) ?? 1).toInt() == 1;
      return entryRole == 'manager' && entryActive;
    }).length;
    final isLastActiveManager =
        role == 'manager' && isActive && activeManagerCount <= 1;
    final toggleDisabled = isActive && (isSelf || isLastActiveManager);
    final statusColor = isActive ? ui.success : ui.danger;
    final roleColor = role == 'manager' ? ui.purple : ui.brand;
    final accessText = role == 'manager'
        ? 'Management access by role'
        : hasFullAccess
            ? 'Extended full access'
            : 'Standard cashier access';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final infoColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: ui.textPrimary,
                  ),
                ),
                if (isSelf)
                  Text(
                    'You',
                    style: TextStyle(
                      color: ui.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildInlineMeta(
                  icon: Icons.badge_outlined,
                  text: _formatRole(role),
                  color: roleColor,
                ),
                _buildMetaDivider(),
                _buildInlineMeta(
                  icon: Icons.circle,
                  text: isActive ? 'Active' : 'Inactive',
                  color: statusColor,
                  iconSize: 10,
                ),
                _buildMetaDivider(),
                Text(
                  accessText,
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (isLastActiveManager) ...[
                  _buildMetaDivider(),
                  Text(
                    'Last active manager',
                    style: TextStyle(
                      color: ui.purple,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Last login • ${_formatLastLogin(user['last_login_at'])}',
              style: TextStyle(
                color: ui.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            _actionButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit user',
              onTap: () => _showUserEditor(user: user),
            ),
            _actionButton(
              icon: Icons.history_rounded,
              tooltip: 'View activity',
              onTap: () => _viewUserActivity(user),
            ),
            Container(
              decoration: BoxDecoration(
                color: ui.surfaceSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ui.border),
              ),
              child: PopupMenuButton<String>(
                tooltip: 'User actions',
                splashRadius: 22,
                icon: Icon(Icons.more_horiz_rounded, color: ui.textSecondary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'pin') {
                    _showResetPinDialog(user);
                  } else if (value == 'toggle') {
                    _toggleUserStatus(user);
                  } else if (value == 'full_access') {
                    _toggleUserFullAccess(user);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'pin',
                    child: Text('Reset PIN'),
                  ),
                  if (role != 'manager')
                    PopupMenuItem(
                      value: 'full_access',
                      child: Text(hasFullAccess ? 'Remove Full Access' : 'Give Full Access'),
                    ),
                  PopupMenuItem(
                    value: 'toggle',
                    enabled: !toggleDisabled,
                    child: Text(
                      isActive
                          ? (isSelf
                              ? 'Cannot deactivate yourself'
                              : isLastActiveManager
                                  ? 'Cannot deactivate last manager'
                                  : 'Deactivate')
                          : 'Reactivate',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isActive ? ui.brandSoft : ui.surfaceSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: isActive ? ui.brand : ui.textMuted,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: infoColumn),
                  ],
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isActive ? ui.brandSoft : ui.surfaceSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: isActive ? ui.brand : ui.textMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: infoColumn),
              const SizedBox(width: 16),
              actions,
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final ui = _ui;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: ui.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ui.border),
          ),
          child: Icon(icon, size: 18, color: ui.textSecondary),
        ),
      ),
    );
  }

  
  Widget _buildLogsTab() {
    final ui = _ui;
    return Container(
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ui.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User Log History',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ui.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Review sign-ins, approvals, account edits, and PIN updates recorded across the system.',
                        style: TextStyle(
                          color: ui.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_logs.length} records',
                  style: TextStyle(
                    color: ui.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: ui.border),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: _buildEmptyState(
                icon: Icons.history_toggle_off,
                title: 'No log records found',
                subtitle: 'User activity will appear here once actions are recorded.',
              ),
            )
          else
            ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              itemCount: _logs.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => Divider(height: 1, color: ui.border),
              itemBuilder: (context, index) => _buildLogRow(_logs[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildLogRow(Map<String, dynamic> log) {
    final ui = _ui;
    final actionType = (log['action_type'] ?? 'unknown').toString();
    final actorName = (log['actor_name'] ?? 'Unknown').toString().trim();
    final targetName = (log['target_user_name'] ?? '').toString().trim();
    final description = (log['description'] ?? '').toString().trim();
    final color = _actionColor(actionType);
    final formattedTime = _formatLastLogin(log['created_at']);
    final title = description.isEmpty ? _formatActionLabel(actionType) : description;
    final details = _buildLogDetails(
      actionType: actionType,
      actorName: actorName,
      targetName: targetName,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_actionIcon(actionType), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatActionLabel(actionType),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    _buildMetaDivider(),
                    Text(
                      formattedTime,
                      style: TextStyle(
                        color: ui.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    color: ui.textPrimary,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: ui.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (actorName.isNotEmpty)
                      _buildInlineMeta(
                        icon: Icons.person_outline_rounded,
                        text: actorName,
                        color: ui.textSecondary,
                      ),
                    if (targetName.isNotEmpty &&
                        targetName.toLowerCase() != actorName.toLowerCase()) ...[
                      _buildMetaDivider(),
                      _buildInlineMeta(
                        icon: Icons.badge_outlined,
                        text: targetName,
                        color: ui.textSecondary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _actionIcon(String actionType) {
    switch (actionType) {
      case 'login_success':
        return Icons.login_rounded;
      case 'login_failed':
        return Icons.error_outline_rounded;
      case 'logout':
        return Icons.logout_rounded;
      case 'user_created':
        return Icons.person_add_alt_1_rounded;
      case 'user_updated':
        return Icons.edit_outlined;
      case 'pin_reset':
        return Icons.password_rounded;
      case 'full_access_granted':
        return Icons.admin_panel_settings_outlined;
      case 'full_access_revoked':
        return Icons.remove_moderator_outlined;
      case 'user_deactivated':
        return Icons.person_off_outlined;
      case 'user_reactivated':
        return Icons.person_add_alt_rounded;
      case 'role_changed':
        return Icons.badge_outlined;
      case 'manager_approval':
        return Icons.verified_user_outlined;
      default:
        return Icons.history_rounded;
    }
  }

  String _buildLogDetails({
    required String actionType,
    required String actorName,
    required String targetName,
  }) {
    final hasTarget =
        targetName.isNotEmpty && targetName.toLowerCase() != actorName.toLowerCase();

    switch (actionType) {
      case 'login_success':
        return 'A successful sign-in was recorded for $actorName.';
      case 'login_failed':
        return hasTarget
            ? 'A failed sign-in attempt was recorded for $targetName.'
            : 'A failed sign-in attempt was recorded.';
      case 'logout':
        return 'The user session ended and was recorded in the audit trail.';
      case 'user_created':
        return hasTarget
            ? '$targetName was added to the system and is now available for login.'
            : 'A new user account was added to the system.';
      case 'user_updated':
        return hasTarget
            ? '$targetName account details were updated.'
            : 'User account details were updated.';
      case 'pin_reset':
        return hasTarget ? '$targetName now has an updated PIN.' : 'A user PIN was reset.';
      case 'full_access_granted':
        return hasTarget
            ? '$targetName can now access manager-only modules and protected actions.'
            : 'A cashier account was granted full access.';
      case 'full_access_revoked':
        return hasTarget
            ? '$targetName no longer has extended privileged access.'
            : 'Extended access was removed from a cashier account.';
      case 'user_deactivated':
        return hasTarget
            ? '$targetName can no longer sign in until the account is reactivated.'
            : 'A user account was deactivated.';
      case 'user_reactivated':
        return hasTarget
            ? '$targetName can sign in again and use the system.'
            : 'A user account was reactivated.';
      case 'role_changed':
        return hasTarget ? '$targetName role permissions were changed.' : 'A user role was changed.';
      case 'manager_approval':
        return hasTarget
            ? 'This action was approved by a manager for $targetName.'
            : 'This action was approved by a manager.';
      default:
        return '';
    }
  }

  Widget _buildInlineMeta({
    required IconData icon,
    required String text,
    required Color color,
    double iconSize = 14,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaDivider() {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: _ui.textMuted.withOpacity(0.75),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final ui = _ui;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: ui.surfaceSoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ui.border),
              ),
              child: Icon(icon, size: 36, color: ui.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: ui.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ui.textSecondary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ui = _ui;

    if (!auth.hasManagementAccess) {
      return Scaffold(
        backgroundColor: ui.page,
        appBar: AppBar(
          title: const Text('User Management'),
        ),
        body: _buildEmptyState(
          icon: Icons.lock_outline,
          title: 'Access restricted',
          subtitle: 'Only managers or full-access users can access this module.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: ui.page,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ui.page,
        foregroundColor: ui.textPrimary,
        title: const Text('User Management'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageHeader(),
                    const SizedBox(height: 16),
                    if (_showLogsView) _buildLogsInlineToolbar() else _buildUsersInlineToolbar(),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: CircularProgressIndicator(color: ui.brand),
                        ),
                      )
                    else
                      (_showLogsView ? _buildLogsTab() : _buildUsersTab()),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class UserModulePalette {
  final bool isDark;
  final Color page;
  final Color pageAlt;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceAlt;
  final Color inputFill;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brand;
  final Color brandSoft;
  final Color blue;
  final Color blueSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color purple;

  const UserModulePalette({
    required this.isDark,
    required this.page,
    required this.pageAlt,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceAlt,
    required this.inputFill,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brand,
    required this.brandSoft,
    required this.blue,
    required this.blueSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.purple,
  });

  factory UserModulePalette.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brand = Color(0xFF2AAA8A);
    const blue = Color(0xFF4B8DFF);
    const success = Color(0xFF1FCF9A);
    const warning = Color(0xFFFFB65C);
    const danger = Color(0xFFFF6B7A);
    const purple = Color(0xFF8B5CF6);

    if (isDark) {
      return const UserModulePalette(
        isDark: true,
        page: Color(0xFF07111F),
        pageAlt: Color(0xFF0B1729),
        surface: Color(0xFF0F1C31),
        surfaceSoft: Color(0xFF14243C),
        surfaceAlt: Color(0xFF0A1627),
        inputFill: Color(0xFF0B1628),
        border: Color(0xFF23344D),
        borderStrong: Color(0xFF31445E),
        textPrimary: Color(0xFFF4F8FF),
        textSecondary: Color(0xFF9DB0C8),
        textMuted: Color(0xFF7F92AC),
        brand: brand,
        brandSoft: Color(0x142AAA8A),
        blue: blue,
        blueSoft: Color(0x184B8DFF),
        success: success,
        successSoft: Color(0x181FCF9A),
        warning: warning,
        warningSoft: Color(0x18FFB65C),
        danger: danger,
        dangerSoft: Color(0x18FF6B7A),
        purple: purple,
      );
    }

    return const UserModulePalette(
      isDark: false,
      page: Color(0xFFF4F7FB),
      pageAlt: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      surfaceSoft: Color(0xFFF8FAFD),
      surfaceAlt: Color(0xFFFBFCFE),
      inputFill: Color(0xFFF7F9FC),
      border: Color(0xFFD9E3EE),
      borderStrong: Color(0xFFCED9E5),
      textPrimary: Color(0xFF14263B),
      textSecondary: Color(0xFF667A92),
      textMuted: Color(0xFF778BA4),
      brand: brand,
      brandSoft: Color(0x142AAA8A),
      blue: blue,
      blueSoft: Color(0x144B8DFF),
      success: success,
      successSoft: Color(0x141FCF9A),
      warning: warning,
      warningSoft: Color(0x14FFB65C),
      danger: danger,
      dangerSoft: Color(0x14FF6B7A),
      purple: purple,
    );
  }
}
