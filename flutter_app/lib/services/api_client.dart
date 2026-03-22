import 'dart:convert' as convert;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, message: $message)';
}

class ApiClient {
  static const String eventStartPlanning = 'workflow.v2.command.start_planning';
  static const String eventSubmitPlan = 'workflow.v2.command.submit_plan';
  static const String eventApprovePlan = 'workflow.v2.command.approve_plan';
  static const String eventRejectPlan = 'workflow.v2.command.reject_plan';
  static const String eventStopWorkflow = 'workflow.v2.command.stop';
  static const String eventCancelWorkflow = 'workflow.v2.command.cancel';
  static const String eventResumeWorkflow = 'workflow.v2.command.resume';
  static const String eventNodeProgress = 'workflow.v2.command.node_progress';
  static const String eventCompleteCandidate =
      'workflow.v2.command.complete_candidate';
  static const String eventSelectCandidate =
      'workflow.v2.command.select_candidate';
  static const String eventRegenerateNode =
      'workflow.v2.command.regenerate_node';
  static const String eventApproveAssembly =
      'workflow.v2.command.approve_assembly';
  static const String eventRejectAssembly =
      'workflow.v2.command.reject_assembly';
  static const String eventRollbackWorkflow = 'workflow.v2.command.rollback';

  ApiClient({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? _defaultBaseUrl(),
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 15),
                contentType: Headers.jsonContentType,
                responseType: ResponseType.json,
              ),
            ) {
    if (dio != null && baseUrl != null && baseUrl.isNotEmpty) {
      _dio.options.baseUrl = baseUrl;
    }
  }

  final Dio _dio;

  static String _defaultBaseUrl() {
    if (kIsWeb) {
      return '';
    }
    // Android/iOS 连接服务器地址（通过 nginx 代理 API）
    return 'http://35.241.111.186:8002';
  }

  String get baseUrl => _dio.options.baseUrl;

  String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = _dio.options.baseUrl;
    if (base.isEmpty) {
      return path;
    }
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final baseUri = Uri.parse(base.endsWith('/') ? base : '$base/');
    return baseUri.resolve(normalized).toString();
  }

  Future<LiveStatus> liveStatus() =>
      _getModel('/api/tasks/live-status', LiveStatus.fromJson);

  Future<AgentConfig> agentConfig() =>
      _getModel('/api/agent-config', AgentConfig.fromJson);

  Future<List<ChangeLogEntry>> modelChangeLog() async {
    try {
      final response = await _dio.get<dynamic>('/api/model-change-log');
      final list = (response.data as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) =>
              entry.map((key, value) => MapEntry(key.toString(), value)))
          .map(ChangeLogEntry.fromJson)
          .toList();
      return list;
    } catch (_) {
      return <ChangeLogEntry>[];
    }
  }

  Future<OfficialsData> officialsStats() =>
      _getModel('/api/officials-stats', OfficialsData.fromJson);

  Future<MorningBrief> morningBrief() =>
      _getModel('/api/morning-brief', MorningBrief.fromJson);

  Future<SubConfig> morningConfig() =>
      _getModel('/api/morning-config', SubConfig.fromJson);

  Future<AgentsStatusData> agentsStatus() =>
      _getModel('/api/agents-status', AgentsStatusData.fromJson);

  Future<TaskActivityData> taskActivity(String id) => _getModel(
        '/api/task-activity/${Uri.encodeComponent(id)}',
        TaskActivityData.fromJson,
        onError: (message) => TaskActivityData.fromJson(
            <String, dynamic>{'ok': false, 'error': message}),
      );

  Future<SchedulerStateData> schedulerState(String id) => _getModel(
        '/api/scheduler-state/${Uri.encodeComponent(id)}',
        SchedulerStateData.fromJson,
        onError: (message) => SchedulerStateData.fromJson(
          <String, dynamic>{'ok': false, 'error': message},
        ),
      );

  Future<SkillContentResult> skillContent(String agentId, String skillName) =>
      _getModel(
        '/api/skill-content/${Uri.encodeComponent(agentId)}/${Uri.encodeComponent(skillName)}',
        SkillContentResult.fromJson,
        onError: (message) => SkillContentResult.fromJson(
            <String, dynamic>{'ok': false, 'error': message}),
      );

  Future<RemoteSkillsListResult> remoteSkillsList() => _getModel(
        '/api/remote-skills-list',
        RemoteSkillsListResult.fromJson,
        onError: (message) => RemoteSkillsListResult.fromJson(
            <String, dynamic>{'ok': false, 'error': message}),
      );

  Future<NotifyChannelsResult> notifyChannels() => _getModel(
        '/api/notify-channels',
        NotifyChannelsResult.fromJson,
        onError: (message) => NotifyChannelsResult.fromJson(
            <String, dynamic>{'ok': false, 'error': message}),
      );

  String artifactDownloadUrl(String path) {
    final encodedPath = Uri.encodeQueryComponent(path);
    if (baseUrl.isEmpty) {
      return '/api/files/download?path=$encodedPath';
    }
    final baseUri = Uri.parse(baseUrl);
    final uri = baseUri.resolve('/api/files/download').replace(
      queryParameters: <String, String>{'path': path},
    );
    return uri.toString();
  }

  Future<ActionResult> setModel(String agentId, String model) => _postAction(
      '/api/set-model', <String, dynamic>{'agentId': agentId, 'model': model});

  Future<ActionResult> agentWake(String agentId) =>
      _postAction('/api/agent-wake', <String, dynamic>{'agentId': agentId});

  Future<ActionResult> taskAction(
          String taskId, String action, String reason) =>
      _postAction(
        '/api/task-action',
        <String, dynamic>{'taskId': taskId, 'action': action, 'reason': reason},
      );

  Future<ActionResult> reviewAction(
          String taskId, String action, String comment) =>
      _postAction(
        '/api/review-action',
        <String, dynamic>{
          'taskId': taskId,
          'action': action,
          'comment': comment
        },
      );

  Future<ActionResult> advanceState(String taskId, String comment) =>
      _postAction('/api/advance-state',
          <String, dynamic>{'taskId': taskId, 'comment': comment});

  Future<ActionResult> archiveTask(String taskId, bool archived) => _postAction(
      '/api/archive-task',
      <String, dynamic>{'taskId': taskId, 'archived': archived});

  Future<ActionResult> archiveAllDone() => _postAction(
      '/api/archive-task', <String, dynamic>{'archiveAllDone': true});

  Future<ActionResult> schedulerScan({int thresholdSec = 180}) => _postAction(
      '/api/scheduler-scan', <String, dynamic>{'thresholdSec': thresholdSec});

  Future<ActionResult> schedulerRetry(String taskId, String reason) =>
      _postAction('/api/scheduler-retry',
          <String, dynamic>{'taskId': taskId, 'reason': reason});

  Future<ActionResult> schedulerEscalate(String taskId, String reason) =>
      _postAction('/api/scheduler-escalate',
          <String, dynamic>{'taskId': taskId, 'reason': reason});

  Future<ActionResult> schedulerRollback(String taskId, String reason) =>
      _postAction('/api/scheduler-rollback',
          <String, dynamic>{'taskId': taskId, 'reason': reason});

  Future<ActionResult> dispatchTask(
      String taskId, String agent, String message) async {
    final endpoint = '/api/tasks/${Uri.encodeComponent(taskId)}/dispatch';
    try {
      final response = await _dio.post<dynamic>(
        endpoint,
        queryParameters: <String, dynamic>{'agent': agent, 'message': message},
      );
      final data = _asMap(response.data);
      if (data['ok'] is bool) {
        return ActionResult.fromJson(data);
      }
      final normalized = <String, dynamic>{'ok': true, ...data};
      return ActionResult.fromJson(normalized);
    } catch (e) {
      return _errorActionResult(_extractErrorMessage(e));
    }
  }

  Future<ActionResult> refreshMorning() =>
      _postAction('/api/morning-brief/refresh', const <String, dynamic>{});

  Future<ActionResult> saveMorningConfig(SubConfig config) =>
      _postAction('/api/morning-config', config.toJson());

  Future<ActionResult> addSkill(
    String agentId,
    String skillName,
    String description,
    String trigger,
  ) =>
      _postAction(
        '/api/add-skill',
        <String, dynamic>{
          'agentId': agentId,
          'skillName': skillName,
          'description': description,
          'trigger': trigger,
        },
      );

  Future<ActionResult> addRemoteSkill(
    String agentId,
    String skillName,
    String sourceUrl,
    String description,
  ) =>
      _postAction(
        '/api/add-remote-skill',
        <String, dynamic>{
          'agentId': agentId,
          'skillName': skillName,
          'sourceUrl': sourceUrl,
          'description': description,
        },
      );

  Future<ActionResult> updateRemoteSkill(String agentId, String skillName) =>
      _postAction(
        '/api/update-remote-skill',
        <String, dynamic>{'agentId': agentId, 'skillName': skillName},
      );

  Future<ActionResult> removeRemoteSkill(String agentId, String skillName) =>
      _postAction(
        '/api/remove-remote-skill',
        <String, dynamic>{'agentId': agentId, 'skillName': skillName},
      );

  Future<ActionResult> createTask(CreateTaskPayload data) =>
      _postAction('/api/create-task', data.toJson());

  Future<WorkflowCreateResult> createWorkflow({
    required String title,
    String goal = '',
    String workflowType = 'generic',
    String owner = '',
    Map<String, dynamic>? meta,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/workflows',
        data: <String, dynamic>{
          'title': title,
          'goal': goal,
          'workflowType': workflowType,
          'owner': owner,
          if (meta != null) 'meta': meta,
        },
      );
      return WorkflowCreateResult.fromJson(_asMap(response.data));
    } catch (e) {
      return WorkflowCreateResult(
        ok: false,
        workflowId: '',
        taskId: '',
        state: '',
        error: _extractErrorMessage(e),
      );
    }
  }

  Future<Workflow> workflowSummary(String workflowId) => _getModel(
        '/api/workflows/${Uri.encodeComponent(workflowId)}',
        (map) => Workflow.fromJson(
          (map['workflow'] is Map<String, dynamic>)
              ? map['workflow'] as Map<String, dynamic>
              : <String, dynamic>{},
        ),
      );

  Future<WorkflowGraph> workflowGraph(String workflowId) => _getModel(
        '/api/workflows/${Uri.encodeComponent(workflowId)}/graph',
        WorkflowGraph.fromJson,
      );

  Future<List<WorkflowTimelineEvent>> workflowTimeline(String workflowId) =>
      _getModel(
        '/api/workflows/${Uri.encodeComponent(workflowId)}/timeline',
        _parseWorkflowTimeline,
      );

  Future<WorkflowSyncSnapshot> workflowSyncSnapshot(String workflowId) =>
      _getModel(
        '/api/workflows/${Uri.encodeComponent(workflowId)}/sync-snapshot',
        (map) {
          final workflowMap = (map['workflow'] is Map<String, dynamic>)
              ? map['workflow'] as Map<String, dynamic>
              : <String, dynamic>{};
          final graphMap = <String, dynamic>{
            'workflow': workflowMap,
            'revisions': map['revisions'] ?? const <dynamic>[],
            'nodes': map['nodes'] ?? const <dynamic>[],
            'candidates': map['candidates'] ?? const <dynamic>[],
            'decisions': map['decisions'] ?? const <dynamic>[],
            'assemblies': map['assemblies'] ?? const <dynamic>[],
          };
          return WorkflowSyncSnapshot(
            workflow: Workflow.fromJson(workflowMap),
            graph: WorkflowGraph.fromJson(graphMap),
            timeline: _parseWorkflowTimeline(map),
          );
        },
      );

  Future<ActionResult> submitWorkflowCommand(
    String workflowId,
    String eventType, {
    Map<String, dynamic>? payload,
    String producer = 'flutter',
  }) =>
      _postAction(
        '/api/workflows/${Uri.encodeComponent(workflowId)}/commands',
        <String, dynamic>{
          'eventType': eventType,
          'producer': producer,
          if (payload != null) 'payload': payload,
        },
      );

  Future<List<WorkflowCandidate>> workflowCandidates(
    String workflowId, {
    String? nodeId,
  }) =>
      _getModel(
        '/api/workflows/${Uri.encodeComponent(workflowId)}/candidates'
        '${(nodeId != null && nodeId.isNotEmpty) ? '?node_id=${Uri.encodeQueryComponent(nodeId)}' : ''}',
        (map) {
          final raw = map['candidates'] as List<dynamic>? ?? const <dynamic>[];
          return raw
              .whereType<Map>()
              .map((e) =>
                  WorkflowCandidate.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        },
      );

  Future<List<WorkflowAssembly>> workflowAssemblies(String workflowId) =>
      _getModel(
        '/api/workflows/${Uri.encodeComponent(workflowId)}/assemblies',
        (map) {
          final raw = map['assemblies'] as List<dynamic>? ?? const <dynamic>[];
          return raw
              .whereType<Map>()
              .map((e) =>
                  WorkflowAssembly.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        },
      );

  Future<ActionResult> selectWorkflowCandidate(
    String workflowId, {
    required String nodeId,
    required String candidateId,
    String actor = 'zhongshu',
    String comment = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventSelectCandidate,
        payload: <String, dynamic>{
          'node_id': nodeId,
          'candidate_id': candidateId,
          'actor': actor,
          if (comment.isNotEmpty) 'comment': comment,
        },
      );

  Future<ActionResult> regenerateWorkflowNodeCandidate(
    String workflowId, {
    required String nodeId,
    String actor = 'zhongshu',
    String comment = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventRegenerateNode,
        payload: <String, dynamic>{
          'node_id': nodeId,
          'actor': actor,
          if (comment.isNotEmpty) 'comment': comment,
        },
      );

  Future<ActionResult> approveWorkflowAssembly(
    String workflowId, {
    required String assemblyId,
    String summary = '',
    String actor = 'zhongshu',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventApproveAssembly,
        payload: <String, dynamic>{
          'assembly_id': assemblyId,
          if (summary.isNotEmpty) 'summary': summary,
          'actor': actor,
        },
      );

  Future<ActionResult> rejectWorkflowAssembly(
    String workflowId, {
    required String assemblyId,
    String actor = 'zhongshu',
    String reason = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventRejectAssembly,
        payload: <String, dynamic>{
          'assembly_id': assemblyId,
          'actor': actor,
          if (reason.isNotEmpty) 'reason': reason,
        },
      );

  Future<ActionResult> rollbackWorkflow(
    String workflowId, {
    String actor = 'zhongshu',
    String reason = '',
    String? targetRevisionId,
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventRollbackWorkflow,
        payload: <String, dynamic>{
          'actor': actor,
          if (reason.isNotEmpty) 'reason': reason,
          if (targetRevisionId != null && targetRevisionId.isNotEmpty)
            'target_revision_id': targetRevisionId,
        },
      );

  /// 推进节点状态（如 pending→running），触发 worker dispatch
  Future<ActionResult> updateNodeProgress(
    String workflowId, {
    required String nodeId,
    required String toState,
    String reason = '',
    String executorId = '',
    String message = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventNodeProgress,
        payload: <String, dynamic>{
          'node_id': nodeId,
          'to_state': toState,
          if (reason.isNotEmpty) 'reason': reason,
          if (executorId.isNotEmpty) 'executor_id': executorId,
          if (message.isNotEmpty) 'message': message,
        },
      );

  /// 手动完成候选（标记 produced/failed 等）
  Future<ActionResult> completeWorkflowCandidate(
    String workflowId, {
    required String candidateId,
    required String status,
    String summary = '',
    double? score,
    Map<String, dynamic>? metrics,
    List<Map<String, dynamic>>? artifacts,
    Map<String, dynamic>? meta,
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventCompleteCandidate,
        payload: <String, dynamic>{
          'candidate_id': candidateId,
          'status': status,
          if (summary.isNotEmpty) 'summary': summary,
          if (score != null) 'score': score,
          if (metrics != null) 'metrics': metrics,
          if (artifacts != null) 'artifacts': artifacts,
          if (meta != null) 'meta': meta,
        },
      );

  Future<ActionResult> startPlanningWorkflow(
    String workflowId, {
    String content = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventStartPlanning,
        payload: <String, dynamic>{if (content.isNotEmpty) 'content': content},
      );

  Future<ActionResult> startPlanning(
    String workflowId, {
    String content = '',
  }) =>
      startPlanningWorkflow(workflowId, content: content);

  Future<ActionResult> submitPlanWorkflow(
    String workflowId, {
    String comment = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventSubmitPlan,
        payload: <String, dynamic>{if (comment.isNotEmpty) 'comment': comment},
      );

  Future<ActionResult> submitPlan(
    String workflowId, {
    String comment = '',
  }) =>
      submitPlanWorkflow(workflowId, comment: comment);

  Future<ActionResult> approveWorkflowRevision(
    String workflowId, {
    required String revisionId,
    String actor = 'zhongshu',
    String comment = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventApprovePlan,
        payload: <String, dynamic>{
          'revision_id': revisionId,
          'actor': actor,
          if (comment.isNotEmpty) 'comment': comment,
        },
      );

  Future<ActionResult> rejectWorkflowRevision(
    String workflowId, {
    required String revisionId,
    String actor = 'zhongshu',
    String comment = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventRejectPlan,
        payload: <String, dynamic>{
          'revision_id': revisionId,
          'actor': actor,
          if (comment.isNotEmpty) 'comment': comment,
        },
      );

  Future<ActionResult> stopWorkflow(
    String workflowId, {
    String reason = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventStopWorkflow,
        payload: <String, dynamic>{if (reason.isNotEmpty) 'reason': reason},
      );

  Future<ActionResult> cancelWorkflow(
    String workflowId, {
    String reason = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventCancelWorkflow,
        payload: <String, dynamic>{if (reason.isNotEmpty) 'reason': reason},
      );

  Future<ActionResult> resumeWorkflow(
    String workflowId, {
    String reason = '',
  }) =>
      submitWorkflowCommand(
        workflowId,
        eventResumeWorkflow,
        payload: <String, dynamic>{if (reason.isNotEmpty) 'reason': reason},
      );

  Future<ActionResult> saveNotifyConfig(
    Map<String, dynamic> config,
  ) =>
      _postAction('/api/notify-config', config);

  Future<ActionResult> testNotifyChannel(
    String channelId,
    Map<String, String> params,
  ) =>
      _postAction('/api/notify-test',
          <String, dynamic>{'channel_id': channelId, 'params': params});

  Future<T> _getModel<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    T Function(String message)? onError,
  }) async {
    try {
      final response = await _dio.get<dynamic>(path);
      final map = _asMap(response.data);
      return fromJson(map);
    } catch (e, stackTrace) {
      final message = _extractErrorMessage(e);
      if (kDebugMode) {
        print('[ApiClient] _getModel($path) failed: $e\n$stackTrace');
      }
      if (onError != null) {
        return onError(message);
      }
      throw ApiException(message);
    }
  }

  Future<ActionResult> _postAction(String path, Object? data) async {
    try {
      final response = await _dio.post<dynamic>(path, data: data);
      return ActionResult.fromJson(_asMap(response.data));
    } catch (e) {
      return _errorActionResult(_extractErrorMessage(e));
    }
  }

  ActionResult _errorActionResult(String message) => ActionResult.fromJson(
      <String, dynamic>{'ok': false, 'error': message, 'message': message});

  List<WorkflowTimelineEvent> _parseWorkflowTimeline(Map<String, dynamic> map) {
    final timelineRaw = map['timeline'] as List<dynamic>? ?? const <dynamic>[];
    final parsed = timelineRaw
        .whereType<Map>()
        .map(
          (e) => WorkflowTimelineEvent.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();

    final dedup = <String, WorkflowTimelineEvent>{};
    for (final item in parsed) {
      dedup[item.timelineKey] = item;
    }
    final merged = dedup.values.toList();
    merged.sort((a, b) => a.at.compareTo(b.at));
    return merged;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      try {
        return Map<String, dynamic>.from(data);
      } catch (_) {
        // Fall through to JSON round-trip
      }
    }
    // On Web, Dio may return a JS object that doesn't match Dart Map types.
    // Force a round-trip through JSON to guarantee a clean Dart Map.
    if (data != null) {
      try {
        final encoded = convert.jsonEncode(data);
        final decoded = convert.jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        // Fall through to empty map
      }
    }
    return <String, dynamic>{};
  }

  String _extractErrorMessage(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final responseData = error.response?.data;

      String? serverMessage;
      if (responseData is Map<String, dynamic>) {
        // 优先取 detail（FastAPI HTTPException 默认字段），再取 error / message
        final detail = responseData['detail'];
        if (detail is List) {
          // 422 校验错误：detail 是 [{loc, msg, type}, ...]，提取首条 msg
          final msgs = detail
              .whereType<Map>()
              .map((e) => e['msg']?.toString() ?? '')
              .where((m) => m.isNotEmpty)
              .take(3)
              .toList();
          serverMessage =
              msgs.isNotEmpty ? '参数校验失败：${msgs.join('；')}' : detail.toString();
        } else {
          serverMessage =
              (detail ?? responseData['error'] ?? responseData['message'])
                  ?.toString();
        }
      } else if (responseData is Map) {
        try {
          final m = Map<String, dynamic>.from(responseData);
          serverMessage =
              (m['detail'] ?? m['error'] ?? m['message'])?.toString();
        } catch (_) {}
      }

      if (serverMessage != null && serverMessage.isNotEmpty) {
        // 403 权限失败特殊提示
        if (statusCode == 403) {
          return '当前角色无权限执行该动作：$serverMessage';
        }
        return serverMessage;
      }

      if (responseData is String && responseData.isNotEmpty) {
        if (statusCode == 403) {
          return '当前角色无权限执行该动作：$responseData';
        }
        return responseData;
      }

      if (statusCode == 403) {
        return '当前角色无权限执行该动作（HTTP 403）';
      }

      if (statusCode != null) {
        return 'Request failed with status $statusCode';
      }

      return error.message ?? 'Network request failed';
    }

    return error.toString();
  }
}
