import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isLoggingOut = false;

  Future<void> _handleBackupExport() async {
    setState(() => _isExporting = true);
    final message = await context.read<AdminProvider>().exportDataBackup();
    if (!mounted) return;
    setState(() => _isExporting = false);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message ?? 'Backup file created and opened in the share sheet.',
          ),
        ),
      );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Log out?'),
              content: const Text(
                'You will return to the admin login screen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Log Out'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _isLoggingOut = true);
    await context.read<AdminProvider>().logout();
    if (!mounted) return;
    setState(() => _isLoggingOut = false);

    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Logged out successfully.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF222B45), Color(0xFF3F4C6B)],
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
                    child: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${provider.currentOwnerName} • ${provider.currentOwnerRole.isEmpty ? 'Owner Access' : provider.currentOwnerRole.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'App Actions',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF172433),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.backup_outlined,
              color: const Color(0xFF9C5A00),
              title: 'Data Backup',
              subtitle: 'Export a JSON backup snapshot through the device share sheet.',
              trailing: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isExporting ? null : _handleBackupExport,
            ),
            _SettingsTile(
              icon: Icons.logout_outlined,
              color: const Color(0xFFB42318),
              title: 'Logout',
              subtitle: 'End the current admin session and return to the login screen.',
              trailing: _isLoggingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isLoggingOut ? null : _handleLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
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
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconTheme(
                  data: const IconThemeData(color: Color(0xFF98A2B3)),
                  child: trailing ?? const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
