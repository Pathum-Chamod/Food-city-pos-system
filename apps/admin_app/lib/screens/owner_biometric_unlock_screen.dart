import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/admin_provider.dart';
import '../widgets/app_snackbar.dart';

class OwnerBiometricUnlockScreen extends StatefulWidget {
  const OwnerBiometricUnlockScreen({super.key});

  @override
  State<OwnerBiometricUnlockScreen> createState() =>
      _OwnerBiometricUnlockScreenState();
}

class _OwnerBiometricUnlockScreenState
    extends State<OwnerBiometricUnlockScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _startedAutoPrompt = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _startedAutoPrompt) return;
      _startedAutoPrompt = true;
      _unlock();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final provider = context.read<AdminProvider>();
    final message = await provider.unlockWithBiometrics();
    if (!mounted || message == null) return;

    AppSnackBar.show(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          body: Stack(
            children: [
              Positioned(
                top: -80,
                right: -30,
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2C6BDB).withOpacity(0.14),
                  ),
                ),
              ),
              Positioned(
                left: -50,
                bottom: -70,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFDCE7FF).withOpacity(0.65),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFFE5ECF6)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.08),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Quick unlock',
                              style: TextStyle(
                                color: Color(0xFF172433),
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Welcome back, ${provider.currentOwnerName}. Unlock with ${provider.biometricTypeLabel.toLowerCase()} to continue.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            AnimatedBuilder(
                              animation: _controller,
                              builder: (context, child) {
                                final scale = 1 + (_controller.value * 0.06);
                                return Transform.scale(
                                  scale: scale,
                                  child: child,
                                );
                              },
                              child: Container(
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF173E96),
                                      Color(0xFF2C6BDB),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(34),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF173E96).withOpacity(0.24),
                                      blurRadius: 28,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.fingerprint_rounded,
                                  color: Colors.white,
                                  size: 52,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              provider.isBiometricBusy
                                  ? 'Waiting for biometric confirmation...'
                                  : 'Touch the fingerprint sensor to unlock.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: provider.isBiometricBusy ? null : _unlock,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF173E96),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: provider.isBiometricBusy
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
                                          Icon(Icons.fingerprint_rounded, size: 20),
                                          SizedBox(width: 10),
                                          Text(
                                            'Unlock now',
                                            style: TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: provider.isBiometricBusy
                                  ? null
                                  : () {
                                      context.read<AdminProvider>().usePinInsteadOfBiometrics();
                                    },
                              child: const Text(
                                'Use owner PIN instead',
                                style: TextStyle(fontWeight: FontWeight.w700),
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
        );
      },
    );
  }
}
