import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  String? _errorText;

  @override
  void initState() {
    super.initState();
    _pinFocusNode.addListener(_refreshPinPanel);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusPinEntry();
    });
  }

  @override
  void dispose() {
    _pinFocusNode.removeListener(_refreshPinPanel);
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _refreshPinPanel() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusPinEntry() {
    if (!_pinFocusNode.hasFocus) {
      _pinFocusNode.requestFocus();
    }
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();

    if (pin.length != 4) {
      setState(() {
        _errorText = 'Enter your 4-digit owner PIN';
      });
      _focusPinEntry();
      return;
    }

    setState(() {
      _errorText = null;
    });

    final provider = context.read<AdminProvider>();
    final message = await provider.loginOwner(pin);

    if (!mounted) return;

    if (message != null) {
      setState(() {
        _errorText = message;
      });
      _pinController.clear();
      _focusPinEntry();
      return;
    }

    _pinController.clear();
  }

  void _onPinChanged(String value) {
    if (_errorText != null) {
      setState(() {
        _errorText = null;
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminProvider>(
      builder: (context, provider, _) {
        final isBusy = provider.isAuthenticating;

        return GestureDetector(
          onTap: _focusPinEntry,
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F7FB),
            body: Stack(
              children: [
                const _BackgroundDecor(),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - value) * 22),
                                child: child,
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECF3FF),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0xFFD6E4FF),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shield_rounded,
                                        size: 16,
                                        color: Color(0xFF173E96),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Owner Monitoring Access',
                                        style: TextStyle(
                                          color: Color(0xFF173E96),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF173E96),
                                        Color(0xFF2C6BDB),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF173E96).withOpacity(0.24),
                                        blurRadius: 28,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.admin_panel_settings_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                'Welcome back',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF101828),
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Sign in to continue to the owner dashboard. Keep the flow fast, secure, and focused.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: const Color(0xFFE5ECF6)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withOpacity(0.07),
                                      blurRadius: 36,
                                      offset: const Offset(0, 18),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.lock_outline_rounded,
                                          color: Color(0xFF173E96),
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Secure PIN login',
                                          style: TextStyle(
                                            color: Color(0xFF172433),
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Use your 4-digit owner PIN. Type it directly and press Enter to continue.',
                                      style: TextStyle(
                                        color: Color(0xFF667085),
                                        fontSize: 13.2,
                                        fontWeight: FontWeight.w500,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Stack(
                                      children: [
                                        Opacity(
                                          opacity: 0,
                                          child: SizedBox(
                                            width: 1,
                                            height: 1,
                                            child: TextField(
                                              controller: _pinController,
                                              focusNode: _pinFocusNode,
                                              enabled: !isBusy,
                                              autofocus: true,
                                              keyboardType: TextInputType.number,
                                              textInputAction: TextInputAction.done,
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              obscureText: true,
                                              obscuringCharacter: '•',
                                              maxLength: 4,
                                              inputFormatters: [
                                                FilteringTextInputFormatter.digitsOnly,
                                                LengthLimitingTextInputFormatter(4),
                                              ],
                                              onChanged: _onPinChanged,
                                              onSubmitted: (_) => _submit(),
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                                counterText: '',
                                                contentPadding: EdgeInsets.zero,
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(24),
                                          onTap: isBusy
                                              ? null
                                              : _focusPinEntry,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FBFF),
                                              borderRadius: BorderRadius.circular(24),
                                              border: Border.all(
                                                color: _errorText != null
                                                    ? const Color(0xFFE15A5A)
                                                    : _pinFocusNode.hasFocus
                                                        ? const Color(0xFF96B7FF)
                                                        : const Color(0xFFDCE6F3),
                                                width: _pinFocusNode.hasFocus || _errorText != null ? 1.5 : 1.1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: List.generate(4, (index) {
                                                final filled = index < _pinController.text.length;
                                                final active = _pinFocusNode.hasFocus &&
                                                    _pinController.text.length == index;

                                                return AnimatedContainer(
                                                  duration: const Duration(milliseconds: 180),
                                                  curve: Curves.easeOutCubic,
                                                  width: 70,
                                                  height: 76,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    color: filled
                                                        ? const Color(0xFFEFF4FF)
                                                        : Colors.white,
                                                    borderRadius: BorderRadius.circular(22),
                                                    border: Border.all(
                                                      color: _errorText != null
                                                          ? const Color(0xFFE15A5A)
                                                          : active
                                                              ? const Color(0xFF173E96)
                                                              : filled
                                                                  ? const Color(0xFFBDD0FF)
                                                                  : const Color(0xFFD6E1F0),
                                                      width: active || _errorText != null ? 1.8 : 1.1,
                                                    ),
                                                    boxShadow: filled
                                                        ? [
                                                            BoxShadow(
                                                              color: const Color(0xFF173E96).withOpacity(0.06),
                                                              blurRadius: 12,
                                                              offset: const Offset(0, 5),
                                                            ),
                                                          ]
                                                        : null,
                                                  ),
                                                  child: AnimatedScale(
                                                    duration: const Duration(milliseconds: 180),
                                                    curve: Curves.easeOutBack,
                                                    scale: filled ? 1 : 0.88,
                                                    child: Container(
                                                      width: 12,
                                                      height: 12,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: filled
                                                            ? const Color(0xFF173E96)
                                                            : Colors.transparent,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 180),
                                      child: _errorText == null
                                          ? const Text(
                                              'Type your PIN and press Enter.',
                                              key: ValueKey('helper'),
                                              style: TextStyle(
                                                color: Color(0xFF667085),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            )
                                          : Text(
                                              _errorText!,
                                              key: const ValueKey('error'),
                                              style: const TextStyle(
                                                color: Color(0xFFCB3A31),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: isBusy ? null : _submit,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF173E96),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 18),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        ),
                                        child: isBusy
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.arrow_forward_rounded, size: 20),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'Enter workspace',
                                                    style: TextStyle(
                                                      fontSize: 15.5,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Returning owners stay signed in until they log out from Settings.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF98A2B3),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Cashiers without full access should continue using POS_APP.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.w600,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BackgroundDecor extends StatelessWidget {
  const _BackgroundDecor();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF8FBFF),
                Color(0xFFF1F5FB),
              ],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -40,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF8DB5FF).withOpacity(0.24),
            ),
          ),
        ),
        Positioned(
          top: 70,
          left: -70,
          child: Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2C6BDB).withOpacity(0.12),
            ),
          ),
        ),
        Positioned(
          bottom: -90,
          left: -30,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD7E7FF).withOpacity(0.55),
            ),
          ),
        ),
      ],
    );
  }
}
