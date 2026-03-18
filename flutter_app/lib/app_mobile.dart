import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/mobile_theme.dart';
import 'models/models.dart';
import 'providers/api_provider.dart';
import 'providers/live_status_provider.dart';
import 'widgets/mobile/home_screen.dart';
import 'widgets/mobile/task_list_screen.dart';
import 'widgets/mobile/task_detail_screen.dart';
import 'widgets/mobile/create_screen.dart';
import 'widgets/mobile/template_screen.dart';
import 'widgets/mobile/news_screen.dart';

class EdictMobileApp extends StatelessWidget {
  const EdictMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '三省六部',
      debugShowCheckedModeBanner: false,
      theme: MobileTheme.lightTheme,
      home: const _MobileEntry(),
    );
  }
}

class _MobileEntry extends StatefulWidget {
  const _MobileEntry();

  @override
  State<_MobileEntry> createState() => _MobileEntryState();
}

class _MobileEntryState extends State<_MobileEntry> {
  Timer? _fadeTimer;
  Timer? _removeTimer;
  bool _fadeSplash = false;
  bool _hideSplash = false;

  @override
  void initState() {
    super.initState();
    _fadeTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() => _fadeSplash = true);
    });
    _removeTimer = Timer(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      setState(() => _hideSplash = true);
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _MobileShell(),
        if (!_hideSplash)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _fadeSplash ? 0 : 1,
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOut,
              child: const _SplashOverlay(),
            ),
          ),
      ],
    );
  }
}

class _MobileShell extends ConsumerStatefulWidget {
  const _MobileShell();

  @override
  ConsumerState<_MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<_MobileShell> {
  int _currentIndex = 0;

  void _openTaskDetail(String taskId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileTaskDetailScreen(taskId: taskId),
      ),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _archiveTask(Task task) async {
    final result = await ref.read(apiClientProvider).archiveTask(task.id, true);
    if (!mounted) return;
    if (result.ok) {
      await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      _showToast('已归档「${task.title.isEmpty ? task.id : task.title}」');
      return;
    }
    _showToast(result.error ?? '归档失败');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navHeight = 84.0 + bottomInset;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              MobileHomeScreen(
                onTaskTap: _openTaskDetail,
                onCreateTaskTap: () => setState(() => _currentIndex = 2),
                onViewTemplatesTap: () => setState(() => _currentIndex = 3),
                onMorningNewsTap: () => setState(() => _currentIndex = 4),
              ),
              MobileTaskListScreen(
                onTaskTap: _openTaskDetail,
                onCreateTap: () => setState(() => _currentIndex = 2),
                onArchiveTask: _archiveTask,
                showFab: false,
              ),
              MobileCreateScreen(
                onCreated: (title) {
                  setState(() => _currentIndex = 1);
                  _showToast('已创建「$title」');
                },
              ),
              const MobileTemplateScreen(),
              const MobileNewsScreen(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomNavBar(
              currentIndex: _currentIndex,
              onSelect: (index) => setState(() => _currentIndex = index),
              bottomInset: bottomInset,
              navHeight: navHeight,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentIndex,
    required this.onSelect,
    required this.bottomInset,
    required this.navHeight,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final double bottomInset;
  final double navHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: navHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: const Color(0xFFEBE9E6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 14,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 2),
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.home_rounded,
                label: '首页',
                active: currentIndex == 0,
                onTap: () => onSelect(0),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.task_alt_rounded,
                label: '旨意',
                active: currentIndex == 1,
                onTap: () => onSelect(1),
              ),
            ),
            Expanded(
              child: _CreateNavItem(
                active: currentIndex == 2,
                onTap: () => onSelect(2),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.menu_book_rounded,
                label: '旨库',
                active: currentIndex == 3,
                onTap: () => onSelect(3),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.newspaper_rounded,
                label: '要闻',
                active: currentIndex == 4,
                onTap: () => onSelect(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF4338CA) : const Color(0xFF78716C);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateNavItem extends StatelessWidget {
  const _CreateNavItem({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        active ? const Color(0xFF4338CA) : const Color(0xFF78716C);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4338CA).withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                '＋',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '新建',
              style: TextStyle(
                color: labelColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashOverlay extends StatefulWidget {
  const _SplashOverlay();

  @override
  State<_SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<_SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sealScale;
  late final Animation<double> _sealRotation;
  late final Animation<double> _sealOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleOffset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    _sealScale = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.82, curve: Curves.easeOutBack),
      ),
    );
    _sealRotation = Tween<double>(begin: -14 * math.pi / 180, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.82, curve: Curves.easeOutCubic),
      ),
    );
    _sealOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.76, curve: Curves.easeOut),
      ),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.48, 1, curve: Curves.easeOut),
      ),
    );
    _titleOffset = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.48, 1, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.15,
              colors: [Color(0xFFEEF2FF), Color(0xFFDDD6FE), Color(0xFFC7D2FE)],
              stops: [0, 0.45, 1],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _sealOpacity.value,
                  child: Transform.rotate(
                    angle: _sealRotation.value,
                    child: Transform.scale(
                      scale: _sealScale.value,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFF4338CA),
                            width: 4,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x404338CA),
                              blurRadius: 22,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '令',
                          style: TextStyle(
                            color: Color(0xFF4338CA),
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Transform.translate(
                  offset: Offset(0, _titleOffset.value),
                  child: Opacity(
                    opacity: _titleOpacity.value,
                    child: const Text(
                      'EDICT',
                      style: TextStyle(
                        color: Color(0xFF312E81),
                        fontSize: 32,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Transform.translate(
                  offset: Offset(0, _titleOffset.value),
                  child: Opacity(
                    opacity: _titleOpacity.value,
                    child: const Text(
                      '三省六部 · AI 编排中枢',
                      style: TextStyle(
                        color: Color(0xFF4338CA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
