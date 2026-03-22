import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';

class E2EFlowPanel extends ConsumerStatefulWidget {
  const E2EFlowPanel({super.key});

  @override
  ConsumerState<E2EFlowPanel> createState() => _E2EFlowPanelState();
}

class _E2EFlowPanelState extends ConsumerState<E2EFlowPanel> {
  late final TextEditingController _titleController;
  final List<String> _logs = <String>[];
  bool _busy = false;
  String _workflowId = '';
  String _taskId = '';
  String _revisionId = '';
  String _nodeId = '';
  String _candidateId = '';
  String _assemblyId = '';
  String _finalState = '';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: 'e2e-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    setState(() => _logs.add('[$ts] $message'));
  }

  Future<void> _withBusy(Future<void> Function() fn) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createWorkflow() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _log('创建失败：标题为空');
      return;
    }
    final api = ref.read(apiClientProvider);
    final result = await api.createWorkflow(
      title: title,
      goal: 'E2E full flow by Flutter web panel',
      workflowType: 'generic',
      owner: '中书省',
      meta: <String, dynamic>{'source': 'web-e2e-panel'},
    );
    if (!result.ok || result.workflowId.isEmpty) {
      _log('创建失败：${result.error ?? result.message ?? 'unknown'}');
      return;
    }
    setState(() {
      _workflowId = result.workflowId;
      _taskId = result.taskId;
      _revisionId = '';
      _nodeId = '';
      _candidateId = '';
      _assemblyId = '';
      _finalState = '';
    });
    _titleController.text = 'wf:${result.workflowId}';
    _log('已创建 workflow=$_workflowId task=$_taskId');
  }

  Future<void> _refreshGraph() async {
    if (_workflowId.isEmpty) {
      _log('刷新失败：workflowId 为空');
      return;
    }
    final api = ref.read(apiClientProvider);
    final graph = await api.workflowGraph(_workflowId);
    setState(() {
      if (graph.revisions.isNotEmpty) {
        _revisionId = graph.revisions.first.id;
      }
      if (graph.nodes.isNotEmpty) {
        _nodeId = graph.nodes.first.id;
      }
      if (graph.candidates.isNotEmpty) {
        _candidateId = graph.candidates.first.id;
      }
      final draftAssemblies = graph.assemblies
          .where((item) => item.status.toLowerCase() == 'draft')
          .toList();
      if (draftAssemblies.isNotEmpty) {
        _assemblyId = draftAssemblies.last.id;
      } else if (graph.assemblies.isNotEmpty) {
        _assemblyId = graph.assemblies.last.id;
      }
    });
    _log(
      '刷新完成 rev=$_revisionId node=$_nodeId cand=$_candidateId asm=$_assemblyId',
    );
  }

  Future<void> _startPlanning() async {
    if (_workflowId.isEmpty) {
      _log('开始规划失败：workflowId 为空');
      return;
    }
    final result = await ref.read(apiClientProvider).startPlanning(_workflowId);
    _log('开始规划: ok=${result.ok} ${result.error ?? result.message ?? ''}');
  }

  Future<void> _submitPlan() async {
    if (_workflowId.isEmpty) {
      _log('提交方案失败：workflowId 为空');
      return;
    }
    final result = await ref.read(apiClientProvider).submitPlan(_workflowId);
    _log('提交方案: ok=${result.ok} ${result.error ?? result.message ?? ''}');
  }

  Future<void> _approvePlan() async {
    if (_workflowId.isEmpty || _revisionId.isEmpty) {
      _log('批准方案失败：workflowId/revisionId 为空');
      return;
    }
    final result = await ref.read(apiClientProvider).approveWorkflowRevision(
          _workflowId,
          revisionId: _revisionId,
          actor: 'zhongshu',
        );
    _log('批准方案: ok=${result.ok} ${result.error ?? result.message ?? ''}');
  }

  Future<void> _startNodeExecution() async {
    if (_workflowId.isEmpty || _nodeId.isEmpty) {
      _log('节点执行失败：workflowId/nodeId 为空');
      return;
    }
    final result = await ref.read(apiClientProvider).updateNodeProgress(
          _workflowId,
          nodeId: _nodeId,
          toState: 'running',
          reason: 'web-e2e run',
        );
    _log('启动执行节点: ok=${result.ok} ${result.error ?? result.message ?? ''}');
  }

  Future<void> _selectCandidate() async {
    if (_workflowId.isEmpty || _nodeId.isEmpty || _candidateId.isEmpty) {
      _log('选定候选失败：workflowId/nodeId/candidateId 为空');
      return;
    }
    final result = await ref.read(apiClientProvider).selectWorkflowCandidate(
          _workflowId,
          nodeId: _nodeId,
          candidateId: _candidateId,
          actor: 'zhongshu',
        );
    _log('选定候选: ok=${result.ok} ${result.error ?? result.message ?? ''}');
  }

  Future<void> _approveAssembly() async {
    if (_workflowId.isEmpty || _assemblyId.isEmpty) {
      _log('通过汇总失败：workflowId/assemblyId 为空');
      return;
    }
    final result = await ref.read(apiClientProvider).approveWorkflowAssembly(
          _workflowId,
          assemblyId: _assemblyId,
          actor: 'zhongshu',
        );
    _log('通过汇总: ok=${result.ok} ${result.error ?? result.message ?? ''}');
  }

  Future<void> _poll({
    required String label,
    required bool Function() done,
    Duration interval = const Duration(seconds: 1),
    int maxTicks = 20,
  }) async {
    for (var i = 0; i < maxTicks; i++) {
      await _refreshGraph();
      if (done()) {
        _log('$label: 条件已满足');
        return;
      }
      await Future<void>.delayed(interval);
    }
    _log('$label: 轮询超时');
  }

  Future<void> _runAll() async {
    await _createWorkflow();
    if (_workflowId.isEmpty) return;
    await _startPlanning();
    await _poll(label: '等待 revision', done: () => _revisionId.isNotEmpty);
    await _submitPlan();
    await _approvePlan();
    await _poll(label: '等待 node', done: () => _nodeId.isNotEmpty);
    await _startNodeExecution();
    await _poll(label: '等待 candidate', done: () => _candidateId.isNotEmpty);
    await _selectCandidate();
    await _poll(label: '等待 assembly', done: () => _assemblyId.isNotEmpty);
    await _approveAssembly();
    if (_workflowId.isNotEmpty) {
      final summary =
          await ref.read(apiClientProvider).workflowSummary(_workflowId);
      setState(() => _finalState = summary.state);
      _titleController.text = 'done:${_workflowId}:${summary.state}';
      _log('最终状态: ${summary.state}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Web E2E 流程面板（仅 ?e2e=1）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '任务标题',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_createWorkflow),
              child: const Text('1) 创建旨意'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_startPlanning),
              child: const Text('2) 开始规划'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_submitPlan),
              child: const Text('3) 提交方案'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_approvePlan),
              child: const Text('4) 批准方案'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_startNodeExecution),
              child: const Text('5) 启动节点'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_selectCandidate),
              child: const Text('6) 选定候选'),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _withBusy(_approveAssembly),
              child: const Text('7) 通过汇总'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _withBusy(_refreshGraph),
              child: const Text('刷新图谱ID'),
            ),
            ElevatedButton(
              onPressed: _busy ? null : () => _withBusy(_runAll),
              child: Text(_busy ? '执行中…' : '一键跑通全流程'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          'workflowId=$_workflowId\n'
          'taskId=$_taskId\n'
          'revisionId=$_revisionId\n'
          'nodeId=$_nodeId\n'
          'candidateId=$_candidateId\n'
          'assemblyId=$_assemblyId\n'
          'finalState=$_finalState',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const SizedBox(height: 12),
        const Text('执行日志', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF334155)),
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(8),
          child: SelectableText(
            _logs.isEmpty ? '(暂无日志)' : _logs.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
