import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/task.dart';

class HeartbeatBadge extends StatefulWidget {
  final Heartbeat heartbeat;

  const HeartbeatBadge({super.key, required this.heartbeat});

  @override
  State<HeartbeatBadge> createState() => _HeartbeatBadgeState();
}

class _HeartbeatBadgeState extends State<HeartbeatBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _isStalled => widget.heartbeat.status == HeartbeatStatus.stalled;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (_isStalled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant HeartbeatBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isStalled) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = heartbeatStatusToJson(widget.heartbeat.status);
    final color = EdictTheme.heartbeatColorMap[key] ?? EdictTheme.muted;

    final dot = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scale = _isStalled ? (0.85 + (_controller.value * 0.25)) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      },
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(
          widget.heartbeat.label,
          style: const TextStyle(
            color: EdictTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
