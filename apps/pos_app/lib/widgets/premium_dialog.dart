import 'dart:ui';

import 'package:flutter/material.dart';

Future<T?> showPremiumDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool includeBackdrop = true,
  Color? barrierColor,
  double maxBlurSigma = 16,
  Duration transitionDuration = const Duration(milliseconds: 240),
}) {
  final overlayColor = barrierColor ?? Colors.black.withOpacity(0.32);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: transitionDuration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Builder(
        builder: (innerContext) => Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: builder(innerContext),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value.clamp(0.0, 1.0);
          final blur = maxBlurSigma * t;
          final overlayOpacity = overlayColor.opacity * t;
          final animatedOverlay = overlayColor.withOpacity(overlayOpacity);

          return Stack(
            children: [
              if (includeBackdrop)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: barrierDismissible
                        ? () => Navigator.of(context, rootNavigator: true).maybePop()
                        : null,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blur,
                        sigmaY: blur,
                      ),
                      child: ColoredBox(color: animatedOverlay),
                    ),
                  ),
                ),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.975, end: 1.0).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
