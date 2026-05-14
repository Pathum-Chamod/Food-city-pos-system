import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class PermissionGuard extends StatelessWidget {
  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.title = 'Access restricted',
    this.message = 'You do not have permission to open this screen.',
  });

  final String permission;
  final Widget child;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.can(permission)) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final page = isDark ? const Color(0xFF07111F) : const Color(0xFFF4F7FB);
    final text = isDark ? const Color(0xFFF4F8FF) : const Color(0xFF14263B);
    final muted = isDark ? const Color(0xFF9DB0C8) : const Color(0xFF667A92);

    return Scaffold(
      backgroundColor: page,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 46, color: muted),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
