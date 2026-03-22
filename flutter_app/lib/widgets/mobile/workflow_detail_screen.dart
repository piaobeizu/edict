import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../core/core.dart';
import '../../providers/api_provider.dart';
import '../../providers/live_status_provider.dart';
import '../../providers/workflow_events_provider.dart';
import '../../providers/workflow_projection_sync_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../services/api_client.dart';
import 'mobile_tokens.dart';

class WorkflowDetailScreen extends ConsumerStatefulWidget {
  const WorkflowDetailScreen({
    super.key,
    required this.workflowId,
    this.showAppBar = true,
  });

  final String workflowId;
  final bool showAppBar;

  @override
  ConsumerState<WorkflowDetailScreen> createState() =>
      _WorkflowDetailScreenState();
}

class _WorkflowDetailScreenState extends ConsumerState<WorkflowDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _submitting = false;
  final Set<String> _expandedCandidateIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(workflowSummaryProvider(widget.workflowId));
    final graphAsync = ref.watch(workflowGraphProvider(widget.workflowId));
    final timelineAsync =
        ref.watch(workflowTimelineProvider(widget.workflowId));
    final eventsAsync = ref.watch(workflowEventsProvider(widget.workflowId));

    final body = summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorBlock(text: '加载 workflow 摘要失败：$error'),
      data: (summary) => graphAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBlock(text: '加载 workflow graph 失败：$error'),
        data: (graph) => _buildContent(
          summary,
          graph,
          timelineAsync.valueOrNull ?? const <WorkflowTimelineEvent>[],
          eventsAsync.valueOrNull ?? WorkflowEventsState.initial(),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: MobileUiTokens.pageBg,
      body: SafeArea(
        bottom: false,
        child: body,
      ),
    );
  }

  Widget _buildContent(
    Workflow summary,
    WorkflowGraph graph,
    List<WorkflowTimelineEvent> timeline,
    WorkflowEventsState eventsState,
  ) {
    return Column(
      children: [
        _DetailHeader(
          title: summary.title.isEmpty ? summary.id : summary.title,
          state: summary.state,
          workflowId: summary.id,
          revisionId: summary.currentRevisionId,
          showBack: widget.showAppBar,
        ),
        if (eventsState.dirty || eventsState.pendingMutations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _WorkflowSyncBanner(
              hintText: _syncHintText(eventsState),
              pendingMutations: eventsState.pendingMutations,
              onRefresh: () => ref
                  .read(workflowEventsProvider(widget.workflowId).notifier)
                  .reconcileNow(),
            ),
          ),
        if (eventsState.recentEventKeys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: _WorkflowRecentEventsPanel(
              lastEventType: eventsState.lastEventType,
              recentEventKeys: eventsState.recentEventKeys,
            ),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x476366F1),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF5B57A7),
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: '概览'),
              Tab(text: '方案'),
              Tab(text: '执行'),
              Tab(text: '汇总'),
              Tab(text: '动态'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(summary, graph, eventsState),
              _buildRevisionTab(summary, graph, eventsState),
              _buildExecutionTab(graph, eventsState),
              _buildAssemblyTab(summary, graph, eventsState),
              _buildTimelineTab(timeline),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildWorkflowActions(
    Workflow summary,
    WorkflowEventsState eventsState,
  ) {
    final actions = <Widget>[];
    final state = summary.state.toLowerCase();
    final nonTerminal = !{'done', 'cancelled'}.contains(state);
    final hasWorkflowCommandPending = _hasBlockingMutation(
      eventsState,
      eventTypePrefix: 'workflow.v2.command.',
    );
    const workflowBlockedReason = '有 workflow 级动作待确认，请先点击上方刷新核对状态';

    if (state == 'draft') {
      actions.add(
        _ActionButton(
          label: '开始规划',
          busy: _submitting,
          disabledReason:
              hasWorkflowCommandPending ? workflowBlockedReason : null,
          onPressed: hasWorkflowCommandPending
              ? null
              : () => _runAction(
                    eventType: ApiClient.eventStartPlanning,
                    taskId: summary.taskId,
                    action: () =>
                        ref.read(apiClientProvider).startPlanning(summary.id),
                  ),
        ),
      );
    }
    if (state == 'blocked') {
      actions.add(
        _ActionButton(
          label: '恢复',
          busy: _submitting,
          disabledReason:
              hasWorkflowCommandPending ? workflowBlockedReason : null,
          onPressed: hasWorkflowCommandPending
              ? null
              : () => _runAction(
                    eventType: ApiClient.eventResumeWorkflow,
                    taskId: summary.taskId,
                    action: () =>
                        ref.read(apiClientProvider).resumeWorkflow(summary.id),
                  ),
        ),
      );
    }
    if (nonTerminal) {
      actions.add(
        _ActionButton(
          label: '叫停',
          busy: _submitting,
          disabledReason:
              hasWorkflowCommandPending ? workflowBlockedReason : null,
          onPressed: hasWorkflowCommandPending
              ? null
              : () => _runAction(
                    eventType: ApiClient.eventStopWorkflow,
                    taskId: summary.taskId,
                    action: () =>
                        ref.read(apiClientProvider).stopWorkflow(summary.id),
                  ),
        ),
      );
      actions.add(
        _ActionButton(
          label: '取消',
          busy: _submitting,
          disabledReason:
              hasWorkflowCommandPending ? workflowBlockedReason : null,
          onPressed: hasWorkflowCommandPending
              ? null
              : () => _runAction(
                    eventType: ApiClient.eventCancelWorkflow,
                    taskId: summary.taskId,
                    action: () =>
                        ref.read(apiClientProvider).cancelWorkflow(summary.id),
                  ),
        ),
      );
    }
    return actions;
  }

  Widget _buildOverviewTab(
    Workflow summary,
    WorkflowGraph graph,
    WorkflowEventsState eventsState,
  ) {
    final revisions = graph.revisions;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionCard(
          title: '当前阶段',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _overviewStageText(summary, graph),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF44403C),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipLabel(label: '状态：${summary.state}'),
                  _ChipLabel(label: '类型：${summary.type}'),
                  _ChipLabel(label: '待审：${_pendingReviewCount(graph)}'),
                  _ChipLabel(label: '运行节点：${_runningNodeCount(graph)}'),
                ],
              ),
              if (summary.goal.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  summary.goal,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildWorkflowActions(summary, eventsState),
              ),
              if (eventsState.pendingMutations.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '待确认动作：${eventsState.pendingMutations.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C2D12),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '交互指引',
          child: _buildInteractionGuide(summary, graph, eventsState),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '当前摘要',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CopyableLine(label: 'Workflow ID', value: summary.id),
              _CopyableLine(label: 'Task ID', value: summary.taskId),
              _CopyableLine(
                label: '当前 revision',
                value: summary.currentRevisionId ?? '-',
              ),
              _CopyableLine(
                label: '当前 assembly',
                value: summary.currentAssemblyId ?? '-',
              ),
              if ((summary.summaryOutput ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '汇总内容',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  summary.summaryOutput!,
                  style: const TextStyle(color: Colors.black87, height: 1.5),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => copyTextToClipboard(
                      context,
                      summary.summaryOutput!,
                      successMessage: '已复制汇总内容',
                    ),
                    icon: const Icon(Icons.content_copy_rounded, size: 14),
                    label: const Text('复制汇总'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'Revision 概况',
          child: Text(
            '共 ${revisions.length} 个方案版本，待审 ${_pendingReviewCount(graph)} 个。',
          ),
        ),
      ],
    );
  }

  Widget _buildRevisionTab(
    Workflow summary,
    WorkflowGraph graph,
    WorkflowEventsState eventsState,
  ) {
    if (graph.revisions.isEmpty) {
      return const Center(child: Text('暂无方案版本'));
    }
    final workflowState = summary.state.toLowerCase();
    final workflowCommandPending = _hasBlockingMutation(
      eventsState,
      eventTypePrefix: 'workflow.v2.command.',
    );
    WorkflowRevision? currentRevision;
    final currentRevisionId = summary.currentRevisionId ?? '';
    for (final revision in graph.revisions) {
      if (revision.id == currentRevisionId) {
        currentRevision = revision;
        break;
      }
    }
    final showRegeneratePlanAction = currentRevision != null &&
        !{'done', 'cancelled'}.contains(workflowState);
    final leadingCards = showRegeneratePlanAction ? 1 : 0;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: graph.revisions.length + leadingCards,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        if (showRegeneratePlanAction && index == 0) {
          return _SectionCard(
            title: '方案操作',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前激活版本：Revision #${currentRevision!.number}。重新生成会创建新的方案版本，并保留历史版本卡片。',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF44403C),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  label: '重新生成方案',
                  busy: _submitting,
                  disabledReason:
                      workflowCommandPending ? '有 workflow 动作待确认，请先刷新' : null,
                  onPressed: workflowCommandPending
                      ? null
                      : () async {
                          final reason = await _askReason(
                            title: '重新生成方案',
                            hintText: '请输入原因（可选）',
                            requiredReason: false,
                          );
                          if (!mounted || reason == null) {
                            return;
                          }
                          if (workflowState == 'draft') {
                            await _runAction(
                              eventType: ApiClient.eventStartPlanning,
                              taskId: summary.taskId,
                              targetType: 'workflow',
                              targetId: summary.id,
                              action: () => ref
                                  .read(apiClientProvider)
                                  .startPlanning(summary.id),
                            );
                            return;
                          }
                          await _runAction(
                            eventType: ApiClient.eventRollbackWorkflow,
                            taskId: summary.taskId,
                            targetType: 'workflow',
                            targetId: summary.id,
                            action: () =>
                                ref.read(apiClientProvider).rollbackWorkflow(
                                      summary.id,
                                      reason: reason,
                                    ),
                          );
                        },
                ),
              ],
            ),
          );
        }
        final revision = graph.revisions[index - leadingCards];
        final status = revision.status.toLowerCase();
        final canReview = status == 'submitted' || status == 'awaiting_review';
        final isCurrentRevision =
            revision.id == (summary.currentRevisionId ?? '');
        final canSubmitPlan = isCurrentRevision &&
            workflowState == 'planning' &&
            status == 'draft';
        final revisionActionPending = _hasBlockingMutation(
          eventsState,
          targetType: 'revision',
          targetId: revision.id,
        );
        return _SectionCard(
          title: 'Revision #${revision.number}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${revision.id}'),
              Text('状态: ${revision.status}'),
              Text(
                  '创建者: ${revision.createdBy.isEmpty ? '-' : revision.createdBy}'),
              if (revision.source.isNotEmpty) Text('来源: ${revision.source}'),
              if (revision.updatedAt.isNotEmpty)
                Text('更新时间: ${revision.updatedAt}'),
              if (revision.changeSummary.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '方案摘要',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  revision.changeSummary,
                  style: const TextStyle(color: Colors.black87, height: 1.45),
                ),
              ],
              if (revision.content.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '方案正文',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  revision.content,
                  style: const TextStyle(color: Colors.black87, height: 1.5),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => copyTextToClipboard(
                      context,
                      revision.content,
                      successMessage: '已复制方案正文',
                    ),
                    icon: const Icon(Icons.content_copy_rounded, size: 14),
                    label: const Text('复制方案正文'),
                  ),
                ),
              ],
              if (canReview) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _ActionButton(
                      label: '批准方案',
                      busy: _submitting,
                      disabledReason:
                          revisionActionPending ? '该方案版本有待确认动作，请先刷新' : null,
                      onPressed: revisionActionPending
                          ? null
                          : () => _runAction(
                                eventType: ApiClient.eventApprovePlan,
                                taskId: summary.taskId,
                                targetType: 'revision',
                                targetId: revision.id,
                                action: () => ref
                                    .read(apiClientProvider)
                                    .approveWorkflowRevision(
                                      summary.id,
                                      revisionId: revision.id,
                                    ),
                              ),
                    ),
                    _ActionButton(
                      label: '驳回方案',
                      busy: _submitting,
                      disabledReason:
                          revisionActionPending ? '该方案版本有待确认动作，请先刷新' : null,
                      onPressed: revisionActionPending
                          ? null
                          : () async {
                              final reason = await _askReason(
                                title: '驳回方案',
                                hintText: '请输入驳回原因',
                                requiredReason: true,
                              );
                              if (reason == null || reason.isEmpty) {
                                return;
                              }
                              await _runAction(
                                eventType: ApiClient.eventRejectPlan,
                                taskId: summary.taskId,
                                targetType: 'revision',
                                targetId: revision.id,
                                action: () => ref
                                    .read(apiClientProvider)
                                    .rejectWorkflowRevision(
                                      summary.id,
                                      revisionId: revision.id,
                                      comment: reason,
                                    ),
                              );
                            },
                    ),
                  ],
                ),
              ],
              if (canSubmitPlan) ...[
                const SizedBox(height: 10),
                _ActionButton(
                  label: '提交方案',
                  busy: _submitting,
                  disabledReason:
                      (revisionActionPending || workflowCommandPending)
                          ? '有待确认动作，请先刷新后再提交方案'
                          : null,
                  onPressed: (revisionActionPending || workflowCommandPending)
                      ? null
                      : () => _runAction(
                            eventType: ApiClient.eventSubmitPlan,
                            taskId: summary.taskId,
                            targetType: 'revision',
                            targetId: revision.id,
                            action: () => ref
                                .read(apiClientProvider)
                                .submitPlan(summary.id),
                          ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildExecutionTab(
    WorkflowGraph graph,
    WorkflowEventsState eventsState,
  ) {
    if (graph.nodes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _SectionCard(
            title: '执行步骤（node）',
            child: Text('当前还没有可展示的执行步骤。'),
          ),
        ],
      );
    }

    final nodes = [...graph.nodes]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: nodes.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        if (index == 0) {
          final producedCandidates = graph.candidates.where((candidate) {
            final status = candidate.status.toLowerCase();
            return status == 'produced' || status == 'approved';
          }).length;
          return _SectionCard(
            title: '执行步骤（node）',
            child: Text(
              '总计候选 ${graph.candidates.length}，已产出/已通过 $producedCandidates。',
            ),
          );
        }
        final node = nodes[index - 1];
        final nodeCandidates = graph.candidates
            .where((candidate) => candidate.nodeId == node.id)
            .toList();
        final latestCandidate =
            nodeCandidates.isEmpty ? null : nodeCandidates.last;
        final approvedCandidates = nodeCandidates
            .where((c) => c.status.toLowerCase() == 'approved')
            .toList();
        final latestApprovedCandidate =
            approvedCandidates.isEmpty ? null : approvedCandidates.last;
        final producedCandidates = nodeCandidates
            .where((c) => {
                  'produced',
                  'approved',
                }.contains(c.status.toLowerCase()))
            .toList();
        final latestProducedCandidate =
            producedCandidates.isEmpty ? null : producedCandidates.last;
        final nodeState = node.state.toLowerCase();

        // 判断可用动作（与后端状态机对齐：pending→ready→running）
        final canMakeReady = nodeState == 'pending';
        final canDispatch = nodeState == 'ready';
        final hasProduced =
            nodeCandidates.any((c) => c.status.toLowerCase() == 'produced');
        final canRegenerate =
            {'running', 'produced', 'failed', 'rejected'}.contains(nodeState) ||
                nodeCandidates.isNotEmpty;
        final nodeActionPending = _hasBlockingMutation(
          eventsState,
          targetType: 'node',
          targetId: node.id,
        );

        return _SectionCard(
          title:
              '${node.sequence}. ${node.title.isEmpty ? '未命名步骤' : node.title}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CopyableLine(label: 'ID', value: node.id),
              Text(
                '状态: ${node.state}',
                style: const TextStyle(color: Color(0xFF111827)),
              ),
              Text(
                '类型: ${node.kind.isEmpty ? '-' : node.kind}',
                style: const TextStyle(color: Color(0xFF111827)),
              ),
              Text(
                '执行方: ${node.assignee.isEmpty ? '-' : node.assignee}',
                style: const TextStyle(color: Color(0xFF111827)),
              ),
              Text(
                '候选数: ${nodeCandidates.length}'
                '（approved ${approvedCandidates.length} / produced ${producedCandidates.length}）',
                style: const TextStyle(color: Color(0xFF111827)),
              ),
              if (latestCandidate != null)
                Text(
                  '最新候选: ${latestCandidate.status}'
                  '${latestCandidate.summary.isEmpty ? '' : ' · ${latestCandidate.summary}'}',
                  style: const TextStyle(color: Color(0xFF334155)),
                ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '结果',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (latestApprovedCandidate != null) ...[
                      Text(
                        '已选结果：${latestApprovedCandidate.id}',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (latestApprovedCandidate.summary.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(
                            latestApprovedCandidate.summary,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (latestApprovedCandidate.artifacts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '产物数：${latestApprovedCandidate.artifacts.length}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        '该步骤已有有效结果，可进入「汇总」页继续审核。',
                        style:
                            TextStyle(color: Color(0xFF0F766E), fontSize: 12),
                      ),
                    ] else if (latestProducedCandidate != null) ...[
                      Text(
                        '已产出候选：${latestProducedCandidate.id}',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                        ),
                      ),
                      if (latestProducedCandidate.summary.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(
                            latestProducedCandidate.summary,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              height: 1.4,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '产物数：${latestProducedCandidate.artifacts.length}',
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '还未选定该候选，点击下方「选定候选」后才能进入稳定汇总。',
                        style:
                            TextStyle(color: Color(0xFF9A3412), fontSize: 12),
                      ),
                    ] else ...[
                      Text(
                        _executionNoResultHint(
                            nodeState, nodeCandidates.isNotEmpty),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (nodeCandidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '候选列表',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ...nodeCandidates.map((c) {
                  final status = c.status.toLowerCase();
                  final isSelected = status == 'approved';
                  final canComplete = status == 'queued' || status == 'running';
                  final candidateActionPending = _hasBlockingMutation(
                    eventsState,
                    targetType: 'candidate',
                    targetId: c.id,
                  );
                  final expanded = _expandedCandidateIds.contains(c.id);
                  final summary = c.summary.trim();
                  final preview = summary.isEmpty
                      ? '暂无摘要'
                      : (summary.length > 64
                          ? '${summary.substring(0, 64)}...'
                          : summary);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setState(() {
                              if (expanded) {
                                _expandedCandidateIds.remove(c.id);
                              } else {
                                _expandedCandidateIds.add(c.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.id,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$status · $preview',
                                        style: const TextStyle(
                                          color: Color(0xFF475569),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1FAE5),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      '已选中',
                                      style: TextStyle(
                                        color: Color(0xFF065F46),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                Icon(
                                  expanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: const Color(0xFF64748B),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (expanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 8),
                                Text(
                                  'provider: ${c.provider.isEmpty ? '-' : c.provider}',
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 12,
                                  ),
                                ),
                                if (c.score != null)
                                  Text(
                                    'score: ${c.score}',
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 12,
                                    ),
                                  ),
                                Text(
                                  'metrics: ${c.metrics.isEmpty ? '-' : c.metrics.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'artifacts: ${c.artifacts.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '结果详情',
                                  style: TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  summary.isEmpty ? '(空)' : summary,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (canComplete)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _ActionButton(
                                label:
                                    '完成候选 ${c.id.length > 6 ? c.id.substring(0, 6) : c.id}',
                                busy: _submitting,
                                disabledReason: (nodeActionPending ||
                                        candidateActionPending)
                                    ? '节点/候选有待确认动作，请先刷新'
                                    : null,
                                onPressed: (nodeActionPending ||
                                        candidateActionPending)
                                    ? null
                                    : () async {
                                        final resultSummary = await _askReason(
                                          title: '完成候选',
                                          hintText: '请输入候选产出摘要（可选）',
                                          requiredReason: false,
                                        );
                                        if (!mounted || resultSummary == null) {
                                          return;
                                        }
                                        await _runAction(
                                          eventType:
                                              ApiClient.eventCompleteCandidate,
                                          taskId: graph.workflow.taskId,
                                          targetType: 'candidate',
                                          targetId: c.id,
                                          action: () => ref
                                              .read(apiClientProvider)
                                              .completeWorkflowCandidate(
                                                graph.workflow.id,
                                                candidateId: c.id,
                                                status: 'produced',
                                                summary: resultSummary,
                                              ),
                                        );
                                      },
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // 推进节点到 ready（pending→ready）
                  if (canMakeReady)
                    _ActionButton(
                      label: '标记就绪',
                      busy: _submitting,
                      disabledReason:
                          nodeActionPending ? '该步骤有待确认动作，请先刷新' : null,
                      onPressed: nodeActionPending
                          ? null
                          : () => _runAction(
                                eventType: ApiClient.eventNodeProgress,
                                taskId: graph.workflow.taskId,
                                targetType: 'node',
                                targetId: node.id,
                                action: () => ref
                                    .read(apiClientProvider)
                                    .updateNodeProgress(
                                      graph.workflow.id,
                                      nodeId: node.id,
                                      toState: 'ready',
                                      reason: '前端手动就绪',
                                    ),
                              ),
                    ),
                  // 推进节点到 running（ready→running，触发 dispatch）
                  if (canDispatch)
                    _ActionButton(
                      label: '启动执行',
                      busy: _submitting,
                      disabledReason:
                          nodeActionPending ? '该步骤有待确认动作，请先刷新' : null,
                      onPressed: nodeActionPending
                          ? null
                          : () => _runAction(
                                eventType: ApiClient.eventNodeProgress,
                                taskId: graph.workflow.taskId,
                                targetType: 'node',
                                targetId: node.id,
                                action: () => ref
                                    .read(apiClientProvider)
                                    .updateNodeProgress(
                                      graph.workflow.id,
                                      nodeId: node.id,
                                      toState: 'running',
                                      reason: '前端手动启动',
                                    ),
                              ),
                    ),
                  // 选择候选（produced 状态的 candidate）
                  if (hasProduced)
                    ...nodeCandidates
                        .where((c) => c.status.toLowerCase() == 'produced')
                        .map(
                      (c) {
                        final candidateActionPending = _hasBlockingMutation(
                          eventsState,
                          targetType: 'candidate',
                          targetId: c.id,
                        );
                        return _ActionButton(
                          label:
                              '选定候选 ${c.id.length > 6 ? c.id.substring(0, 6) : c.id}',
                          busy: _submitting,
                          disabledReason:
                              (nodeActionPending || candidateActionPending)
                                  ? '节点/候选有待确认动作，请先刷新'
                                  : null,
                          onPressed: (nodeActionPending ||
                                  candidateActionPending)
                              ? null
                              : () => _runAction(
                                    eventType: ApiClient.eventSelectCandidate,
                                    taskId: graph.workflow.taskId,
                                    targetType: 'candidate',
                                    targetId: c.id,
                                    action: () => ref
                                        .read(apiClientProvider)
                                        .selectWorkflowCandidate(
                                          graph.workflow.id,
                                          nodeId: node.id,
                                          candidateId: c.id,
                                        ),
                                  ),
                        );
                      },
                    ),
                  // 重新生成候选
                  if (canRegenerate)
                    _ActionButton(
                      label: '重新生成',
                      busy: _submitting,
                      disabledReason:
                          nodeActionPending ? '该步骤有待确认动作，请先刷新' : null,
                      onPressed: nodeActionPending
                          ? null
                          : () async {
                              final comment = await _askReason(
                                title: '重新生成候选',
                                hintText: '补充说明（可选）',
                                requiredReason: false,
                              );
                              if (!mounted || comment == null) return;
                              await _runAction(
                                eventType: ApiClient.eventRegenerateNode,
                                taskId: graph.workflow.taskId,
                                targetType: 'node',
                                targetId: node.id,
                                action: () => ref
                                    .read(apiClientProvider)
                                    .regenerateWorkflowNodeCandidate(
                                      graph.workflow.id,
                                      nodeId: node.id,
                                      comment: comment,
                                    ),
                              );
                            },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAssemblyTab(
    Workflow summary,
    WorkflowGraph graph,
    WorkflowEventsState eventsState,
  ) {
    final assemblyId = summary.currentAssemblyId ?? '';
    final assemblies = graph.assemblies;
    final matchedAssembly = assemblies.where((item) => item.id == assemblyId);
    final currentAssembly = assemblyId.isEmpty
        ? (assemblies.isNotEmpty ? assemblies.last : null)
        : (matchedAssembly.isNotEmpty
            ? matchedAssembly.first
            : (assemblies.isNotEmpty ? assemblies.last : null));
    final assemblyDecisions = graph.decisions.where((decision) {
      return decision.targetType.toLowerCase() == 'assembly';
    }).toList();
    final assemblyActionPending = currentAssembly == null
        ? false
        : _hasBlockingMutation(
            eventsState,
            targetType: 'assembly',
            targetId: currentAssembly.id,
          );
    final rollbackPending = _hasBlockingMutation(
      eventsState,
      eventTypes: {'workflow.v2.command.rollback'},
      targetType: 'workflow',
      targetId: summary.id,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionCard(
          title: '最终汇总（assembly）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前汇总版本: ${assemblyId.isEmpty ? '-' : assemblyId}'),
              const SizedBox(height: 6),
              Text('汇总数量: ${assemblies.length}'),
              if (currentAssembly != null)
                Text(
                  '当前汇总状态: ${currentAssembly.status}'
                  '${currentAssembly.summary.isEmpty ? '' : ' · ${currentAssembly.summary}'}',
                ),
              const SizedBox(height: 6),
              const Text('可在下方执行通过、驳回或回滚操作。'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '汇总相关决策',
          child: assemblyDecisions.isEmpty
              ? const Text('暂无汇总相关 decision')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: assemblyDecisions
                      .take(5)
                      .map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${d.action} · ${d.actor.isEmpty ? '-' : d.actor} · ${d.targetId.isEmpty ? '-' : d.targetId}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 10),
        _SectionCard(
          title: '汇总操作',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: '通过汇总',
                busy: _submitting,
                disabledReason: currentAssembly == null
                    ? '当前没有可操作的汇总版本'
                    : (assemblyActionPending ? '汇总动作待确认，请先刷新' : null),
                onPressed: currentAssembly == null || assemblyActionPending
                    ? null
                    : () => _runAction(
                          eventType: ApiClient.eventApproveAssembly,
                          taskId: summary.taskId,
                          targetType: 'assembly',
                          targetId: currentAssembly.id,
                          action: () => ref
                              .read(apiClientProvider)
                              .approveWorkflowAssembly(
                                summary.id,
                                assemblyId: currentAssembly.id,
                              ),
                        ),
              ),
              _ActionButton(
                label: '驳回汇总',
                busy: _submitting,
                disabledReason: currentAssembly == null
                    ? '当前没有可操作的汇总版本'
                    : (assemblyActionPending ? '汇总动作待确认，请先刷新' : null),
                onPressed: currentAssembly == null || assemblyActionPending
                    ? null
                    : () async {
                        final reason = await _askReason(
                          title: '驳回汇总',
                          hintText: '请输入驳回原因',
                          requiredReason: false,
                        );
                        if (!mounted || reason == null) {
                          return;
                        }
                        await _runAction(
                          eventType: ApiClient.eventRejectAssembly,
                          taskId: summary.taskId,
                          targetType: 'assembly',
                          targetId: currentAssembly.id,
                          action: () => ref
                              .read(apiClientProvider)
                              .rejectWorkflowAssembly(
                                summary.id,
                                assemblyId: currentAssembly.id,
                                reason: reason,
                              ),
                        );
                      },
              ),
              _ActionButton(
                label: '回滚',
                busy: _submitting,
                disabledReason: rollbackPending ? '回滚动作待确认，请先刷新' : null,
                onPressed: rollbackPending
                    ? null
                    : () async {
                        final reason = await _askReason(
                          title: '回滚 workflow',
                          hintText: '请输入回滚原因（可选）',
                          requiredReason: false,
                        );
                        if (!mounted || reason == null) {
                          return;
                        }
                        await _runAction(
                          eventType: ApiClient.eventRollbackWorkflow,
                          taskId: summary.taskId,
                          targetType: 'workflow',
                          targetId: summary.id,
                          action: () =>
                              ref.read(apiClientProvider).rollbackWorkflow(
                                    summary.id,
                                    reason: reason,
                                  ),
                        );
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _pendingReviewCount(WorkflowGraph graph) {
    return graph.revisions.where((r) {
      final status = r.status.toLowerCase();
      return status == 'submitted' || status == 'awaiting_review';
    }).length;
  }

  int _runningNodeCount(WorkflowGraph graph) {
    return graph.nodes
        .where((n) => {
              'running',
              'in_progress',
              'executing',
              'doing',
            }.contains(n.state.toLowerCase()))
        .length;
  }

  String _executionNoResultHint(String nodeState, bool hasCandidates) {
    if (nodeState == 'pending') {
      return '该步骤尚未启动，暂无执行结果。请先点击「标记就绪」。';
    }
    if (nodeState == 'ready') {
      return '该步骤已就绪但未执行，暂无结果。请点击「启动执行」。';
    }
    if (nodeState == 'running') {
      return hasCandidates ? '该步骤执行中，候选正在生成，结果会在产出后展示。' : '该步骤执行中，暂未收到候选产出。';
    }
    if (nodeState == 'failed' || nodeState == 'rejected') {
      return '该步骤当前没有可用结果，可点击「重新生成」。';
    }
    return hasCandidates ? '当前候选尚未进入 produced/approved，暂无可展示结果。' : '暂无可展示结果。';
  }

  Widget _buildInteractionGuide(
    Workflow summary,
    WorkflowGraph graph,
    WorkflowEventsState eventsState,
  ) {
    final phase = _phaseLabel(summary.state);
    final suggestions = _suggestedActions(summary, graph);
    final blocking = eventsState.pendingMutations.values
        .where((m) => m.status == 'pending' || m.status == 'timed_out')
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final failed = eventsState.pendingMutations.values
        .where((m) => m.status == 'failed')
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('当前阶段：$phase'),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            '下一步建议',
            style: TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...suggestions.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('• $item'),
            ),
          ),
        ],
        if (blocking.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            '待确认动作（会导致对应按钮置灰）',
            style: TextStyle(
              color: Color(0xFF7C2D12),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...blocking.take(5).map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${_eventTypeLabel(m.eventType)}'
                    ' · ${m.status == 'timed_out' ? '超时待确认' : (m.acceptedAt != null ? '已入队待执行' : '等待确认')}'
                    '${_mutationTargetLabel(m).isEmpty ? '' : ' · ${_mutationTargetLabel(m)}'}',
                    style: const TextStyle(color: Color(0xFF7C2D12)),
                  ),
                ),
              ),
          if (blocking.length > 5)
            Text(
              '… 还有 ${blocking.length - 5} 条',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7C2D12)),
            ),
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            '确认失败动作（可重试）',
            style: TextStyle(
              color: Color(0xFFB91C1C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...failed.take(3).map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${_eventTypeLabel(m.eventType)} · ${_mutationTargetLabel(m)}',
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ),
              ),
        ],
      ],
    );
  }

  String _phaseLabel(String rawState) {
    final state = rawState.toLowerCase();
    if (state == 'draft') return '草稿（可开始规划）';
    if (state == 'planning') return '规划中（可提交方案）';
    if (state == 'awaiting_plan_review' || state == 'review') {
      return '方案待审核';
    }
    if (state == 'executing' || state == 'running') {
      return '执行中（推进节点与候选）';
    }
    if (state == 'blocked') return '阻塞（可恢复）';
    if (state == 'done') return '已完成';
    if (state == 'cancelled') return '已取消';
    return rawState;
  }

  List<String> _suggestedActions(Workflow summary, WorkflowGraph graph) {
    final state = summary.state.toLowerCase();
    if (state == 'draft') {
      return const ['点击「开始规划」，创建首个方案版本。'];
    }
    if (state == 'planning') {
      return const ['在「方案」确认正文后，点击「提交方案」进入待审核。'];
    }
    if (state == 'awaiting_plan_review' || state == 'review') {
      return const ['在「方案」中执行「批准方案 / 驳回方案」。'];
    }
    if (state == 'executing' || state == 'running') {
      final hasNodes = graph.nodes.isNotEmpty;
      final hasProduced =
          graph.candidates.any((c) => c.status.toLowerCase() == 'produced');
      final hasAssembly = (summary.currentAssemblyId ?? '').isNotEmpty ||
          graph.assemblies.isNotEmpty;
      final hints = <String>[];
      if (!hasNodes) {
        hints.add('当前还没有执行节点，等待后端拆解执行步骤。');
      } else {
        hints.add('在「执行」中按 pending→ready→running 推进节点。');
      }
      if (hasProduced) {
        hints.add('有 produced 候选时，优先执行「选定候选」。');
      }
      if (!hasAssembly) {
        hints.add('尚未生成汇总，需先选定候选后再到「汇总」操作。');
      } else {
        hints.add('在「汇总」执行通过/驳回，并查看最终输出。');
      }
      return hints;
    }
    if (state == 'blocked') {
      return const ['可先点击「恢复」继续流程，或点击「取消」结束。'];
    }
    if (state == 'done') {
      return const ['流程已结束，可在「汇总」查看结果并复制输出。'];
    }
    return const ['当前状态可先查看动态，确认最近事件后再操作。'];
  }

  String _eventTypeLabel(String eventType) {
    final e = eventType.toLowerCase();
    if (e.endsWith('start_planning')) return '开始规划';
    if (e.endsWith('submit_plan')) return '提交方案';
    if (e.endsWith('approve_plan')) return '批准方案';
    if (e.endsWith('reject_plan')) return '驳回方案';
    if (e.endsWith('approve_assembly')) return '通过汇总';
    if (e.endsWith('reject_assembly')) return '驳回汇总';
    if (e.endsWith('rollback')) return '回滚';
    if (e.endsWith('stop')) return '叫停';
    if (e.endsWith('cancel')) return '取消';
    if (e.endsWith('resume')) return '恢复';
    if (e.contains('node.progress') || e.contains('node_progress')) {
      return '推进节点';
    }
    if (e.contains('select_candidate')) return '选定候选';
    if (e.contains('candidate.complete') || e.contains('complete_candidate')) {
      return '完成候选';
    }
    if (e.contains('decision.regenerate') || e.contains('regenerate_node')) {
      return '重新生成';
    }
    return eventType;
  }

  String _mutationTargetLabel(PendingWorkflowMutation mutation) {
    final type = (mutation.targetType ?? '').trim();
    final id = (mutation.targetId ?? '').trim();
    if (type.isEmpty || id.isEmpty) {
      return '';
    }
    final shortId = id.length > 12 ? id.substring(0, 12) : id;
    return '$type:$shortId';
  }

  bool _hasBlockingMutation(
    WorkflowEventsState eventsState, {
    Set<String>? eventTypes,
    String? eventTypePrefix,
    String? targetType,
    String? targetId,
  }) {
    final eventTypeSet =
        eventTypes?.map((item) => item.toLowerCase()).toSet() ?? const {};
    final normalizedPrefix = (eventTypePrefix ?? '').toLowerCase();
    final normalizedTargetType = (targetType ?? '').toLowerCase();
    final normalizedTargetId = (targetId ?? '').toLowerCase();

    for (final mutation in eventsState.pendingMutations.values) {
      if (mutation.status != 'pending' && mutation.status != 'timed_out') {
        continue;
      }
      final mutationEventType = mutation.eventType.toLowerCase();
      if (eventTypeSet.isNotEmpty &&
          !eventTypeSet.contains(mutationEventType)) {
        continue;
      }
      if (normalizedPrefix.isNotEmpty &&
          !mutationEventType.startsWith(normalizedPrefix)) {
        continue;
      }
      if (normalizedTargetType.isNotEmpty &&
          (mutation.targetType ?? '').toLowerCase() != normalizedTargetType) {
        continue;
      }
      if (normalizedTargetId.isNotEmpty &&
          (mutation.targetId ?? '').toLowerCase() != normalizedTargetId) {
        continue;
      }
      return true;
    }
    return false;
  }

  Widget _buildTimelineTab(List<WorkflowTimelineEvent> timeline) {
    if (timeline.isEmpty) {
      return const Center(child: Text('暂无动态事件'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: timeline.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final event = timeline[index];
        return _SectionCard(
          title: event.kind.isEmpty ? 'event' : event.kind,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.id.isNotEmpty)
                _CopyableLine(label: 'ID', value: event.id),
              if (event.at.isNotEmpty) Text('时间: ${event.at}'),
              if (event.action.isNotEmpty) Text('动作: ${event.action}'),
              if (event.actor.isNotEmpty) Text('执行者: ${event.actor}'),
              if (event.targetType.isNotEmpty || event.targetId.isNotEmpty)
                Text('目标: ${event.targetType}/${event.targetId}'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runAction({
    required String eventType,
    required String taskId,
    String? targetType,
    String? targetId,
    required Future<ActionResult> Function() action,
  }) async {
    if (_submitting) return; // 防重入
    final baseProjectionVersion =
        ref.read(taskByIdProvider(taskId))?.projectionVersion;
    setState(() => _submitting = true);
    final result = await action();
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);

    if (result.ok) {
      final mutationId = (result.entryId ?? '').isNotEmpty
          ? result.entryId!
          : 'local-${DateTime.now().microsecondsSinceEpoch}';
      ref
          .read(workflowEventsProvider(widget.workflowId).notifier)
          .registerPendingMutation(
            mutationId: mutationId,
            eventType: eventType,
            taskId: taskId,
            targetType: targetType,
            targetId: targetId,
          );
      ref.read(workflowProjectionSyncProvider.notifier).markSyncing(
            workflowId: widget.workflowId,
            taskId: taskId,
            baseProjectionVersion: baseProjectionVersion,
          );
      await ref
          .read(workflowEventsProvider(widget.workflowId).notifier)
          .reconcileNow();
      _showSnack(result.message ?? '指令已提交（accepted）');
      return;
    }
    _showSnack(result.error ?? '操作失败', isError: true);
  }

  Future<String?> _askReason({
    required String title,
    required String hintText,
    required bool requiredReason,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: hintText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (requiredReason && reason.isEmpty) {
                return;
              }
              Navigator.of(context).pop(reason);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (isError && message.length > 80) {
      // 长错误用可滚动弹窗，避免 SnackBar 截断关键信息
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('操作失败'),
          content: SingleChildScrollView(
            child: SelectableText(
              message,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 4, overflow: TextOverflow.ellipsis),
        duration: Duration(seconds: isError ? 5 : 2),
        backgroundColor: isError ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  String _syncHintText(WorkflowEventsState eventsState) {
    final pending = eventsState.pendingMutations.values
        .where((m) => m.status == 'pending')
        .toList();
    final acceptedPending = pending.where((m) => m.acceptedAt != null).length;
    final timedOut = eventsState.pendingMutations.values
        .where((m) => m.status == 'timed_out')
        .length;
    final failed = eventsState.pendingMutations.values
        .where((m) => m.status == 'failed')
        .length;

    if (timedOut > 0) {
      return '有 $timedOut 个动作状态待确认，请手动刷新核对';
    }
    if (failed > 0) {
      return '有 $failed 个动作确认失败，请重试';
    }
    if (pending.isNotEmpty) {
      final now = DateTime.now();
      final hasOver3s = pending.any(
        (m) => now.difference(m.startedAt) > const Duration(seconds: 3),
      );
      if (acceptedPending > 0) {
        return '已入队 $acceptedPending 个动作，等待执行结果同步';
      }
      return hasOver3s ? '同步中... 已提交动作正在等待服务端确认' : '已提交动作，正在等待确认';
    }
    return '检测到 workflow 变更，正在对账刷新';
  }

  String _overviewStageText(Workflow summary, WorkflowGraph graph) {
    final state = summary.state.toLowerCase();
    if (state == 'planning') {
      return '方案正在生成与迭代中，当前 revision=${summary.currentRevisionId ?? '-'}。';
    }
    if (state == 'awaiting_plan_review' || state == 'review') {
      return '当前方案待审批，批准后会自动进入执行步骤拆解。';
    }
    if (state == 'executing' || state == 'running') {
      return '流程已进入执行阶段，当前运行节点 ${_runningNodeCount(graph)} 个。';
    }
    if (state == 'done') {
      return '流程已完成，可在汇总页查看最终结果。';
    }
    if (state == 'cancelled') {
      return '流程已取消，可按需重新发起。';
    }
    return 'workflow 已创建，等待下一步动作推进。';
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.state,
    required this.workflowId,
    required this.revisionId,
    required this.showBack,
  });

  final String title;
  final String state;
  final String workflowId;
  final String? revisionId;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: MobileUiTokens.pageBg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: MobileUiTokens.heading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StateChip(text: state),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'workflowId · $workflowId · 当前 ${revisionId ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MobileUiTokens.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => copyTextToClipboard(
                  context,
                  workflowId,
                  successMessage: '已复制 workflowId',
                ),
                tooltip: '复制 workflowId',
                icon: const Icon(
                  Icons.content_copy_rounded,
                  size: 16,
                  color: MobileUiTokens.muted,
                ),
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final label = _stateLabel(text);
    Color bg = const Color(0xFFF5F5F4);
    Color fg = const Color(0xFF57534E);
    if (lower.contains('running') || lower.contains('execut')) {
      bg = const Color(0xFFDDF6EA);
      fg = const Color(0xFF047857);
    } else if (lower.contains('review') || lower.contains('plan')) {
      bg = const Color(0xFFEEF2FF);
      fg = const Color(0xFF3730A3);
    } else if (lower.contains('cancel') || lower.contains('block')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFB91C1C);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _stateLabel(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('execut') || value.contains('running')) {
      return '执行中';
    }
    if (value.contains('review') ||
        value.contains('plan') ||
        value.contains('await')) {
      return '待审批';
    }
    if (value.contains('done')) {
      return '已完成';
    }
    if (value.contains('cancel')) {
      return '已取消';
    }
    if (value.contains('block')) {
      return '已阻塞';
    }
    return raw;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MobileUiTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MobileUiTokens.border),
        boxShadow: const [MobileUiTokens.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _CopyableLine extends StatelessWidget {
  const _CopyableLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = value.trim();
    final copyable = text.isNotEmpty && text != '-';
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            '$label: $value',
            style: const TextStyle(color: Color(0xFF111827)),
          ),
        ),
        IconButton(
          onPressed: copyable
              ? () => copyTextToClipboard(
                    context,
                    text,
                    successMessage: '已复制$label',
                  )
              : null,
          tooltip: '复制$label',
          icon: const Icon(Icons.content_copy_rounded, size: 15),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.busy,
    required this.onPressed,
    this.disabledReason,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = busy ? null : onPressed;
    final tooltipMessage = busy
        ? '提交中，请稍候'
        : (effectiveOnPressed == null
            ? (disabledReason?.trim().isNotEmpty == true
                ? disabledReason!.trim()
                : '当前不可操作，请先完成上一步或点击刷新')
            : '');
    final button = OutlinedButton(
      onPressed: effectiveOnPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: MobileUiTokens.primary,
        side: const BorderSide(color: Color(0xFFD8D6F7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(busy ? '提交中...' : label),
    );
    if (tooltipMessage.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltipMessage, child: button);
  }
}

class _WorkflowSyncBanner extends StatelessWidget {
  const _WorkflowSyncBanner({
    required this.hintText,
    required this.pendingMutations,
    required this.onRefresh,
  });

  final String hintText;
  final Map<String, PendingWorkflowMutation> pendingMutations;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final pending = pendingMutations.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_rounded,
                  size: 14, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hintText,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF7C2D12)),
                ),
              ),
              TextButton(
                onPressed: onRefresh,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('立即刷新'),
              ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pending
                  .take(4)
                  .map(
                    (m) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        '${m.eventType.split('.').last} · ${m.status}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9A3412)),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkflowRecentEventsPanel extends StatelessWidget {
  const _WorkflowRecentEventsPanel({
    required this.lastEventType,
    required this.recentEventKeys,
  });

  final String? lastEventType;
  final List<String> recentEventKeys;

  @override
  Widget build(BuildContext context) {
    final recent = recentEventKeys.reversed.take(8).toList();
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      title: Text(
        '最近事件（${recentEventKeys.length}）',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        lastEventType ?? '-',
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      ),
      children: [
        for (final key in recent)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                key,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text),
      ),
    );
  }
}
