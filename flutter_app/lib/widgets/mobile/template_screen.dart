import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/live_status_provider.dart';
import 'mobile_tokens.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileTemplateScreen extends ConsumerStatefulWidget {
  const MobileTemplateScreen({super.key, this.onCreated});

  final void Function({String? taskId, String? workflowId})? onCreated;

  @override
  ConsumerState<MobileTemplateScreen> createState() =>
      _MobileTemplateScreenState();
}

class _MobileTemplateScreenState extends ConsumerState<MobileTemplateScreen> {
  String? _selectedCat;
  String? _creatingTemplateId;

  Map<String, String> _defaultParamsFor(TemplateInfo template) {
    final params = <String, String>{};
    for (final p in template.params) {
      if ((p.defaultValue ?? '').isNotEmpty) {
        params[p.key] = p.defaultValue!;
      }
    }
    return params;
  }

  Future<void> _createTaskFromTemplate(TemplateInfo template) async {
    if (_creatingTemplateId != null) {
      return;
    }
    setState(() => _creatingTemplateId = template.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final owner = template.depts.isNotEmpty ? template.depts.first : '尚书省';
      final workflow = await api.createWorkflow(
        title: template.name,
        goal: template.desc,
        workflowType: 'generic',
        owner: owner,
        meta: <String, dynamic>{
          'templateId': template.id,
          'source': 'mobile-template-screen',
          'params': _defaultParamsFor(template),
        },
      );
      if (!mounted) return;
      if (workflow.ok && workflow.workflowId.isNotEmpty) {
        await ref.read(liveStatusProvider.notifier).refresh(silent: true);
        messenger.showSnackBar(
          SnackBar(
            content: Text('已创建任务：${template.name}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1400),
          ),
        );
        widget.onCreated?.call(
          workflowId: workflow.workflowId,
          taskId: workflow.taskId,
        );
        return;
      }

      // Fallback to legacy create-task path to keep compatibility.
      final result = await api.createTask(
        CreateTaskPayload(
          title: template.name,
          org: owner,
          targetDept: owner,
          priority: 'P2',
          templateId: template.id,
          params: _defaultParamsFor(template),
        ),
      );
      if (!mounted) return;
      if (!result.ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '创建失败：${workflow.error ?? result.error ?? result.message ?? '未知错误'}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await ref.read(liveStatusProvider.notifier).refresh(silent: true);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已创建任务：${template.name}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
      widget.onCreated?.call(
        taskId: (result.taskId ?? '').trim().isEmpty ? null : result.taskId,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('创建失败：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _creatingTemplateId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = <String>{for (final t in kTemplates) t.cat}.toList()..sort();
    final templates = _selectedCat == null
        ? kTemplates
        : kTemplates
            .where((t) => t.cat == _selectedCat)
            .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF9),
      body: MobileImmersiveBackground(
        child: ListView(
            padding: MobileUiTokens.pagePaddingWide,
            children: [
              const MobileSectionTitle(
                title: '旨库',
                trailing: Text(
                  '九类高频模板',
                  style: MobileUiTokens.trailingText,
                ),
              ),
              const SizedBox(height: MobileUiTokens.gap10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('全部', _selectedCat == null,
                        () => setState(() => _selectedCat = null)),
                    const SizedBox(width: 8),
                    for (final c in cats) ...[
                      _chip(c, _selectedCat == c,
                          () => setState(() => _selectedCat = c)),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: MobileUiTokens.gap12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: templates.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.86,
                ),
                itemBuilder: (context, index) {
                  final card = templates[index];
                  final creating = _creatingTemplateId == card.id;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFFFFF), Color(0xFFFCFCFF)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF0EEEB)),
                      boxShadow: const [MobileImmersiveBackground.cardShadow],
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
                          child: Text(card.icon, style: const TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          card.name,
                          style: MobileUiTokens.cardTitle.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: MobileUiTokens.gap6),
                        Text(
                          card.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MobileUiTokens.cardDesc,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4F4F5),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${card.est} · ${card.cost}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MobileUiTokens.miniMeta,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: creating
                                  ? null
                                  : () => _createTaskFromTemplate(card),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: const Color(0xFFD6DDFF)),
                                ),
                                child: Text(
                                  creating ? '创建中...' : '一键下旨',
                                  style: const TextStyle(
                                    color: Color(0xFF3730A3),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                )
              : null,
          color: selected ? null : const Color(0xFFF5F5F4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF57534E),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
