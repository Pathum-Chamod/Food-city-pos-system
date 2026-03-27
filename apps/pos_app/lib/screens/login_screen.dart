import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'pos_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _enteredPin = '';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().clearLoginState();
    });
  }

  void _clearPinAndState() {
    final auth = context.read<AuthProvider>();
    auth.clearLoginState();
    setState(() {
      _enteredPin = '';
    });
  }

  void _onKeyPress(String value) {
    if (_isSubmitting) return;

    final auth = context.read<AuthProvider>();
    if (auth.loginError != null || auth.inactiveLoginAttempt) {
      auth.clearLoginState();
    }

    setState(() {
      if (value == 'CLEAR') {
        _enteredPin = '';
      } else if (value == 'DEL') {
        if (_enteredPin.isNotEmpty) {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        }
      } else if (_enteredPin.length < 4) {
        _enteredPin += value;
      }
    });

    if (_enteredPin.length == 4) {
      _attemptLogin();
    }
  }

  Future<void> _attemptLogin() async {
    if (_isSubmitting || _enteredPin.length != 4) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final auth = context.read<AuthProvider>();

    setState(() {
      _isSubmitting = true;
    });

    final success = await auth.login(_enteredPin);

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const PosScreen()),
      );
      return;
    }

    final message = auth.loginError ?? 'Login failed. Please try again.';
    final isInactive = auth.inactiveLoginAttempt;

    scaffoldMessenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(isInactive ? '⛔ $message' : '❌ $message'),
          backgroundColor: isInactive ? Colors.orange[700] : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

    setState(() {
      _enteredPin = '';
    });
  }

  Widget _buildKey(String value) {
    final isAction = value == 'CLEAR' || value == 'DEL';

    return Padding(
      padding: const EdgeInsets.all(6),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isAction ? Colors.grey[200] : Colors.white,
          foregroundColor: isAction ? Colors.red[700] : Colors.black,
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        onPressed: _isSubmitting ? null : () => _onKeyPress(value),
        child: value == 'CLEAR'
            ? const Icon(Icons.refresh, size: 26)
            : value == 'DEL'
                ? const Icon(Icons.backspace_outlined, size: 24)
                : Text(value),
      ),
    );
  }

  Widget _buildStatusCard(AuthProvider auth) {
    if (auth.loginError == null) {
      return const SizedBox(height: 18);
    }

    final isInactive = auth.inactiveLoginAttempt;
    final backgroundColor = isInactive
        ? Colors.orange.withValues(alpha: 0.12)
        : Colors.red.withValues(alpha: 0.08);
    final borderColor = isInactive ? Colors.orange.shade300 : Colors.red.shade200;
    final iconColor = isInactive ? Colors.orange.shade700 : Colors.red.shade700;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isInactive ? Icons.lock_person_rounded : Icons.error_outline,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              auth.loginError!,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return Scaffold(
          backgroundColor: Colors.blueGrey[50],
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 15),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_person,
                      size: 60,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Employee Login',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSubmitting
                          ? 'Checking PIN...'
                          : 'Enter your 4-digit PIN to access register',
                      style: TextStyle(
                        color: _isSubmitting ? Colors.blueGrey : Colors.grey,
                      ),
                    ),
                    _buildStatusCard(auth),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index < _enteredPin.length
                                ? Colors.blueAccent
                                : Colors.grey[300],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 28),
                    AbsorbPointer(
                      absorbing: _isSubmitting,
                      child: GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        childAspectRatio: 1.8,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildKey('1'),
                          _buildKey('2'),
                          _buildKey('3'),
                          _buildKey('4'),
                          _buildKey('5'),
                          _buildKey('6'),
                          _buildKey('7'),
                          _buildKey('8'),
                          _buildKey('9'),
                          _buildKey('CLEAR'),
                          _buildKey('0'),
                          _buildKey('DEL'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _clearPinAndState,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset PIN Entry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
