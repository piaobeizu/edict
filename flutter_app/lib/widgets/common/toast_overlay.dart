import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';

enum ToastType { ok, err }

class ToastMessage {
  final String id;
  final String text;
  final ToastType type;

  const ToastMessage({required this.id, required this.text, required this.type});
}

class ToastController extends StateNotifier<List<ToastMessage>> {
  ToastController() : super(const []);

  void show(String text, {ToastType type = ToastType.ok}) {
    final item = ToastMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      type: type,
    );
    state = [...state, item];
    Timer(const Duration(seconds: 3), () => dismiss(item.id));
  }

  void dismiss(String id) {
    state = state.where((e) => e.id != id).toList(growable: false);
  }
}

final toastProvider =
    StateNotifierProvider<ToastController, List<ToastMessage>>(
  (ref) => ToastController(),
);

class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastProvider);
    if (toasts.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: true,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: toasts
                  .map((t) => _ToastItem(key: ValueKey(t.id), toast: t))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastItem extends StatefulWidget {
  final ToastMessage toast;

  const _ToastItem({super.key, required this.toast});

  @override
  State<_ToastItem> createState() => _ToastItemState();
}

class _ToastItemState extends State<_ToastItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
    _offset = Tween<Offset>(
      begin: const Offset(0.25, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = widget.toast.type == ToastType.ok;
    final color = ok ? EdictTheme.ok : EdictTheme.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _offset,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: EdictTheme.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.85), width: 1.2),
            ),
            child: Text(
              widget.toast.text,
              style: const TextStyle(color: EdictTheme.text, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
