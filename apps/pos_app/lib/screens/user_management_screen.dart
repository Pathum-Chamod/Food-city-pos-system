import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadAll();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging || !_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _userSearchController.dispose();
    _logSearchController.dispose();
    super.dispose();
  }

  int? get _actorUserId => context.read<AuthProvider>().currentUser?.id;

  String get _actorName =>
      context.read<AuthProvider>().currentUser?.name ?? 'System';

  bool get _isManager => context.read<AuthProvider>().isManager;

  Future<void> _loadAll({bool keepUserActivityFilter = true}) async {
    if (!mounted) return;

    final relatedUserId = keepUserActivityFilter ? _selectedActivityUserId : null;
    final logSearch = _logSearchController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        DatabaseHelper.instance.getUserSummaryCounts(),
        DatabaseHelper.instance.getUsers(
          search: _userSearchController.text,
          role: _userRoleFilter,
          status: _userStatusFilter,
        ),
        DatabaseHelper.instance.getUserLogs(
          search: logSearch,
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
        backgroundColor: Colors.red,
      );
    }
  }

  void _showMessage(String message, {Color? backgroundColor}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
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
        return Colors.green;
      case 'login_failed':
      case 'user_deactivated':
        return Colors.red;
      case 'pin_reset':
      case 'manager_approval':
        return Colors.orange;
      case 'role_changed':
      case 'user_updated':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showUserFormBottomSheet({Map<String, dynamic>? user}) async {
    final isEdit = user != null;
    final nameController = TextEditingController(text: (user?['name'] ?? '').toString());
    final pinController = TextEditingController();
    var role = (user?['role'] ?? 'cashier').toString().trim().toLowerCase();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD5DCE7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isEdit ? 'Edit User' : 'Add User',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isEdit
                                        ? 'Update the user profile details.'
                                        : 'Create a new cashier or manager account.',
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _fieldDecoration(
                            hintText: 'Enter full name',
                            labelText: 'Full Name',
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: role,
                          items: const [
                            DropdownMenuItem(value: 'manager', child: Text('Manager')),
                            DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() {
                              role = value;
                            });
                          },
                          decoration: _fieldDecoration(
                            hintText: 'Select role',
                            labelText: 'Role',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                        if (!isEdit) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: _fieldDecoration(
                              hintText: '4-digit PIN',
                              labelText: 'PIN',
                              icon: Icons.pin_outlined,
                              counterText: '',
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    final name = nameController.text.trim();
                                    final pin = pinController.text.trim();

                                    if (name.isEmpty) {
                                      _showMessage(
                                        'User name is required.',
                                        backgroundColor: Colors.orange,
                                      );
                                      return;
                                    }

                                    if (!isEdit && !RegExp(r'^\d{4}$').hasMatch(pin)) {
                                      _showMessage(
                                        'PIN must be exactly 4 digits.',
                                        backgroundColor: Colors.orange,
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
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(isEdit ? 'SAVE CHANGES' : 'CREATE USER'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
    final previousRole = (user?['role'] ?? 'cashier').toString().trim().toLowerCase();
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
      Navigator.pop(context);
      await _loadAll(keepUserActivityFilter: false);
      _showMessage(
        isEdit
            ? (roleChanged
                ? 'User role updated successfully.'
                : 'User details updated successfully.')
            : 'User created successfully.',
        backgroundColor: Colors.green,
      );
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showResetPinDialog(Map<String, dynamic> user) async {
    final pinController = TextEditingController();
    final userId = ((user['id'] as num?) ?? 0).toInt();
    final userName = (user['name'] ?? 'User').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Reset PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set a new 4-digit PIN for $userName.'),
            const SizedBox(height: 12),
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
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final pin = pinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      _showMessage(
        'PIN must be exactly 4 digits.',
        backgroundColor: Colors.orange,
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
      _showMessage('PIN reset for $userName.', backgroundColor: Colors.green);
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: Colors.red,
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
        backgroundColor: Colors.orange,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(isActive ? 'Deactivate User?' : 'Reactivate User?'),
        content: Text(
          isActive
              ? 'This will block $userName from logging in until reactivated.'
              : 'This will allow $userName to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
        backgroundColor: Colors.green,
      );
      await context.read<AuthProvider>().refreshCurrentUser();
    } catch (e) {
      _showMessage(
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: Colors.red,
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
    });
    _tabController.animateTo(1);
    _loadAll();
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    String? labelText,
    IconData? icon,
    Widget? suffixIcon,
    String? counterText,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      counterText: counterText,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.blue.shade700, width: 1.4),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E9F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E9F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _buildSegmentItem(index: 0, label: 'Users', icon: Icons.group_outlined)),
          const SizedBox(width: 8),
          Expanded(child: _buildSegmentItem(index: 1, label: 'User Log', icon: Icons.history_outlined)),
        ],
      ),
    );
  }

  Widget _buildSegmentItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _tabController.index == index;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _tabController.animateTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEAF2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF9DBFFF) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? const Color(0xFF1552C4) : Colors.grey.shade600,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF1552C4) : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E9F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildUsersToolbar() {
    return _buildToolbarCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1050;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 420,
                child: TextField(
                  controller: _userSearchController,
                  decoration: _fieldDecoration(
                    hintText: 'Search users by name, role, or PIN',
                    icon: Icons.search,
                    suffixIcon: _userSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _userSearchController.clear();
                              setState(() {});
                              _loadAll(keepUserActivityFilter: false);
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadAll(keepUserActivityFilter: false),
                ),
              ),
              SizedBox(
                width: compact ? (constraints.maxWidth - 12) / 2 : 180,
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
              ),
              SizedBox(
                width: compact ? (constraints.maxWidth - 12) / 2 : 180,
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
              ),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () => _showUserFormBottomSheet(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add User'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = (user['name'] ?? 'User').toString();
    final role = (user['role'] ?? 'cashier').toString().trim().toLowerCase();
    final isActive = ((user['is_active'] as num?) ?? 1).toInt() == 1;
    final initial = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    final userId = ((user['id'] as num?) ?? 0).toInt();
    final isSelf = _actorUserId == userId;
    final activeManagerCount = _users.where((entry) {
      final entryRole = (entry['role'] ?? 'cashier').toString().trim().toLowerCase();
      final entryActive = ((entry['is_active'] as num?) ?? 1).toInt() == 1;
      return entryRole == 'manager' && entryActive;
    }).length;
    final isLastActiveManager = role == 'manager' && isActive && activeManagerCount <= 1;
    final toggleDisabled = isActive && (isSelf || isLastActiveManager);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E9F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFEAF2FF) : const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: isActive ? const Color(0xFF1552C4) : Colors.grey[700],
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (isSelf)
                      _buildPill(label: 'You', color: Colors.blue, compact: true),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPill(
                      label: _formatRole(role),
                      color: role == 'manager' ? Colors.deepPurple : Colors.teal,
                    ),
                    _buildPill(
                      label: isActive ? 'Active' : 'Inactive',
                      color: isActive ? Colors.green : Colors.red,
                    ),
                    _buildPill(label: 'PIN Set', color: Colors.orange),
                    if (isLastActiveManager)
                      _buildPill(label: 'Last Active Manager', color: Colors.indigo),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Last login • ${_formatLastLogin(user['last_login_at'])}',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E9F2)),
            ),
            child: PopupMenuButton<String>(
              tooltip: 'User actions',
              splashRadius: 22,
              icon: const Icon(Icons.more_vert_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (value) {
                if (value == 'edit') {
                  _showUserFormBottomSheet(user: user);
                } else if (value == 'pin') {
                  _showResetPinDialog(user);
                } else if (value == 'toggle') {
                  _toggleUserStatus(user);
                } else if (value == 'activity') {
                  _viewUserActivity(user);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit user'),
                ),
                const PopupMenuItem(
                  value: 'pin',
                  child: Text('Reset PIN'),
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
                const PopupMenuItem(
                  value: 'activity',
                  child: Text('View activity'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        _buildUsersToolbar(),
        const SizedBox(height: 16),
        Expanded(
          child: _users.isEmpty
              ? _buildEmptyState(
                  icon: Icons.group_outlined,
                  title: 'No users found',
                  subtitle: 'Try changing the filters or add a new user.',
                )
              : ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _buildUserCard(_users[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildLogFilterChip(String value) {
    final selected = _logFilter == value;
    return FilterChip(
      label: Text(_formatLogFilterLabel(value)),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _logFilter = value;
        });
        _loadAll();
      },
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? const Color(0xFF1552C4) : Colors.grey[800],
      ),
      backgroundColor: const Color(0xFFF7F9FC),
      selectedColor: const Color(0xFFEAF2FF),
      side: BorderSide(
        color: selected ? const Color(0xFF9DBFFF) : const Color(0xFFE3E9F2),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }

  Widget _buildLogsToolbar() {
    return _buildToolbarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Feed',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search and filter user activity, approvals, and account changes.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    child: TextField(
                      controller: _logSearchController,
                      decoration: _fieldDecoration(
                        hintText: 'Search activity, user, or approval details',
                        icon: Icons.search,
                        suffixIcon:
                            (_logSearchController.text.isEmpty && _selectedActivityUserName == null)
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
                                    icon: const Icon(Icons.close),
                                  ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _loadAll(),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildLogFilterChip('all'),
                      _buildLogFilterChip('logins'),
                      _buildLogFilterChip('user_changes'),
                      _buildLogFilterChip('pin_changes'),
                      _buildLogFilterChip('approvals'),
                    ],
                  ),
                ],
              );
            },
          ),
          if (_selectedActivityUserName != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF9DBFFF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_search_outlined, color: Color(0xFF1552C4), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Viewing activity for $_selectedActivityUserName',
                      style: const TextStyle(
                        color: Color(0xFF1552C4),
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
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 18, color: Color(0xFF1552C4)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
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

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E9F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _actionIcon(actionType),
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildPill(label: _formatActionLabel(actionType), color: color),
                    _buildLogInfoChip(
                      icon: Icons.schedule_outlined,
                      text: formattedTime,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (actorName.isNotEmpty)
                      _buildLogInfoChip(
                        icon: Icons.person_outline_rounded,
                        text: actorName,
                      ),
                    if (targetName.isNotEmpty && targetName.toLowerCase() != actorName.toLowerCase())
                      _buildLogInfoChip(
                        icon: Icons.badge_outlined,
                        text: targetName,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return Column(
      children: [
        _buildLogsToolbar(),
        const SizedBox(height: 16),
        Expanded(
          child: _logs.isEmpty
              ? _buildEmptyState(
                  icon: Icons.history_toggle_off,
                  title: 'No log records found',
                  subtitle: 'User activity will appear here once actions are recorded.',
                )
              : ListView.separated(
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _buildLogCard(_logs[index]),
                ),
        ),
      ],
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
        return hasTarget
            ? '$targetName now has an updated PIN.'
            : 'A user PIN was reset.';
      case 'user_deactivated':
        return hasTarget
            ? '$targetName can no longer sign in until the account is reactivated.'
            : 'A user account was deactivated.';
      case 'user_reactivated':
        return hasTarget
            ? '$targetName can sign in again and use the system.'
            : 'A user account was reactivated.';
      case 'role_changed':
        return hasTarget
            ? '$targetName role permissions were changed.'
            : 'A user role was changed.';
      case 'manager_approval':
        return hasTarget
            ? 'This action was approved by a manager for $targetName.'
            : 'This action was approved by a manager.';
      default:
        return '';
    }
  }

  Widget _buildLogInfoChip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E9F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey[800],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE3E9F2)),
              ),
              child: Icon(icon, size: 36, color: Colors.grey[500]),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(BoxConstraints constraints) {
    final isNarrow = constraints.maxWidth < 980;
    final itemWidth = isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: itemWidth,
          child: _buildSummaryCard(
            title: 'Total Users',
            value: ((_summary['total_users'] as num?) ?? 0).toInt(),
            icon: Icons.group_outlined,
            color: Colors.blue,
          ),
        ),
        SizedBox(
          width: itemWidth,
          child: _buildSummaryCard(
            title: 'Active Users',
            value: ((_summary['active_users'] as num?) ?? 0).toInt(),
            icon: Icons.verified_user_outlined,
            color: Colors.green,
          ),
        ),
        SizedBox(
          width: itemWidth,
          child: _buildSummaryCard(
            title: 'Managers',
            value: ((_summary['managers'] as num?) ?? 0).toInt(),
            icon: Icons.admin_panel_settings_outlined,
            color: Colors.deepPurple,
          ),
        ),
        SizedBox(
          width: itemWidth,
          child: _buildSummaryCard(
            title: 'Cashiers',
            value: ((_summary['cashiers'] as num?) ?? 0).toInt(),
            icon: Icons.point_of_sale_outlined,
            color: Colors.teal,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isManager) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('User Management'),
        ),
        body: _buildEmptyState(
          icon: Icons.lock_outline,
          title: 'Access restricted',
          subtitle: 'Only managers can access this module.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _loadAll(),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            children: [
              LayoutBuilder(builder: (context, constraints) {
                return _buildSummaryGrid(constraints);
              }),
              const SizedBox(height: 14),
              _buildSegmentedTabs(),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBFCFE),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE3E9F2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.025),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildUsersTab(),
                            _buildLogsTab(),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
