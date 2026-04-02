import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _pinController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<AdminProvider>();
    final message = await provider.loginOwner(_pinController.text);

    if (!mounted) return;

    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message)),
        );
      return;
    }

    _pinController.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${provider.currentOwnerName}'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<AdminProvider>(
          builder: (context, provider, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F3D91), Color(0xFF284EAA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0x1FFFFFFF),
                        child: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Admin Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Use a manager PIN or a full-access user PIN to enter the owner app.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE6EBF3)),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '4-digit PIN',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF172433),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 4,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            letterSpacing: 10,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            hintText: '••••',
                            counterText: '',
                          ),
                          validator: (value) {
                            final pin = (value ?? '').trim();
                            if (pin.length != 4 || int.tryParse(pin) == null) {
                              return 'Enter a valid 4-digit PIN';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: provider.isAuthenticating ? null : _submit,
                            icon: provider.isAuthenticating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_outlined),
                            label: Text(
                              provider.isAuthenticating
                                  ? 'Signing in...'
                                  : 'Sign In',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
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
                        child: Text(
                          'This login is for owner access only. Cashiers without full access should continue using POS_APP.',
                          style: TextStyle(
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
