
import 'package:flutter/material.dart';

import 'admin_home.dart';

class OwnerMoreScreen extends StatelessWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tune, color: Colors.white, size: 30),
                const SizedBox(height: 12),
                const Text(
                  'More',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Supporting tools and advanced admin areas.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MenuTile(
            icon: Icons.store_outlined,
            color: const Color(0xFF0F3D91),
            title: 'Business Info',
            subtitle: 'Store details and business settings',
            enabled: false,
          ),
          _MenuTile(
            icon: Icons.group_outlined,
            color: const Color(0xFF147A5A),
            title: 'Users & Activity',
            subtitle: 'Owner users, permissions, and activity logs',
            enabled: false,
          ),
          _MenuTile(
            icon: Icons.ios_share_outlined,
            color: const Color(0xFF9C5A00),
            title: 'Export / Share',
            subtitle: 'Share reports and summaries later',
            enabled: false,
          ),
          const SizedBox(height: 12),
          const Text(
            'Advanced Tools',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.build_outlined,
            color: const Color(0xFF7A1CAC),
            title: 'Open previous admin workspace',
            subtitle:
                'Access stock take, supplier workspace, and the older admin screen without deleting it yet.',
            enabled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminHome(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
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
    final tile = Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: enabled ? onTap : null,
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : const Icon(Icons.lock_outline, color: Color(0xFF98A2B3)),
      ),
    );

    return enabled
        ? tile
        : Opacity(
            opacity: 0.76,
            child: tile,
          );
  }
}
