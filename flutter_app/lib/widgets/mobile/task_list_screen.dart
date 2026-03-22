import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import 'mobile_tokens.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileTaskListScreen extends ConsumerStatefulWidget {
  const MobileTaskListScreen({
    super.key,
    required this.onTaskTap,
    required this.onCreateTap,
    this.onArchiveTask,
    this.enableSwipeArchive = true,
    this.showFab = true,
  });

  final ValueChanged<String> onTaskTap;
  final VoidCallback onCreateTap;
  final Future<void> Function(Task task)? onArchiveTask;
  final bool enableSwipeArchive;
  final bool showFab;

  @override
  ConsumerState<MobileTaskListScreen> createState() => _MobileTaskListScreenState();
}

class _MobileTaskListScreenState extends ConsumerState<MobileTaskListScreen> {
  final ScrollController _listController = ScrollController();
  Timer? _focusClearTimer;
  String? _lastScheduledFocusId;

  @override
  void dispose() {
    _focusClearTimer?.cancel();
    _listController.dispose();
    super.dispose();
  }

  void _scheduleFocusHandling(String focusedTaskId) {
    if (_lastScheduledFocusId == focusedTaskId) {
      return;
    }
    _lastScheduledFocusId = focusedTaskId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_listController.hasClients) {
        _listController.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });

    _focusClearTimer?.cancel();
    _focusClearTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      final current = ref.read(mobileFocusedTaskIdProvider);
      if (current == focusedTaskId) {
        ref.read(mobileFocusedTaskIdProvider.notifier).state = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final liveStatusAsync = ref.watch(liveStatusProvider);
    final topFilter = ref.watch(edictFilterProvider);
    final baseTasks = ref.watch(filteredEdictsProvider);
    final stateFilter = ref.watch(mobileTaskStateFilterProvider);
    final focusedTaskId = ref.watch(mobileFocusedTaskIdProvider);
    final queryText = ref.watch(mobileTaskSearchQueryProvider).trim();
    final queryTerms = _splitQueryTerms(queryText);

    if ((focusedTaskId ?? '').isNotEmpty) {
      _scheduleFocusHandling(focusedTaskId!);
    } else if (_lastScheduledFocusId != null) {
      _lastScheduledFocusId = null;
      _focusClearTimer?.cancel();
    }

    final availableStates = _collectStates(baseTasks);
    final tasks = baseTasks.where((task) {
      if (stateFilter != null && !_matchesStateFilter(task.state, stateFilter)) {
        return false;
      }
      if (queryTerms.isNotEmpty && !_matchesTaskQuery(task, queryTerms)) {
        return false;
      }
      return true;
    }).toList(growable: false);
    final syncHints = ref.watch(workflowProjectionSyncProvider);
    tasks.sort((a, b) {
      if ((focusedTaskId ?? '').isNotEmpty) {
        if (a.id == focusedTaskId && b.id != focusedTaskId) return -1;
        if (b.id == focusedTaskId && a.id != focusedTaskId) return 1;
      }
      return compareTasksByWorkflowSyncHint(
        left: a,
        right: b,
        hints: syncHints,
      );
    });

    return Scaffold(
      backgroundColor: MobileUiTokens.pageBg,
      body: MobileImmersiveBackground(
        child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SearchBar(
                          query: ref.watch(mobileTaskSearchQueryProvider),
                          onChanged: (value) => ref
                              .read(mobileTaskSearchQueryProvider.notifier)
                              .state = value,
                        ),
                        if (queryText.isNotEmpty) ...[
                          const SizedBox(height: MobileUiTokens.gap8),
                          _ActiveSearchBanner(
                            query: queryText,
                            hitCount: tasks.length,
                            onClear: () => ref
                                .read(mobileTaskSearchQueryProvider.notifier)
                                .state = '',
                          ),
                        ],
                        if ((stateFilter ?? '').isNotEmpty) ...[
                          const SizedBox(height: MobileUiTokens.gap8),
                          _ActiveStateBanner(
                            label: _stateFilterDisplayLabel(stateFilter!),
                            onClear: () => ref
                                .read(mobileTaskStateFilterProvider.notifier)
                                .state = null,
                          ),
                        ],
                        const SizedBox(height: MobileUiTokens.gap12),
                        _TopFilterBar(
                          filter: topFilter,
                          onChanged: (next) {
                            ref.read(edictFilterProvider.notifier).state = next;
                            ref
                                .read(mobileTaskStateFilterProvider.notifier)
                                .state = null;
                          },
                        ),
                        const SizedBox(height: MobileUiTokens.gap10),
                        _StateFilterChips(
                          states: availableStates,
                          selectedState: stateFilter,
                          onChanged: (state) => ref
                              .read(mobileTaskStateFilterProvider.notifier)
                              .state = state,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: liveStatusAsync.when(
                      loading: () => const _LoadingList(),
                      error: (error, _) => _ErrorState(
                        error: error.toString(),
                        onRetry: () =>
                            ref.read(liveStatusProvider.notifier).refresh(),
                      ),
                      data: (_) {
                        if (tasks.isEmpty) {
                          return const _EmptyState();
                        }
                        return RefreshIndicator(
                          onRefresh: () =>
                              ref.read(liveStatusProvider.notifier).refresh(),
                          child: ListView.separated(
                            controller: _listController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: MobileUiTokens.pagePadding,
                            itemCount: tasks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: MobileUiTokens.gap10),
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return _TaskCard(
                                key: ValueKey(task.id),
                                task: task,
                                queryTerms: queryTerms,
                                focused: focusedTaskId == task.id,
                                onTap: () {
                                  ref.read(mobileFocusedTaskIdProvider.notifier).state =
                                      null;
                                  widget.onTaskTap(task.id);
                                },
                                onArchiveTask: widget.onArchiveTask,
                                enableSwipeArchive:
                                    widget.enableSwipeArchive &&
                                    widget.onArchiveTask != null,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (widget.showFab)
                Positioned(
                  right: 18,
                  bottom: 92,
                  child: _GradientFab(onTap: widget.onCreateTap),
                ),
            ],
          ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: '搜索旨意 / Agent / 标签',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => onChanged(''),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.3),
        ),
      ),
    );
  }
}

class _ActiveSearchBanner extends StatelessWidget {
  const _ActiveSearchBanner({
    required this.query,
    required this.hitCount,
    required this.onClear,
  });

  final String query;
  final int hitCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_rounded, size: 16, color: Color(0xFF4338CA)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '当前搜索：$query · 命中 $hitCount 条',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF3730A3),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

class _ActiveStateBanner extends StatelessWidget {
  const _ActiveStateBanner({
    required this.label,
    required this.onClear,
  });

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '状态筛选：$label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

class _TopFilterBar extends StatelessWidget {
  const _TopFilterBar({required this.filter, required this.onChanged});

  final TaskListFilter filter;
  final ValueChanged<TaskListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEEFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _SegmentItem(
            label: '全部',
            selected: filter == TaskListFilter.all,
            onTap: () => onChanged(TaskListFilter.all),
          ),
          _SegmentItem(
            label: '活跃',
            selected: filter == TaskListFilter.active,
            onTap: () => onChanged(TaskListFilter.active),
          ),
          _SegmentItem(
            label: '已归档',
            selected: filter == TaskListFilter.archived,
            onTap: () => onChanged(TaskListFilter.archived),
          ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? MobileUiTokens.primaryGradient
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF475569),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _StateFilterChips extends StatelessWidget {
  const _StateFilterChips({
    required this.states,
    required this.selectedState,
    required this.onChanged,
  });

  final List<String> states;
  final String? selectedState;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: states.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _StateChip(
              label: '全部状态',
              selected: selectedState == null,
              color: const Color(0xFF4338CA),
              onTap: () => onChanged(null),
            );
          }
          final state = states[index - 1];
          final color = _stateColor(state);
          return _StateChip(
            label: _mobileStateLabel(state),
            selected: selectedState == state,
            color: color,
            onTap: () => onChanged(state == selectedState ? null : state),
          );
        },
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? null : Colors.white,
          gradient: selected
              ? LinearGradient(
                  colors: [color.withValues(alpha: 0.95), color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.queryTerms,
    required this.focused,
    required this.onTap,
    required this.enableSwipeArchive,
    required this.onArchiveTask,
  });

  final Task task;
  final List<String> queryTerms;
  final bool focused;
  final VoidCallback onTap;
  final bool enableSwipeArchive;
  final Future<void> Function(Task task)? onArchiveTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncHints = ref.watch(workflowProjectionSyncProvider);
    final content = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: focused
                ? Border.all(color: const Color(0xFF6366F1), width: 1.3)
                : null,
            boxShadow: [
              MobileImmersiveBackground.cardShadow,
              if (focused)
                const BoxShadow(
                  color: Color(0x306366F1),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 132,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: _stateColor(task.state),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _HighlightedText(
                              text: task.title.isEmpty ? '(无标题任务)' : task.title,
                              queryTerms: queryTerms,
                              maxLines: 2,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatePill(state: task.state),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _DeptTag(dept: task.org, queryTerms: queryTerms),
                          if (shouldShowWorkflowProjectionSyncBadge(
                            task: task,
                            hints: syncHints,
                          ))
                            const MobilePillTag(
                              text: '同步中',
                              background: Color(0xFFFFF7ED),
                              foreground: Color(0xFFB45309),
                            ),
                          if (focused)
                            const MobilePillTag(
                              text: '新创建',
                              background: Color(0xFFEEF2FF),
                              foreground: Color(0xFF4338CA),
                            ),
                          if (task.archived) const _TinyArchivedTag(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _HighlightedText(
                        text: _shortNow(task.now),
                        queryTerms: queryTerms,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            timeAgo(task.updatedAt),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          _HeartbeatIndicator(task: task),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '↔ 左滑可快速归档',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFA8A29E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!enableSwipeArchive) return content;

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '归档任务',
              style: TextStyle(
                color: Color(0xFF4F46E5),
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.archive_rounded, color: Color(0xFF4F46E5)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('归档任务'),
            content: const Text('确认将该任务归档吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('确认'),
              ),
            ],
          ),
        );
        if (confirm != true) return false;
        await onArchiveTask?.call(task);
        return true;
      },
      child: content,
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);
    final label = _mobileStateLabel(state);
    return MobilePillTag(
      text: label,
      background: color.withValues(alpha: 0.12),
      foreground: color,
    );
  }
}

class _DeptTag extends StatelessWidget {
  const _DeptTag({required this.dept, required this.queryTerms});

  final String dept;
  final List<String> queryTerms;

  @override
  Widget build(BuildContext context) {
    final color = deptColor(dept);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: _HighlightedText(
        text: dept,
        queryTerms: queryTerms,
        maxLines: 1,
        style: TextStyle(
          color: color.withValues(alpha: 0.85),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.queryTerms,
    required this.style,
    this.maxLines,
  });

  final String text;
  final List<String> queryTerms;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    if (queryTerms.isEmpty || text.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final spans = _buildHighlightSpans(
      text: text,
      queryTerms: queryTerms,
      normalStyle: style,
      highlightStyle: style.copyWith(
        color: const Color(0xFF4338CA),
        fontWeight: FontWeight.w800,
      ),
    );

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

List<InlineSpan> _buildHighlightSpans({
  required String text,
  required List<String> queryTerms,
  required TextStyle normalStyle,
  required TextStyle highlightStyle,
}) {
  final terms = queryTerms.toSet().toList(growable: false)
    ..sort((a, b) => b.length.compareTo(a.length));
  final lowerText = text.toLowerCase();
  final spans = <InlineSpan>[];
  var start = 0;
  while (start < text.length) {
    final match = _nextMatch(lowerText, terms, start);
    if (match == null) {
      spans.add(TextSpan(text: text.substring(start), style: normalStyle));
      break;
    }
    final index = match.$1;
    final end = match.$2;
    if (index > start) {
      spans.add(TextSpan(
        text: text.substring(start, index),
        style: normalStyle,
      ));
    }
    spans.add(TextSpan(
      text: text.substring(index, end),
      style: highlightStyle,
    ));
    start = end;
  }
  return spans;
}

(int, int)? _nextMatch(String lowerText, List<String> queryTerms, int from) {
  int? bestIndex;
  int? bestEnd;
  for (final term in queryTerms) {
    final index = lowerText.indexOf(term, from);
    if (index < 0) continue;
    final end = index + term.length;
    if (bestIndex == null ||
        index < bestIndex ||
        (index == bestIndex && end > (bestEnd ?? end))) {
      bestIndex = index;
      bestEnd = end;
    }
  }
  if (bestIndex == null || bestEnd == null) return null;
  return (bestIndex, bestEnd);
}

class _TinyArchivedTag extends StatelessWidget {
  const _TinyArchivedTag();

  @override
  Widget build(BuildContext context) {
    return const MobilePillTag(
      text: '已归档',
      background: Color(0xFFF1F5F9),
      foreground: Color(0xFF64748B),
    );
  }
}

class _HeartbeatIndicator extends StatelessWidget {
  const _HeartbeatIndicator({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final color = _heartbeatColor(task.heartbeat.status);
    final agent = extractAgent(task);
    final hbText = task.heartbeat.label.isEmpty
        ? _heartbeatTextByState(task.heartbeat.status)
        : task.heartbeat.label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$agent · $hbText',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

String _mobileStateLabel(String state) {
  switch (state) {
    case 'Inbox':
    case 'Pending':
    case 'Taizi':
      return '分拣中';
    case 'Zhongshu':
      return '规划中';
    case 'Menxia':
      return '审议中';
    case 'YuLan':
      return '待御览';
    case 'Assigned':
    case 'Next':
      return '待派发';
    case 'Doing':
      return '执行中';
    case 'Review':
      return '审查中';
    case 'Done':
      return '已完成';
    case 'Blocked':
      return '已阻塞';
    case 'Cancelled':
      return '已取消';
    default:
      return kStateLabel[state] ?? state;
  }
}

String _heartbeatTextByState(HeartbeatStatus status) {
  switch (status) {
    case HeartbeatStatus.active:
      return '心跳正常';
    case HeartbeatStatus.warn:
      return '持续执行';
    case HeartbeatStatus.stalled:
      return '待复核';
    case HeartbeatStatus.idle:
      return '待调度';
    case HeartbeatStatus.unknown:
      return '状态未知';
  }
}

class _GradientFab extends StatelessWidget {
  const _GradientFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: MobileUiTokens.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4338CA).withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inbox_rounded,
                size: 42,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '暂无符合条件的任务',
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '试试切换筛选条件，或点击右下角 + 快速创建任务。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 30),
            const SizedBox(height: 10),
            const Text(
              '加载失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 132,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [MobileImmersiveBackground.cardShadow],
        ),
      ),
    );
  }
}

List<String> _collectStates(List<Task> tasks) {
  final states =
      tasks.map((task) => task.state).toSet().toList(growable: false);
  states.sort((a, b) {
    final ao = kStateOrder[a] ?? 999;
    final bo = kStateOrder[b] ?? 999;
    if (ao != bo) return ao.compareTo(bo);
    return a.compareTo(b);
  });
  return states;
}

String _shortNow(String now) {
  final normalized = now.trim();
  if (normalized.isEmpty || normalized == '-') {
    return '暂无最近动态';
  }
  if (normalized.length <= 60) return normalized;
  return '${normalized.substring(0, 60)}…';
}

Color _stateColor(String state) {
  switch (state) {
    case 'Doing':
      return const Color(0xFFF59E0B);
    case 'Review':
      return const Color(0xFF3B82F6);
    case 'Done':
      return const Color(0xFF10B981);
    case 'Blocked':
    case 'Cancelled':
      return const Color(0xFFEF4444);
    case 'YuLan':
      return const Color(0xFF8B5CF6);
    default:
      return const Color(0xFF6366F1);
  }
}

Color _heartbeatColor(HeartbeatStatus status) {
  switch (status) {
    case HeartbeatStatus.active:
      return const Color(0xFF22C55E);
    case HeartbeatStatus.warn:
      return const Color(0xFFF59E0B);
    case HeartbeatStatus.stalled:
      return const Color(0xFFEF4444);
    case HeartbeatStatus.idle:
      return const Color(0xFF64748B);
    case HeartbeatStatus.unknown:
      return const Color(0xFF94A3B8);
  }
}

List<String> _splitQueryTerms(String raw) {
  return raw
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

bool _matchesTaskQuery(Task task, List<String> queryTerms) {
  if (queryTerms.isEmpty) {
    return true;
  }
  final fields = <String>[
    task.title,
    task.org,
    task.now,
    task.id,
    task.state,
    _mobileStateLabel(task.state),
  ];
  final loweredFields = fields.map((e) => e.toLowerCase()).toList(growable: false);
  for (final term in queryTerms) {
    var matched = false;
    for (final field in loweredFields) {
      if (field.contains(term)) {
        matched = true;
        break;
      }
    }
    if (!matched) return false;
  }
  return true;
}

bool _matchesStateFilter(String taskState, String stateFilter) {
  switch (stateFilter) {
    case '@group:review':
      return taskState == 'Review' || taskState == 'YuLan';
    case '@group:attention':
      return taskState == 'Blocked' ||
          taskState == 'YuLan' ||
          taskState == 'Cancelled';
    default:
      return taskState == stateFilter;
  }
}

String _stateFilterDisplayLabel(String stateFilter) {
  switch (stateFilter) {
    case '@group:review':
      return '待评审（审查中 + 待御览）';
    case '@group:attention':
      return '需要关注（阻塞 + 待御览 + 已取消）';
    default:
      return _mobileStateLabel(stateFilter);
  }
}
