import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/app_theme_provider.dart';
import 'pos_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color _brandColor = Color(0xFF2AAA8A);

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

  bool get _isDarkMode => context.read<AppThemeProvider>().isDarkMode;

  Color get _pageBackground => _isDarkMode
      ? const Color(0xFF071427)
      : const Color(0xFFF4F7FB);

  Color get _surfaceColor => _isDarkMode
      ? const Color(0xFF0E213F)
      : const Color(0xFFFFFFFF);

  Color get _surfaceSoft => _isDarkMode
      ? const Color(0xFF142B4D)
      : const Color(0xFFF7FAFD);

  Color get _panelColor => _isDarkMode
      ? const Color(0xFF102645)
      : const Color(0xFFFFFFFF);

  Color get _cardBorder => _isDarkMode
      ? Colors.white.withOpacity(0.08)
      : const Color(0xFFD9E4F0);

  Color get _mutedText => _isDarkMode
      ? const Color(0xFF93A7C2)
      : const Color(0xFF61758F);

  Color get _strongText => _isDarkMode
      ? const Color(0xFFF2F7FC)
      : const Color(0xFF18263A);

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

  Widget _buildThemeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: IconButton(
        tooltip: _isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: () {
          context.read<AppThemeProvider>().toggleTheme();
        },
        icon: Icon(
          _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          color: _brandColor,
        ),
      ),
    );
  }

  Widget _buildBrandPanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDarkMode ? 0.28 : 0.05),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _brandColor.withOpacity(_isDarkMode ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _brandColor.withOpacity(0.22),
              ),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: _brandColor,
              size: 34,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'FOOD CITY POS',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: _strongText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Premium cashier workspace with fast PIN login, polished checkout flow, and a clean modern design system.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: _mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          _buildFeaturePill(Icons.qr_code_scanner_rounded, 'Fast barcode-ready selling'),
          const SizedBox(height: 12),
          _buildFeaturePill(Icons.receipt_long_rounded, 'Smooth checkout and receipt flow'),
          const SizedBox(height: 12),
          _buildFeaturePill(Icons.dark_mode_rounded, 'Premium light and dark UI'),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _surfaceSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _brandColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: _brandColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure employee access',
                        style: TextStyle(
                          color: _strongText,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use your 4-digit PIN to enter the register.',
                        style: TextStyle(
                          color: _mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _brandColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _brandColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: _strongText,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < _enteredPin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isFilled ? 22 : 18,
          height: isFilled ? 22 : 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? _brandColor : Colors.transparent,
            border: Border.all(
              color: isFilled ? _brandColor : _cardBorder,
              width: 2,
            ),
            boxShadow: isFilled
                ? [
                    BoxShadow(
                      color: _brandColor.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildStatusCard(AuthProvider auth) {
    if (auth.loginError == null) {
      return const SizedBox(height: 14);
    }

    final isInactive = auth.inactiveLoginAttempt;
    final backgroundColor = isInactive
        ? Colors.orange.withOpacity(_isDarkMode ? 0.14 : 0.10)
        : Colors.red.withOpacity(_isDarkMode ? 0.14 : 0.08);
    final borderColor = isInactive
        ? Colors.orange.withOpacity(0.30)
        : Colors.red.withOpacity(0.24);
    final iconColor = isInactive ? Colors.orange.shade700 : Colors.red.shade700;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isInactive ? Icons.lock_person_rounded : Icons.error_outline_rounded,
            color: iconColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              auth.loginError!,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String value) {
    final isAction = value == 'CLEAR' || value == 'DEL';
    final Color buttonColor = isAction
        ? (_isDarkMode ? const Color(0xFF14284B) : const Color(0xFFF5F7FB))
        : _surfaceSoft;

    final Color foreground = isAction
        ? (_isDarkMode ? Colors.white : const Color(0xFF24364F))
        : _strongText;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _isSubmitting ? null : () => _onKeyPress(value),
          child: Ink(
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isDarkMode ? 0.14 : 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: value == 'CLEAR'
                  ? Icon(Icons.refresh_rounded, size: 24, color: foreground)
                  : value == 'DEL'
                      ? Icon(Icons.backspace_outlined, size: 24, color: foreground)
                      : Text(
                          value,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: foreground,
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginPanel(AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDarkMode ? 0.28 : 0.06),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _brandColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.lock_person_rounded,
                  color: _brandColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employee Login',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _strongText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSubmitting
                          ? 'Checking PIN...'
                          : 'Enter your 4-digit PIN to access the register.',
                      style: TextStyle(
                        color: _mutedText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _buildStatusCard(auth),
          const SizedBox(height: 24),
          Center(child: _buildPinDots()),
          const SizedBox(height: 24),
          AbsorbPointer(
            absorbing: _isSubmitting,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 1.22,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                '1', '2', '3',
                '4', '5', '6',
                '7', '8', '9',
                'CLEAR', '0', 'DEL',
              ].map(_buildKey).toList(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _isSubmitting ? null : _clearPinAndState,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset PIN Entry'),
              style: TextButton.styleFrom(
                foregroundColor: _brandColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
        context.watch<AppThemeProvider>();
        return Scaffold(
          backgroundColor: _pageBackground,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isDarkMode
                    ? const [Color(0xFF071427), Color(0xFF0A1C33), Color(0xFF0D2340)]
                    : const [Color(0xFFF5F7FB), Color(0xFFF2F8FB), Color(0xFFF8FBFC)],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 980;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 40,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _buildThemeToggle(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1260),
                              child: isWide
                                  ? SizedBox(
                                      height: 720,
                                      child: Row(
                                        children: [
                                          Expanded(flex: 11, child: _buildBrandPanel()),
                                          const SizedBox(width: 22),
                                          Expanded(flex: 9, child: _buildLoginPanel(auth)),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        _buildBrandPanel(),
                                        const SizedBox(height: 18),
                                        _buildLoginPanel(auth),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
