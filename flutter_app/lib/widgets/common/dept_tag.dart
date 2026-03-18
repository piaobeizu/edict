import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

class DeptTag extends StatelessWidget {
  final String dept;

  const DeptTag({super.key, required this.dept});

  @override
  Widget build(BuildContext context) {
    final color = kDeptColor[dept] ?? EdictTheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        dept,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}
