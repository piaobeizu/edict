import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

const List<String> _fallbackModels = <String>[
  'claude-sonnet-4-20250514',
  'gpt-4o',
  'gpt-4o-mini',
  'claude-3-5-haiku-20241022',
  'deepseek-chat',
  'deepseek-reasoner',
  'gemini-2.5-pro',
  'gemini-2.0-flash',
  'qwen-max',
  'qwen-plus',
];

enum _ApplyStatus { idle, pending, ok, err }

class _AgentModelState {
  _AgentModelState({required this.selectedModel, required this.syncedModel});

  String selectedModel;
  String syncedModel;
  _ApplyStatus status = _ApplyStatus.idle;
  String statusText = '';
}

class ModelConfigPanel extends ConsumerStatefulWidget {
  const ModelConfigPanel({super.key});

  @override
  ConsumerState<ModelConfigPanel> createState() => _ModelConfigPanelState();
}

class _ModelConfigPanelState extends ConsumerState<ModelConfigPanel> {
  final Map<String, _AgentModelState> _agentLocalState = <String, _AgentModelState>{};

  _AgentModelState _stateFor(AgentInfo agent) {
    final state = _agentLocalState.putIfAbsent(
      agent.id,
      () => _AgentModelState(selectedModel: agent.model, syncedModel: agent.model),
    );
    if (state.status == _ApplyStatus.idle) {
      final wasTrackingServer = state.selectedModel == state.syncedModel;
      state.syncedModel = agent.model;
      if (wasTrackingServer || state.selectedModel.isEmpty) {
        state.selectedModel = agent.model;
      }
    } else {
      state.syncedModel = agent.model;
    }
    return state;
  }

  List<String> _modelOptions(AgentConfig config, String currentModel) {
    final options = <String>{
      ...(config.knownModels?.map((m) => m.id) ?? const Iterable<String>.empty()),
      ..._fallbackModels,
      currentModel,
    };
    return options.where((e) => e.trim().isNotEmpty).toList(growable: false);
  }

  Future<void> _applyModel(AgentInfo agent, _AgentModelState localState) async {
    final selected = localState.selectedModel.trim();
    if (selected.isEmpty || selected == agent.model) {
      return;
    }
    setState(() {
      localState.status = _ApplyStatus.pending;
      localState.statusText = '正在应用模型...';
    });

    final api = ref.read(apiClientProvider);
    final result = await api.setModel(agent.id, selected);
    if (!mounted) return;

    setState(() {
      if (result.ok) {
        localState.status = _ApplyStatus.ok;
        localState.statusText = result.message?.isNotEmpty == true
            ? result.message!
            : '模型已应用，5.5 秒后自动刷新配置';
      } else {
        localState.status = _ApplyStatus.err;
        localState.statusText = result.error?.isNotEmpty == true
            ? result.error!
            : (result.message?.isNotEmpty == true ? result.message! : '模型切换失败');
      }
    });

    if (!result.ok) return;

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 5500), () async {
        if (!mounted) return;
        await ref.read(agentConfigProvider.notifier).refresh();
        ref.invalidate(changeLogProvider);
      }),
    );
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final configValue = ref.watch(agentConfigProvider);
    final changeLogValue = ref.watch(changeLogProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('模型配置', style: EdictTheme.headerStyle),
          const SizedBox(height: 12),
          configValue.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: EdictTheme.panelDecoration,
              child: Text('加载模型配置失败：$error', style: EdictTheme.bodyStyle),
            ),
            data: (config) {
              final agents = config.agents;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 242,
                ),
                itemCount: agents.length,
                itemBuilder: (context, index) {
                  final agent = agents[index];
                  final localState = _stateFor(agent);
                  final options = _modelOptions(config, agent.model);
                  final unchanged = localState.selectedModel == agent.model;
                  final disabled = localState.status == _ApplyStatus.pending || unchanged;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: EdictTheme.cardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${agent.emoji} ${agent.label} · ${agent.id} ${agent.role}',
                          style: EdictTheme.titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text('当前模型：${agent.model}', style: EdictTheme.mutedStyle),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: localState.selectedModel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: options
                              .map(
                                (model) => DropdownMenuItem<String>(
                                  value: model,
                                  child: Text(
                                    model,
                                    style: EdictTheme.bodyStyle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              localState.selectedModel = value;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: disabled ? null : () => _applyModel(agent, localState),
                              child: const Text('应用'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: localState.status == _ApplyStatus.pending
                                  ? null
                                  : () {
                                      setState(() {
                                        localState.selectedModel = agent.model;
                                        localState.status = _ApplyStatus.idle;
                                        localState.statusText = '';
                                      });
                                    },
                              child: const Text('重置'),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (localState.status != _ApplyStatus.idle)
                          _StatusBar(status: localState.status, text: localState.statusText),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: EdictTheme.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('模型变更记录', style: EdictTheme.titleStyle),
                const SizedBox(height: 10),
                changeLogValue.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('加载变更记录失败：$error', style: EdictTheme.bodyStyle),
                  ),
                  data: (logs) {
                    final recent = logs.length <= 15 ? logs : logs.sublist(logs.length - 15);
                    final rows = recent.reversed.toList(growable: false);
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('暂无模型变更记录', style: EdictTheme.mutedStyle),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: EdictTheme.panel2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: EdictTheme.line),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: EdictTheme.line.withOpacity(0.8))),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 3, child: Text('时间', style: EdictTheme.captionStyle)),
                                Expanded(flex: 2, child: Text('Agent', style: EdictTheme.captionStyle)),
                                Expanded(flex: 5, child: Text('模型变更', style: EdictTheme.captionStyle)),
                              ],
                            ),
                          ),
                          ...rows.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                border: idx == rows.length - 1
                                    ? null
                                    : Border(bottom: BorderSide(color: EdictTheme.line.withOpacity(0.55))),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(_formatTime(item.at), style: EdictTheme.mutedStyle),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(item.agentId, style: EdictTheme.bodyStyle),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        Text(
                                          '${item.oldModel} → ${item.newModel}',
                                          style: EdictTheme.bodyStyle,
                                        ),
                                        if (item.rolledBack == true)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: EdictTheme.warn.withOpacity(0.16),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(
                                                color: EdictTheme.warn.withOpacity(0.45),
                                              ),
                                            ),
                                            child: Text(
                                              '⚠ 已回滚',
                                              style: EdictTheme.captionStyle.copyWith(
                                                color: EdictTheme.warn,
                                              ),
                                            ),
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
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status, required this.text});

  final _ApplyStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _ApplyStatus.pending => EdictTheme.warn,
      _ApplyStatus.ok => EdictTheme.ok,
      _ApplyStatus.err => EdictTheme.danger,
      _ApplyStatus.idle => EdictTheme.muted,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: EdictTheme.captionStyle.copyWith(color: color),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
