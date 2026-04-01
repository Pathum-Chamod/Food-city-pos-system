import 'package:flutter/material.dart';

import 'admin_home.dart';
import 'users_activity_screen.dart';

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
          const _FeatureTile(
            icon: Icons.store_outlined,
            color: Color(0xFF0F3D91),
            title: 'Business Info',
            subtitle: 'Store details, contact info, and business settings.',
            status: 'Coming Soon',
            enabled: false,
          ),
          _FeatureTile(
            icon: Icons.group_outlined,
            color: const Color(0xFF147A5A),
            title: 'Users & Activity',
            subtitle: 'Owner users, activity logs, and permission controls.',
            status: 'Available',
            enabled: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UsersActivityScreen(),
                ),
              );
            },
          ),
          const _FeatureTile(
            icon: Icons.ios_share_outlined,
            color: Color(0xFF9C5A00),
            title: 'Export / Share',
            subtitle: 'Share snapshots and reports when export tools are added.',
            status: 'Coming Soon',
            enabled: false,
          ),
          const _FeatureTile(
            icon: Icons.settings_outlined,
            color: Color(0xFF7A1CAC),
            title: 'Settings',
            subtitle: 'Owner app preferences and future notification settings.',
            status: 'Coming Soon',
            enabled: false,
          ),
          const SizedBox(height: 18),
          const _SectionTitle(
            title: 'Advanced Tools',
            subtitle: 'Older operational tools kept outside the main owner flow.',
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFBD7A3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFFFFEDD5),
                  child: Icon(
                    Icons.info_outline,
                    color: Color(0xFFB45309),
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Advanced tools are separated on purpose',
                        style: TextStyle(
                          color: Color(0xFF9A3412),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Stock take, supplier workspace, and older admin actions stay here so the main owner app remains clean and focused.',
                        style: TextStyle(
                          color: Color(0xFF9A3412),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _FeatureTile(
            icon: Icons.build_outlined,
            color: const Color(0xFF7A1CAC),
            title: 'Open Previous Admin Workspace',
            subtitle:
                'Access stock take, supplier workspace, and the old operational admin screen.',
            status: 'Available',
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
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

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
    required this.status,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String status;
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF172433),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: status,
                            enabled: enabled,
                          ),
                        ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final background = enabled
        ? const Color(0xFFE8FFF2)
        : const Color(0xFFF2F4F7);
    final foreground = enabled
        ? const Color(0xFF147A5A)
        : const Color(0xFF667085);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
