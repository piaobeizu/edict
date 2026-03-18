import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

class StateTag extends StatelessWidget {
  final String state;

  const StateTag({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = EdictTheme.stateTagColorMap[state] ??
        const TagColors(
          foreground: EdictTheme.text,
          background: EdictTheme.panel2,
          border: EdictTheme.line,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        kStateLabel[state] ?? state,
        style: const TextStyle(
          color: EdictTheme.text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ).copyWith(color: colors.foreground),
      ),
    );
  }
}
