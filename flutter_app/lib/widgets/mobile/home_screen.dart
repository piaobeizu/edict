import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../providers/live_status_provider.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileHomeScreen extends ConsumerWidget {
  const MobileHomeScreen({
    super.key,
    this.onStatusTap,
    this.onTaskTap,
    this.onSearchTap,
    this.onNotificationTap,
    this.onCreateTaskTap,
    this.onViewTemplatesTap,
    this.onMorningNewsTap,
  });

  final ValueChanged<String>? onStatusTap;
  final ValueChanged<String>? onTaskTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onCreateTaskTap;
  final VoidCallback? onViewTemplatesTap;
  final VoidCallback? onMorningNewsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveStatusAsync = ref.watch(liveStatusProvider);
    final now = DateTime.now();

    final allTasks = liveStatusAsync.valueOrNull?.tasks ?? const <Task>[];
    final tasks = allTasks.where(isEdict).toList(growable: false);

    final pendingCount = tasks.where(_isPendingState).length;
    final doingCount = tasks.where((t) => t.state == 'Doing').length;
    final reviewCount =
        tasks.where((t) => t.state == 'Review' || t.state == 'YuLan').length;
    final doneCount = tasks.where(isArchived).length;

    final needsAttention = tasks.where(_needsAttention).toList()
      ..sort((a, b) =>
          _safeParseDate(b.updatedAt).compareTo(_safeParseDate(a.updatedAt)));

    final recentResults = tasks.where((t) => t.state == 'Done').toList()
      ..sort((a, b) =>
          _safeParseDate(b.updatedAt).compareTo(_safeParseDate(a.updatedAt)));

    return MobileImmersiveBackground(
      backgroundColor: _HomePalette.pageBg,
      child: SafeArea(
        bottom: false,
        child: liveStatusAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          error: (error, _) => _HomeErrorState(error: error.toString()),
          data: (_) => SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: MobileImmersiveBackground.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GreetingHeader(
                  greeting: _greetingForHour(now.hour),
                  subtitle: _formatChineseDate(now),
                  onSearchTap: onSearchTap,
                  onNotificationTap: onNotificationTap,
                ),
                const SizedBox(height: 20),
                _StatusSummaryRow(
                  pendingCount: pendingCount,
                  doingCount: doingCount,
                  reviewCount: reviewCount,
                  doneCount: doneCount,
                  onTap: onStatusTap,
                ),
                const SizedBox(height: 22),
                _NeedsAttentionSection(
                  tasks: needsAttention,
                  onTaskTap: onTaskTap,
                ),
                const SizedBox(height: 24),
                _RecentResultsSection(
                  tasks: recentResults.take(5).toList(growable: false),
                  onTaskTap: onTaskTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
    required this.greeting,
    required this.subtitle,
    this.onSearchTap,
    this.onNotificationTap,
  });

  final String greeting;
  final String subtitle;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  color: _HomePalette.heading,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _HomePalette.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _IconButtonShell(
          icon: Icons.search_rounded,
          onTap: onSearchTap,
        ),
        const SizedBox(width: 8),
        _IconButtonShell(
          icon: Icons.notifications_none_rounded,
          onTap: onNotificationTap,
        ),
      ],
    );
  }
}

class _StatusSummaryRow extends StatelessWidget {
  const _StatusSummaryRow({
    required this.pendingCount,
    required this.doingCount,
    required this.reviewCount,
    required this.doneCount,
    this.onTap,
  });

  final int pendingCount;
  final int doingCount;
  final int reviewCount;
  final int doneCount;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final chips = <_StatusChipData>[
      _StatusChipData('待处理', pendingCount, const Color(0xFFFFF1D8),
          const Color(0xFFB46A00)),
      _StatusChipData('执行中', doingCount, const Color(0xFF5A4DE2), Colors.white),
      _StatusChipData(
          '待评审', reviewCount, const Color(0xFFFFE9E9), const Color(0xFFBC2E2E)),
      _StatusChipData(
          '已完成', doneCount, const Color(0xFFDDF6EA), const Color(0xFF047857)),
    ];

    return GridView.builder(
      itemCount: chips.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 2.7,
      ),
      itemBuilder: (context, index) {
        final chip = chips[index];
        return _StatusChip(
          data: chip,
          onTap: () => onTap?.call(chip.label),
        );
      },
    );
  }
}

class _NeedsAttentionSection extends StatelessWidget {
  const _NeedsAttentionSection({
    required this.tasks,
    this.onTaskTap,
  });

  final List<Task> tasks;
  final ValueChanged<String>? onTaskTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MobileSectionTitle(
          title: '⚠️ 需要关注',
          trailing: Text(
            '查看全部',
            style: TextStyle(
              color: Color(0xFF78716C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          const _EmptyAttentionCard()
        else
          Column(
            children: [
              for (final task in tasks) ...[
                _AttentionCard(
                  task: task,
                  onTap: () => onTaskTap?.call(task.id),
                ),
                if (task != tasks.last) const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }
}

class _RecentResultsSection extends StatelessWidget {
  const _RecentResultsSection({required this.tasks, this.onTaskTap});

  final List<Task> tasks;
  final ValueChanged<String>? onTaskTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MobileSectionTitle(
          title: '✅ 最新结果',
          trailing: Text(
            '横向滑动',
            style: TextStyle(
              color: Color(0xFF78716C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: _HomePalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _HomePalette.border),
            ),
            child: const Text(
              '暂无最新完成任务',
              style: TextStyle(
                color: _HomePalette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final task = tasks[index];
                return _ResultCard(
                  task: task,
                  onTap: () => onTaskTap?.call(task.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.task, this.onTap});

  final Task task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final preview = _preview(task.output, max: 60);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 258,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF7FAFF),
              Color(0xFFF3F6FF),
              Color(0xFFEFF8F6),
            ],
          ),
          border: Border.all(color: _HomePalette.border),
          boxShadow: const [MobileImmersiveBackground.cardShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title.isEmpty ? task.id : task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _HomePalette.heading,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '完成于 ${timeAgo(task.updatedAt)}',
              style: const TextStyle(
                color: _HomePalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              preview.isEmpty ? '（无输出预览）' : preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _HomePalette.body,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.task, this.onTap});

  final Task task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stateColor = _stateColor(task.state);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: _HomePalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _HomePalette.border),
          boxShadow: const [MobileImmersiveBackground.cardShadow],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 96,
              decoration: BoxDecoration(
                color: stateColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title.isEmpty ? task.id : task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _HomePalette.heading,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        MobilePillTag(
                          text: stateLabel(task),
                          background: stateColor.withValues(alpha: 0.14),
                          foreground: stateColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            timeAgo(task.updatedAt),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: _HomePalette.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_agentEmoji(task)} ${task.org.isEmpty ? '部门未知' : task.org}',
                      style: const TextStyle(
                        color: _HomePalette.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.data, this.onTap});

  final _StatusChipData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: data.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              data.label,
              style: TextStyle(
                color: data.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${data.count}',
              style: TextStyle(
                color: data.accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButtonShell extends StatelessWidget {
  const _IconButtonShell({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _HomePalette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _HomePalette.border),
          ),
          child: Icon(icon, color: _HomePalette.heading, size: 20),
        ),
      ),
    );
  }
}

class _EmptyAttentionCard extends StatelessWidget {
  const _EmptyAttentionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: _HomePalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _HomePalette.border),
      ),
      child: const Text(
        '一切顺利 ✨',
        style: TextStyle(
          color: _HomePalette.muted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HomeErrorState extends StatelessWidget {
  const _HomeErrorState({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _HomePalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _HomePalette.border),
          ),
          child: Text(
            '加载失败：$error',
            style: const TextStyle(
              color: _HomePalette.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChipData {
  const _StatusChipData(this.label, this.count, this.bg, this.accent);

  final String label;
  final int count;
  final Color bg;
  final Color accent;
}

class _HomePalette {
  static const pageBg = Color(0xFFFAFAF9);
  static const surface = Color(0xFFFFFFFF);
  static const heading = Color(0xFF1C1917);
  static const body = Color(0xFF292524);
  static const muted = Color(0xFF78716C);
  static const border = Color(0xFFF0EEEB);
}

String _greetingForHour(int hour) {
  if (hour < 6) return '夜深了，执令官';
  if (hour < 11) return '早上好，执令官';
  if (hour < 14) return '中午好，执令官';
  if (hour < 18) return '下午好，执令官';
  return '晚上好，执令官';
}

String _formatChineseDate(DateTime dt) {
  const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final weekday = weekdays[dt.weekday - 1];
  return '${dt.month}月${dt.day}日 $weekday';
}

bool _isPendingState(Task t) {
  const pending = <String>{
    'Inbox',
    'Pending',
    'Taizi',
    'Zhongshu',
    'Menxia',
    'Assigned',
    'Next',
  };
  return pending.contains(t.state);
}

bool _needsAttention(Task t) {
  if (t.state == 'Blocked') return true;
  if (t.state == 'YuLan') return true;
  if (t.state == 'Cancelled') {
    final updatedAt = _safeParseDate(t.updatedAt);
    return DateTime.now().difference(updatedAt) <= const Duration(hours: 24);
  }
  return false;
}

DateTime _safeParseDate(String? raw) {
  if (raw == null || raw.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  final normalized = raw.contains('T') ? raw : '${raw.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(normalized)?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

Color _stateColor(String state) {
  switch (state) {
    case 'Blocked':
      return const Color(0xFFEF4444);
    case 'Cancelled':
      return const Color(0xFFF97316);
    case 'YuLan':
      return const Color(0xFFF59E0B);
    case 'Review':
      return const Color(0xFF3B82F6);
    default:
      return const Color(0xFF6366F1);
  }
}

String _agentEmoji(Task t) {
  final dept = kDepts.firstWhere(
    (d) => d.label == t.org,
    orElse: () => const DeptInfo(
      id: 'unknown',
      label: '',
      emoji: '🏛️',
      role: '',
      rank: 99,
    ),
  );
  if (dept.emoji.isNotEmpty) return dept.emoji;

  final lower = t.org.toLowerCase();
  if (lower.contains('礼')) return '📝';
  if (lower.contains('户')) return '💰';
  if (lower.contains('兵')) return '⚔️';
  if (lower.contains('刑')) return '⚖️';
  if (lower.contains('工')) return '🔧';
  if (lower.contains('吏')) return '👔';
  return '🏛️';
}

String _preview(String text, {required int max}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty || clean == '-') return '';
  return clean.length <= max ? clean : '${clean.substring(0, max)}…';
}
