import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/task.dart';

class MiniPipe extends StatelessWidget {
  final Task task;

  const MiniPipe({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final nodes = getPipeStatus(task);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(nodes.length * 2 - 1, (index) {
          if (index.isOdd) {
            final prev = nodes[(index - 1) ~/ 2];
            final done = prev.status == PipeNodeStatus.done;
            return Container(
              width: 14,
              height: 2,
              color: (done ? EdictTheme.ok : EdictTheme.line)
                  .withOpacity(done ? 0.9 : 0.35),
            );
          }

          final node = nodes[index ~/ 2];
          final isDone = node.status == PipeNodeStatus.done;
          final isActive = node.status == PipeNodeStatus.active;
          final isPending = node.status == PipeNodeStatus.pending;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: isActive ? 11 : 9,
            height: isActive ? 11 : 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone
                  ? EdictTheme.ok
                  : isActive
                      ? EdictTheme.panel
                      : EdictTheme.muted.withOpacity(0.3),
              border: Border.all(
                color: isActive
                    ? EdictTheme.acc
                    : isDone
                        ? EdictTheme.ok
                        : EdictTheme.muted.withOpacity(0.35),
                width: isActive ? 1.8 : 1,
              ),
            ),
            child: isPending
                ? Opacity(
                    opacity: 0.3,
                    child: const SizedBox.expand(),
                  )
                : null,
          );
        }),
      ),
    );
  }
}
