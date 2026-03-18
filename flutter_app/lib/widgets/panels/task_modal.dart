import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/core.dart';
import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/live_status_provider.dart';
import '../../providers/task_detail_provider.dart';
import '../../providers/ui_provider.dart';
import '../common/confirm_dialog.dart';
import '../common/heartbeat_badge.dart';
import '../common/state_tag.dart';

const Map<String, String> _agentLabels = <String, String>{
  'main': '太子',
  'zhongshu': '中书省',
  'menxia': '门下省',
  'shangshu': '尚书省',
  'libu': '礼部',
  'hubu': '户部',
  'bingbu': '兵部',
  'xingbu': '刑部',
  'gongbu': '工部',
  'libu_hr': '吏部',
  'zaochao': '钦天监',
};

const Map<String, String> _nextLabels = <String, String>{
  'Taizi': '中书省起草',
  'Zhongshu': '门下省审议',
  'Menxia': '皇上御览',
  'YuLan': '尚书省派发',
  'Assigned': '开始执行',
  'Doing': '进入审查',
  'Review': '完成',
};

const Map<String, Color> _phaseColor = <String, Color>{
  '皇上': Color(0xFFEAB308),
  '太子': Color(0xFFF97316),
  '中书省': Color(0xFF3B82F6),
  '门下省': Color(0xFF8B5CF6),
  '尚书省': Color(0xFF10B981),
  '六部': Color(0xFF06B6D4),
  '礼部': Color(0xFFEC4899),
  '户部': Color(0xFFF59E0B),
  '兵部': Color(0xFFEF4444),
  '刑部': Color(0xFF6366F1),
  '工部': Color(0xFF14B8A6),
  '吏部': Color(0xFFD946EF),
};

class TaskModalHost extends ConsumerStatefulWidget {
  const TaskModalHost({super.key});

  @override
  ConsumerState<TaskModalHost> createState() => _TaskModalHostState();
}

class TaskModal extends StatelessWidget {
  const TaskModal({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaskModalHost();
  }
}

class _TaskModalHostState extends ConsumerState<TaskModalHost> {
  bool _showing = false;
  ProviderSubscription<String?>? _modalSub;

  @override
  void initState() {
    super.initState();
    _modalSub = ref.listenManual<String?>(modalTaskIdProvider, (previous, next) {
      if (next != null && !_showing) {
        _open(next);
        return;
      }
      if (next == null && _showing && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  @override
  void dispose() {
    _modalSub?.close();
    super.dispose();
  }

  Future<void> _open(String taskId) async {
    _showing = true;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'task-modal',
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) => _TaskModalView(taskId: taskId),
      transitionBuilder: (_, animation, __, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(curve), child: child),
        );
      },
    );
    _showing = false;
    if (mounted) {
      ref.read(modalTaskIdProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _TaskModalView extends ConsumerStatefulWidget {
  const _TaskModalView({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_TaskModalView> createState() => _TaskModalViewState();
}

class _TaskModalViewState extends ConsumerState<_TaskModalView> {
  final _extraMaterialController = TextEditingController();
  final Set<String> _expandedTodoIds = <String>{};
  bool _materialSending = false;
  bool _busyAction = false;

  @override
  void dispose() {
    _extraMaterialController.dispose();
    super.dispose();
  }

  void _close() {
    ref.read(modalTaskIdProvider.notifier).state = null;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? EdictTheme.danger : EdictTheme.ok),
    );
  }

  Future<void> _refreshAll(String taskId) async {
    await ref.read(liveStatusProvider.notifier).refresh();
    unawaited(ref.read(taskActivityProvider(taskId).notifier).refresh());
    unawaited(ref.read(schedulerStateProvider(taskId).notifier).refresh());
  }

  Future<void> _taskAction(Task task, String action, String title, String msg) async {
    final result = await showConfirmDialog(
      context: context,
      title: title,
      message: msg,
      actionLabel: '确认',
      hintText: '请输入原因/备注（可选）',
    );
    if (!result.$1) return;
    setState(() => _busyAction = true);
    final api = ref.read(apiClientProvider);
    final r = await api.taskAction(task.id, action, result.$2);
    if (!mounted) return;
    setState(() => _busyAction = false);
    if (r.ok) {
      _toast(r.message ?? '操作成功');
      await _refreshAll(task.id);
      _close();
    } else {
      _toast(r.error ?? '操作失败', error: true);
    }
  }

  Future<void> _review(Task task, String action) async {
    final label = action == 'approve' ? '准奏' : '封驳';
    final result = await showConfirmDialog(
      context: context,
      title: '$label ${task.id}',
      message: '请确认是否$label此任务。',
      actionLabel: label,
      hintText: '请输入批注（可选）',
    );
    if (!result.$1) return;
    setState(() => _busyAction = true);
    final api = ref.read(apiClientProvider);
    final r = await api.reviewAction(task.id, action, result.$2);
    if (!mounted) return;
    setState(() => _busyAction = false);
    if (r.ok) {
      _toast('✅ ${task.id} 已$label');
      await _refreshAll(task.id);
      _close();
    } else {
      _toast(r.error ?? '操作失败', error: true);
    }
  }

  Future<void> _advance(Task task) async {
    final next = _nextLabels[task.state] ?? '下一步';
    final result = await showConfirmDialog(
      context: context,
      title: '⏩ 推进 ${task.id}',
      message: '当前: ${task.state} → 下一步: $next',
      actionLabel: '确认推进',
      hintText: '请输入说明（可选）',
    );
    if (!result.$1) return;
    setState(() => _busyAction = true);
    final api = ref.read(apiClientProvider);
    final r = await api.advanceState(task.id, result.$2);
    if (!mounted) return;
    setState(() => _busyAction = false);
    if (r.ok) {
      _toast('⏩ ${r.message ?? '已推进'}');
      await _refreshAll(task.id);
      _close();
    } else {
      _toast(r.error ?? '推进失败', error: true);
    }
  }

  Future<void> _schedulerAction(Task task, String action) async {
    final api = ref.read(apiClientProvider);

    if (action == 'scan') {
      final cf = await showConfirmDialog(
        context: context,
        title: '立即扫描',
        message: '确认立即触发调度扫描？',
        actionLabel: '扫描',
      );
      if (!cf.$1) return;
      setState(() => _busyAction = true);
      final r = await api.schedulerScan();
      if (!mounted) return;
      setState(() => _busyAction = false);
      if (r.ok) {
        _toast(r.message ?? '扫描完成');
      } else {
        _toast(r.error ?? '扫描失败', error: true);
      }
      unawaited(ref.read(schedulerStateProvider(task.id).notifier).refresh());
      return;
    }

    final title = switch (action) {
      'retry' => '🔁 重试派发',
      'escalate' => '📣 升级协调',
      'rollback' => '↩️ 回滚稳定点',
      _ => '确认操作',
    };

    final cf = await showConfirmDialog(
      context: context,
      title: title,
      message: '确认执行此调度动作？',
      hintText: '请输入原因（可选）',
      actionLabel: '确认',
    );
    if (!cf.$1) return;

    setState(() => _busyAction = true);
    final result = switch (action) {
      'retry' => await api.schedulerRetry(task.id, cf.$2),
      'escalate' => await api.schedulerEscalate(task.id, cf.$2),
      'rollback' => await api.schedulerRollback(task.id, cf.$2),
      _ => const ActionResult(ok: false, error: '未知动作'),
    };
    if (!mounted) return;
    setState(() => _busyAction = false);
    if (result.ok) {
      _toast(result.message ?? '操作成功');
      await _refreshAll(task.id);
    } else {
      _toast(result.error ?? '操作失败', error: true);
    }
  }

  String? _resolveDispatchAgent(Task t) {
    if (t.state == 'Pending' || t.state == 'Taizi') return 'taizi';
    if (t.state == 'Zhongshu') return 'zhongshu';
    if (t.state == 'Menxia') return 'menxia';
    if (t.state == 'Assigned' || t.state == 'Review' || t.state == 'Next') return 'shangshu';
    if (t.state == 'Doing') {
      final orgMap = <String, String>{
        '户部': 'hubu',
        '礼部': 'libu',
        '兵部': 'bingbu',
        '刑部': 'xingbu',
        '工部': 'gongbu',
        '吏部': 'libu_hr',
      };
      return orgMap[t.org.trim()];
    }
    return null;
  }

  Future<void> _supplement(Task task) async {
    final agent = _resolveDispatchAgent(task);
    if (agent == null) {
      _toast('当前状态暂无可自动识别的经办 Agent', error: true);
      return;
    }
    final material = _extraMaterialController.text.trim();
    if (material.isEmpty) {
      _toast('请先填写补充材料', error: true);
      return;
    }
    setState(() => _materialSending = true);
    final api = ref.read(apiClientProvider);
    final r = await api.dispatchTask(task.id, agent, '【补充材料】\n$material');
    if (!mounted) return;
    setState(() => _materialSending = false);
    if (r.ok) {
      _toast('📨 已补发至 ${_agentLabels[agent] ?? agent}');
      _extraMaterialController.clear();
      unawaited(ref.read(taskActivityProvider(task.id).notifier).refresh());
      unawaited(ref.read(schedulerStateProvider(task.id).notifier).refresh());
    } else {
      _toast(r.error ?? '补发失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(taskByIdProvider(widget.taskId));
    final activityAsync = ref.watch(taskActivityProvider(widget.taskId));
    final schedulerAsync = ref.watch(schedulerStateProvider(widget.taskId));

    if (task == null) {
      return _modalShell(
        context,
        child: const Center(child: Text('任务不存在或已关闭', style: EdictTheme.bodyStyle)),
      );
    }

    final stages = getPipeStatus(task);
    final activeStage = stages.firstWhere(
      (e) => e.status == PipeNodeStatus.active,
      orElse: () => stages[math.max(0, stages.length - 1)],
    );
    final flowLog = task.flowLog;
    final todos = task.todos;
    final todoDone = todos.where((x) => x.status == TodoStatus.completed).length;
    final todoTotal = todos.length;

    final canStop = !<String>{'Done', 'Blocked', 'Cancelled'}.contains(task.state);
    final canResume = <String>{'Blocked', 'Cancelled'}.contains(task.state);
    final sched = schedulerAsync.valueOrNull?.scheduler;
    final stalledSec = schedulerAsync.valueOrNull?.stalledSec ?? 0;
    final isDispatching = sched?.lastDispatchStatus == 'running';
    final terminal = task.state == 'Done' || task.state == 'Cancelled';

    return _modalShell(
      context,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(task.id, style: EdictTheme.captionStyle.copyWith(fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(task.title.isEmpty ? '(无标题)' : task.title, style: EdictTheme.headerStyle),
                  const SizedBox(height: 14),
                  _CurrentStageBanner(task: task, stage: activeStage),
                  const SizedBox(height: 12),
                  _FullPipeStrip(stages: stages),
                  const SizedBox(height: 14),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canStop)
                        _ActBtn(
                          label: '⏸ 叫停任务',
                          fg: EdictTheme.warn,
                          bg: EdictTheme.warn.withOpacity(0.12),
                          border: EdictTheme.warn.withOpacity(0.4),
                          onTap: _busyAction ? null : () => _taskAction(task, 'stop', '叫停任务', '确定要叫停 ${task.id} 吗？'),
                        ),
                      if (canStop)
                        _ActBtn(
                          label: '🚫 取消任务',
                          fg: EdictTheme.danger,
                          bg: EdictTheme.danger.withOpacity(0.12),
                          border: EdictTheme.danger.withOpacity(0.4),
                          onTap: _busyAction ? null : () => _taskAction(task, 'cancel', '取消任务', '确定要取消 ${task.id} 吗？'),
                        ),
                      if (canResume)
                        _ActBtn(
                          label: '▶️ 恢复执行',
                          fg: EdictTheme.ok,
                          bg: EdictTheme.ok.withOpacity(0.12),
                          border: EdictTheme.ok.withOpacity(0.4),
                          onTap: _busyAction
                              ? null
                              : () async {
                                  final api = ref.read(apiClientProvider);
                                  setState(() => _busyAction = true);
                                  final r = await api.taskAction(task.id, 'resume', '恢复执行');
                                  if (!mounted) return;
                                  setState(() => _busyAction = false);
                                  if (r.ok) {
                                    _toast(r.message ?? '已恢复');
                                    await _refreshAll(task.id);
                                    _close();
                                  } else {
                                    _toast(r.error ?? '恢复失败', error: true);
                                  }
                                },
                        ),
                    ],
                  ),

                  if (isDispatching)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x153B82F6),
                        border: Border.all(color: const Color(0x333B82F6)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          _PulseDot(color: Color(0xFF60A5FA), size: 8),
                          SizedBox(width: 8),
                          Expanded(child: Text('Agent 正在执行中，请等待完成后再操作', style: TextStyle(fontSize: 12, color: Color(0xFF60A5FA)))),
                        ],
                      ),
                    ),

                  if (task.state == 'YuLan')
                    _YuLanPanel(
                      disabled: isDispatching || _busyAction,
                      onApprove: () => _review(task, 'approve'),
                      onReject: () => _review(task, 'reject'),
                    ),

                  if (<String>{'Review', 'Menxia'}.contains(task.state))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ActBtn(
                            label: '✅ 准奏',
                            fg: EdictTheme.ok,
                            bg: EdictTheme.ok.withOpacity(0.12),
                            border: EdictTheme.ok.withOpacity(0.4),
                            onTap: (isDispatching || _busyAction) ? null : () => _review(task, 'approve'),
                          ),
                          _ActBtn(
                            label: '🚫 封驳',
                            fg: EdictTheme.danger,
                            bg: EdictTheme.danger.withOpacity(0.12),
                            border: EdictTheme.danger.withOpacity(0.4),
                            onTap: (isDispatching || _busyAction) ? null : () => _review(task, 'reject'),
                          ),
                        ],
                      ),
                    ),

                  if (<String>{'Pending', 'Taizi', 'Zhongshu', 'Menxia', 'YuLan', 'Assigned', 'Doing', 'Review', 'Next'}.contains(task.state))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _ActBtn(
                        label: '⏩ 推进到下一步',
                        fg: const Color(0xFF7C5CFC),
                        bg: const Color(0x187C5CFC),
                        border: const Color(0x447C5CFC),
                        onTap: (isDispatching || _busyAction) ? null : () => _advance(task),
                      ),
                    ),

                  if (!terminal)
                    _SupplementSection(
                      controller: _extraMaterialController,
                      sending: _materialSending,
                      label: _agentLabels[_resolveDispatchAgent(task) ?? ''] ?? '当前经办',
                      onSend: _materialSending ? null : () => _supplement(task),
                    ),

                  const SizedBox(height: 14),
                  _SchedulerSection(
                    scheduler: sched,
                    stalledSec: stalledSec,
                    isDispatching: isDispatching,
                    onRetry: () => _schedulerAction(task, 'retry'),
                    onEscalate: () => _schedulerAction(task, 'escalate'),
                    onRollback: () => _schedulerAction(task, 'rollback'),
                    onScan: () => _schedulerAction(task, 'scan'),
                  ),

                  if (todoTotal > 0) ...[
                    const SizedBox(height: 14),
                    _TodoSection(
                      todos: todos,
                      done: todoDone,
                      total: todoTotal,
                      expanded: _expandedTodoIds,
                      onToggle: (id) {
                        setState(() {
                          if (_expandedTodoIds.contains(id)) {
                            _expandedTodoIds.remove(id);
                          } else {
                            _expandedTodoIds.add(id);
                          }
                        });
                      },
                    ),
                  ],

                  const SizedBox(height: 14),
                  _BasicInfoGrid(task: task),

                  if (flowLog.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _FlowTimeline(flowLog: flowLog),
                  ],

                  if (task.output.isNotEmpty && task.output != '-') ...[
                    const SizedBox(height: 14),
                    _OutputSection(output: task.output),
                  ],

                  const SizedBox(height: 14),
                  _LiveActivitySection(
                    task: task,
                    asyncData: activityAsync,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              tooltip: '关闭',
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modalShell(BuildContext context, {required Widget child}) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: GestureDetector(
        onTap: _close,
        child: Material(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: math.min(MediaQuery.sizeOf(context).width * 0.98, 1260),
                height: MediaQuery.sizeOf(context).height * 0.96,
                decoration: EdictTheme.modalDecoration,
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentStageBanner extends StatelessWidget {
  const _CurrentStageBanner({required this.task, required this.stage});

  final Task task;
  final PipeStatus stage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: Row(
        children: [
          Text(stage.icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stage.dept, style: TextStyle(color: deptColor(stage.dept), fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('当前阶段：${stage.action}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          HeartbeatBadge(heartbeat: task.heartbeat),
        ],
      ),
    );
  }
}

class _FullPipeStrip extends StatelessWidget {
  const _FullPipeStrip({required this.stages});

  final List<PipeStatus> stages;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(stages.length * 2 - 1, (i) {
          if (i.isOdd) {
            final done = stages[(i - 1) ~/ 2].status == PipeNodeStatus.done;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('→', style: TextStyle(color: done ? EdictTheme.ok.withOpacity(0.65) : EdictTheme.muted.withOpacity(0.4))),
            );
          }

          final s = stages[i ~/ 2];
          final isDone = s.status == PipeNodeStatus.done;
          final isActive = s.status == PipeNodeStatus.active;
          final pending = s.status == PipeNodeStatus.pending;
          return Opacity(
            opacity: pending ? 0.3 : 1,
            child: Container(
              width: 96,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              child: Column(
                children: [
                  Container(
                    width: isActive ? 26 : 22,
                    height: isActive ? 26 : 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? EdictTheme.ok : isActive ? EdictTheme.panel : EdictTheme.panel2,
                      border: Border.all(
                        color: isDone ? EdictTheme.ok : isActive ? EdictTheme.acc : EdictTheme.line,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isDone
                        ? const Text('✓', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black))
                        : Text(s.icon, style: TextStyle(fontSize: isActive ? 13 : 11)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.dept,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDone ? EdictTheme.ok : isActive ? EdictTheme.acc : EdictTheme.muted,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  Text(s.action, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ActBtn extends StatelessWidget {
  const _ActBtn({required this.label, required this.fg, required this.bg, required this.border, required this.onTap});

  final String label;
  final Color fg;
  final Color bg;
  final Color border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
          child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _YuLanPanel extends StatelessWidget {
  const _YuLanPanel({required this.disabled, required this.onApprove, required this.onReject});

  final bool disabled;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x15FFD700),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x44FFD700)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('👑 御览 — 等待皇上御批', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFFD700))),
            const SizedBox(height: 8),
            const Text('门下省已审议通过，请审阅方案后御批。', style: TextStyle(fontSize: 12, color: EdictTheme.muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActBtn(
                    label: '👑 准奏 — 交付执行',
                    fg: EdictTheme.ok,
                    bg: EdictTheme.ok.withOpacity(0.12),
                    border: EdictTheme.ok.withOpacity(0.4),
                    onTap: disabled ? null : onApprove,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActBtn(
                    label: '🚫 封驳 — 退回修改',
                    fg: EdictTheme.danger,
                    bg: EdictTheme.danger.withOpacity(0.12),
                    border: EdictTheme.danger.withOpacity(0.4),
                    onTap: disabled ? null : onReject,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplementSection extends StatelessWidget {
  const _SupplementSection({required this.controller, required this.sending, required this.label, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final String label;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: EdictTheme.panel2,
        border: Border.all(color: EdictTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🧩 补充材料', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('可将新增背景/约束补发给当前经办。', style: TextStyle(fontSize: 11, color: EdictTheme.muted)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '输入补充材料后点击右侧按钮发送'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _ActBtn(
              label: sending ? '发送中…' : '📨 发送给$label',
              fg: const Color(0xFF60A5FA),
              bg: const Color(0x223B82F6),
              border: const Color(0x553B82F6),
              onTap: sending ? null : onSend,
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulerSection extends StatelessWidget {
  const _SchedulerSection({
    required this.scheduler,
    required this.stalledSec,
    required this.isDispatching,
    required this.onRetry,
    required this.onEscalate,
    required this.onRollback,
    required this.onScan,
  });

  final SchedulerInfo? scheduler;
  final int stalledSec;
  final bool isDispatching;
  final VoidCallback onRetry;
  final VoidCallback onEscalate;
  final VoidCallback onRollback;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final statusText = scheduler == null
        ? '加载中...'
        : '${scheduler!.enabled == false ? '已禁用' : '运行中'} · 阈值 ${scheduler!.stallThresholdSec ?? 180}s';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧭 太子调度', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(child: Text(statusText, style: const TextStyle(fontSize: 11, color: EdictTheme.muted))),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth;
              final cardW = (width - 12) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _KpiCard(label: '停滞时长', value: _fmtStalled(stalledSec), width: cardW),
                  _KpiCard(label: '重试次数', value: '${scheduler?.retryCount ?? 0}', width: cardW),
                  _KpiCard(
                    label: '升级级别',
                    value: scheduler?.escalationLevel == null || scheduler?.escalationLevel == 0
                        ? '无'
                        : (scheduler!.escalationLevel == 1 ? '门下省' : '尚书省'),
                    width: cardW,
                  ),
                  _KpiCard(label: '派发状态', value: scheduler?.lastDispatchStatus ?? 'idle', width: cardW),
                ],
              );
            },
          ),
          if (scheduler != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if ((scheduler!.lastProgressAt ?? '').isNotEmpty) Text('最近进展 ${_fmtTs(scheduler!.lastProgressAt)}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                if ((scheduler!.lastDispatchAt ?? '').isNotEmpty) Text('最近派发 ${_fmtTs(scheduler!.lastDispatchAt)}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                Text('自动回滚 ${scheduler!.autoRollback == false ? '关闭' : '开启'}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                if ((scheduler!.lastDispatchAgent ?? '').isNotEmpty)
                  Text('目标 ${scheduler!.lastDispatchAgent}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActBtn(
                label: '🔁 重试派发',
                fg: EdictTheme.acc,
                bg: EdictTheme.acc.withOpacity(0.1),
                border: EdictTheme.acc.withOpacity(0.35),
                onTap: isDispatching ? null : onRetry,
              ),
              _ActBtn(
                label: '📣 升级协调',
                fg: EdictTheme.warn,
                bg: EdictTheme.warn.withOpacity(0.1),
                border: EdictTheme.warn.withOpacity(0.35),
                onTap: isDispatching ? null : onEscalate,
              ),
              _ActBtn(
                label: '↩️ 回滚稳定点',
                fg: EdictTheme.danger,
                bg: EdictTheme.danger.withOpacity(0.1),
                border: EdictTheme.danger.withOpacity(0.35),
                onTap: isDispatching ? null : onRollback,
              ),
              _ActBtn(label: '🔍 立即扫描', fg: EdictTheme.acc2, bg: EdictTheme.acc2.withOpacity(0.1), border: EdictTheme.acc2.withOpacity(0.35), onTap: onScan),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.width});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EdictTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EdictTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _TodoSection extends StatelessWidget {
  const _TodoSection({
    required this.todos,
    required this.done,
    required this.total,
    required this.expanded,
    required this.onToggle,
  });

  final List<TodoItem> todos;
  final int done;
  final int total;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : ((done / total) * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('子任务清单（$done/$total）', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              SizedBox(
                width: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 7),
                ),
              ),
              const SizedBox(width: 6),
              Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...todos.map((td) {
            final ico = td.status == TodoStatus.completed ? '✅' : td.status == TodoStatus.inProgress ? '🔄' : '⬜';
            final statusLabel = td.status == TodoStatus.completed ? '已完成' : td.status == TodoStatus.inProgress ? '进行中' : '待开始';
            final color = td.status == TodoStatus.completed
                ? EdictTheme.ok
                : td.status == TodoStatus.inProgress
                    ? EdictTheme.acc
                    : EdictTheme.muted;
            final open = expanded.contains(td.id);
            return InkWell(
              onTap: () => onToggle(td.id),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EdictTheme.line),
                  color: td.status == TodoStatus.completed ? EdictTheme.ok.withOpacity(0.06) : EdictTheme.panel,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(ico),
                        const SizedBox(width: 6),
                        Text('#${td.id}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            td.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              decoration: td.status == TodoStatus.completed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: color.withOpacity(0.38)),
                          ),
                          child: Text(statusLabel, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if ((td.detail ?? '').isNotEmpty && open) ...[
                      const SizedBox(height: 6),
                      Text(td.detail!, style: const TextStyle(fontSize: 11, color: EdictTheme.muted, height: 1.45)),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BasicInfoGrid extends StatelessWidget {
  const _BasicInfoGrid({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _InfoRow(label: '状态', child: Row(children: [StateTag(state: task.state), if (task.reviewRound > 0) ...[const SizedBox(width: 8), Text('共磋商 ${task.reviewRound} 轮', style: const TextStyle(fontSize: 11, color: EdictTheme.muted))]])),
      _InfoRow(label: '执行部门', child: Text(task.org.isEmpty ? '—' : task.org)),
      if (task.eta.isNotEmpty && task.eta != '-') _InfoRow(label: '预计完成', child: Text(task.eta)),
      if (task.block.isNotEmpty && task.block != '无' && task.block != '-') _InfoRow(label: '阻塞项', child: Text(task.block, style: const TextStyle(color: EdictTheme.danger))),
      if (task.now.isNotEmpty && task.now != '-') _InfoRow(label: '当前进展', child: Text(task.now, style: const TextStyle(fontSize: 12))),
      if (task.ac.isNotEmpty) _InfoRow(label: '验收标准', child: Text(task.ac, style: const TextStyle(fontSize: 12))),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          if (isNarrow) {
            return Column(children: rows.map((e) => Padding(padding: const EdgeInsets.only(bottom: 6), child: e)).toList(growable: false));
          }
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            children: rows.map((e) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: e)).toList(growable: false),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 11, color: EdictTheme.muted))),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _FlowTimeline extends StatelessWidget {
  const _FlowTimeline({required this.flowLog});

  final List<FlowEntry> flowLog;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('流转日志（${flowLog.length} 条）', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Stack(
            children: [
              Positioned(left: 46, top: 2, bottom: 2, child: Container(width: 1, color: EdictTheme.line)),
              Column(
                children: flowLog.map((fl) {
                  final ts = fl.at ?? fl.ts ?? '';
                  final remark = fl.remark ?? fl.reason ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 40, child: Text(_hhmm(ts), style: const TextStyle(fontSize: 10, color: EdictTheme.muted))),
                        const SizedBox(width: 6),
                        Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: deptColor(fl.from))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: fl.from, style: TextStyle(color: deptColor(fl.from), fontWeight: FontWeight.w700)),
                                    const TextSpan(text: ' → ', style: TextStyle(color: EdictTheme.muted)),
                                    TextSpan(text: fl.to, style: TextStyle(color: deptColor(fl.to), fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (remark.isNotEmpty)
                                Text(remark, style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(growable: false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutputSection extends StatelessWidget {
  const _OutputSection({required this.output});

  final String output;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('产出物', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EdictTheme.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EdictTheme.line),
            ),
            child: SelectableText(output, style: EdictTheme.monoStyle),
          ),
        ],
      ),
    );
  }
}

class _LiveActivitySection extends StatelessWidget {
  const _LiveActivitySection({required this.task, required this.asyncData});

  final Task task;
  final AsyncValue<TaskActivityData> asyncData;

  @override
  Widget build(BuildContext context) {
    final data = asyncData.valueOrNull;
    if (asyncData.isLoading && data == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: EdictTheme.panelDecoration,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (data == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: EdictTheme.panelDecoration,
        child: Text('实时动态加载失败：${asyncData.error ?? '未知错误'}', style: const TextStyle(color: EdictTheme.danger, fontSize: 12)),
      );
    }

    final terminal = task.state == 'Done' || task.state == 'Cancelled';
    final activity = data.activity ?? const <ActivityEntry>[];
    final last = activity.isEmpty ? null : activity.last;
    final active = _isActivityActive(last?.at);

    final agentParts = <String>[];
    if ((data.agentLabel ?? '').isNotEmpty) agentParts.add(data.agentLabel!);
    if ((data.relatedAgents?.length ?? 0) > 1) agentParts.add('${data.relatedAgents!.length}个 Agent');
    if ((data.lastActive ?? '').isNotEmpty) agentParts.add('最后活跃: ${data.lastActive}');

    final flowItems = activity.where((a) => a.kind == 'flow').toList(growable: false);
    final grouped = <String, List<ActivityEntry>>{};
    for (final item in activity.where((a) => a.kind != 'flow')) {
      final key = (item.agent ?? 'unknown');
      grouped.putIfAbsent(key, () => <ActivityEntry>[]).add(item);
    }

    final phases = data.phaseDurations ?? const <PhaseDuration>[];
    final maxDur = phases.fold<int>(1, (acc, p) => math.max(acc, p.durationSec));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseDot(color: active ? EdictTheme.ok : EdictTheme.muted, size: 8),
              const SizedBox(width: 8),
              Text(terminal ? '执行回顾' : '实时动态', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(agentParts.isEmpty ? '加载中...' : agentParts.join(' · '), style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
              ),
            ],
          ),

          if (phases.isNotEmpty) ...[
            const SizedBox(height: 10),
            _divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('⏱ 阶段耗时', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const Spacer(),
                if ((data.totalDuration ?? '').isNotEmpty) Text('总耗时 ${data.totalDuration}', style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
              ],
            ),
            const SizedBox(height: 6),
            ...phases.map((p) {
              final pct = math.max(5, ((p.durationSec / maxDur) * 100).round());
              final c = _phaseColor[p.phase] ?? EdictTheme.muted;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(width: 54, child: Text(p.phase, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: EdictTheme.muted))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 14,
                          color: EdictTheme.panel,
                          child: FractionallySizedBox(
                            widthFactor: pct / 100,
                            alignment: Alignment.centerLeft,
                            child: Container(color: c.withOpacity(p.ongoing == true ? 0.6 : 0.85)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 84,
                      child: Text('${p.durationText}${p.ongoing == true ? ' ●进行中' : ''}', style: TextStyle(fontSize: 10, color: p.ongoing == true ? const Color(0xFF60A5FA) : EdictTheme.muted)),
                    ),
                  ],
                ),
              );
            }),
          ],

          if (data.todosSummary != null) ...[
            const SizedBox(height: 8),
            _divider(),
            const SizedBox(height: 8),
            _TodosSummaryBar(summary: data.todosSummary!),
          ],

          if (data.resourceSummary != null &&
              (data.resourceSummary!.totalTokens != null || data.resourceSummary!.totalCost != null)) ...[
            const SizedBox(height: 8),
            _divider(),
            const SizedBox(height: 8),
            _ResourceSummaryView(summary: data.resourceSummary!),
          ],

          if (data.retrySummary != null && data.retrySummary!.count > 0) ...[
            const SizedBox(height: 8),
            _divider(),
            const SizedBox(height: 8),
            _RetrySummaryView(summary: data.retrySummary!),
          ],

          if ((data.artifacts ?? const <ArtifactInfo>[]).isNotEmpty) ...[
            const SizedBox(height: 8),
            _divider(),
            const SizedBox(height: 8),
            _ArtifactsView(artifacts: data.artifacts!),
          ],

          const SizedBox(height: 8),
          _divider(),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (flowItems.isNotEmpty)
                    ...flowItems.map(
                      (a) => _ActivityRow(
                        icon: '📋',
                        body: Text.rich(TextSpan(children: [TextSpan(text: a.from ?? ''), const TextSpan(text: ' → '), TextSpan(text: a.to ?? ''), TextSpan(text: '　${a.remark ?? ''}')]), style: const TextStyle(fontSize: 11)),
                        time: _fmtActivityTime(a.at),
                      ),
                    ),
                  if (grouped.isNotEmpty)
                    ...grouped.entries.map((entry) {
                      final agent = entry.key;
                      final items = entry.value;
                      final label = _agentLabels[agent] ?? agent;
                      final lastTime = items.isEmpty ? '--:--:--' : _fmtActivityTime(items.last.at);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: EdictTheme.panel,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: EdictTheme.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: EdictTheme.panel2,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                border: Border(bottom: BorderSide(color: EdictTheme.line.withOpacity(0.8))),
                              ),
                              child: Text('$label · 最近更新 $lastTime', style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: items.map((a) => _ActivityEntryView(entry: a)).toList(growable: false),
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                  else if (flowItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(data.message ?? data.error ?? 'Agent 尚未上报进展（等待 Agent 调用 progress 命令）', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(height: 1, color: EdictTheme.line);
}

class _TodosSummaryBar extends StatelessWidget {
  const _TodosSummaryBar({required this.summary});

  final TodosSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('📊 执行进度', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text('${summary.percent.toStringAsFixed(summary.percent % 1 == 0 ? 0 : 1)}%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: summary.percent >= 100 ? EdictTheme.ok : summary.percent >= 50 ? EdictTheme.acc : EdictTheme.text)),
            const SizedBox(width: 8),
            Text('✅${summary.completed} 🔄${summary.inProgress} ⬜${summary.notStarted} / 共${summary.total}项', style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 8,
            color: EdictTheme.panel,
            child: Row(
              children: [
                if (summary.completed > 0)
                  Expanded(flex: summary.completed, child: Container(color: const Color(0xFF22C55E))),
                if (summary.inProgress > 0)
                  Expanded(flex: summary.inProgress, child: Container(color: const Color(0xFF3B82F6))),
                if (summary.notStarted > 0)
                  Expanded(flex: summary.notStarted, child: Container(color: EdictTheme.muted.withOpacity(0.5))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResourceSummaryView extends StatelessWidget {
  const _ResourceSummaryView({required this.summary});

  final ResourceSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        const Text('📈 资源消耗', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        if (summary.totalTokens != null)
          Text('🔢 ${NumberFormat.decimalPattern().format(summary.totalTokens)} tokens', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
        if (summary.totalCost != null) Text('💰 \$${summary.totalCost!.toStringAsFixed(4)}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
        if (summary.totalElapsedSec != null)
          Text('⏳ ${_elapsed(summary.totalElapsedSec!)}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
      ],
    );
  }
}

class _RetrySummaryView extends StatelessWidget {
  const _RetrySummaryView({required this.summary});

  final RetrySummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = summary.records.length > 8 ? summary.records.sublist(summary.records.length - 8) : summary.records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('🔁 失败重试记录（${summary.count}）', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...rows.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(_fmtActivityTime(r.at), style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
                Text(_agentLabels[r.agent ?? ''] ?? (r.agent ?? 'unknown'), style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
                Text('attempts: ${r.attempts ?? 1}', style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
                Text('type: ${r.errorType ?? 'unknown'}', style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
                if (r.exhausted == true) const Text('exhausted', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ArtifactsView extends ConsumerWidget {
  const _ArtifactsView({required this.artifacts});

  final List<ArtifactInfo> artifacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final rows = artifacts.length > 10 ? artifacts.sublist(artifacts.length - 10) : artifacts;

    Future<void> openPath(String path, bool downloadable) async {
      final raw = path.trim();
      if (raw.isEmpty) return;
      final url = RegExp(r'^https?://').hasMatch(raw) ? raw : (downloadable ? api.artifactDownloadUrl(raw) : '');
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📦 产出文件', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...rows.map((a) {
          final web = RegExp(r'^https?://').hasMatch(a.path);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('[${a.kind ?? 'file'}]', style: const TextStyle(fontSize: 10, color: EdictTheme.muted, fontFamily: 'monospace')),
                if (web || (a.downloadable ?? false))
                  InkWell(
                    onTap: () => openPath(a.path, a.downloadable ?? false),
                    child: Text(a.path, style: const TextStyle(fontSize: 11, color: Color(0xFF60A5FA), decoration: TextDecoration.underline)),
                  )
                else
                  Text(a.path, style: const TextStyle(fontSize: 11, color: EdictTheme.muted)),
                if (!web && (a.downloadable ?? false))
                  InkWell(
                    onTap: () => openPath(a.path, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EdictTheme.panel,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: EdictTheme.line),
                      ),
                      child: const Text('下载', style: TextStyle(fontSize: 10, color: EdictTheme.muted)),
                    ),
                  ),
                if (!web && !(a.downloadable ?? false)) const Text('文件不存在', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
                InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: a.path)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: EdictTheme.panel,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: EdictTheme.line),
                    ),
                    child: const Text('复制', style: TextStyle(fontSize: 10, color: EdictTheme.muted)),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.icon, required this.body, required this.time});

  final String icon;
  final Widget body;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(child: body),
          const SizedBox(width: 6),
          Text(time, style: const TextStyle(fontSize: 10, color: EdictTheme.muted)),
        ],
      ),
    );
  }
}

class _ActivityEntryView extends StatelessWidget {
  const _ActivityEntryView({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final time = _fmtActivityTime(entry.at);
    final badge = (entry.agent ?? '').isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: EdictTheme.panel2, borderRadius: BorderRadius.circular(3)),
            child: Text(_agentLabels[entry.agent!] ?? entry.agent!, style: const TextStyle(fontSize: 9, color: EdictTheme.muted)),
          );

    if (entry.kind == 'progress') {
      return _ActivityRow(
        icon: '🔄',
        time: time,
        body: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 11, color: EdictTheme.text),
            children: [
              WidgetSpan(child: badge ?? const SizedBox.shrink()),
              const TextSpan(text: '当前进展：', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: entry.text ?? ''),
            ],
          ),
        ),
      );
    }

    if (entry.kind == 'todos') {
      final items = entry.items ?? const <TodoItem>[];
      final diffMap = <String, ({String type, String? from, String? to})>{};
      final diff = entry.diff;
      for (final c in diff?.changed ?? const <DiffChanged>[]) {
        diffMap[c.id] = (type: 'changed', from: c.from, to: c.to);
      }
      for (final a in diff?.added ?? const <DiffItem>[]) {
        diffMap[a.id] = (type: 'added', from: null, to: null);
      }
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [if (badge != null) badge, const Text('📝 执行计划', style: TextStyle(fontSize: 11, color: EdictTheme.muted)), const Spacer(), Text(time, style: const TextStyle(fontSize: 10, color: EdictTheme.muted))]),
            const SizedBox(height: 2),
            ...items.map((td) {
              final d = diffMap[td.id];
              final icon = td.status == TodoStatus.completed ? '✅' : td.status == TodoStatus.inProgress ? '🔄' : '⬜';
              final style = TextStyle(
                fontSize: 11,
                color: td.status == TodoStatus.inProgress ? const Color(0xFF60A5FA) : EdictTheme.text,
                fontWeight: td.status == TodoStatus.inProgress ? FontWeight.bold : FontWeight.normal,
                decoration: td.status == TodoStatus.completed ? TextDecoration.lineThrough : null,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children: [
                      TextSpan(text: '$icon ${td.title}'),
                      if (d != null && d.type == 'changed' && d.to == 'completed') const TextSpan(text: ' ✨刚完成', style: TextStyle(fontSize: 9, color: Color(0xFF22C55E))),
                      if (d != null && d.type == 'changed' && d.to != 'completed') TextSpan(text: ' ↻${d.from}→${d.to}', style: const TextStyle(fontSize: 9, color: Color(0xFFF59E0B))),
                      if (d != null && d.type == 'added') const TextSpan(text: ' 🆕新增', style: TextStyle(fontSize: 9, color: Color(0xFF3B82F6))),
                    ],
                  ),
                ),
              );
            }),
            ...diff?.removed?.map((r) => Text('🗑 ${r.title}', style: const TextStyle(fontSize: 11, color: EdictTheme.muted, decoration: TextDecoration.lineThrough))) ?? const <Widget>[],
          ],
        ),
      );
    }

    if (entry.kind == 'assistant') {
      final rows = <Widget>[];
      if ((entry.thinking ?? '').isNotEmpty) {
        rows.add(_ActivityRow(icon: '💭', time: time, body: Row(children: [if (badge != null) badge, Expanded(child: Text(entry.thinking!, style: const TextStyle(fontSize: 11)))])));
      }
      for (final tool in entry.tools ?? const <ToolCall>[]) {
        rows.add(
          _ActivityRow(
            icon: '🔧',
            time: time,
            body: Row(
              children: [
                if (badge != null) badge,
                Text(tool.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Expanded(child: Text(tool.inputPreview ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: EdictTheme.muted))),
              ],
            ),
          ),
        );
      }
      if ((entry.text ?? '').isNotEmpty) {
        rows.add(_ActivityRow(icon: '🤖', time: time, body: Row(children: [if (badge != null) badge, Expanded(child: Text(entry.text!, style: const TextStyle(fontSize: 11)))])));
      }
      return Column(children: rows);
    }

    if (entry.kind == 'tool_result') {
      final ok = entry.exitCode == null || entry.exitCode == 0;
      return _ActivityRow(
        icon: ok ? '✅' : '❌',
        time: time,
        body: Row(
          children: [
            if (badge != null) badge,
            Text(entry.tool ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Expanded(child: Text((entry.output ?? '').substring(0, math.min(150, (entry.output ?? '').length)), style: const TextStyle(fontSize: 10, color: EdictTheme.muted))),
          ],
        ),
      );
    }

    if (entry.kind == 'user') {
      return _ActivityRow(
        icon: '📥',
        time: time,
        body: Row(children: [if (badge != null) badge, Expanded(child: Text(entry.text ?? '', style: const TextStyle(fontSize: 11)))]),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
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
      builder: (_, __) {
        final scale = 0.85 + _controller.value * 0.25;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}

String _fmtStalled(int sec) {
  final v = math.max(0, sec);
  if (v < 60) return '${v}秒';
  if (v < 3600) return '${v ~/ 60}分${v % 60}秒';
  final h = v ~/ 3600;
  final m = (v % 3600) ~/ 60;
  return '${h}小时${m}分';
}

String _elapsed(int sec) {
  if (sec >= 60) return '${sec ~/ 60}分${sec % 60}秒';
  return '${sec}秒';
}

String _fmtTs(String? ts) {
  if ((ts ?? '').isEmpty) return '';
  return ts!.replaceFirst('T', ' ').substring(0, math.min(19, ts.length));
}

String _hhmm(String ts) {
  if (ts.length >= 16) {
    return ts.substring(11, 16);
  }
  return '';
}

String _fmtActivityTime(dynamic ts) {
  if (ts == null) return '';
  if (ts is num) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    return DateFormat('HH:mm:ss').format(d);
  }
  final s = ts.toString();
  if (s.length >= 19) return s.substring(11, 19);
  return s.substring(0, math.min(8, s.length));
}

bool _isActivityActive(dynamic at) {
  if (at == null) return false;
  int? ms;
  if (at is num) {
    ms = at.toInt();
  } else {
    ms = DateTime.tryParse(at.toString())?.millisecondsSinceEpoch;
  }
  if (ms == null) return false;
  return DateTime.now().millisecondsSinceEpoch - ms < 5 * 60 * 1000;
}
