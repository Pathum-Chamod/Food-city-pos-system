import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/admin_provider.dart';
import 'screens/admin_login_screen.dart';
import 'screens/owner_shell.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AdminProvider()),
      ],
      child: const AdminApp(),
    ),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Store Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFF0F3D91),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD8E0EF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD8E0EF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF0F3D91), width: 1.4),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFD8E0EF)),
          ),
          selectedColor: const Color(0xFFE6F0FF),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          side: const BorderSide(color: Color(0xFFD8E0EF)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        ),
      ),
      home: const _AdminRoot(),
    );
  }
}

class _AdminRoot extends StatelessWidget {
  const _AdminRoot();

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminProvider>(
      builder: (context, provider, _) {
        if (!provider.isSessionReady) {
          return const _SessionLoadingScreen();
        }

        if (provider.isAuthenticated) {
          return const OwnerShell();
        }

        return const AdminLoginScreen();
      },
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'Preparing Admin App...',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF172433),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
