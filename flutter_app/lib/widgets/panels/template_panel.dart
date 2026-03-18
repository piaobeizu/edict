import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../models/template.dart' as m;
import '../../providers/providers.dart';
import '../common/common.dart';

class TemplatePanel extends ConsumerWidget {
  const TemplatePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(tplCatFilterProvider);
    final templates = cat == null
        ? kTemplates
        : kTemplates.where((t) => t.cat == cat).toList(growable: false);

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              _CatPill(
                label: '📋全部',
                active: cat == null,
                onTap: () => ref.read(tplCatFilterProvider.notifier).state = null,
              ),
              const SizedBox(width: 8),
              _CatPill(
                label: '💼日常办公',
                active: cat == '日常办公',
                onTap: () => ref.read(tplCatFilterProvider.notifier).state = '日常办公',
              ),
              const SizedBox(width: 8),
              _CatPill(
                label: '📊数据分析',
                active: cat == '数据分析',
                onTap: () => ref.read(tplCatFilterProvider.notifier).state = '数据分析',
              ),
              const SizedBox(width: 8),
              _CatPill(
                label: '⚙️工程开发',
                active: cat == '工程开发',
                onTap: () => ref.read(tplCatFilterProvider.notifier).state = '工程开发',
              ),
              const SizedBox(width: 8),
              _CatPill(
                label: '✍️内容创作',
                active: cat == '内容创作',
                onTap: () => ref.read(tplCatFilterProvider.notifier).state = '内容创作',
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.28,
            ),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              return EdictCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(t.icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.name,
                            style: EdictTheme.titleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EdictTheme.mutedStyle,
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final d in t.depts) DeptTag(dept: d)],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('${t.est} · ${t.cost}', style: EdictTheme.captionStyle),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            await showDialog<void>(
                              context: context,
                              builder: (_) => _TemplateFormDialog(template: t),
                            );
                          },
                          child: const Text('下旨'),
                        ),
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
}

class _TemplateFormDialog extends ConsumerStatefulWidget {
  const _TemplateFormDialog({required this.template});

  final TemplateInfo template;

  @override
  ConsumerState<_TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends ConsumerState<_TemplateFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, String> _values;
  final TextEditingController _extraCtrl = TextEditingController();
  String _preview = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final p in widget.template.params)
        p.key: (p.defaultValue ?? (p.options.isNotEmpty ? p.options.first : '')),
    };
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tpl = widget.template;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 780),
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
                        Text('圣旨模板', style: EdictTheme.captionStyle.copyWith(color: EdictTheme.acc)),
                        const SizedBox(height: 4),
                        Text('${tpl.icon} ${tpl.name}', style: EdictTheme.headerStyle),
                        const SizedBox(height: 6),
                        Text(tpl.desc, style: EdictTheme.mutedStyle),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final d in tpl.depts) DeptTag(dept: d),
                            _meta('${tpl.est} · ${tpl.cost}'),
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
              const SizedBox(height: 12),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      for (final p in tpl.params) ...[
                        Text(p.label, style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        _fieldFor(p),
                        const SizedBox(height: 12),
                      ],
                      Text('补充材料（可选）', style: EdictTheme.bodyStyle.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _extraCtrl,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: '可填写背景、限制条件、补充上下文。下旨后会自动代发给太子。',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_preview.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0E16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: EdictTheme.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('📜 将发送给中书省的旨意：', style: EdictTheme.captionStyle.copyWith(color: EdictTheme.text)),
                              const SizedBox(height: 8),
                              SelectableText(
                                _preview,
                                style: EdictTheme.monoStyle.copyWith(height: 1.5),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _preview = _buildCommand();
                      });
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('预览旨意'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('📜 下旨'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldFor(TemplateParam p) {
    final requiredMark = p.required ? ' *' : '';
    if (p.type == 'select') {
      final options = (p.options ?? <String>[]).isEmpty ? <String>[''] : p.options!;
      return DropdownButtonFormField<String>(
        value: (_values[p.key] ?? '').isEmpty ? options.first : _values[p.key],
        items: options
            .map((o) => DropdownMenuItem<String>(value: o, child: Text(o, style: EdictTheme.bodyStyle)))
            .toList(),
        onChanged: (v) => setState(() => _values[p.key] = v ?? ''),
        decoration: InputDecoration(hintText: '请选择$requiredMark'),
        validator: (v) {
          if (p.required && (v == null || v.trim().isEmpty)) return '该字段必填';
          return null;
        },
      );
    }

    return TextFormField(
      initialValue: _values[p.key],
      maxLines: p.type == 'textarea' ? 4 : 1,
      onChanged: (v) => _values[p.key] = v,
      decoration: InputDecoration(hintText: '${p.label}$requiredMark'),
      validator: (v) {
        if (p.required && (v == null || v.trim().isEmpty)) return '该字段必填';
        return null;
      },
    );
  }

  String _buildCommand() {
    var cmd = widget.template.command;
    for (final p in widget.template.params) {
      final replacement = (_values[p.key] ?? '').trim().isEmpty
          ? (p.defaultValue ?? '')
          : (_values[p.key] ?? '');
      cmd = cmd.replaceAll('{${p.key}}', replacement);
    }
    return cmd;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final cmd = _buildCommand().trim();
    if (cmd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写必填参数')),
      );
      return;
    }

    final api = ref.read(apiClientProvider);

    setState(() => _submitting = true);
    try {
      var allow = true;
      try {
        final st = await api.agentsStatus();
        if (st.ok && !st.gateway.alive) {
          allow = await _confirm(
            context,
            title: 'Gateway 未启动',
            content: '任务可能无法派发，是否继续下旨？',
          );
        }
      } catch (_) {
        // ignore gateway pre-check errors
      }

      if (!allow) return;

      final confirmed = await _confirm(
        context,
        title: '确认下旨？',
        content: cmd.length > 220 ? '${cmd.substring(0, 220)}…' : cmd,
      );
      if (!confirmed) return;

      final params = <String, String>{
        for (final p in widget.template.params)
          p.key: (_values[p.key] ?? '').trim().isEmpty
              ? (p.defaultValue ?? '')
              : (_values[p.key] ?? ''),
      };

      final createResp = await api.createTask(
        m.CreateTaskPayload(
          title: cmd.length > 120 ? cmd.substring(0, 120) : cmd,
          org: '中书省',
          targetDept: widget.template.depts.isEmpty ? null : widget.template.depts.first,
          priority: 'normal',
          templateId: widget.template.id,
          params: params,
        ),
      );

      if (!createResp.ok) {
        final err = (createResp.error ?? '').isNotEmpty
            ? createResp.error!
            : '下旨失败';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
        }
        return;
      }

      final taskId = createResp.taskId ?? '';
      if (taskId.isNotEmpty && _extraCtrl.text.trim().isNotEmpty) {
        await api.dispatchTask(
          taskId,
          'taizi',
          _extraCtrl.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📜 ${taskId.isEmpty ? '新任务' : taskId} 旨意已下达')),
        );
      }
      await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _CatPill extends StatelessWidget {
  const _CatPill({required this.label, required this.active, required this.onTap});

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

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      );
    },
  );
  return ok == true;
}
