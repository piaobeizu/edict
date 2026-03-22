import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workflow_entry.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../common/heartbeat_badge.dart';
import '../common/state_tag.dart';
import '../common/toast_overlay.dart';

class OfficialPanel extends ConsumerWidget {
  const OfficialPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final officialsAsync = ref.watch(officialsProvider);
    final selectedId = ref.watch(selectedOfficialProvider);

    return officialsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: EdictTheme.acc),
        ),
      ),
      error: (_, __) => _EmptyCard(text: '⚠️ 请确保本地服务器已启动'),
      data: (data) {
        final officials = [...data.officials]
          ..sort((a, b) => a.meritRank.compareTo(b.meritRank));

        if (officials.isEmpty) {
          return const _EmptyCard(text: '暂无官员数据');
        }

        final selected = officials.firstWhere(
          (official) => official.id == selectedId,
          orElse: () => officials.first,
        );

        final maxTokenTotal = officials
            .map((official) => official.tokensIn + official.tokensOut + official.cacheRead + official.cacheWrite)
            .reduce((a, b) => a > b ? a : b);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KpiRow(data: data),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth <= 700;
                  final rankPanel = _RankListPanel(
                    officials: officials,
                    selectedId: selected.id,
                    onSelect: (id) {
                      ref.read(selectedOfficialProvider.notifier).state = id;
                    },
                  );

                  final detailPanel = _OfficialDetailPanel(
                    official: selected,
                    maxToken: maxTokenTotal <= 0 ? 1 : maxTokenTotal,
                    onOpenTask: (taskId) {
                      final task = ref.read(taskByIdProvider(taskId));
                      if (task == null) {
                        ref.read(toastProvider.notifier).show(
                              '未找到任务，请刷新后重试',
                              type: ToastType.err,
                            );
                        return;
                      }
                      final route = resolveTaskEntryRoute(task);
                      if (route.unresolved) {
                        ref.read(toastProvider.notifier).show(
                              'workflow 数据待同步，请稍后重试',
                              type: ToastType.err,
                            );
                        return;
                      }
                      ref.read(modalWorkflowIdProvider.notifier).state = route.workflowId;
                    },
                  );

                  if (narrow) {
                    return Column(
                      children: [
                        rankPanel,
                        const SizedBox(height: 12),
                        detailPanel,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 260, child: rankPanel),
                      const SizedBox(width: 12),
                      Expanded(child: detailPanel),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.data});

  final OfficialsData data;

  @override
  Widget build(BuildContext context) {
    final officials = data.officials;
    final totalCost = data.totals.costCny;
    final costWarn = totalCost > 20;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _KpiCard(
          title: '在职官员',
          value: '${officials.length}',
          icon: '👥',
          valueColor: EdictTheme.acc,
        ),
        _KpiCard(
          title: '累计完成旨意',
          value: '${data.totals.tasksDone}',
          icon: '🏅',
          valueColor: EdictTheme.warn,
        ),
        _KpiCard(
          title: '累计费用',
          value: '¥${totalCost.toStringAsFixed(2)}',
          icon: '💴',
          valueColor: costWarn ? EdictTheme.warn : EdictTheme.ok,
        ),
        _KpiCard(
          title: '功绩最高',
          value: data.topOfficial.isNotEmpty ? data.topOfficial : '—',
          icon: '👑',
          valueColor: EdictTheme.text,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.valueColor,
  });

  final String title;
  final String value;
  final String icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.cardDecoration,
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: EdictTheme.text,
                  ).copyWith(color: valueColor),
                ),
                Text(title, style: EdictTheme.captionStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankListPanel extends StatelessWidget {
  const _RankListPanel({
    required this.officials,
    required this.selectedId,
    required this.onSelect,
  });

  final List<OfficialInfo> officials;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: EdictTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('功绩排行', style: EdictTheme.titleStyle),
          ),
          ...officials.map((official) {
            final selected = official.id == selectedId;
            final rank = official.meritRank;
            final rankText = switch (rank) {
              1 => '🥇',
              2 => '🥈',
              3 => '🥉',
              _ => '#$rank',
            };

            return InkWell(
              onTap: () => onSelect(official.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF0D1322) : EdictTheme.panel2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? EdictTheme.acc : EdictTheme.line,
                    width: selected ? 1.3 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        rankText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: EdictTheme.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(official.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            official.role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: EdictTheme.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            official.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: EdictTheme.captionStyle,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${official.meritScore.toStringAsFixed(1)}分',
                      style: const TextStyle(
                        color: EdictTheme.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _HeartbeatDot(status: official.heartbeat.status),
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

class _OfficialDetailPanel extends StatelessWidget {
  const _OfficialDetailPanel({
    required this.official,
    required this.maxToken,
    required this.onOpenTask,
  });

  final OfficialInfo official;
  final int maxToken;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final tokenTotal = official.tokensIn +
        official.tokensOut +
        official.cacheRead +
        official.cacheWrite;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(official.emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(official.role, style: EdictTheme.headerStyle),
                    const SizedBox(height: 2),
                    Text(
                      '${official.label} · ${official.modelShort.isNotEmpty ? official.modelShort : official.model}',
                      style: EdictTheme.mutedStyle.copyWith(color: EdictTheme.acc),
                    ),
                    Text(
                      '🏅 ${official.rank} · 功绩分 ${official.meritScore.toStringAsFixed(1)}',
                      style: EdictTheme.captionStyle,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  HeartbeatBadge(heartbeat: official.heartbeat),
                  if (official.lastActive.isNotEmpty)
                    Text('活跃 ${timeAgo(official.lastActive)}',
                        style: EdictTheme.captionStyle),
                  Text(
                    '${official.sessions} 个会话 · ${official.messages} 条消息',
                    style: EdictTheme.captionStyle,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('功绩统计', style: EdictTheme.titleStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _BigStatCard(
                  value: '${official.tasksDone}',
                  label: '完成旨意',
                  color: EdictTheme.ok,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStatCard(
                  value: '${official.tasksActive}',
                  label: '执行中',
                  color: EdictTheme.warn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStatCard(
                  value: '${official.flowParticipations}',
                  label: '流转参与',
                  color: EdictTheme.acc,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Token 消耗', style: EdictTheme.titleStyle),
          const SizedBox(height: 8),
          _TokenBar(
            label: 'tokensIn',
            value: official.tokensIn,
            maxValue: maxToken,
            color: EdictTheme.acc,
          ),
          _TokenBar(
            label: 'tokensOut',
            value: official.tokensOut,
            maxValue: maxToken,
            color: EdictTheme.acc2,
          ),
          _TokenBar(
            label: 'cacheRead',
            value: official.cacheRead,
            maxValue: maxToken,
            color: EdictTheme.ok,
          ),
          _TokenBar(
            label: 'cacheWrite',
            value: official.cacheWrite,
            maxValue: maxToken,
            color: EdictTheme.warn,
          ),
          const SizedBox(height: 14),
          const Text('累计费用', style: EdictTheme.titleStyle),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                '¥${official.costCny.toStringAsFixed(2)} 人民币',
                style: EdictTheme.bodyStyle.copyWith(
                  color: official.costCny > 10
                      ? EdictTheme.danger
                      : official.costCny > 3
                          ? EdictTheme.warn
                          : EdictTheme.ok,
                ),
              ),
              Text(
                '\$${official.costUsd.toStringAsFixed(4)} 美元',
                style: EdictTheme.bodyStyle,
              ),
              Text(
                '总计 ${_fmtInt(tokenTotal)} tokens',
                style: EdictTheme.mutedStyle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '参与旨意（${official.participatedEdicts.length} 道）',
            style: EdictTheme.titleStyle,
          ),
          const SizedBox(height: 8),
          if (official.participatedEdicts.isEmpty)
            Text('暂无旨意记录', style: EdictTheme.mutedStyle)
          else
            ...official.participatedEdicts.map((edict) {
              return InkWell(
                onTap: () => onOpenTask(edict.id),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: EdictTheme.panel2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EdictTheme.line),
                  ),
                  child: Row(
                    children: [
                      Text(
                        edict.id,
                        style: const TextStyle(
                          color: EdictTheme.acc,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          edict.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EdictTheme.bodyStyle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StateTag(state: edict.state),
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

class _BigStatCard extends StatelessWidget {
  const _BigStatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: EdictTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ).copyWith(color: color),
          ),
          Text(label, style: EdictTheme.captionStyle),
        ],
      ),
    );
  }
}

class _TokenBar extends StatelessWidget {
  const _TokenBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final widthFactor = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: EdictTheme.captionStyle)),
              Text(_fmtInt(value), style: EdictTheme.monoStyle),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 7,
              color: EdictTheme.panel2,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                alignment: Alignment.centerLeft,
                child: Container(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartbeatDot extends StatelessWidget {
  const _HeartbeatDot({required this.status});

  final HeartbeatStatus status;

  @override
  Widget build(BuildContext context) {
    final color = EdictTheme.heartbeatColorMap[heartbeatStatusToJson(status)] ??
        EdictTheme.muted;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: EdictTheme.cardDecoration,
      child: Text(text, style: EdictTheme.mutedStyle),
    );
  }
}

String _fmtInt(int value) {
  final raw = value.toString();
  final chars = raw.split('');
  final buffer = StringBuffer();
  for (int i = 0; i < chars.length; i++) {
    final fromEnd = chars.length - i;
    buffer.write(chars[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
