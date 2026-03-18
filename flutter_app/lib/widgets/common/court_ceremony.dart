import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

class CourtCeremony extends StatefulWidget {
  final int pendingCount;
  final int doneCount;
  final int overdueCount;
  final VoidCallback? onDismissed;

  const CourtCeremony({
    super.key,
    required this.pendingCount,
    required this.doneCount,
    this.overdueCount = 0,
    this.onDismissed,
  });

  static const _dateKey = 'openclaw_court_date';

  static Future<bool> shouldShowToday() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = _resolveEnabled(prefs);
    if (!enabled) return false;

    final today = _dayStamp(DateTime.now());
    final lastShown = prefs.getString(_dateKey);
    return lastShown != today;
  }

  static Future<void> markShownToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dateKey, _dayStamp(DateTime.now()));
  }

  static bool _resolveEnabled(SharedPreferences prefs) {
    final direct = prefs.getBool('openclaw_court_pref.enabled');
    if (direct != null) return direct;

    final raw = prefs.getString('openclaw_court_pref');
    if (raw == null || raw.isEmpty) return true;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final value = decoded['enabled'];
        if (value is bool) return value;
      }
    } catch (_) {
      return true;
    }
    return true;
  }

  static String _dayStamp(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  State<CourtCeremony> createState() => _CourtCeremonyState();
}

class _CourtCeremonyState extends State<CourtCeremony>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..forward();

    Future<void>.delayed(const Duration(milliseconds: 3500), _dismiss);
    CourtCeremony.markShownToday();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _dismissed) return;
    setState(() => _dismissed = true);
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final titleIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.02, 0.32, curve: Curves.easeOutCubic),
    );
    final subIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.46, curve: Curves.easeOutCubic),
    );
    final statsIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.7, curve: Curves.easeOut),
    );
    final dateIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.62, 0.88, curve: Curves.easeOut),
    );

    final today = DateTime.now();
    final dateText =
        '${today.year}年${today.month.toString().padLeft(2, '0')}月${today.day.toString().padLeft(2, '0')}日';

    return GestureDetector(
      onTap: _dismiss,
      child: Material(
        color: Colors.black.withOpacity(0.85),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.9,
                    colors: [
                      EdictTheme.acc.withOpacity(0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SlideTransition(
                    position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
                        .animate(titleIn),
                    child: FadeTransition(
                      opacity: titleIn,
                      child: ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          colors: [EdictTheme.acc, EdictTheme.acc2],
                        ).createShader(r),
                        child: const Text(
                          '三省六部 · 开朝',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SlideTransition(
                    position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
                        .animate(subIn),
                    child: FadeTransition(
                      opacity: subIn,
                      child: const Text(
                        'AI 多 Agent 协作平台 · 早朝简报',
                        style: TextStyle(
                          color: EdictTheme.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: statsIn,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        _StatPill(label: '待办', value: widget.pendingCount, color: EdictTheme.warn),
                        _StatPill(label: '已结', value: widget.doneCount, color: EdictTheme.ok),
                        if (widget.overdueCount > 0)
                          _StatPill(label: '逾期', value: widget.overdueCount, color: EdictTheme.danger),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: dateIn,
                    child: Text(
                      dateText,
                      style: const TextStyle(color: EdictTheme.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EdictTheme.panel.withOpacity(0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
