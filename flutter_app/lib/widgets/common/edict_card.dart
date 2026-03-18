import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class EdictCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool archived;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const EdictCard({
    super.key,
    required this.child,
    this.onTap,
    this.archived = false,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = CustomPaint(
      painter: archived ? _DashedBorderPainter() : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: archived ? 0.6 : 1,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: EdictTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: archived
                ? Border.all(color: Colors.transparent)
                : Border.all(color: EdictTheme.line),
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      body = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: body,
      );
    }

    return Container(margin: margin, child: body);
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(14);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final paint = Paint()
      ..color = EdictTheme.muted.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      const dash = 6.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
