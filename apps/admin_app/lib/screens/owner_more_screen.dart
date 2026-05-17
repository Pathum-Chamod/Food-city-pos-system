import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';
import '../widgets/app_snackbar.dart';
import 'business_info_screen.dart';
import 'customer_monitor_screen.dart';
import 'users_activity_screen.dart';
import 'settings_screen.dart';

class OwnerMoreScreen extends StatelessWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const _HeaderCard(),
          const SizedBox(height: 16),
          const _SectionTitle(
            title: 'Owner Tools',
            subtitle: 'Support features for the owner app.',
          ),
          const SizedBox(height: 10),
          _FeatureTile(
            icon: Icons.manage_accounts_outlined,
            color: const Color(0xFF0F3D91),
            title: 'Customer Monitor',
            subtitle: 'Credit, loyalty, pricing, and customer health overview.',
            enabled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerMonitorScreen(),
                ),
              );
            },
          ),
          _FeatureTile(
            icon: Icons.store_outlined,
            color: const Color(0xFF0F3D91),
            title: 'Business Info',
            subtitle: 'Store details, contact info, and business settings.',
            enabled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BusinessInfoScreen()),
              );
            },
          ),
          _FeatureTile(
            icon: Icons.group_outlined,
            color: const Color(0xFF147A5A),
            title: 'Users & Activity',
            subtitle: 'Owner users, activity logs, and permission controls.',
            enabled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UsersActivityScreen()),
              );
            },
          ),
          _FeatureTile(
            icon: Icons.settings_outlined,
            color: const Color(0xFF7A1CAC),
            title: 'Settings',
            subtitle: 'Biometrics and data backup controls for the owner app.',
            enabled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          _FeatureTile(
            icon: Icons.logout_outlined,
            color: const Color(0xFFB42318),
            title: 'Logout',
            subtitle: 'End this admin session and return to the login screen.',
            enabled: true,
            onTap: () async {
              final confirmed =
                  await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Log out?'),
                        content: const Text(
                          'You will return to the admin login screen.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Log Out'),
                          ),
                        ],
                      );
                    },
                  ) ??
                  false;

              if (!confirmed || !context.mounted) return;
              await context.read<AdminProvider>().logout();
              if (!context.mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
              AppSnackBar.show(context, message: 'Logged out successfully.');
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tune, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'More',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Supporting tools and advanced admin areas.',
                  style: TextStyle(
                    color: Colors.white70,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
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
      ],
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
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
          onTap: enabled ? onTap : null,
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
                Icon(
                  enabled ? Icons.chevron_right : Icons.lock_outline,
                  color: const Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return enabled ? tile : Opacity(opacity: 0.82, child: tile);
  }
}
