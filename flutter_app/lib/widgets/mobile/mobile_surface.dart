import 'package:flutter/material.dart';

/// Shared immersive background for mobile pages.
class MobileImmersiveBackground extends StatelessWidget {
  const MobileImmersiveBackground({
    super.key,
    required this.child,
    this.backgroundColor = const Color(0xFFFAFAF9),
  });

  final Widget child;
  final Color backgroundColor;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 96);
  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x12000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: backgroundColor),
          ),
        ),
        Positioned(
          top: -44,
          left: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x336366F1), Color(0x006366F1)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: -34,
          right: -58,
          child: Container(
            width: 240,
            height: 240,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x2910B981), Color(0x0010B981)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
