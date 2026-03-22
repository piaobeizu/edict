import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/clipboard.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../common/common.dart';

class SkillsConfigPanel extends ConsumerStatefulWidget {
  const SkillsConfigPanel({super.key});

  @override
  ConsumerState<SkillsConfigPanel> createState() => _SkillsConfigPanelState();
}

class _SkillsConfigPanelState extends ConsumerState<SkillsConfigPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Map<String, String> _communityAgentSelect = <String, String>{};
  final Set<String> _expandedCommunity = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toastOk(String msg) {
    ref.read(toastProvider.notifier).show(msg, type: ToastType.ok);
  }

  void _toastErr(String msg) {
    ref.read(toastProvider.notifier).show(msg, type: ToastType.err);
  }

  String _fmtTime(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
  }

  Future<void> _showSkillContent(AgentInfo agent, SkillInfo skill) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final future = ref.read(apiClientProvider).skillContent(agent.id, skill.name);
        return AlertDialog(
          title: Text('${agent.emoji} ${skill.name}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
            child: FutureBuilder<SkillContentResult>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Text('技能内容加载失败');
                }
                if (!data.ok) {
                  return Text('读取失败：${data.error ?? '未知错误'}');
                }
                final content = data.content ?? '';
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: EdictTheme.panelDecoration,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        content,
                        style: EdictTheme.monoStyle.copyWith(fontSize: 12, height: 1.5),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddSkillDialog({String? defaultAgentId}) async {
    final agentConfig = ref.read(agentConfigProvider).value;
    final agents = agentConfig?.agents ?? const <AgentInfo>[];
    if (agents.isEmpty) {
      _toastErr('暂无可选 Agent');
      return;
    }

    String agentId = defaultAgentId ?? agents.first.id;
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    final triggerCtl = TextEditingController();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('添加技能'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: agentId,
                      items: agents
                          .map(
                            (agent) => DropdownMenuItem<String>(
                              value: agent.id,
                              child: Text('${agent.emoji} ${agent.label} · ${agent.id}'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setLocalState(() => agentId = value);
                            },
                      decoration: const InputDecoration(labelText: 'Agent'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtl,
                      enabled: !submitting,
                      decoration: const InputDecoration(labelText: 'skillName'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtl,
                      enabled: !submitting,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'description'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: triggerCtl,
                      enabled: !submitting,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'trigger inputs'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final skillName = nameCtl.text.trim();
                          final description = descCtl.text.trim();
                          final trigger = triggerCtl.text.trim();
                          if (skillName.isEmpty || description.isEmpty || trigger.isEmpty) {
                            _toastErr('请填写完整字段');
                            return;
                          }
                          setLocalState(() => submitting = true);
                          final result = await ref
                              .read(apiClientProvider)
                              .addSkill(agentId, skillName, description, trigger);
                          if (!mounted) return;
                          if (!result.ok) {
                            setLocalState(() => submitting = false);
                            _toastErr(result.error ?? result.message ?? '添加失败');
                            return;
                          }
                          _toastOk('技能已添加');
                          await ref.read(agentConfigProvider.notifier).refresh();
                          if (mounted) Navigator.of(context).pop();
                        },
                  child: Text(submitting ? '提交中...' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtl.dispose();
    descCtl.dispose();
    triggerCtl.dispose();
  }

  Future<void> _showAddRemoteSkillDialog() async {
    final agentConfig = ref.read(agentConfigProvider).value;
    final agents = agentConfig?.agents ?? const <AgentInfo>[];
    if (agents.isEmpty) {
      _toastErr('暂无可选 Agent');
      return;
    }

    String agentId = agents.first.id;
    final skillNameCtl = TextEditingController();
    final sourceCtl = TextEditingController();
    final descCtl = TextEditingController();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('添加远程 Skill'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: agentId,
                      items: agents
                          .map(
                            (agent) => DropdownMenuItem<String>(
                              value: agent.id,
                              child: Text('${agent.emoji} ${agent.label} · ${agent.id}'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setLocalState(() => agentId = value);
                            },
                      decoration: const InputDecoration(labelText: 'agentId'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: skillNameCtl,
                      enabled: !submitting,
                      decoration: const InputDecoration(labelText: 'skillName'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: sourceCtl,
                      enabled: !submitting,
                      decoration: const InputDecoration(labelText: 'sourceUrl'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtl,
                      enabled: !submitting,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'description'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final skillName = skillNameCtl.text.trim();
                          final sourceUrl = sourceCtl.text.trim();
                          final description = descCtl.text.trim();
                          if (skillName.isEmpty || sourceUrl.isEmpty || description.isEmpty) {
                            _toastErr('请填写完整字段');
                            return;
                          }
                          setLocalState(() => submitting = true);
                          final result = await ref
                              .read(apiClientProvider)
                              .addRemoteSkill(agentId, skillName, sourceUrl, description);
                          if (!mounted) return;
                          if (!result.ok) {
                            setLocalState(() => submitting = false);
                            _toastErr(result.error ?? result.message ?? '添加失败');
                            return;
                          }
                          _toastOk('远程 Skill 已添加');
                          await ref.read(remoteSkillsProvider.notifier).refresh();
                          if (mounted) Navigator.of(context).pop();
                        },
                  child: Text(submitting ? '提交中...' : '添加'),
                ),
              ],
            );
          },
        );
      },
    );

    skillNameCtl.dispose();
    sourceCtl.dispose();
    descCtl.dispose();
  }

  Future<void> _importCommunitySkill({
    required String agentId,
    required _CommunitySkillDefinition skill,
  }) async {
    final result = await ref
        .read(apiClientProvider)
        .addRemoteSkill(agentId, skill.skillName, skill.sourceUrl, skill.description);
    if (!mounted) return;
    if (!result.ok) {
      _toastErr(result.error ?? result.message ?? '导入失败');
      return;
    }
    _toastOk('已导入 ${skill.skillName}');
    await ref.read(remoteSkillsProvider.notifier).refresh();
  }

  Future<void> _openSourceUrl(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
    if (!mounted) return;
    final copied = await copyTextToClipboard(context, sourceUrl);
    if (mounted && copied) {
      _toastOk('链接已复制：$sourceUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentConfigValue = ref.watch(agentConfigProvider);
    final remoteSkillsValue = ref.watch(remoteSkillsProvider);

    final localSkillCount = agentConfigValue.asData?.value.agents
            .fold<int>(0, (sum, agent) => sum + agent.skills.length) ??
        0;
    final remoteCount = remoteSkillsValue.asData?.value.remoteSkills?.length ?? 0;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          decoration: EdictTheme.cardDecoration,
          child: TabBar(
            controller: _tabController,
            indicatorColor: EdictTheme.acc,
            labelColor: EdictTheme.text,
            unselectedLabelColor: EdictTheme.muted,
            tabs: [
              Tab(text: '🏛 本地技能 ($localSkillCount)'),
              Tab(text: '🌐 远程技能 ($remoteCount)'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildLocalTab(agentConfigValue),
              _buildRemoteTab(agentConfigValue, remoteSkillsValue),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocalTab(AsyncValue<AgentConfig> configValue) {
    return configValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('本地技能加载失败：$error', style: EdictTheme.bodyStyle),
        ),
      ),
      data: (config) {
        final agents = config.agents;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 260,
            ),
            itemCount: agents.length,
            itemBuilder: (context, index) {
              final agent = agents[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: EdictTheme.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${agent.emoji} ${agent.label} · ${agent.skills.length}',
                      style: EdictTheme.titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: agent.skills.isEmpty
                          ? Center(
                              child: Text('暂无技能', style: EdictTheme.mutedStyle),
                            )
                          : ListView.separated(
                              itemCount: agent.skills.length,
                              separatorBuilder: (_, __) =>
                                  Divider(color: EdictTheme.line.withOpacity(0.65), height: 8),
                              itemBuilder: (context, idx) {
                                final skill = agent.skills[idx];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _showSkillContent(agent, skill),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(skill.name, style: EdictTheme.bodyStyle),
                                              const SizedBox(height: 2),
                                              Text(
                                                skill.description,
                                                style: EdictTheme.mutedStyle,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '›',
                                          style: EdictTheme.bodyStyle.copyWith(
                                            color: EdictTheme.acc,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showAddSkillDialog(defaultAgentId: agent.id),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: EdictTheme.panel2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: EdictTheme.line),
                        ),
                        child: Text(
                          '+ 添加技能',
                          style: EdictTheme.bodyStyle.copyWith(color: EdictTheme.acc),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRemoteTab(
    AsyncValue<AgentConfig> agentConfigValue,
    AsyncValue<RemoteSkillsListResult> remoteSkillsValue,
  ) {
    final agents = agentConfigValue.asData?.value.agents ?? const <AgentInfo>[];
    final remoteSkills = remoteSkillsValue.asData?.value.remoteSkills ?? const <RemoteSkillItem>[];
    final remoteTotal = remoteSkills.length;

    for (final source in _communitySources) {
      if (_communityAgentSelect[source.id] == null && agents.isNotEmpty) {
        _communityAgentSelect[source.id] = agents.first.id;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: EdictTheme.cardDecoration,
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _showAddRemoteSkillDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('添加远程 Skill'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => ref.read(remoteSkillsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('⟳ 刷新'),
                ),
                const Spacer(),
                Text('总计 $remoteTotal', style: EdictTheme.bodyStyle),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('Community Quick-Pick', style: EdictTheme.titleStyle),
          const SizedBox(height: 8),
          ..._communitySources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCommunityCard(source, agents, remoteSkills),
            ),
          ),
          const SizedBox(height: 8),
          Text('已安装远程技能', style: EdictTheme.titleStyle),
          const SizedBox(height: 8),
          remoteSkillsValue.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: EdictTheme.panelDecoration,
              child: Text('远程技能列表加载失败：$error', style: EdictTheme.bodyStyle),
            ),
            data: (data) {
              final list = data.remoteSkills ?? const <RemoteSkillItem>[];
              if (list.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: EdictTheme.panelDecoration,
                  child: Text('暂无远程技能', style: EdictTheme.mutedStyle),
                );
              }
              return Column(
                children: list
                    .map(
                      (skill) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildInstalledRemoteSkillCard(skill),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(
    _CommunitySourceDefinition source,
    List<AgentInfo> agents,
    List<RemoteSkillItem> remoteSkills,
  ) {
    final expanded = _expandedCommunity.contains(source.id);
    final selectedAgentId = _communityAgentSelect[source.id];

    return Container(
      decoration: EdictTheme.cardDecoration,
      child: ExpansionTile(
        key: PageStorageKey<String>('community-${source.id}'),
        initiallyExpanded: expanded,
        onExpansionChanged: (value) {
          setState(() {
            if (value) {
              _expandedCommunity.add(source.id);
            } else {
              _expandedCommunity.remove(source.id);
            }
          });
        },
        title: Text('${source.title} (${source.starText})', style: EdictTheme.titleStyle),
        subtitle: Text(source.subtitle, style: EdictTheme.mutedStyle),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (agents.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('暂无 Agent，无法导入', style: EdictTheme.mutedStyle),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 320,
                child: DropdownButtonFormField<String>(
                  value: selectedAgentId ?? agents.first.id,
                  items: agents
                      .map(
                        (agent) => DropdownMenuItem<String>(
                          value: agent.id,
                          child: Text('${agent.emoji} ${agent.label} · ${agent.id}'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _communityAgentSelect[source.id] = value);
                  },
                  decoration: const InputDecoration(labelText: '导入到 Agent'),
                ),
              ),
            ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 142,
            ),
            itemCount: source.skills.length,
            itemBuilder: (context, idx) {
              final item = source.skills[idx];
              final imported = remoteSkills.any(
                (r) =>
                    r.skillName == item.skillName &&
                    r.sourceUrl == item.sourceUrl &&
                    (selectedAgentId == null || r.agentId == selectedAgentId),
              );
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: EdictTheme.panel2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: EdictTheme.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.skillName,
                      style: EdictTheme.bodyStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        item.description,
                        style: EdictTheme.mutedStyle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: imported
                          ? OutlinedButton(
                              onPressed: null,
                              child: const Text('✓ 已导入'),
                            )
                          : FilledButton(
                              onPressed: selectedAgentId == null
                                  ? null
                                  : () => _importCommunitySkill(
                                        agentId: selectedAgentId,
                                        skill: item,
                                      ),
                              child: const Text('导入'),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledRemoteSkillCard(RemoteSkillItem skill) {
    final statusValid = skill.status == 'valid';
    final statusColor = statusValid ? EdictTheme.ok : EdictTheme.danger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: EdictTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(skill.skillName, style: EdictTheme.titleStyle),
              _tag(
                text: skill.status,
                fg: statusColor,
                bg: statusColor.withOpacity(0.13),
                border: statusColor.withOpacity(0.45),
              ),
              _tag(
                text: skill.agentId,
                fg: EdictTheme.acc,
                bg: EdictTheme.acc.withOpacity(0.12),
                border: EdictTheme.acc.withOpacity(0.45),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(skill.description, style: EdictTheme.bodyStyle),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openSourceUrl(skill.sourceUrl),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                skill.sourceUrl,
                style: EdictTheme.mutedStyle.copyWith(
                  color: EdictTheme.acc,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'addedAt: ${_fmtTime(skill.addedAt)}    lastUpdated: ${_fmtTime(skill.lastUpdated)}',
            style: EdictTheme.captionStyle,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('远程 Skill 详情'),
                      content: SizedBox(
                        width: 560,
                        child: SelectableText(
                          'skillName: ${skill.skillName}\n'
                          'agentId: ${skill.agentId}\n'
                          'status: ${skill.status}\n'
                          'sourceUrl: ${skill.sourceUrl}\n'
                          'localPath: ${skill.localPath}\n'
                          'description: ${skill.description}\n'
                          'addedAt: ${_fmtTime(skill.addedAt)}\n'
                          'lastUpdated: ${_fmtTime(skill.lastUpdated)}',
                          style: EdictTheme.monoStyle.copyWith(fontSize: 12, height: 1.5),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('查看'),
              ),
              FilledButton(
                onPressed: () async {
                  final result = await ref
                      .read(apiClientProvider)
                      .updateRemoteSkill(skill.agentId, skill.skillName);
                  if (!mounted) return;
                  if (!result.ok) {
                    _toastErr(result.error ?? result.message ?? '更新失败');
                    return;
                  }
                  _toastOk('已更新 ${skill.skillName}');
                  await ref.read(remoteSkillsProvider.notifier).refresh();
                },
                child: const Text('更新'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await showConfirmDialog(
                    context: context,
                    title: '删除远程 Skill',
                    message: '确认删除 ${skill.skillName} 吗？',
                    actionLabel: '删除',
                    hintText: '备注（可选）',
                  );
                  if (!confirmed.$1) return;
                  final result = await ref
                      .read(apiClientProvider)
                      .removeRemoteSkill(skill.agentId, skill.skillName);
                  if (!mounted) return;
                  if (!result.ok) {
                    _toastErr(result.error ?? result.message ?? '删除失败');
                    return;
                  }
                  _toastOk('已删除 ${skill.skillName}');
                  await ref.read(remoteSkillsProvider.notifier).refresh();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: EdictTheme.danger,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag({
    required String text,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: EdictTheme.captionStyle.copyWith(color: fg),
      ),
    );
  }
}

class _CommunitySourceDefinition {
  const _CommunitySourceDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.starText,
    required this.skills,
  });

  final String id;
  final String title;
  final String subtitle;
  final String starText;
  final List<_CommunitySkillDefinition> skills;
}

class _CommunitySkillDefinition {
  const _CommunitySkillDefinition({
    required this.skillName,
    required this.description,
    required this.sourceUrl,
  });

  final String skillName;
  final String description;
  final String sourceUrl;
}

const List<_CommunitySourceDefinition> _communitySources = <_CommunitySourceDefinition>[
  _CommunitySourceDefinition(
    id: 'obra-superpowers',
    title: 'obra/superpowers',
    subtitle: '高热度社区技能合集',
    starText: '66.9k⭐',
    skills: <_CommunitySkillDefinition>[
      _CommunitySkillDefinition(
        skillName: 'repo-scan',
        description: '快速扫描仓库并生成结构摘要',
        sourceUrl: 'https://github.com/obra/superpowers/tree/main/repo-scan',
      ),
      _CommunitySkillDefinition(
        skillName: 'release-helper',
        description: '自动整理变更并输出 release notes',
        sourceUrl: 'https://github.com/obra/superpowers/tree/main/release-helper',
      ),
      _CommunitySkillDefinition(
        skillName: 'incident-debug',
        description: '生产故障快速定位与处置建议',
        sourceUrl: 'https://github.com/obra/superpowers/tree/main/incident-debug',
      ),
    ],
  ),
  _CommunitySourceDefinition(
    id: 'anthropic-skills',
    title: 'anthropics/skills',
    subtitle: '官方技能示例与最佳实践',
    starText: '官方',
    skills: <_CommunitySkillDefinition>[
      _CommunitySkillDefinition(
        skillName: 'prompt-audit',
        description: '对提示词进行质量审查与改进建议',
        sourceUrl: 'https://github.com/anthropics/skills/tree/main/prompt-audit',
      ),
      _CommunitySkillDefinition(
        skillName: 'safety-guard',
        description: '内容安全策略检查与分级处理',
        sourceUrl: 'https://github.com/anthropics/skills/tree/main/safety-guard',
      ),
      _CommunitySkillDefinition(
        skillName: 'eval-runner',
        description: '标准化评测任务执行器',
        sourceUrl: 'https://github.com/anthropics/skills/tree/main/eval-runner',
      ),
    ],
  ),
  _CommunitySourceDefinition(
    id: 'composiohq',
    title: 'ComposioHQ',
    subtitle: 'SaaS 工具连接技能库',
    starText: '39.2k⭐',
    skills: <_CommunitySkillDefinition>[
      _CommunitySkillDefinition(
        skillName: 'github-ops',
        description: 'GitHub Issue / PR 自动化处理',
        sourceUrl: 'https://github.com/ComposioHQ/skills/tree/main/github-ops',
      ),
      _CommunitySkillDefinition(
        skillName: 'slack-ops',
        description: 'Slack 消息通知与指令桥接',
        sourceUrl: 'https://github.com/ComposioHQ/skills/tree/main/slack-ops',
      ),
      _CommunitySkillDefinition(
        skillName: 'notion-sync',
        description: 'Notion 文档同步与知识沉淀',
        sourceUrl: 'https://github.com/ComposioHQ/skills/tree/main/notion-sync',
      ),
    ],
  ),
];
