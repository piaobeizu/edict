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

      if (responseData is Map<String, dynamic>) {
        final message = responseData['error'] ?? responseData['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }

      if (responseData is String && responseData.isNotEmpty) {
        return responseData;
      }

      if (statusCode != null) {
        return 'Request failed with status $statusCode';
      }

      return error.message ?? 'Network request failed';
    }

    return error.toString();
  }
}
