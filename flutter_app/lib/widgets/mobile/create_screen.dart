import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/live_status_provider.dart';
import 'mobile_tokens.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileCreateScreen extends ConsumerStatefulWidget {
  const MobileCreateScreen({super.key, required this.onCreated});

  final void Function(String title, String? taskId, String? workflowId) onCreated;

  @override
  ConsumerState<MobileCreateScreen> createState() => _MobileCreateScreenState();
}

class _MobileCreateScreenState extends ConsumerState<MobileCreateScreen> {
  final TextEditingController _titleController = TextEditingController();
  bool _submitting = false;
  CreateMode _mode = CreateMode.template;
  String _selectedTemplateId = 'tpl-api-design';
  String _selectedDept = '中书省 · 制诰AI';
  String _selectedPriority = '普通';

  static const _recommendedTemplateIds = <String>[
    'tpl-api-design',
    'tpl-data-report',
  ];

  static const _deptToOrg = <String, String>{
    '中书省 · 制诰AI': '中书省',
    '门下省 · 封驳AI': '门下省',
    '尚书省 · 执行AI': '尚书省',
  };

  TemplateInfo? _templateById(String templateId) {
    for (final item in kTemplates) {
      if (item.id == templateId) return item;
    }
    return null;
  }

  List<TemplateInfo> get _recommendedTemplates {
    final list = <TemplateInfo>[];
    for (final id in _recommendedTemplateIds) {
      final item = _templateById(id);
      if (item != null) list.add(item);
    }
    return list;
  }

  Map<String, String> _defaultTemplateParams(TemplateInfo template) {
    final out = <String, String>{};
    for (final param in template.params) {
      final value = (param.defaultValue ?? '').trim();
      if (value.isNotEmpty) {
        out[param.key] = value;
      }
    }
    return out;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modeTabs = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEEFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: '从模板创建',
              selected: _mode == CreateMode.template,
              onTap: () => setState(() => _mode = CreateMode.template),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ModeButton(
              label: '自由输入',
              selected: _mode == CreateMode.free,
              onTap: () => setState(() => _mode = CreateMode.free),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: MobileImmersiveBackground(
        child: ListView(
            padding: MobileUiTokens.pagePadding,
            children: [
              const MobileSectionTitle(
                title: '➕ 新建旨意',
                trailing: Text(
                  '选择模板或自由创建',
                  style: MobileUiTokens.trailingText,
                ),
              ),
              _InputCard(
                child: Row(
                  children: [
                    const Text('✍️', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          hintText: '输入任务标题，如：Q2 增长复盘方案',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MobileUiTokens.gap10),
              _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '创建方式',
                      style: MobileUiTokens.sectionLabel,
                    ),
                    const SizedBox(height: MobileUiTokens.gap10),
                    modeTabs,
                  ],
                ),
              ),
              const SizedBox(height: MobileUiTokens.gap16),
              const MobileSectionTitle(title: '推荐模板', topPadding: 4),
              const SizedBox(height: MobileUiTokens.gap10),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.78,
                children: [
                  for (final template in _recommendedTemplates)
                    _TemplateCard(
                      emoji: template.icon,
                      name: template.name,
                      desc: template.desc,
                      meta: '${template.est} · ${template.cost}',
                      selected: _selectedTemplateId == template.id,
                      onTap: () =>
                          setState(() => _selectedTemplateId = template.id),
                    ),
                ],
              ),
              const SizedBox(height: MobileUiTokens.gap10),
              _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '执行配置',
                      style: MobileUiTokens.sectionLabel,
                    ),
                    const SizedBox(height: MobileUiTokens.gap10),
                    _DropdownCard(
                      icon: '🏛️',
                      value: _selectedDept,
                      items: const ['中书省 · 制诰AI', '门下省 · 封驳AI', '尚书省 · 执行AI'],
                      onChanged: (v) => setState(() => _selectedDept = v),
                    ),
                    const SizedBox(height: 8),
                    _DropdownCard(
                      icon: '⚡',
                      value: _selectedPriority,
                      items: const ['普通', '加急', '阻塞'],
                      onChanged: (v) => setState(() => _selectedPriority = v),
                    ),
                    const SizedBox(height: MobileUiTokens.gap8),
                    const Text(
                      '默认调度：中书省（分拣）→ 门下省（审议）→ 尚书省（执行），预计总耗时 15-35 分钟。',
                      style: MobileUiTokens.bodyMuted,
                    ),
                    const SizedBox(height: MobileUiTokens.gap12),
                    SizedBox(
                      width: double.infinity,
                      child: MobilePrimaryButton(
                        label: _submitting ? '创建中...' : '确认下旨',
                        onPressed: _submitting ? null : _submitCreate,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ),
    );
  }

  Future<void> _submitCreate() async {
    final selectedTemplate = _templateById(_selectedTemplateId);
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (_mode == CreateMode.template
            ? '${selectedTemplate?.name ?? '模板任务'} · 新任务'
            : '自由输入 · 新任务');
    final org = _mode == CreateMode.template && selectedTemplate != null
        ? (selectedTemplate.depts.isNotEmpty
            ? selectedTemplate.depts.first
            : (_deptToOrg[_selectedDept] ?? '中书省'))
        : (_deptToOrg[_selectedDept] ?? '中书省');
    final priority = switch (_selectedPriority) {
      '加急' => 'urgent',
      '阻塞' => 'blocked',
      _ => 'normal',
    };
    final templateParams = _mode == CreateMode.template && selectedTemplate != null
        ? _defaultTemplateParams(selectedTemplate)
        : <String, String>{};

    final payload = CreateTaskPayload(
      title: title.length > 120 ? title.substring(0, 120) : title,
      org: org,
      targetDept: org,
      priority: priority,
      templateId: _mode == CreateMode.template
          ? selectedTemplate?.id
          : null,
      params: _mode == CreateMode.template
          ? <String, String>{
              'templateName': selectedTemplate?.name ?? '',
              ...templateParams,
            }
          : <String, String>{'mode': 'free'},
    );

    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final workflow = await api.createWorkflow(
        title: payload.title,
        goal: _mode == CreateMode.template && selectedTemplate != null
            ? '${selectedTemplate.desc}\n${selectedTemplate.command}'
            : (payload.params?.entries.map((e) => '${e.key}=${e.value}').join('；') ??
                ''),
        workflowType: 'generic',
        owner: org,
        meta: <String, dynamic>{
          if ((payload.templateId ?? '').isNotEmpty)
            'templateId': payload.templateId,
          'priority': priority,
          if ((payload.targetDept ?? '').isNotEmpty)
            'targetDept': payload.targetDept,
          'source': 'mobile-create-screen',
        },
      );
      if (!mounted) return;
      if (workflow.ok && workflow.workflowId.isNotEmpty) {
        await ref.read(liveStatusProvider.notifier).refresh(silent: true);
        _titleController.clear();
        widget.onCreated(title, workflow.taskId, workflow.workflowId);
        return;
      }

      // Fallback to legacy create-task path to keep compatibility.
      final result = await api.createTask(payload);
      if (!mounted) return;
      if (!result.ok) {
        final message = (workflow.error ?? '').isNotEmpty
            ? workflow.error!
            : ((result.error ?? '').isNotEmpty ? result.error! : '创建失败');
        _showSnack(message);
        return;
      }
      await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      _titleController.clear();
      widget.onCreated(title, result.taskId, null);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

enum CreateMode { template, free }

class _InputCard extends StatelessWidget {
  const _InputCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MobileSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MobileSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x476366F1),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF57534E),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.emoji,
    required this.name,
    required this.desc,
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final String desc;
  final String meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFFCFCFF)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF7C6DF6) : const Color(0xFFF0EEEB),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x144338CA),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDBE4FF)),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: MobileUiTokens.cardTitle,
            ),
            const SizedBox(height: MobileUiTokens.gap8),
            Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: MobileUiTokens.cardDesc,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F4F5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileUiTokens.miniMeta,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const _MiniActionButton(label: '使用模板'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6DDFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F4338CA),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF3730A3),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String icon;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Colors.white,
                items: items
                    .map((item) => DropdownMenuItem<String>(
                          value: item,
                          child:
                              Text(item, style: const TextStyle(fontSize: 14)),
                        ))
                    .toList(growable: false),
                onChanged: (next) {
                  if (next != null) {
                    onChanged(next);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
