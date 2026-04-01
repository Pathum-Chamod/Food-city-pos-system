import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class UsersActivityScreen extends StatefulWidget {
  const UsersActivityScreen({super.key});

  @override
  State<UsersActivityScreen> createState() => _UsersActivityScreenState();
}

class _UsersActivityScreenState extends State<UsersActivityScreen> {
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _activitySearchController = TextEditingController();

  String _selectedActivityFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    _activitySearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await context.read<AdminProvider>().fetchOwnerUsersActivity(
          userSearch: _userSearchController.text,
          role: 'all',
          status: 'all',
          activitySearch: _activitySearchController.text,
          activityFilter: _selectedActivityFilter,
        );
  }


  Future<void> _reloadAfterUserAction() async {
    setState(() {
      _activitySearchController.clear();
      _selectedActivityFilter = 'all';
    });
    await _load();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? const Color(0xFFD92D20) : const Color(0xFF147A5A),
        ),
      );
  }

  String _formatDateTime(String raw) {
    try {
      final dateTime = DateTime.parse(raw).toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      final day = two(dateTime.day);
      final month = two(dateTime.month);
      final year = dateTime.year;
      final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final minute = two(dateTime.minute);
      final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$day/$month/$year  $hour:$minute $suffix';
    } catch (_) {
      return raw;
    }
  }

  String _roleLabel(String value) {
    return value.toLowerCase() == 'manager' ? 'Manager' : 'Cashier';
  }

  Color _roleColor(String value) {
    return value.toLowerCase() == 'manager'
        ? const Color(0xFF7A1CAC)
        : const Color(0xFF0F3D91);
  }

  Color _activityColor(String actionType) {
    switch (actionType) {
      case 'login_success':
      case 'logout':
        return const Color(0xFF147A5A);
      case 'login_failed':
      case 'user_deactivated':
        return const Color(0xFFD92D20);
      case 'pin_reset':
      case 'role_changed':
      case 'full_access_granted':
      case 'full_access_revoked':
        return const Color(0xFF9C5A00);
      case 'user_created':
      case 'user_updated':
      case 'user_reactivated':
        return const Color(0xFF0F3D91);
      case 'manager_approval':
        return const Color(0xFF7A1CAC);
      default:
        return const Color(0xFF667085);
    }
  }

  IconData _activityIcon(String actionType) {
    switch (actionType) {
      case 'login_success':
        return Icons.login_rounded;
      case 'logout':
        return Icons.logout_rounded;
      case 'login_failed':
        return Icons.warning_amber_rounded;
      case 'pin_reset':
        return Icons.password_rounded;
      case 'user_created':
        return Icons.person_add_alt_1_rounded;
      case 'user_updated':
      case 'role_changed':
        return Icons.edit_note_rounded;
      case 'user_deactivated':
        return Icons.person_off_outlined;
      case 'user_reactivated':
        return Icons.person_outline_rounded;
      case 'full_access_granted':
      case 'full_access_revoked':
        return Icons.verified_user_outlined;
      case 'manager_approval':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.history_rounded;
    }
  }

  Future<void> _openCreateUserSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserEditorSheet(
        title: 'Add User',
        subtitle: 'Create a new cashier or manager account.',
        submitLabel: 'Create User',
        showPinField: true,
        onSubmit: (name, role, pin) async {
          final message = await context.read<AdminProvider>().createOwnerUser(
                name: name,
                role: role,
                pin: pin ?? '',
              );
          return message;
        },
      ),
    );

    if (result == true) {
      await _reloadAfterUserAction();
      _showSnack('User created successfully');
    }
  }

  Future<void> _openEditUserSheet(Map<String, dynamic> user) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserEditorSheet(
        title: 'Edit User',
        subtitle: 'Update the user name or role.',
        initialName: (user['name'] ?? '').toString(),
        initialRole: (user['role'] ?? 'cashier').toString(),
        submitLabel: 'Save Changes',
        showPinField: false,
        onSubmit: (name, role, pin) async {
          final message = await context.read<AdminProvider>().updateOwnerUserProfile(
                userId: (user['id'] as num?)?.toInt() ?? 0,
                name: name,
                role: role,
              );
          return message;
        },
      ),
    );

    if (result == true) {
      await _reloadAfterUserAction();
      _showSnack('User updated successfully');
    }
  }

  Future<void> _openResetPinSheet(Map<String, dynamic> user) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinResetSheet(
        userName: (user['name'] ?? 'User').toString(),
        onSubmit: (pin) async {
          final message = await context.read<AdminProvider>().resetOwnerUserPin(
                userId: (user['id'] as num?)?.toInt() ?? 0,
                newPin: pin,
              );
          return message;
        },
      ),
    );

    if (result == true) {
      await _reloadAfterUserAction();
      _showSnack('PIN reset successfully');
    }
  }

  Future<void> _confirmActiveStatus(Map<String, dynamic> user, bool nextIsActive) async {
    final userName = (user['name'] ?? 'User').toString();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmActionSheet(
        title: nextIsActive ? 'Reactivate User' : 'Deactivate User',
        message: nextIsActive
            ? 'Bring $userName back to active use.'
            : 'This user will no longer be able to log in until reactivated.',
        confirmLabel: nextIsActive ? 'Reactivate' : 'Deactivate',
        confirmColor: nextIsActive ? const Color(0xFF147A5A) : const Color(0xFFD92D20),
      ),
    );
    if (confirmed != true) return;

    final message = await context.read<AdminProvider>().setOwnerUserActiveStatus(
          userId: (user['id'] as num?)?.toInt() ?? 0,
          isActive: nextIsActive,
        );
    if (message != null) {
      _showSnack(message, isError: true);
      return;
    }

    await _reloadAfterUserAction();
    _showSnack(nextIsActive ? 'User reactivated' : 'User deactivated');
  }

  Future<void> _confirmFullAccess(Map<String, dynamic> user, bool nextHasFullAccess) async {
    final userName = (user['name'] ?? 'User').toString();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmActionSheet(
        title: nextHasFullAccess ? 'Grant Full Access' : 'Remove Full Access',
        message: nextHasFullAccess
            ? '$userName will receive wider access inside the POS system.'
            : '$userName will go back to normal cashier access.',
        confirmLabel: nextHasFullAccess ? 'Grant Access' : 'Remove Access',
        confirmColor: nextHasFullAccess ? const Color(0xFF147A5A) : const Color(0xFF9C5A00),
      ),
    );
    if (confirmed != true) return;

    final message = await context.read<AdminProvider>().setOwnerUserFullAccess(
          userId: (user['id'] as num?)?.toInt() ?? 0,
          hasFullAccess: nextHasFullAccess,
        );
    if (message != null) {
      _showSnack(message, isError: true);
      return;
    }

    await _reloadAfterUserAction();
    _showSnack(nextHasFullAccess ? 'Full access granted' : 'Full access removed');
  }

  Future<void> _handleUserAction(String action, Map<String, dynamic> user) async {
    switch (action) {
      case 'edit':
        await _openEditUserSheet(user);
        break;
      case 'pin':
        await _openResetPinSheet(user);
        break;
      case 'status':
        final active = ((user['is_active'] as num?)?.toInt() ?? 1) == 1;
        await _confirmActiveStatus(user, !active);
        break;
      case 'access':
        final hasFullAccess = ((user['has_full_access'] as num?)?.toInt() ?? 0) == 1;
        await _confirmFullAccess(user, !hasFullAccess);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final users = provider.ownerUsers;
    final logs = provider.ownerActivityLogs;
    final isLoading = provider.isOwnerUsersLoading;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF172433),
        elevation: 0,
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Users & Activity',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 2),
            Text(
              'Owner visibility into staff access and activity.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF667085),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF4F7FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateUserSheet,
        backgroundColor: const Color(0xFF0F3D91),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Add User',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            const _HeroCard(),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Users',
              subtitle: 'View and manage current staff access.',
              child: Column(
                children: [
                  _SearchField(
                    controller: _userSearchController,
                    hintText: 'Search by user name, role, or PIN',
                    onSubmitted: (_) => _load(),
                    onRefreshTap: _load,
                  ),
                  const SizedBox(height: 14),
                  if (isLoading && users.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (users.isEmpty)
                    const _EmptyBlock(
                      icon: Icons.group_off_outlined,
                      title: 'No users found',
                      subtitle: 'Users from POS will appear here.',
                    )
                  else
                    Column(
                      children: users.map((user) {
                        final role = (user['role'] ?? 'cashier').toString();
                        final active = ((user['is_active'] as num?)?.toInt() ?? 1) == 1;
                        final fullAccess = ((user['has_full_access'] as num?)?.toInt() ?? 0) == 1;
                        final name = (user['name'] ?? 'Unknown User').toString();
                        final pinSet = ((user['pin'] ?? '').toString().trim()).isNotEmpty;
                        final lastLogin = (user['last_login_at'] ?? '').toString();
                        return _UserTile(
                          name: name,
                          roleLabel: _roleLabel(role),
                          roleColor: _roleColor(role),
                          isActive: active,
                          hasFullAccess: fullAccess,
                          pinSet: pinSet,
                          lastLoginText: lastLogin.isEmpty
                              ? 'No login recorded yet'
                              : 'Last login • ${_formatDateTime(lastLogin)}',
                          isCurrentUser: false,
                          canToggleAccess: role.toLowerCase() != 'manager',
                          onActionSelected: (action) => _handleUserAction(action, user),
                        );
                      }).toList(growable: false),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Recent Activity',
              subtitle: 'Latest staff access and account activity.',
              child: Column(
                children: [
                  _SearchField(
                    controller: _activitySearchController,
                    hintText: 'Search by actor, target, or description',
                    onSubmitted: (_) => _load(),
                    onRefreshTap: _load,
                  ),
                  const SizedBox(height: 12),
                  _ActivityFilterBar(
                    selectedFilter: _selectedActivityFilter,
                    onChanged: (value) {
                      setState(() => _selectedActivityFilter = value);
                      _load();
                    },
                  ),
                  const SizedBox(height: 14),
                  if (isLoading && logs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (logs.isEmpty)
                    const _EmptyBlock(
                      icon: Icons.history_toggle_off_rounded,
                      title: 'No activity logs yet',
                      subtitle: 'Recent user activity will appear here.',
                    )
                  else
                    Column(
                      children: logs.map((log) {
                        final actionType = (log['action_type'] ?? '').toString();
                        return _ActivityTile(
                          icon: _activityIcon(actionType),
                          color: _activityColor(actionType),
                          title: (log['description'] ?? 'Activity').toString(),
                          subtitle: [
                            if ((log['actor_name'] ?? '').toString().trim().isNotEmpty)
                              'By ${(log['actor_name'] ?? '').toString()}',
                            if ((log['created_at'] ?? '').toString().trim().isNotEmpty)
                              _formatDateTime((log['created_at'] ?? '').toString()),
                          ].join(' • '),
                        );
                      }).toList(growable: false),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF147A5A), Color(0xFF2FA36B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.manage_accounts_outlined, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Users & Activity',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track account access, roles, and recent activity.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EBF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onSubmitted,
    required this.onRefreshTap,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onRefreshTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          onPressed: onRefreshTap,
          icon: const Icon(Icons.refresh_rounded),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6EBF3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE6EBF3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFB6C4D6)),
        ),
      ),
    );
  }
}

class _ActivityFilterBar extends StatelessWidget {
  const _ActivityFilterBar({
    required this.selectedFilter,
    required this.onChanged,
  });

  final String selectedFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label) {
      final selected = value == selectedFilter;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(value),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0F3D91) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? const Color(0xFF0F3D91) : const Color(0xFFD8E0EA),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('all', 'All'),
        chip('logins', 'Logins'),
        chip('user_changes', 'User Changes'),
        chip('pin_changes', 'PIN Changes'),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.name,
    required this.roleLabel,
    required this.roleColor,
    required this.isActive,
    required this.hasFullAccess,
    required this.pinSet,
    required this.lastLoginText,
    required this.isCurrentUser,
    required this.canToggleAccess,
    required this.onActionSelected,
  });

  final String name;
  final String roleLabel;
  final Color roleColor;
  final bool isActive;
  final bool hasFullAccess;
  final bool pinSet;
  final String lastLoginText;
  final bool isCurrentUser;
  final bool canToggleAccess;
  final ValueChanged<String> onActionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE7EFFC),
            child: Text(
              name.isNotEmpty ? name.trim()[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFF1E5EFF),
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Color(0xFF172433),
                            ),
                          ),
                          if (isCurrentUser)
                            const _InfoBadge(
                              label: 'You',
                              background: Color(0xFFEAF1FF),
                              foreground: Color(0xFF0F3D91),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: onActionSelected,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit User')),
                        const PopupMenuItem(value: 'pin', child: Text('Reset PIN')),
                        PopupMenuItem(
                          value: 'status',
                          child: Text(isActive ? 'Deactivate User' : 'Reactivate User'),
                        ),
                        if (canToggleAccess)
                          PopupMenuItem(
                            value: 'access',
                            child: Text(hasFullAccess ? 'Remove Full Access' : 'Grant Full Access'),
                          ),
                      ],
                      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF667085)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoBadge(
                      label: roleLabel,
                      background: roleColor.withOpacity(0.12),
                      foreground: roleColor,
                    ),
                    _InfoBadge(
                      label: isActive ? 'Active' : 'Inactive',
                      background: isActive ? const Color(0xFFE8FFF2) : const Color(0xFFFDECEC),
                      foreground: isActive ? const Color(0xFF147A5A) : const Color(0xFFD92D20),
                    ),
                    _InfoBadge(
                      label: pinSet ? 'PIN Set' : 'No PIN',
                      background: const Color(0xFFFFF4D6),
                      foreground: const Color(0xFF9C5A00),
                    ),
                    if (hasFullAccess)
                      const _InfoBadge(
                        label: 'Full Access',
                        background: Color(0xFFEAF1FF),
                        foreground: Color(0xFF3B4CC0),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  lastLoginText,
                  style: const TextStyle(
                    color: Color(0xFF667085),
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
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF172433),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFEAF1FF),
            child: Icon(icon, color: const Color(0xFF0F3D91), size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserEditorSheet extends StatefulWidget {
  const _UserEditorSheet({
    required this.title,
    required this.subtitle,
    required this.submitLabel,
    required this.showPinField,
    required this.onSubmit,
    this.initialName = '',
    this.initialRole = 'cashier',
  });

  final String title;
  final String subtitle;
  final String submitLabel;
  final bool showPinField;
  final Future<String?> Function(String name, String role, String? pin) onSubmit;
  final String initialName;
  final String initialRole;

  @override
  State<_UserEditorSheet> createState() => _UserEditorSheetState();
}

class _UserEditorSheetState extends State<_UserEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  late String _role;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _pinController = TextEditingController();
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    final message = await widget.onSubmit(
      _nameController.text.trim(),
      _role,
      widget.showPinField ? _pinController.text.trim() : null,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFD92D20),
        ),
      );
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8E0EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172433),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _nameController,
                decoration: _sheetInputDecoration('User Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: _sheetInputDecoration('Role'),
                items: const [
                  DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _role = value);
                  }
                },
              ),
              if (widget.showPinField) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  decoration: _sheetInputDecoration('4-digit PIN').copyWith(counterText: ''),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F3D91),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.submitLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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

class _PinResetSheet extends StatefulWidget {
  const _PinResetSheet({
    required this.userName,
    required this.onSubmit,
  });

  final String userName;
  final Future<String?> Function(String pin) onSubmit;

  @override
  State<_PinResetSheet> createState() => _PinResetSheetState();
}

class _PinResetSheetState extends State<_PinResetSheet> {
  final TextEditingController _pinController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    final message = await widget.onSubmit(_pinController.text.trim());
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFD92D20),
        ),
      );
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8E0EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Reset PIN',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172433),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set a new 4-digit PIN for ${widget.userName}.',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: _sheetInputDecoration('New 4-digit PIN').copyWith(counterText: ''),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F3D91),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Reset PIN',
                          style: TextStyle(fontWeight: FontWeight.w700),
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

class _ConfirmActionSheet extends StatelessWidget {
  const _ConfirmActionSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E0EA),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172433),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _sheetInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF8FAFD),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE6EBF3)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE6EBF3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFB6C4D6)),
    ),
  );
}
