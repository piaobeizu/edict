import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../providers/api_provider.dart';
import '../../providers/live_status_provider.dart';
import '../../providers/task_detail_provider.dart';
import 'mobile_ui_kit.dart';
import 'mobile_surface.dart';

class MobileTaskDetailScreen extends ConsumerStatefulWidget {
  const MobileTaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<MobileTaskDetailScreen> createState() =>
      _MobileTaskDetailScreenState();
}

class _MobileTaskDetailScreenState extends ConsumerState<MobileTaskDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _busyAction = false;

  static const _bgColor = Color(0xFFFAFAF9);
  static const _lineColor = Color(0xFFF0EEEB);
  static const _textMain = Color(0xFF1C1917);
  static const _textSub = Color(0xFF78716C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(taskByIdProvider(widget.taskId));
    final taskActivityAsync = ref.watch(taskActivityProvider(widget.taskId));

    if (task == null) {
      return Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          foregroundColor: _textMain,
          elevation: 0,
          title: const Text('任务详情'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final pipe = getPipeStatus(task);
    final activeStage = pipe.firstWhere(
      (node) => node.status == PipeNodeStatus.active,
      orElse: () => pipe[math.max(0, pipe.length - 1)],
    );

    final dept = activeStage.dept;
    final isTerminal = task.state == 'Done' || task.state == 'Cancelled';
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: _bgColor,
        body: MobileImmersiveBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: _textMain,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(
                    task.title.isEmpty ? '(无标题任务)' : task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textMain,
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    children: [
                      _StatePill(state: task.state),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$dept · ${extractAgent(task)} · ${task.eta.isEmpty ? '预计处理中' : task.eta}',
                          style: const TextStyle(
                            color: _textSub,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEEFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4338CA).withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: const Color(0xFF5B57A7),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    labelPadding: EdgeInsets.zero,
                    tabs: const [
                      Tab(text: '概览'),
                      Tab(text: '结果'),
                      Tab(text: '流程'),
                      Tab(text: '活动'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(task, activeStage),
                      _buildResultTab(task, taskActivityAsync, isTerminal),
                      _buildFlowTab(task),
                      _buildActivityTab(taskActivityAsync),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(Task task, PipeStatus activeStage) {
    final todos = task.todos;
    final done = todos.where((e) => e.status == TodoStatus.completed).length;
    final progress = todos.isEmpty ? 0.0 : done / todos.length;
    final stageIndex = _simpleStageIndex(task.state);
    const simpleStages = <String>['分拣', '规划', '审议', '派发', '执行', '审查', '完成'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前阶段',
                style: TextStyle(
                  color: _textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${activeStage.icon} ${activeStage.dept} · ${activeStage.key}正在处理中',
                style: const TextStyle(
                  fontSize: 16,
                  color: _textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '当前动作：${activeStage.action}',
                style: const TextStyle(color: _textSub),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '流程进度',
                style: TextStyle(
                  color: _textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(simpleStages.length, (i) {
                    final active = i == stageIndex;
                    final done = i < stageIndex;
                    final color = active
                        ? const Color(0xFF6A9EFF)
                        : done
                            ? const Color(0xFF2ECC8A)
                            : const Color(0xFFD4CCBE);
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Container(
                            width: active ? 14 : 10,
                            height: active ? 14 : 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            simpleStages[i],
                            style: TextStyle(
                              color: active ? _textMain : _textSub,
                              fontSize: 11,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '关键信息',
                style: TextStyle(
                  color: _textMain,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child:
                        _infoCell('状态', kStateLabel[task.state] ?? task.state),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _infoCell('部门', activeStage.dept)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child:
                          _infoCell('ETA', task.eta.isEmpty ? '-' : task.eta)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _infoCell(
                      '阻塞',
                      task.block.isEmpty || task.block == '-'
                          ? '无'
                          : task.block,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (todos.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('待办进度',
                        style: TextStyle(
                            color: _textMain, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                      '$done / ${todos.length}',
                      style: const TextStyle(color: _textSub),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFF0EBE2),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF6A9EFF)),
                  ),
                ),
                const SizedBox(height: 12),
                ...todos.map((item) {
                  final isDone = item.status == TodoStatus.completed;
                  final isDoing = item.status == TodoStatus.inProgress;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isDone
                              ? Icons.check_circle_rounded
                              : isDoing
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: isDone
                              ? const Color(0xFF2ECC8A)
                              : isDoing
                                  ? const Color(0xFF6A9EFF)
                                  : _textSub,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              color: isDone ? _textSub : _textMain,
                              decoration:
                                  isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildActionButtons(task),
      ],
    );
  }

  Widget _buildActionButtons(Task task) {
    final canStop =
        !<String>{'Done', 'Blocked', 'Cancelled'}.contains(task.state);
    final canCancel = !<String>{'Done', 'Cancelled'}.contains(task.state);
    final canResume = <String>{'Blocked', 'Cancelled'}.contains(task.state);

    if (!canStop && !canCancel && !canResume) {
      return const SizedBox.shrink();
    }

    return _card(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (canStop)
            MobileOutlineButton(
              label: '叫停',
              icon: Icons.pause_circle_outline_rounded,
              onPressed: _busyAction
                  ? null
                  : () => _doTaskAction(task, 'stop', '叫停任务'),
            ),
          if (canCancel)
            MobileOutlineButton(
              label: '取消',
              icon: Icons.cancel_outlined,
              onPressed: _busyAction
                  ? null
                  : () => _doTaskAction(task, 'cancel', '取消任务'),
            ),
          if (canResume)
            MobileOutlineButton(
              label: '恢复',
              icon: Icons.play_circle_outline_rounded,
              onPressed: _busyAction
                  ? null
                  : () => _doTaskAction(task, 'resume', '恢复执行'),
            ),
        ],
      ),
    );
  }

  Widget _buildResultTab(
    Task task,
    AsyncValue<TaskActivityData> taskActivityAsync,
    bool isTerminal,
  ) {
    final output = task.output.trim();
    final hasOutput = output.isNotEmpty && output != '-';
    final summary = _extractSummary(output);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (hasOutput)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '摘要结论',
                  style: TextStyle(
                    color: _textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  summary,
                  style: const TextStyle(
                    fontSize: 17,
                    color: _textMain,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    MobileOutlineButton(
                      label: '复制',
                      icon: Icons.copy_rounded,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: output));
                        _showSnack('结果已复制');
                      },
                    ),
                    const SizedBox(width: 10),
                    MobileOutlineButton(
                      label: '分享',
                      icon: Icons.ios_share_rounded,
                      onPressed: () => _showSnack('分享功能即将支持'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: _lineColor),
                const SizedBox(height: 14),
                const Text(
                  '执行输出（节选）',
                  style:
                      TextStyle(color: _textMain, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F7F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _lineColor),
                  ),
                  child: SelectableText(
                    output,
                    style: const TextStyle(
                      color: _textMain,
                      height: 1.65,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('结果尚未生成',
                    style: TextStyle(
                      color: _textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 10),
                Text(
                  task.now.isEmpty ? '正在处理任务...' : task.now,
                  style: const TextStyle(color: _textSub, height: 1.5),
                ),
                if (!isTerminal) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Color(0xFFF0EBE2),
                    valueColor: AlwaysStoppedAnimation(Color(0xFF6A9EFF)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        _card(
          child: taskActivityAsync.when(
            data: (data) {
              final artifacts = data.artifacts ?? const <ArtifactInfo>[];
              if (artifacts.isEmpty) {
                return const Text(
                  '暂无产出附件',
                  style: TextStyle(color: _textSub),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('产出附件',
                      style: TextStyle(
                          color: _textMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...artifacts.map(_artifactRow),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text(
              '加载产物失败：$error',
              style: const TextStyle(color: Color(0xFFBE3B3B)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _artifactRow(ArtifactInfo artifact) {
    final fileName = artifact.path.split('/').last;
    final canDownload = artifact.downloadable == true ||
        RegExp(r'^https?://').hasMatch(artifact.path.trim());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F7F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _lineColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, color: _textSub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName.isEmpty ? artifact.path : fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _textMain, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  artifact.kind ?? '大小未知',
                  style: const TextStyle(color: _textSub, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MobileOutlineButton(
            label: '下载',
            onPressed: canDownload ? () => _downloadArtifact(artifact) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFlowTab(Task task) {
    if (task.flowLog.isEmpty) {
      return const Center(
        child: Text('暂无流程记录', style: TextStyle(color: _textSub)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: task.flowLog.length,
      itemBuilder: (context, index) {
        final entry = task.flowLog[index];
        final current =
            entry.to == task.state || index == task.flowLog.length - 1;
        final fromIdx = kPipeStateIdx[entry.from] ?? 0;
        final toIdx = kPipeStateIdx[entry.to] ?? 0;
        final rejectLike = toIdx < fromIdx ||
            (entry.remark ?? '').contains('驳') ||
            (entry.reason ?? '').contains('reject');
        final dotColor =
            rejectLike ? const Color(0xFFE45757) : const Color(0xFF2ECC8A);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Container(
                    width: current ? 14 : 10,
                    height: current ? 14 : 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: current
                          ? [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.28),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  if (index != task.flowLog.length - 1)
                    Container(
                      width: 2,
                      height: 78,
                      color: _lineColor,
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_pipeLabel(entry.from)} → ${_pipeLabel(entry.to)}',
                        style: TextStyle(
                          color: _textMain,
                          fontWeight:
                              current ? FontWeight.w800 : FontWeight.w700,
                          fontSize: current ? 16 : 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatFlowTime(entry.at ?? entry.ts),
                        style: const TextStyle(color: _textSub, fontSize: 12),
                      ),
                      if ((entry.remark ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(entry.remark!,
                            style:
                                const TextStyle(color: _textSub, height: 1.4)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActivityTab(AsyncValue<TaskActivityData> taskActivityAsync) {
    return taskActivityAsync.when(
      data: (data) {
        final list = [...?data.activity];
        if (list.isEmpty) {
          return const Center(
            child: Text('暂无活动日志', style: TextStyle(color: _textSub)),
          );
        }
        list.sort((a, b) => _activityMs(b.at).compareTo(_activityMs(a.at)));

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final entry = list[index];
            final preview = _activityPreview(entry);
            final full = _activityFullText(entry);
            return _card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                title: Row(
                  children: [
                    Text(_kindEmoji(entry.kind),
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMain,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${entry.agent ?? 'system'} · ${_formatActivityTime(entry.at)}',
                    style: const TextStyle(color: _textSub, fontSize: 12),
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      full,
                      style: const TextStyle(color: _textSub, height: 1.5),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('活动日志加载失败：$error',
            style: const TextStyle(color: Color(0xFFBE3B3B))),
      ),
    );
  }

  Future<void> _doTaskAction(Task task, String action, String label) async {
    setState(() => _busyAction = true);
    final api = ref.read(apiClientProvider);
    final result = await api.taskAction(task.id, action, label);
    if (!mounted) return;
    setState(() => _busyAction = false);

    if (result.ok) {
      _showSnack(result.message ?? '$label 已提交');
      ref.invalidate(liveStatusProvider);
      unawaited(ref.read(taskActivityProvider(task.id).notifier).refresh());
      return;
    }
    _showSnack(result.error ?? '$label 失败');
  }

  Future<void> _downloadArtifact(ArtifactInfo artifact) async {
    final api = ref.read(apiClientProvider);
    final raw = artifact.path.trim();
    final url = RegExp(r'^https?://').hasMatch(raw)
        ? raw
        : api.artifactDownloadUrl(raw);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('下载链接无效');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('无法打开下载链接');
    }
  }

  Widget _infoCell(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF9F7F2),
        border: Border.all(color: _lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _textSub,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textMain,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      child: MobileSurfaceCard(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final label = kStateLabel[state] ?? state;
    final (bg, fg) = switch (state) {
      'Done' => (const Color(0xFFEAF9F1), const Color(0xFF1F9D63)),
      'Blocked' || 'Cancelled' => (
          const Color(0xFFFDECEC),
          const Color(0xFFC43F3F)
        ),
      'Doing' => (const Color(0xFFEFF5FF), const Color(0xFF346EDB)),
      _ => (const Color(0xFFF4EFE6), const Color(0xFF7A6B57)),
    };
    return MobilePillTag(
      text: label,
      background: bg,
      foreground: fg,
    );
  }
}

String _extractSummary(String output) {
  final text = output.trim();
  if (text.isEmpty) return '暂无摘要';
  final byParagraph = text.split(RegExp(r'\n\s*\n')).first.trim();
  return byParagraph.isEmpty ? text.split('\n').first : byParagraph;
}

String _pipeLabel(String state) => kStateLabel[state] ?? state;

int _simpleStageIndex(String state) {
  switch (state) {
    case 'Inbox':
    case 'Pending':
    case 'Taizi':
      return 0;
    case 'Zhongshu':
      return 1;
    case 'Menxia':
    case 'YuLan':
      return 2;
    case 'Assigned':
    case 'Next':
      return 3;
    case 'Doing':
    case 'Blocked':
    case 'Cancelled':
      return 4;
    case 'Review':
      return 5;
    case 'Done':
      return 6;
    default:
      return 0;
  }
}

int _activityMs(dynamic at) {
  if (at is num) return at.toInt();
  if (at == null) return 0;
  return DateTime.tryParse(at.toString())?.millisecondsSinceEpoch ?? 0;
}

String _formatActivityTime(dynamic at) {
  if (at is num) {
    final dt = DateTime.fromMillisecondsSinceEpoch(at.toInt()).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
  final s = at?.toString() ?? '';
  if (s.contains('T')) {
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt != null) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    }
  }
  return s.length > 8 ? s.substring(0, 8) : s;
}

String _kindEmoji(String kind) {
  switch (kind) {
    case 'progress':
      return '🔄';
    case 'assistant':
      return '🤖';
    case 'tool_result':
      return '🔧';
    case 'user':
      return '📥';
    case 'todos':
      return '📝';
    default:
      return '•';
  }
}

String _activityPreview(ActivityEntry e) {
  if ((e.text ?? '').isNotEmpty) return e.text!;
  if ((e.thinking ?? '').isNotEmpty) return e.thinking!;
  if ((e.output ?? '').isNotEmpty) return e.output!;
  if ((e.remark ?? '').isNotEmpty) return e.remark!;
  if ((e.tool ?? '').isNotEmpty) return e.tool!;
  return e.kind;
}

String _activityFullText(ActivityEntry e) {
  final chunks = <String>[
    if ((e.text ?? '').isNotEmpty) e.text!,
    if ((e.thinking ?? '').isNotEmpty) e.thinking!,
    if ((e.output ?? '').isNotEmpty) e.output!,
    if ((e.remark ?? '').isNotEmpty) e.remark!,
    if ((e.tool ?? '').isNotEmpty) 'tool: ${e.tool}',
    if ((e.from ?? '').isNotEmpty || (e.to ?? '').isNotEmpty)
      '${e.from ?? '-'} -> ${e.to ?? '-'}',
  ];
  return chunks.isEmpty ? e.kind : chunks.join('\n\n');
}

String _formatFlowTime(String? atOrTs) {
  if (atOrTs == null || atOrTs.isEmpty) return '-';
  final d = DateTime.tryParse(atOrTs);
  if (d == null) {
    return atOrTs.length > 19 ? atOrTs.substring(0, 19) : atOrTs;
  }
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
