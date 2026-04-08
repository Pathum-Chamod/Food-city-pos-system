import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../providers/auth_provider.dart';
import 'pos_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color _brandColor = Color(0xFF2AAA8A);
  static const Color _accentColor = Color(0xFF7C9BFF);
  static const Color _warningColor = Color(0xFFF4A340);

  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'login_screen');
  String _enteredPin = '';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().clearLoginState();
      _focusKeyboard();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  bool get _isDarkMode => context.read<AppThemeProvider>().isDarkMode;

  Color get _pageBackground =>
      _isDarkMode ? const Color(0xFF09121E) : const Color(0xFFF5F7FB);

  Color get _cardColor =>
      _isDarkMode ? const Color(0xFF101C2C) : const Color(0xFFFFFFFF);

  Color get _surfaceSoft =>
      _isDarkMode ? const Color(0xFF162436) : const Color(0xFFF4F7FB);

  Color get _borderColor => _isDarkMode
      ? Colors.white.withOpacity(0.08)
      : const Color(0xFFD9E2EC);

  Color get _primaryText =>
      _isDarkMode ? const Color(0xFFF3F7FB) : const Color(0xFF1B2838);

  Color get _secondaryText =>
      _isDarkMode ? const Color(0xFFA3B3C8) : const Color(0xFF66788F);

  Color get _hintText =>
      _isDarkMode ? const Color(0xFF7F93AD) : const Color(0xFF8393A8);

  void _focusKeyboard() {
    if (!_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
    }
  }

  void _clearPinAndState() {
    context.read<AuthProvider>().clearLoginState();
    setState(() {
      _enteredPin = '';
    });
    _focusKeyboard();
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isSubmitting) {
      return KeyEventResult.ignored;
    }

    final label = event.logicalKey.keyLabel;
    if (RegExp(r'^\d$').hasMatch(label)) {
      _onKeyPress(label);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _onKeyPress('DEL');
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearPinAndState();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _attemptLogin();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
      navigator.pushReplacement(_buildPosRoute(auth.currentUser?.name));
      return;
    }

    final message = auth.loginError ?? 'Login failed. Please try again.';
    final isInactive = auth.inactiveLoginAttempt;

    scaffoldMessenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isInactive ? 'Access blocked: $message' : 'Login failed: $message',
          ),
          backgroundColor: isInactive ? Colors.orange[700] : Colors.red,
        ),
      );

    setState(() {
      _enteredPin = '';
    });

    _focusKeyboard();
  }

  Route<void> _buildPosRoute(String? userName) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 720),
      reverseTransitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (_, animation, secondaryAnimation) => PosScreen(
        showWelcomeAnimation: true,
        welcomeUserName: userName,
      ),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.78, curve: Curves.easeOut),
        );
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.045),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final scale = Tween<double>(
          begin: 0.985,
          end: 1,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor.withOpacity(_isDarkMode ? 0.88 : 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
      ),
      child: IconButton(
        tooltip: _isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: () {
          context.read<AppThemeProvider>().toggleTheme();
          _focusKeyboard();
        },
        icon: Icon(
          _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          color: _brandColor,
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, {bool isDense = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDense ? 10 : 12,
        vertical: isDense ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _brandColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _primaryText,
              fontSize: isDense ? 12.5 : 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(AuthProvider auth, {bool isDense = false}) {
    late final IconData icon;
    late final String message;
    late final Color tone;
    late final Color background;
    late final Color border;

    if (_isSubmitting) {
      icon = Icons.hourglass_top_rounded;
      message = 'Checking your PIN...';
      tone = _accentColor;
      background = tone.withOpacity(_isDarkMode ? 0.16 : 0.10);
      border = tone.withOpacity(0.22);
    } else if (auth.loginError != null) {
      final isInactive = auth.inactiveLoginAttempt;
      icon = isInactive
          ? Icons.lock_person_rounded
          : Icons.error_outline_rounded;
      message = auth.loginError!;
      tone = isInactive ? _warningColor : Colors.red.shade400;
      background = tone.withOpacity(_isDarkMode ? 0.16 : 0.10);
      border = tone.withOpacity(0.22);
    } else {
      icon = Icons.verified_user_rounded;
      message = 'Enter 4 digits. Sign in will submit automatically.';
      tone = _brandColor;
      background = tone.withOpacity(_isDarkMode ? 0.14 : 0.10);
      border = tone.withOpacity(0.20);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isDense ? 12 : 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: tone,
                fontSize: isDense ? 13 : 14,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinSlot(int index, {bool isDense = false}) {
    final isFilled = index < _enteredPin.length;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: isDense ? 56 : 66,
        margin: EdgeInsets.only(right: index == 3 ? 0 : (isDense ? 8 : 10)),
        decoration: BoxDecoration(
          color: isFilled ? _brandColor.withOpacity(0.12) : _surfaceSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isFilled ? _brandColor : _borderColor,
            width: isFilled ? 1.4 : 1,
          ),
        ),
        child: Center(
          child: Icon(
            isFilled ? Icons.circle_rounded : Icons.circle_outlined,
            size: isDense ? 12 : 14,
            color: isFilled ? _brandColor : _hintText,
          ),
        ),
      ),
    );
  }

  Widget _buildPinPanel({bool isDense = false}) {
    return Container(
      padding: EdgeInsets.all(isDense ? 14 : 18),
      decoration: BoxDecoration(
        color: _surfaceSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Employee PIN',
                style: TextStyle(
                  color: _primaryText,
                  fontSize: isDense ? 14 : 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${_enteredPin.length}/4',
                style: TextStyle(
                  color: _secondaryText,
                  fontSize: isDense ? 13 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: isDense ? 12 : 16),
          Row(
            children: List.generate(
              4,
              (index) => _buildPinSlot(index, isDense: isDense),
            ),
          ),
          if (_isSubmitting) ...[
            SizedBox(height: isDense ? 10 : 14),
            LinearProgressIndicator(
              minHeight: isDense ? 5 : 6,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: _cardColor,
              valueColor: const AlwaysStoppedAnimation<Color>(_brandColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKey(String value, {bool isDense = false}) {
    final isAction = value == 'CLEAR' || value == 'DEL';

    return Padding(
      padding: EdgeInsets.all(isDense ? 3.5 : 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(isDense ? 16 : 20),
          onTap: _isSubmitting
              ? null
              : () {
                  _focusKeyboard();
                  _onKeyPress(value);
                },
          child: Ink(
            decoration: BoxDecoration(
              color: isAction ? _surfaceSoft : _cardColor,
              borderRadius: BorderRadius.circular(isDense ? 16 : 20),
              border: Border.all(
                color: isAction ? _borderColor : _brandColor.withOpacity(0.20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isDarkMode ? 0.18 : 0.04),
                  blurRadius: isDense ? 8 : 12,
                  offset: Offset(0, isDense ? 5 : 8),
                ),
              ],
            ),
            child: Center(
              child: value == 'CLEAR'
                  ? Icon(
                      Icons.refresh_rounded,
                      color: _primaryText,
                      size: isDense ? 20 : 24,
                    )
                  : value == 'DEL'
                      ? Icon(
                          Icons.backspace_rounded,
                          color: _primaryText,
                          size: isDense ? 20 : 24,
                        )
                      : Text(
                          value,
                          style: TextStyle(
                            color: _primaryText,
                            fontSize: isDense ? 20 : 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(AuthProvider auth, bool isCompact, bool isDense) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? (isDense ? 18 : 22) : (isDense ? 22 : 30),
        isCompact ? (isDense ? 20 : 24) : (isDense ? 22 : 30),
        isCompact ? (isDense ? 18 : 22) : (isDense ? 22 : 30),
        isDense ? 16 : 22,
      ),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(isDense ? 28 : 32),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDarkMode ? 0.24 : 0.06),
            blurRadius: isDense ? 22 : 30,
            offset: Offset(0, isDense ? 12 : 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: isDense ? 58 : 68,
            height: isDense ? 58 : 68,
            decoration: BoxDecoration(
              color: _brandColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(isDense ? 18 : 22),
              border: Border.all(color: _brandColor.withOpacity(0.20)),
            ),
            child: Icon(
              Icons.storefront_rounded,
              color: _brandColor,
              size: isDense ? 28 : 32,
            ),
          ),
          SizedBox(height: isDense ? 14 : 18),
          Text(
            'FOOD CITY POS',
            style: TextStyle(
              color: _brandColor,
              fontSize: isDense ? 12 : 13,
              fontWeight: FontWeight.w900,
              letterSpacing: isDense ? 0.9 : 1.1,
            ),
          ),
          SizedBox(height: isDense ? 8 : 10),
          Text(
            'Welcome back',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _primaryText,
              fontSize: isCompact
                  ? (isDense ? 24 : 28)
                  : (isDense ? 28 : 32),
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: isDense ? 6 : 8),
          Text(
            'Use your 4-digit PIN to access the register.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _secondaryText,
              fontSize: isDense ? 13 : 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: isDense ? 14 : 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: isDense ? 8 : 10,
            runSpacing: isDense ? 8 : 10,
            children: [
              _buildMetaChip(Icons.pin_rounded, 'Secure PIN', isDense: isDense),
              _buildMetaChip(
                Icons.keyboard_rounded,
                'Numpad Ready',
                isDense: isDense,
              ),
            ],
          ),
          SizedBox(height: isDense ? 14 : 20),
          _buildStatusCard(auth, isDense: isDense),
          SizedBox(height: isDense ? 14 : 18),
          _buildPinPanel(isDense: isDense),
          SizedBox(height: isDense ? 12 : 18),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            crossAxisSpacing: isDense ? 2 : 0,
            mainAxisSpacing: isDense ? 2 : 0,
            childAspectRatio: isDense ? 1.34 : 1.16,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              '1',
              '2',
              '3',
              '4',
              '5',
              '6',
              '7',
              '8',
              '9',
              'CLEAR',
              '0',
              'DEL',
            ].map((value) => _buildKey(value, isDense: isDense)).toList(),
          ),
          SizedBox(height: isDense ? 8 : 12),
          Text(
            'Enter submits, Backspace deletes, Esc resets.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _hintText,
              fontSize: isDense ? 12.5 : 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: isDense ? 2 : 6),
          TextButton.icon(
            onPressed: _isSubmitting ? null : _clearPinAndState,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset PIN Entry'),
            style: TextButton.styleFrom(
              foregroundColor: _brandColor,
              visualDensity:
                  isDense ? VisualDensity.compact : VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundOrb({
    required double size,
    required List<Color> colors,
    double blur = 12,
  }) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    context.watch<AppThemeProvider>();

    return Scaffold(
      backgroundColor: _pageBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _focusKeyboard,
        child: Focus(
          autofocus: true,
          focusNode: _keyboardFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _isDarkMode
                          ? const [
                              Color(0xFF08111C),
                              Color(0xFF0B1624),
                              Color(0xFF0D1929),
                            ]
                          : const [
                              Color(0xFFF7F9FC),
                              Color(0xFFF3F7FB),
                              Color(0xFFEEF3F8),
                            ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -80,
                right: -50,
                child: _buildBackgroundOrb(
                  size: 220,
                  colors: [
                    _brandColor.withOpacity(0.24),
                    _brandColor.withOpacity(0.02),
                  ],
                ),
              ),
              Positioned(
                bottom: -90,
                left: -40,
                child: _buildBackgroundOrb(
                  size: 240,
                  colors: [
                    _accentColor.withOpacity(0.18),
                    _accentColor.withOpacity(0.02),
                  ],
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 480;
                    final isDense = constraints.maxHeight < 860;
                    final cardWidth =
                        (isCompact
                                ? constraints.maxWidth - (isDense ? 32 : 40)
                                : 520.0)
                            .clamp(320.0, 520.0)
                            .toDouble();

                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 16 : 20,
                        isDense ? 10 : 16,
                        isCompact ? 16 : 20,
                        isDense ? 8 : 12,
                      ),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: _buildThemeToggle(),
                          ),
                          SizedBox(height: isDense ? 10 : 16),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: cardWidth,
                                  child: _buildLoginCard(
                                    auth,
                                    isCompact,
                                    isDense,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: isDense ? 8 : 12),
                          Text(
                            'Food City POS | Secure shift access',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _hintText,
                              fontSize: isDense ? 12.5 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
