import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../core/core.dart';
import '../../core/workflow_entry.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../common/common.dart';

class EdictBoardPanel extends ConsumerWidget {
  const EdictBoardPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveStatusAsync = ref.watch(liveStatusProvider);
    final filteredEdicts = ref.watch(filteredEdictsProvider);
    final syncHints = ref.watch(workflowProjectionSyncProvider);
    final sortedEdicts = [...filteredEdicts];
    sortedEdicts.sort((a, b) {
      return compareTasksByWorkflowSyncHint(
        left: a,
        right: b,
        hints: syncHints,
      );
    });
    final filter = ref.watch(edictFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterBar(filter: filter),
        const SizedBox(height: 12),
        Expanded(
          child: liveStatusAsync.when(
            loading: () => const _LoadingGrid(),
            error: (error, _) => _ErrorState(
              errorText: error.toString(),
              onRetry: () => ref.read(liveStatusProvider.notifier).refresh(),
            ),
            data: (_) {
              if (sortedEdicts.isEmpty) {
                return const _EmptyState();
              }

              return GridView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 380,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.08,
                ),
                itemCount: sortedEdicts.length,
                itemBuilder: (context, index) {
                  final task = sortedEdicts[index];
                  return EdictCardItem(task: task);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});

  final TaskListFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
    final allEdicts = (liveStatus?.tasks ?? const <Task>[])
        .where(_isEdictTask)
        .toList(growable: false);
    final activeCount = allEdicts.where((t) => !t.archived).length;
    final archivedCount = allEdicts.where((t) => t.archived).length;
    final unArchivedDoneCount = allEdicts
        .where(
            (t) => !t.archived && (t.state == 'Done' || t.state == 'Cancelled'))
        .length;

    Future<void> runArchiveAllDone() async {
      final (confirmed, reason) = await showConfirmDialog(
        context: context,
        title: '一键归档',
        message: '将全部已完成/已取消旨意移入归档？',
        actionLabel: '确认归档',
        hintText: '可选备注',
      );
      if (!confirmed) return;

      final api = ref.read(apiClientProvider);
      final toast = ref.read(toastProvider.notifier);
      final result = await api.archiveAllDone();
      if (result.ok) {
        final suffix = reason.isEmpty ? '' : '（$reason）';
        toast.show(result.message ?? '📦 已完成一键归档$suffix');
        await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      } else {
        toast.show(result.error ?? '一键归档失败', type: ToastType.err);
      }
    }

    Future<void> runSchedulerScan() async {
      final api = ref.read(apiClientProvider);
      final toast = ref.read(toastProvider.notifier);
      final result = await api.schedulerScan();
      if (result.ok) {
        toast.show(result.message ?? '🧭 太子巡检完成');
        await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      } else {
        toast.show(result.error ?? '太子巡检失败', type: ToastType.err);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: EdictTheme.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EdictTheme.line),
      ),
      child: Row(
        children: [
          _FilterChipButton(
            label: '活跃',
            selected: filter == TaskListFilter.active,
            onTap: () => ref.read(edictFilterProvider.notifier).state =
                TaskListFilter.active,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '已归档',
            selected: filter == TaskListFilter.archived,
            onTap: () => ref.read(edictFilterProvider.notifier).state =
                TaskListFilter.archived,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '全部',
            selected: filter == TaskListFilter.all,
            onTap: () => ref.read(edictFilterProvider.notifier).state =
                TaskListFilter.all,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: unArchivedDoneCount > 0 ? runArchiveAllDone : null,
            style: TextButton.styleFrom(
              foregroundColor: EdictTheme.text,
              backgroundColor: EdictTheme.panel,
              side: BorderSide(
                color: unArchivedDoneCount > 0
                    ? EdictTheme.line
                    : EdictTheme.line.withOpacity(0.35),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Text('📦', style: TextStyle(fontSize: 12)),
            label: const Text('一键归档'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '共 ${allEdicts.length} 道旨意 · 活跃 $activeCount · 归档 $archivedCount',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EdictTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            onPressed: runSchedulerScan,
            icon: const Text('🧭', style: TextStyle(fontSize: 12)),
            label: const Text('太子巡检'),
            style: FilledButton.styleFrom(
              foregroundColor: EdictTheme.text,
              backgroundColor: EdictTheme.panel,
              side: const BorderSide(color: EdictTheme.acc),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ],
      ),
    );
  }
}

class EdictCardItem extends ConsumerWidget {
  const EdictCardItem({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncHints = ref.watch(workflowProjectionSyncProvider);
    final route = resolveTaskEntryRoute(task);
    final workflowId = route.unresolved ? '' : route.workflowId;
    final workflowEventsState = route.unresolved
        ? null
        : ref.watch(workflowEventsProvider(workflowId)).valueOrNull;
    final workflowCommandStatus = _workflowCommandStatus(workflowEventsState);
    final hasWorkflowCommandPending =
        workflowCommandStatus.pending > 0 || workflowCommandStatus.timedOut > 0;
    final isTaskArchived = isArchived(task);
    final canStartPlanning = task.state == 'Pending' && isWorkflowV2Task(task);
    final canStop =
        !const <String>{'Done', 'Blocked', 'Cancelled'}.contains(task.state);
    final canResume =
        const <String>{'Blocked', 'Cancelled'}.contains(task.state);
    final hasBlock =
        task.block.isNotEmpty && task.block != '-' && task.block != '无';

    final stageStatuses = getPipeStatus(task);
    final activeIndex = stageStatuses
        .indexWhere((stage) => stage.status == PipeNodeStatus.active);
    final currentStage = activeIndex >= 0 && activeIndex < kPipe.length
        ? kPipe[activeIndex]
        : null;

    final totalTodos = task.todos.length;
    final doneTodos =
        task.todos.where((todo) => todo.status == TodoStatus.completed).length;
    final todoPercent = totalTodos == 0 ? 0.0 : doneTodos / totalTodos;

    Future<void> doTaskAction(String action, String reason) async {
      final api = ref.read(apiClientProvider);
      final toast = ref.read(toastProvider.notifier);
      if (route.unresolved) {
        toast.show('workflow 数据待同步，暂不能执行该操作', type: ToastType.err);
        return;
      }
      final baseProjectionVersion = task.projectionVersion;
      final eventType = _eventTypeForWorkflowAction(action);
      final result = switch (action) {
        'start_planning' =>
          await api.startPlanning(workflowId, content: reason),
        'stop' => await api.stopWorkflow(workflowId, reason: reason),
        'cancel' => await api.cancelWorkflow(workflowId, reason: reason),
        'resume' => await api.resumeWorkflow(workflowId, reason: reason),
        _ => const ActionResult(ok: false, error: '未知动作'),
      };
      if (result.ok) {
        ref
            .read(workflowEventsProvider(workflowId).notifier)
            .clearFailedMutations(
              eventType: eventType,
              targetType: 'workflow',
              targetId: workflowId,
            );
        final mutationId = (result.entryId ?? '').isNotEmpty
            ? result.entryId!
            : 'local-${DateTime.now().microsecondsSinceEpoch}';
        final workflowEvents =
            ref.read(workflowEventsProvider(workflowId).notifier);
        workflowEvents.registerPendingMutation(
          mutationId: mutationId,
          eventType: eventType,
          taskId: task.id,
          targetType: 'workflow',
          targetId: workflowId,
        );
        ref.read(workflowProjectionSyncProvider.notifier).markSyncing(
              workflowId: workflowId,
              taskId: task.id,
              baseProjectionVersion: baseProjectionVersion,
            );
        await workflowEvents.reconcileNow();
        toast.show(result.message ?? '操作成功');
        await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      } else {
        toast.show(result.error ?? '操作失败', type: ToastType.err);
      }
    }

    Future<void> toggleArchive() async {
      final api = ref.read(apiClientProvider);
      final toast = ref.read(toastProvider.notifier);
      final result = await api.archiveTask(task.id, !task.archived);
      if (result.ok) {
        toast.show(result.message ?? (task.archived ? '已取消归档' : '已归档'));
        await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      } else {
        toast.show(result.error ?? '归档操作失败', type: ToastType.err);
      }
    }

    Future<void> stopOrCancel(String action) async {
      final (confirmed, reason) = await showConfirmDialog(
        context: context,
        title: action == 'stop' ? '确认叫停任务？' : '确认取消任务？',
        message: action == 'stop' ? '叫停后可恢复执行，请输入叫停原因。' : '取消后任务将停止推进，请输入取消原因。',
        actionLabel: action == 'stop' ? '确认叫停' : '确认取消',
        hintText: action == 'stop' ? '请输入叫停原因（可选）' : '请输入取消原因（可选）',
      );
      if (!confirmed) return;
      await doTaskAction(action, reason);
    }

    Future<void> startPlanning() async {
      final (confirmed, content) = await showConfirmDialog(
        context: context,
        title: '开始规划？',
        message: '将工作流从草稿推进到规划阶段，可附加规划说明。',
        actionLabel: '开始规划',
        hintText: '可选：规划说明',
      );
      if (!confirmed) return;
      await doTaskAction('start_planning', content);
    }

    final cardBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiniPipe(task: task),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: EdictTheme.acc.withOpacity(0.14),
                border: Border.all(color: EdictTheme.acc.withOpacity(0.85)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                task.id,
                style: const TextStyle(
                  color: EdictTheme.acc,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(task.title.isEmpty ? '(无标题)' : task.title,
                  style: const TextStyle(
                    color: EdictTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StateTag(state: task.state),
            DeptTag(dept: task.org),
            if (currentStage != null)
              Text.rich(
                TextSpan(
                  style: const TextStyle(color: EdictTheme.muted, fontSize: 11),
                  children: [
                    const TextSpan(text: '当前: '),
                    TextSpan(
                      text: '${currentStage.dept} · ${currentStage.action}',
                      style: TextStyle(
                        color: deptColor(currentStage.dept),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (task.now.isNotEmpty && task.now != '-') ...[
          const SizedBox(height: 8),
          Text(
            task.now.length > 80 ? '${task.now.substring(0, 80)}…' : task.now,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: EdictTheme.muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
        if (task.reviewRound > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 3,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...List<Widget>.generate(task.reviewRound, (i) {
                final isLatest = i == task.reviewRound - 1;
                final ringColor =
                    isLatest ? EdictTheme.acc : const Color(0xFF2A4A8A);
                final bgColor = isLatest
                    ? EdictTheme.acc.withOpacity(0.14)
                    : const Color(0xFF1A3A6A).withOpacity(0.14);
                final textColor =
                    isLatest ? EdictTheme.acc : const Color(0xFF4A6AAA);
                return Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bgColor,
                    border: Border.all(color: ringColor),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                );
              }),
              Text(
                '第 ${task.reviewRound} 轮磋商',
                style: const TextStyle(
                  color: EdictTheme.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
        if (totalTodos > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '📋 $doneTodos/$totalTodos',
                style: const TextStyle(
                  color: EdictTheme.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: todoPercent,
                    minHeight: 6,
                    backgroundColor: EdictTheme.line,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(EdictTheme.acc),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                doneTodos == totalTodos
                    ? '✅ 全部完成'
                    : '${(todoPercent * 100).round()}%',
                style: const TextStyle(color: EdictTheme.muted, fontSize: 10),
              ),
            ],
          ),
        ],
        const Spacer(),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            HeartbeatBadge(heartbeat: task.heartbeat),
            if (shouldShowWorkflowProjectionSyncBadge(
              task: task,
              hints: syncHints,
            ))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '同步中',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (hasWorkflowCommandPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '动作待确认',
                  style: TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (workflowCommandStatus.failed > 0)
              Tooltip(
                message: '存在 ${workflowCommandStatus.failed} 个确认失败动作，可重试对应操作',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    border: Border.all(color: const Color(0xFFF87171)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '可重试',
                    style: TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (task.state == 'YuLan')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x15FFD700),
                  border: Border.all(color: const Color(0x44FFD700)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '👑 待御批',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            if (hasBlock)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF200A10),
                  border: Border.all(color: const Color(0x44FF5270)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '🚫 ${task.block}',
                  style: const TextStyle(
                    color: EdictTheme.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (task.eta.isNotEmpty && task.eta != '-')
              Text(
                '📅 ${task.eta}',
                style: const TextStyle(
                  color: EdictTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (canStartPlanning)
              _MiniActionButton(
                label: '🧭开始规划',
                disabledReason: _workflowPendingReason(workflowCommandStatus),
                onPressed: hasWorkflowCommandPending ? null : startPlanning,
              ),
            if (canStop)
              _MiniActionButton(
                label: '⏸叫停',
                disabledReason: _workflowPendingReason(workflowCommandStatus),
                onPressed: hasWorkflowCommandPending
                    ? null
                    : () => stopOrCancel('stop'),
              ),
            if (canStop)
              _MiniActionButton(
                label: '🚫取消',
                danger: true,
                disabledReason: _workflowPendingReason(workflowCommandStatus),
                onPressed: hasWorkflowCommandPending
                    ? null
                    : () => stopOrCancel('cancel'),
              ),
            if (canResume)
              _MiniActionButton(
                label: '▶恢复',
                disabledReason: _workflowPendingReason(workflowCommandStatus),
                onPressed: hasWorkflowCommandPending
                    ? null
                    : () => doTaskAction('resume', '恢复执行'),
              ),
            if (isTaskArchived && !task.archived)
              _MiniActionButton(label: '📦归档', onPressed: toggleArchive),
            if (task.archived)
              _MiniActionButton(label: '📤取消归档', onPressed: toggleArchive),
          ],
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!route.unresolved) {
            ref.read(modalWorkflowIdProvider.notifier).state = route.workflowId;
            return;
          }
          ref.read(toastProvider.notifier).show(
                '该任务的 workflow 数据待同步，请稍后重试',
                type: ToastType.err,
              );
        },
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: isTaskArchived ? const _DashedCardBorderPainter() : null,
          child: Opacity(
            opacity: isTaskArchived ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EdictTheme.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isTaskArchived ? Colors.transparent : EdictTheme.line,
                ),
              ),
              child: cardBody,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton(
      {required this.label,
      required this.onPressed,
      this.danger = false,
      this.disabledReason});

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: danger ? EdictTheme.danger : EdictTheme.text,
        side: BorderSide(
            color:
                danger ? EdictTheme.danger.withOpacity(0.55) : EdictTheme.line),
        backgroundColor: danger ? const Color(0xFF200A10) : EdictTheme.panel2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: danger ? EdictTheme.danger : EdictTheme.text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (onPressed != null) {
      return button;
    }
    return Tooltip(
      message: disabledReason ?? '当前不可操作，请稍后重试',
      child: button,
    );
  }
}

String _eventTypeForWorkflowAction(String action) {
  return switch (action) {
    'start_planning' => ApiClient.eventStartPlanning,
    'stop' => ApiClient.eventStopWorkflow,
    'cancel' => ApiClient.eventCancelWorkflow,
    'resume' => ApiClient.eventResumeWorkflow,
    _ => 'workflow.v2.command.unknown',
  };
}

({int pending, int timedOut, int failed}) _workflowCommandStatus(
  WorkflowEventsState? state,
) {
  var pending = 0;
  var timedOut = 0;
  var failed = 0;
  if (state == null) {
    return (pending: 0, timedOut: 0, failed: 0);
  }
  for (final mutation in state.pendingMutations.values) {
    if (!mutation.eventType.toLowerCase().startsWith('workflow.v2.command.')) {
      continue;
    }
    if (mutation.status == 'pending') {
      pending += 1;
    } else if (mutation.status == 'timed_out') {
      timedOut += 1;
    } else if (mutation.status == 'failed') {
      failed += 1;
    }
  }
  return (pending: pending, timedOut: timedOut, failed: failed);
}

String _workflowPendingReason(
    ({int pending, int timedOut, int failed}) status) {
  if (status.timedOut > 0) {
    return '有 ${status.timedOut} 个动作确认超时，请先打开详情页刷新核对';
  }
  if (status.pending > 0) {
    return '有 ${status.pending} 个 workflow 动作待确认，请稍后重试';
  }
  return '当前不可操作，请稍后重试';
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: EdictTheme.panel,
      selectedColor: EdictTheme.acc.withOpacity(0.16),
      side: BorderSide(color: selected ? EdictTheme.acc : EdictTheme.line),
      showCheckmark: false,
      label: Text(
        label,
        style: TextStyle(
          color: selected ? EdictTheme.acc : EdictTheme.text,
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EdictTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EdictTheme.line),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '暂无旨意',
              style: TextStyle(
                color: EdictTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '通过飞书向太子发送任务，太子分拣后转中书省处理',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: EdictTheme.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.errorText, required this.onRetry});

  final String errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EdictTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EdictTheme.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '加载失败',
              style: TextStyle(
                color: EdictTheme.danger,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              errorText,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EdictTheme.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: EdictTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EdictTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonLine(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            _skeletonLine(width: 160, height: 14),
            const SizedBox(height: 8),
            _skeletonLine(width: 220, height: 10),
            const SizedBox(height: 12),
            _skeletonLine(width: double.infinity, height: 8),
            const SizedBox(height: 6),
            _skeletonLine(width: double.infinity, height: 8),
            const Spacer(),
            _skeletonLine(width: 210, height: 10),
            const SizedBox(height: 10),
            _skeletonLine(width: 170, height: 26),
          ],
        ),
      ),
    );
  }

  Widget _skeletonLine({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EdictTheme.line.withOpacity(0.55),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _DashedCardBorderPainter extends CustomPainter {
  const _DashedCardBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EdictTheme.muted.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(14),
        ),
      );

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dash = 6.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final end = ((distance + dash) > metric.length)
            ? metric.length
            : (distance + dash);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

bool _isEdictTask(Task task) {
  final sourceMeta = task.sourceMeta ?? const <String, dynamic>{};

  final isEdictFlag = sourceMeta['isEdict'];
  if (isEdictFlag is bool) {
    return isEdictFlag;
  }

  final type =
      (sourceMeta['type'] ?? sourceMeta['taskType'] ?? sourceMeta['kind'])
          ?.toString()
          .toLowerCase();
  if (type == 'edict') {
    return true;
  }
  if (type == 'session') {
    return false;
  }

  final id = task.id.toLowerCase();
  if (id.startsWith('sess:') ||
      id.startsWith('session-') ||
      id.startsWith('sess_')) {
    return false;
  }

  final org = task.org.toLowerCase();
  if (org.contains('session')) {
    return false;
  }

  return true;
}
