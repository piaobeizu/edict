import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/core.dart';
import 'providers/providers.dart';
import 'widgets/common/toast_overlay.dart';
import 'widgets/panels/edict_board.dart';
import 'widgets/panels/memorial_panel.dart';
import 'widgets/panels/model_config.dart';
import 'widgets/panels/monitor_panel.dart';
import 'widgets/panels/morning_panel.dart';
import 'widgets/panels/official_panel.dart';
import 'widgets/panels/sessions_panel.dart';
import 'widgets/panels/skills_config.dart';
import 'widgets/panels/task_modal.dart';
import 'widgets/panels/template_panel.dart';

class EdictApp extends StatelessWidget {
  const EdictApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '三省六部',
      debugShowCheckedModeBanner: false,
      theme: EdictTheme.darkTheme,
      home: const _EdictHome(),
    );
  }
}

class _EdictHome extends ConsumerStatefulWidget {
  const _EdictHome();

  @override
  ConsumerState<_EdictHome> createState() => _EdictHomeState();
}

class _EdictHomeState extends ConsumerState<_EdictHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = <(String, String, Widget)>[
    ('edicts', '📜 旨意看板', EdictBoardPanel()),
    ('monitor', '🏛️ 省部调度', MonitorPanel()),
    ('officials', '👔 官员总览', OfficialPanel()),
    ('models', '🤖 模型配置', ModelConfigPanel()),
    ('skills', '🎯 技能配置', SkillsConfigPanel()),
    ('sessions', '💬 小任务', SessionsPanel()),
    ('memorials', '📜 奏折阁', MemorialPanel()),
    ('templates', '📋 旨库', TemplatePanel()),
    ('morning', '🌅 天下要闻', MorningPanel()),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveStatus = ref.watch(liveStatusProvider);
    final tasks = liveStatus.valueOrNull?.tasks ?? [];
    final activeCount = tasks.where((t) => isEdict(t) && !isArchived(t)).length;
    final syncOk = liveStatus.valueOrNull != null;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            toolbarHeight: 56,
            titleSpacing: 16,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [EdictTheme.acc, EdictTheme.acc2],
                  ).createShader(bounds),
                  child: const Text(
                    '三省六部',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI多Agent协作平台',
                  style: TextStyle(color: EdictTheme.muted, fontSize: 12),
                ),
              ],
            ),
            actions: [
              _Chip(
                dot: syncOk ? EdictTheme.ok : EdictTheme.danger,
                label: syncOk ? '已连接' : '连接中',
              ),
              const SizedBox(width: 6),
              _Chip(label: '活跃旨意 $activeCount'),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => ref.invalidate(liveStatusProvider),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: '刷新',
              ),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: EdictTheme.acc,
              labelColor: EdictTheme.text,
              unselectedLabelColor: EdictTheme.muted,
              tabAlignment: TabAlignment.start,
              dividerHeight: 0,
              tabs: _tabs.map((t) => Tab(text: t.$2)).toList(),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children:
                _tabs.map((t) => _SafePanel(name: t.$2, child: t.$3)).toList(),
          ),
        ),
        const ToastOverlay(),
        const TaskModalHost(),
      ],
    );
  }
}

/// Keeps panel alive across tab switches + catches errors gracefully.
class _SafePanel extends StatefulWidget {
  final String name;
  final Widget child;
  const _SafePanel({required this.name, required this.child});

  @override
  State<_SafePanel> createState() => _SafePanelState();
}

class _SafePanelState extends State<_SafePanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: widget.child,
    );
  }
}

class _Chip extends StatelessWidget {
  final Color? dot;
  final String label;
  const _Chip({this.dot, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EdictTheme.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EdictTheme.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: const TextStyle(fontSize: 11, color: EdictTheme.text)),
        ],
      ),
    );
  }
}
