import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';

Future<(bool confirmed, String reason)> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String actionLabel = '确认',
  String cancelLabel = '取消',
  String hintText = '请输入原因/备注（可选）',
  bool barrierDismissible = true,
}) async {
  final result = await showGeneralDialog<(bool, String)>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'confirm',
    barrierColor: Colors.black54,
    pageBuilder: (_, __, ___) {
      return _ConfirmDialog(
        title: title,
        message: message,
        actionLabel: actionLabel,
        cancelLabel: cancelLabel,
        hintText: hintText,
      );
    },
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
      );
    },
  );

  if (result == null) return (false, '');
  return (result.$1, result.$2);
}

class _ConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String actionLabel;
  final String cancelLabel;
  final String hintText;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.cancelLabel,
    required this.hintText,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(18),
            decoration: EdictTheme.modalDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: EdictTheme.titleStyle),
                const SizedBox(height: 8),
                Text(widget.message, style: EdictTheme.bodyStyle),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 3,
                  decoration: InputDecoration(hintText: widget.hintText),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop((false, _controller.text.trim())),
                      child: Text(widget.cancelLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop((true, _controller.text.trim())),
                      child: Text(widget.actionLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
