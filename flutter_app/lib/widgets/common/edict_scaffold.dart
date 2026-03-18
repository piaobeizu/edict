import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers/providers.dart';

class EdictTabDef {
  final String key;
  final String label;
  final String emoji;

  const EdictTabDef({
    required this.key,
    required this.label,
    required this.emoji,
  });
}

const List<EdictTabDef> kTabDefs = [
  EdictTabDef(key: 'edicts', label: '旨意看板', emoji: '📜'),
  EdictTabDef(key: 'monitor', label: '省部调度', emoji: '🏛️'),
  EdictTabDef(key: 'officials', label: '官员总览', emoji: '👔'),
  EdictTabDef(key: 'models', label: '模型配置', emoji: '🤖'),
  EdictTabDef(key: 'skills', label: '技能配置', emoji: '🎯'),
  EdictTabDef(key: 'sessions', label: '小任务', emoji: '💬'),
  EdictTabDef(key: 'memorials', label: '奏折阁', emoji: '📜'),
  EdictTabDef(key: 'templates', label: '旨库', emoji: '📋'),
  EdictTabDef(key: 'morning', label: '天下要闻', emoji: '🌅'),
];

/// Maps TabKey enum to the string keys used in kTabDefs / panels map.
String _tabKeyToString(TabKey k) => k.name; // e.g. TabKey.edicts -> 'edicts'
TabKey _stringToTabKey(String s) {
  return TabKey.values.firstWhere(
    (k) => k.name == s,
    orElse: () => TabKey.edicts,
  );
}

class EdictScaffold extends ConsumerStatefulWidget {
  final Map<String, Widget> panels;
  final Future<void> Function()? onRefresh;

  const EdictScaffold({
    super.key,
    required this.panels,
    this.onRefresh,
  });

  @override
  ConsumerState<EdictScaffold> createState() => _EdictScaffoldState();
}

class _EdictScaffoldState extends ConsumerState<EdictScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kTabDefs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final key = kTabDefs[_tabController.index].key;
    ref.read(activeTabProvider.notifier).state = _stringToTabKey(key);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrow = width < 860;

    final activeTab = ref.watch(activeTabProvider);
    final activeKey = _tabKeyToString(activeTab);
    final activeIdx = kTabDefs.indexWhere((e) => e.key == activeKey);
    final index = activeIdx < 0 ? 0 : activeIdx;

    // Sync the controller when the provider changes externally.
    if (_tabController.index != index) {
      _tabController.animateTo(index);
    }

    // Read live status for badge counts.
    final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
    final tasks = liveStatus?.tasks ?? [];
    final edictCount = tasks.where((t) => isEdict(t) && !isArchived(t)).length;
    final sessionCount = tasks.where((t) => !isEdict(t)).length;
    final activeCount = tasks.where((t) => isEdict(t) && t.state == 'Doing').length;
    final syncOk = liveStatus != null;

    int? badgeFor(String key) {
      switch (key) {
        case 'edicts':
          return edictCount > 0 ? edictCount : null;
        case 'sessions':
          return sessionCount > 0 ? sessionCount : null;
        case 'monitor':
          return activeCount > 0 ? activeCount : null;
        case 'memorials':
          final c = tasks.where((t) => isEdict(t) && isArchived(t)).length;
          return c > 0 ? c : null;
        default:
          return null;
      }
    }

    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: isNarrow,
      indicatorColor: EdictTheme.acc,
      labelColor: EdictTheme.text,
      unselectedLabelColor: EdictTheme.muted,
      tabAlignment: isNarrow ? TabAlignment.start : TabAlignment.fill,
      dividerHeight: 0,
      tabs: kTabDefs.map((t) {
        final badge = badgeFor(t.key);
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(t.label, style: const TextStyle(fontSize: 13)),
              if (badge != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: EdictTheme.acc.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: EdictTheme.acc.withValues(alpha: 0.65)),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 16,
        title: isNarrow
            ? _buildLogoCompact()
            : _buildLogoFull(),
        actions: [
          _SyncDot(ok: syncOk),
          const SizedBox(width: 6),
          _CountChip(label: '活跃旨意', count: activeCount),
          const SizedBox(width: 6),
          IconButton(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: tabBar,
        ),
      ),
      body: IndexedStack(
        index: index,
        children: kTabDefs
            .map((tab) => widget.panels[tab.key] ?? const SizedBox.shrink())
            .toList(),
      ),
    );
  }

  Widget _buildLogoFull() {
    return Row(
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
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'AI多Agent协作平台',
          style: TextStyle(color: EdictTheme.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLogoCompact() {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [EdictTheme.acc, EdictTheme.acc2],
      ).createShader(bounds),
      child: const Text(
        '三省六部',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SyncDot extends StatelessWidget {
  final bool ok;
  const _SyncDot({required this.ok});

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
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: ok ? EdictTheme.ok : EdictTheme.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            ok ? '已连接' : '断开',
            style: const TextStyle(fontSize: 11, color: EdictTheme.text),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  const _CountChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EdictTheme.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EdictTheme.line),
      ),
      child: Text(
        '$label $count',
        style: const TextStyle(fontSize: 11, color: EdictTheme.text),
      ),
    );
  }
}
