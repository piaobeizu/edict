import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../common/common.dart';

class MemorialPanel extends ConsumerStatefulWidget {
  const MemorialPanel({super.key});

  @override
  ConsumerState<MemorialPanel> createState() => _MemorialPanelState();
}

class _MemorialPanelState extends ConsumerState<MemorialPanel> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveStatusProvider).valueOrNull;
    final tasks = (live?.tasks ?? const <Task>[])
        .where((t) => isEdict(t) && (t.state == 'Done' || t.state == 'Cancelled'))
        .toList(growable: false);

    final list = _filter == 'all'
        ? tasks
        : tasks.where((t) => t.state == _filter).toList(growable: false);

    return Column(
      children: [
        Row(
          children: [
            const Text('筛选：', style: EdictTheme.mutedStyle),
            const SizedBox(width: 8),
            _pill('全部', key: 'all'),
            const SizedBox(width: 8),
            _pill('✅ 已完成', key: 'Done'),
            const SizedBox(width: 8),
            _pill('🚫 已取消', key: 'Cancelled'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    '暂无奏折 — 任务完成后自动生成',
                    style: EdictTheme.mutedStyle,
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final t = list[index];
                    final flow = t.flowLog;
                    final depts = _depts(flow);
                    final firstAt = flow.isEmpty ? '' : _displayAt(flow.first.at ?? flow.first.ts);
                    final lastAt = flow.isEmpty ? '' : _displayAt(flow.last.at ?? flow.last.ts);

                    return EdictCard(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => _MemorialDetailDialog(task: t),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('📜', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${t.state == 'Done' ? '✅' : '🚫'} ${t.title.isEmpty ? t.id : t.title}',
                                  style: EdictTheme.titleStyle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text('${t.id} · ${t.org} · 流转 ${flow.length} 步', style: EdictTheme.mutedStyle),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final d in depts.take(6)) DeptTag(dept: d),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (firstAt.isNotEmpty) Text(firstAt, style: EdictTheme.captionStyle),
                              if (lastAt.isNotEmpty && lastAt != firstAt)
                                Text(lastAt, style: EdictTheme.captionStyle),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _pill(String label, {required String key}) {
    final active = _filter == key;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0A1228) : EdictTheme.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? EdictTheme.acc : EdictTheme.line),
        ),
        child: Text(
          label,
          style: EdictTheme.captionStyle.copyWith(
            color: active ? EdictTheme.text : EdictTheme.muted,
          ),
        ),
      ),
    );
  }
}

class _MemorialDetailDialog extends StatelessWidget {
  const _MemorialDetailDialog({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final flow = task.flowLog;
    final depts = _depts(flow);
    final phases = _phaseMap(flow);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 780),
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
                        Text(
                          '${task.state == 'Done' ? '✅' : task.state == 'Cancelled' ? '🚫' : '🔄'} ${task.title.isEmpty ? task.id : task.title}',
                          style: EdictTheme.headerStyle,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StateTag(state: task.state),
                            _meta('机构：${task.org}'),
                            _meta('流转 ${flow.length} 步'),
                            for (final d in depts) DeptTag(dept: d),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (task.now.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: EdictTheme.panelDecoration,
                  child: Text(task.now, style: EdictTheme.mutedStyle),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _phaseSection('👑 圣旨原文', phases.$1),
                    _phaseSection('📋 中书规划', phases.$2),
                    _phaseSection('🔍 门下审议', phases.$3),
                    _phaseSection('⚔️ 六部执行', phases.$4),
                    _phaseSection('📨 汇总回奏', phases.$5),
                    if (task.output.isNotEmpty && task.output != '-') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: EdictTheme.panelDecoration,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📦 输出产物', style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            SelectableText(task.output, style: EdictTheme.monoStyle),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () async {
                    final md = _buildMemorialMarkdown(task);
                    await copyTextToClipboard(
                      context,
                      md,
                      successMessage: '✅ 奏折已复制为 Markdown',
                    );
                  },
                  child: const Text('📋 复制奏折'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phaseSection(String title, List<FlowEntry> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: EdictTheme.panelDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Text('暂无记录', style: EdictTheme.mutedStyle)
            else
              ...items.map((f) {
                final color = _timelineColor(f);
                final remark = (f.remark ?? f.reason ?? '').trim();
                final at = _displayAt(f.at ?? f.ts);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${f.from} → ${f.to}', style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w600)),
                            if (remark.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(remark, style: EdictTheme.mutedStyle),
                              ),
                            if (at.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(at, style: EdictTheme.captionStyle),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _meta(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EdictTheme.panel2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EdictTheme.line),
      ),
      child: Text(text, style: EdictTheme.captionStyle),
    );
  }
}

List<String> _depts(List<FlowEntry> flow) {
  final set = <String>{};
  for (final f in flow) {
    if (f.from.isNotEmpty && f.from != '皇上') set.add(f.from);
    if (f.to.isNotEmpty && f.to != '皇上') set.add(f.to);
  }
  return set.toList(growable: false);
}

(List<FlowEntry>, List<FlowEntry>, List<FlowEntry>, List<FlowEntry>, List<FlowEntry>) _phaseMap(
  List<FlowEntry> flow,
) {
  final origin = <FlowEntry>[];
  final plan = <FlowEntry>[];
  final review = <FlowEntry>[];
  final exec = <FlowEntry>[];
  final result = <FlowEntry>[];

  for (final f in flow) {
    final remark = (f.remark ?? '').toLowerCase();
    if (f.from == '皇上') {
      origin.add(f);
    } else if (f.to == '中书省' || f.from == '中书省') {
      plan.add(f);
    } else if (f.to == '门下省' || f.from == '门下省') {
      review.add(f);
    } else if (remark.contains('完成') || remark.contains('回奏')) {
      result.add(f);
    } else {
      exec.add(f);
    }
  }

  return (origin, plan, review, exec, result);
}

Color _timelineColor(FlowEntry f) {
  final txt = '${f.remark ?? ''} ${f.reason ?? ''}'.toLowerCase();
  if (txt.contains('✅') || txt.contains('完成')) return EdictTheme.ok;
  if (txt.contains('驳') || txt.contains('拒') || txt.contains('🚫')) return EdictTheme.danger;
  return EdictTheme.acc;
}

String _displayAt(String? at) {
  if (at == null || at.isEmpty) return '';
  final dt = DateTime.tryParse(at);
  if (dt != null) {
    final t = dt.toLocal();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  if (at.length >= 16) return at.substring(0, 16).replaceFirst('T', ' ');
  return at;
}

String _buildMemorialMarkdown(Task t) {
  final flow = t.flowLog;
  final depts = _depts(flow);
  final startAt = flow.isEmpty ? '未知' : _displayAt(flow.first.at ?? flow.first.ts);
  final endAt = flow.isEmpty ? '未知' : _displayAt(flow.last.at ?? flow.last.ts);

  final sb = StringBuffer()
    ..writeln('# 📜 奏折 · ${t.title.isEmpty ? t.id : t.title}')
    ..writeln()
    ..writeln('- **任务编号**: ${t.id}')
    ..writeln('- **状态**: ${t.state}')
    ..writeln('- **负责部门**: ${t.org}')
    ..writeln('- **流转步骤**: ${flow.length}')
    ..writeln('- **涉及部门**: ${depts.join('、')}')
    ..writeln('- **开始时间**: $startAt')
    ..writeln('- **完成时间**: $endAt')
    ..writeln()
    ..writeln('## 描述')
    ..writeln()
    ..writeln(t.now.isEmpty ? '-' : t.now)
    ..writeln()
    ..writeln('## 流转记录')
    ..writeln();

  for (final f in flow) {
    sb
      ..writeln('- **${f.from}** → **${f.to}**')
      ..writeln('  - 备注：${(f.remark ?? f.reason ?? '-').trim()}')
      ..writeln('  - 时间：${_displayAt(f.at ?? f.ts)}');
  }

  if (t.output.isNotEmpty && t.output != '-') {
    sb
      ..writeln()
      ..writeln('## 产出物')
      ..writeln()
      ..writeln('`${t.output}`');
  }

  return sb.toString();
}
