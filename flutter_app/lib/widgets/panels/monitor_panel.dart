import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../common/state_tag.dart';

class MonitorPanel extends ConsumerStatefulWidget {
  const MonitorPanel({super.key});

  @override
  ConsumerState<MonitorPanel> createState() => _MonitorPanelState();
}

class _MonitorPanelState extends ConsumerState<MonitorPanel> {
  Future<void> _refreshAgentsStatus() async {
    await ref.read(agentsStatusProvider.notifier).refresh();
  }

  Future<void> _wakeAgent(String agentId) async {
    final api = ref.read(apiClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    final result = await api.agentWake(agentId);
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text((result.message ?? '').isNotEmpty ? result.message! : '已发送唤醒指令'),
        backgroundColor: result.ok ? EdictTheme.ok : EdictTheme.danger,
      ),
    );

    unawaited(
      Future<void>.delayed(const Duration(seconds: 30), () {
        if (mounted) {
          ref.read(agentsStatusProvider.notifier).refresh();
        }
      }),
    );
  }

  Future<void> _wakeAll() async {
    final data = ref.read(agentsStatusProvider).valueOrNull;
    if (data == null) return;

    final toWake = data.agents
        .where(
          (agent) =>
              agent.id != 'main' &&
              agent.status != AgentRuntimeStatus.running &&
              agent.status != AgentRuntimeStatus.unconfigured,
        )
        .toList(growable: false);

    final messenger = ScaffoldMessenger.of(context);
    if (toWake.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('所有 Agent 均已在线'),
          backgroundColor: EdictTheme.ok,
        ),
      );
      return;
    }

    final api = ref.read(apiClientProvider);
    for (final agent in toWake) {
      await api.agentWake(agent.id);
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${toWake.length} 个唤醒指令已发出，30 秒后刷新状态'),
        backgroundColor: EdictTheme.ok,
      ),
    );

    unawaited(
      Future<void>.delayed(const Duration(seconds: 30), () {
        if (mounted) {
          ref.read(agentsStatusProvider.notifier).refresh();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentsStatusAsync = ref.watch(agentsStatusProvider);
    final officialsAsync = ref.watch(officialsProvider);
    final liveStatusAsync = ref.watch(liveStatusProvider);

    final agentsData = agentsStatusAsync.valueOrNull;
    final officialsData = officialsAsync.valueOrNull;
    final liveStatus = liveStatusAsync.valueOrNull;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (agentsData != null && agentsData.ok) ...[
            _AgentStatusSection(
              data: agentsData,
              onRefresh: _refreshAgentsStatus,
              onWakeAgent: _wakeAgent,
              onWakeAll: _wakeAll,
            ),
            const SizedBox(height: 14),
          ],
          if (officialsData != null)
            _DutyGrid(
              officials: officialsData.officials,
              tasks: liveStatus?.tasks ?? const <Task>[],
              onOpenTask: (taskId) {
                ref.read(modalTaskIdProvider.notifier).state = taskId;
              },
            )
          else
            _buildEmpty('暂无官员数据'),
        ],
      ),
    );
  }

  Widget _buildEmpty(String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: EdictTheme.cardDecoration,
      child: Text(text, style: EdictTheme.mutedStyle),
    );
  }
}

class _AgentStatusSection extends StatelessWidget {
  const _AgentStatusSection({
    required this.data,
    required this.onRefresh,
    required this.onWakeAgent,
    required this.onWakeAll,
  });

  final AgentsStatusData data;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String agentId) onWakeAgent;
  final Future<void> Function() onWakeAll;

  @override
  Widget build(BuildContext context) {
    final agents = data.agents
        .where((agent) => agent.id != 'main')
        .toList(growable: false);

    final running =
        agents.where((a) => a.status == AgentRuntimeStatus.running).length;
    final idle = agents.where((a) => a.status == AgentRuntimeStatus.idle).length;
    final offline =
        agents.where((a) => a.status == AgentRuntimeStatus.offline).length;
    final unconfigured =
        agents.where((a) => a.status == AgentRuntimeStatus.unconfigured).length;

    final gatewayStyle = _gatewayBadgeStyle(data.gateway);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('🏛 省部调度', style: EdictTheme.titleStyle),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: gatewayStyle.background,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: gatewayStyle.border),
                ),
                child: Text(
                  gatewayStyle.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: EdictTheme.text,
                  ).copyWith(color: gatewayStyle.foreground),
                ),
              ),
              OutlinedButton(
                onPressed: onRefresh,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: EdictTheme.line),
                  foregroundColor: EdictTheme.text,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('刷新'),
              ),
              OutlinedButton(
                onPressed: (offline + idle) > 0 ? onWakeAll : null,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: EdictTheme.warn),
                  foregroundColor: EdictTheme.warn,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('唤醒全部'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: agents.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final agent = agents[index];
              final canWake =
                  agent.status != AgentRuntimeStatus.running &&
                  agent.status != AgentRuntimeStatus.unconfigured &&
                  data.gateway.alive;

              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EdictTheme.panel2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: EdictTheme.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RuntimeDot(status: agent.status),
                    const SizedBox(height: 4),
                    Text(agent.emoji, style: const TextStyle(fontSize: 20)),
                    Text(
                      agent.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EdictTheme.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      agent.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EdictTheme.captionStyle,
                    ),
                    Text(
                      agent.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EdictTheme.captionStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      agent.lastActive?.isNotEmpty == true
                          ? '⏰ ${timeAgo(agent.lastActive)}'
                          : '无活动记录',
                      style: EdictTheme.captionStyle,
                    ),
                    const Spacer(),
                    if (canWake)
                      SizedBox(
                        height: 26,
                        child: OutlinedButton(
                          onPressed: () => onWakeAgent(agent.id),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: EdictTheme.warn,
                            side: const BorderSide(color: EdictTheme.warn),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('唤醒'),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            '运行中 $running · 空闲 $idle · 离线 $offline · 未配置 $unconfigured · 检测于 ${_clockOnly(data.checkedAt)}',
            style: EdictTheme.mutedStyle,
          ),
        ],
      ),
    );
  }
}

class _DutyGrid extends StatelessWidget {
  const _DutyGrid({
    required this.officials,
    required this.tasks,
    required this.onOpenTask,
  });

  final List<OfficialInfo> officials;
  final List<Task> tasks;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final activeTasks = tasks
        .where((task) => isEdict(task) && task.state != 'Done' && task.state != 'Next')
        .toList(growable: false);

    if (officials.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: EdictTheme.cardDecoration,
        child: Text('暂无官员数据', style: EdictTheme.mutedStyle),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: officials.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        final official = officials[index];
        final myTasks = activeTasks
            .where((task) => task.org == official.label)
            .toList(growable: false);

        final hasBlocked = myTasks.any((task) => task.state == 'Blocked');
        final isBusy = myTasks.any((task) => task.state == 'Doing');
        final isActive = official.heartbeat.status == HeartbeatStatus.active;

        Color lineColor = EdictTheme.muted;
        _DutyDotStyle dotStyle = const _DutyDotStyle(
          color: EdictTheme.muted,
          pulse: false,
          label: '候命',
        );

        if (hasBlocked) {
          lineColor = EdictTheme.danger;
          dotStyle = const _DutyDotStyle(
            color: EdictTheme.danger,
            pulse: true,
            label: '阻塞',
          );
        } else if (isBusy) {
          lineColor = EdictTheme.warn;
          dotStyle = const _DutyDotStyle(
            color: EdictTheme.warn,
            pulse: true,
            label: '执行中',
          );
        } else if (isActive) {
          lineColor = EdictTheme.ok;
          dotStyle = const _DutyDotStyle(
            color: EdictTheme.ok,
            pulse: false,
            label: '活跃',
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: EdictTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EdictTheme.line),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: lineColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            official.emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  official.label,
                                  style: const TextStyle(
                                    color: EdictTheme.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${official.role} · ${official.rank}',
                                  style: EdictTheme.captionStyle,
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DutyStatusDot(style: dotStyle),
                              const SizedBox(width: 6),
                              Text(dotStyle.label, style: EdictTheme.captionStyle),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: myTasks.isEmpty
                            ? Center(
                                child: Text(
                                  '🪭 候命中',
                                  style: EdictTheme.mutedStyle,
                                ),
                              )
                            : ListView.separated(
                                itemCount: myTasks.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, idx) {
                                  final task = myTasks[idx];
                                  return InkWell(
                                    onTap: () => onOpenTask(task.id),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: EdictTheme.panel2,
                                        borderRadius: BorderRadius.circular(8),
                                        border:
                                            Border.all(color: EdictTheme.line),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            task.id,
                                            style: const TextStyle(
                                              color: EdictTheme.acc,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            task.title.isEmpty
                                                ? '(无标题)'
                                                : task.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: EdictTheme.text,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (task.now.isNotEmpty && task.now != '-')
                                            Text(
                                              task.now,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: EdictTheme.captionStyle,
                                            ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              StateTag(state: task.state),
                                              if (task.block.isNotEmpty &&
                                                  task.block != '无')
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF200a10),
                                                    borderRadius:
                                                        BorderRadius.circular(999),
                                                    border: Border.all(
                                                      color: EdictTheme.danger
                                                          .withOpacity(0.45),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '🚫${task.block}',
                                                    style: const TextStyle(
                                                      color: EdictTheme.danger,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '🤖 ${official.modelShort.isNotEmpty ? official.modelShort : '待配置'}',
                              style: EdictTheme.captionStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (official.lastActive.isNotEmpty)
                            Text(
                              '⏰ ${timeAgo(official.lastActive)}',
                              style: EdictTheme.captionStyle,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DutyDotStyle {
  const _DutyDotStyle({
    required this.color,
    required this.pulse,
    required this.label,
  });

  final Color color;
  final bool pulse;
  final String label;
}

class _DutyStatusDot extends StatefulWidget {
  const _DutyStatusDot({required this.style});

  final _DutyDotStyle style;

  @override
  State<_DutyStatusDot> createState() => _DutyStatusDotState();
}

class _DutyStatusDotState extends State<_DutyStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.style.pulse) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _DutyStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.style.pulse) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
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
        final scale = widget.style.pulse ? (0.85 + (_controller.value * 0.3)) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.style.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class _RuntimeDot extends StatefulWidget {
  const _RuntimeDot({required this.status});

  final AgentRuntimeStatus status;

  @override
  State<_RuntimeDot> createState() => _RuntimeDotState();
}

class _RuntimeDotState extends State<_RuntimeDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _pulse =>
      widget.status == AgentRuntimeStatus.running ||
      widget.status == AgentRuntimeStatus.offline;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    if (_pulse) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _RuntimeDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pulse) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == AgentRuntimeStatus.unconfigured) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: EdictTheme.muted, width: 1.2),
        ),
      );
    }

    final color = switch (widget.status) {
      AgentRuntimeStatus.running => EdictTheme.ok,
      AgentRuntimeStatus.idle => EdictTheme.muted,
      AgentRuntimeStatus.offline => EdictTheme.danger,
      AgentRuntimeStatus.unconfigured => EdictTheme.muted,
    };

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scale = _pulse ? (0.85 + (_controller.value * 0.3)) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}

_GatewayStyle _gatewayBadgeStyle(GatewayStatus gateway) {
  if (!gateway.alive) {
    return const _GatewayStyle(
      label: '网关离线',
      foreground: EdictTheme.danger,
      border: Color(0x66ff5270),
      background: Color(0xFF200a10),
    );
  }
  if (!gateway.probe) {
    return const _GatewayStyle(
      label: '探测失败',
      foreground: EdictTheme.warn,
      border: Color(0x66f5c842),
      background: Color(0xFF201a08),
    );
  }
  return const _GatewayStyle(
    label: '正常',
    foreground: EdictTheme.ok,
    border: Color(0x662ecc8a),
    background: Color(0xFF0a2018),
  );
}

class _GatewayStyle {
  const _GatewayStyle({
    required this.label,
    required this.foreground,
    required this.border,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color border;
  final Color background;
}

String _clockOnly(String input) {
  if (input.length >= 19) {
    return input.substring(11, 19);
  }
  final parsed = DateTime.tryParse(input);
  if (parsed != null) {
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
  return '--:--:--';
}
