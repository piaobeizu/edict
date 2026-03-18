import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/live_status_provider.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileCreateScreen extends ConsumerStatefulWidget {
  const MobileCreateScreen({super.key, required this.onCreated});

  final ValueChanged<String> onCreated;

  @override
  ConsumerState<MobileCreateScreen> createState() => _MobileCreateScreenState();
}

class _MobileCreateScreenState extends ConsumerState<MobileCreateScreen> {
  final TextEditingController _titleController = TextEditingController();
  bool _submitting = false;
  CreateMode _mode = CreateMode.free;
  String _selectedTemplate = 'API设计评审';
  String _selectedDept = '中书省 · 制诰AI';
  String _selectedPriority = '普通';

  static const _templateNameToId = <String, String>{
    'API设计评审': 'tpl-api-design',
    '数据复盘报告': 'tpl-data-report',
  };

  static const _deptToOrg = <String, String>{
    '中书省 · 制诰AI': '中书省',
    '门下省 · 封驳AI': '门下省',
    '尚书省 · 执行AI': '尚书省',
  };

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: MobileImmersiveBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: MobileImmersiveBackground.pagePadding,
            children: [
              const MobileSectionTitle(
                title: '➕ 新建旨意',
                trailing: Text(
                  '选择模板或自由创建',
                  style: TextStyle(
                    color: Color(0xFF78716C),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
              const SizedBox(height: 10),
              _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '创建方式',
                      style: TextStyle(
                        color: Color(0xFF1C1917),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ModeButton(
                            label: '从模板创建',
                            selected: _mode == CreateMode.template,
                            onTap: () =>
                                setState(() => _mode = CreateMode.template),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModeButton(
                            label: '自由输入',
                            selected: _mode == CreateMode.free,
                            onTap: () =>
                                setState(() => _mode = CreateMode.free),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const MobileSectionTitle(title: '推荐模板', topPadding: 4),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.78,
                children: [
                  _TemplateCard(
                    emoji: '🧩',
                    name: 'API设计评审',
                    desc: '自动拆解需求并生成 API 草案',
                    meta: '约 12 分钟 · 4.2¥',
                    selected: _selectedTemplate == 'API设计评审',
                    onTap: () => setState(() => _selectedTemplate = 'API设计评审'),
                  ),
                  _TemplateCard(
                    emoji: '📈',
                    name: '数据复盘报告',
                    desc: '汇总指标、异常与行动建议',
                    meta: '约 9 分钟 · 3.1¥',
                    selected: _selectedTemplate == '数据复盘报告',
                    onTap: () => setState(() => _selectedTemplate = '数据复盘报告'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '执行配置',
                      style: TextStyle(
                        color: Color(0xFF1C1917),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 8),
                    const Text(
                      '默认调度：中书省（分拣）→ 门下省（审议）→ 尚书省（执行），预计总耗时 15-35 分钟。',
                      style: TextStyle(
                        color: Color(0xFF78716C),
                        fontSize: 12,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 12),
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
      ),
    );
  }

  Future<void> _submitCreate() async {
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (_mode == CreateMode.template
            ? '$_selectedTemplate · 新任务'
            : '自由输入 · 新任务');
    final org = _deptToOrg[_selectedDept] ?? '中书省';
    final priority = switch (_selectedPriority) {
      '加急' => 'urgent',
      '阻塞' => 'blocked',
      _ => 'normal',
    };

    final payload = CreateTaskPayload(
      title: title.length > 120 ? title.substring(0, 120) : title,
      org: org,
      targetDept: org,
      priority: priority,
      templateId: _mode == CreateMode.template
          ? _templateNameToId[_selectedTemplate]
          : null,
      params: _mode == CreateMode.template
          ? <String, String>{'templateName': _selectedTemplate}
          : <String, String>{'mode': 'free'},
    );

    setState(() => _submitting = true);
    try {
      final result = await ref.read(apiClientProvider).createTask(payload);
      if (!mounted) return;
      if (!result.ok) {
        final message =
            (result.error ?? '').isNotEmpty ? result.error! : '创建失败';
        _showSnack(message);
        return;
      }
      await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      _titleController.clear();
      widget.onCreated(title);
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 44,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE9E7F6),
          ),
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
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(
                color: Color(0xFF1C1917),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF78716C),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              meta,
              style: const TextStyle(
                color: Color(0xFF57534E),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child:
                  SizedBox(width: 88, child: _MiniActionButton(label: '使用模板')),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(10),
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
