import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../common/common.dart';

class SessionsPanel extends ConsumerStatefulWidget {
  const SessionsPanel({super.key});

  @override
  ConsumerState<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends ConsumerState<SessionsPanel> {
  String? _agentFilter;

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(filteredSessionsProvider);
    final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
    final sessFilter = ref.watch(sessFilterProvider);
    final cfg = ref.watch(agentConfigProvider).valueOrNull;

    final labelMap = <String, String>{
      for (final a in (cfg?.agents ?? const <AgentInfo>[]))
        a.id.toLowerCase(): (a.label.isEmpty ? a.id : a.label),
    };
    final emojiMap = <String, String>{
      for (final a in (cfg?.agents ?? const <AgentInfo>[]))
        a.id.toLowerCase(): (a.emoji.isEmpty ? '🏛️' : a.emoji),
    };

    final allSessions = (liveStatus?.tasks ?? const <Task>[])
        .where((t) => !isEdict(t))
        .toList(growable: false);
    final agentIds = allSessions
        .map(extractAgent)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final shown = _agentFilter == null
        ? sessions
        : sessions.where((t) => extractAgent(t) == _agentFilter).toList(growable: false);

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              _FilterPill(
                label: '全部 (${allSessions.length})',
                active: sessFilter == TaskListFilter.all && _agentFilter == null,
                onTap: () {
                  ref.read(sessFilterProvider.notifier).state = TaskListFilter.all;
                  setState(() => _agentFilter = null);
                },
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: '活跃',
                active: sessFilter == TaskListFilter.active && _agentFilter == null,
                onTap: () {
                  ref.read(sessFilterProvider.notifier).state = TaskListFilter.active;
                  setState(() => _agentFilter = null);
                },
              ),
              for (final id in agentIds.take(8)) ...[
                const SizedBox(width: 8),
                _FilterPill(
                  label: labelMap[id] ?? id,
                  active: _agentFilter == id,
                  onTap: () {
                    ref.read(sessFilterProvider.notifier).state = TaskListFilter.all;
                    setState(() => _agentFilter = id);
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: Text(
                    '暂无小任务/会话数据',
                    style: EdictTheme.mutedStyle,
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.38,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final t = shown[index];
                    return _SessionCard(
                      task: t,
                      labelMap: labelMap,
                      emojiMap: emojiMap,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.task,
    required this.labelMap,
    required this.emojiMap,
  });

  final Task task;
  final Map<String, String> labelMap;
  final Map<String, String> emojiMap;

  @override
  Widget build(BuildContext context) {
    final agent = extractAgent(task);
    final emoji = emojiMap[agent] ?? '🏛️';
    final agentLabel = labelMap[agent] ?? (task.org.isNotEmpty ? task.org : agent);
    final title = humanTitle(task, labelMap);
    final message = _lastMessage(task);
    final ch = channelLabel(task);
    final total = _token(task.sourceMeta, 'totalTokens', 'total_tokens');
    final at = task.eta.isNotEmpty ? task.eta : task.updatedAt;

    return EdictCard(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _SessionDetailDialog(
          task: task,
          labelMap: labelMap,
          emojiMap: emojiMap,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agentLabel, style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    _TinyBadge(text: ch),
                  ],
                ),
              ),
              _HeartbeatDot(status: task.heartbeat.status),
              const SizedBox(width: 6),
              StateTag(state: task.state),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: EdictTheme.titleStyle,
          ),
          const SizedBox(height: 8),
          if (message.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: EdictTheme.line, width: 2)),
              ),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EdictTheme.mutedStyle,
              ),
            ),
          const Spacer(),
          Row(
            children: [
              if (total != null)
                Text('🪙 ${total.toString()} tokens', style: EdictTheme.captionStyle)
              else
                const SizedBox.shrink(),
              const Spacer(),
              if ((at ?? '').isNotEmpty) Text(timeAgo(at), style: EdictTheme.captionStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionDetailDialog extends StatelessWidget {
  const _SessionDetailDialog({
    required this.task,
    required this.labelMap,
    required this.emojiMap,
  });

  final Task task;
  final Map<String, String> labelMap;
  final Map<String, String> emojiMap;

  @override
  Widget build(BuildContext context) {
    final agent = extractAgent(task);
    final emoji = emojiMap[agent] ?? '🏛️';
    final title = humanTitle(task, labelMap);
    final channel = channelLabel(task);
    final acts = task.activity ?? const <ActivityEntry>[];
    final logs = acts.length > 15 ? acts.sublist(acts.length - 15) : acts;

    final total = _token(task.sourceMeta, 'totalTokens', 'total_tokens');
    final input = _token(task.sourceMeta, 'inputTokens', 'input_tokens');
    final output = _token(task.sourceMeta, 'outputTokens', 'output_tokens');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
        decoration: EdictTheme.modalDecoration,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.id, style: EdictTheme.captionStyle.copyWith(color: EdictTheme.acc)),
                        const SizedBox(height: 4),
                        Text('$emoji $title', style: EdictTheme.headerStyle),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StateTag(state: task.state),
                            _TinyBadge(text: channel),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _HeartbeatDot(status: task.heartbeat.status),
                                const SizedBox(width: 6),
                                Text(
                                  task.heartbeat.label.isEmpty ? '未知' : task.heartbeat.label,
                                  style: EdictTheme.captionStyle,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: EdictTheme.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _StatBox(label: '总 Tokens', value: total?.toString() ?? '--', emphasize: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatBox(label: '输入', value: input?.toString() ?? '--')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatBox(label: '输出', value: output?.toString() ?? '--')),
                ],
              ),
              const SizedBox(height: 14),
              Text('📋 最近活动 (${acts.length} 条)', style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: EdictTheme.panelDecoration,
                  child: logs.isEmpty
                      ? const Center(child: Text('暂无活动记录', style: EdictTheme.mutedStyle))
                      : ListView.separated(
                          itemCount: logs.length,
                          reverse: true,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: EdictTheme.line),
                          itemBuilder: (context, index) {
                            final a = logs[index];
                            return Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(_kindIcon(a.kind)),
                                      const SizedBox(width: 6),
                                      Text(_kindLabel(a.kind), style: EdictTheme.captionStyle.copyWith(color: EdictTheme.text)),
                                      const Spacer(),
                                      Text(_shortTime(a.at), style: EdictTheme.captionStyle),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _truncate(_activityText(a), 200),
                                    style: EdictTheme.mutedStyle,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              if (task.output.isNotEmpty && task.output != '-') ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: EdictTheme.panelDecoration,
                  child: Text('📂 ${task.output}', style: EdictTheme.monoStyle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0A1228) : EdictTheme.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? EdictTheme.acc.withOpacity(0.8) : EdictTheme.line,
          ),
        ),
        child: Text(
          label,
          style: EdictTheme.captionStyle.copyWith(
            color: active ? EdictTheme.text : EdictTheme.muted,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: EdictTheme.panel2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EdictTheme.line),
      ),
      child: Text(text, style: EdictTheme.captionStyle),
    );
  }
}

class _HeartbeatDot extends StatelessWidget {
  const _HeartbeatDot({required this.status});

  final HeartbeatStatus status;

  @override
  Widget build(BuildContext context) {
    final color = EdictTheme.heartbeatColorMap[heartbeatStatusToJson(status)] ?? EdictTheme.muted;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: EdictTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: EdictTheme.titleStyle.copyWith(
              color: emphasize ? EdictTheme.acc : EdictTheme.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: EdictTheme.captionStyle),
        ],
      ),
    );
  }
}

String _lastMessage(Task t) {
  final acts = t.activity ?? const <ActivityEntry>[];
  for (var i = acts.length - 1; i >= 0; i--) {
    final a = acts[i];
    if (a.kind != 'assistant') continue;
    var txt = (a.text ?? '').trim();
    if (txt.isEmpty || txt.startsWith('NO_REPLY') || txt.startsWith('Reasoning:')) {
      continue;
    }
    txt = txt.replaceAll(RegExp(r'\[\[.*?\]\]'), '').replaceAll('**', '').replaceAll(RegExp(r'^#+\s', multiLine: true), '').trim();
    if (txt.length > 120) return '${txt.substring(0, 120)}…';
    return txt;
  }
  return '';
}

int? _token(Map<String, dynamic>? meta, String camel, String snake) {
  if (meta == null) return null;
  final v = meta[camel] ?? meta[snake];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String _kindIcon(String kind) {
  switch (kind) {
    case 'assistant':
      return '🤖';
    case 'tool':
      return '🔧';
    case 'user':
      return '👤';
    default:
      return '📝';
  }
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'assistant':
      return '回复';
    case 'tool':
      return '工具';
    case 'user':
      return '用户';
    default:
      return '事件';
  }
}

String _activityText(ActivityEntry a) {
  final txt = (a.text ?? a.output ?? a.remark ?? '').trim();
  return txt.replaceAll(RegExp(r'\[\[.*?\]\]'), '').replaceAll('**', '').trim();
}

String _shortTime(dynamic at) {
  final raw = (at ?? '').toString();
  if (raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt != null) {
    final t = dt.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }
  if (raw.length >= 19) return raw.substring(11, 19);
  return raw;
}

String _truncate(String value, int max) {
  if (value.length <= max) return value;
  return '${value.substring(0, max)}…';
}
