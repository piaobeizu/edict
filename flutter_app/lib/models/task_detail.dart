import 'task.dart';

class PhaseDuration {
  final String phase;
  final int durationSec;
  final String durationText;
  final bool? ongoing;

  const PhaseDuration({
    required this.phase,
    required this.durationSec,
    required this.durationText,
    this.ongoing,
  });

  factory PhaseDuration.fromJson(Map<String, dynamic> json) {
    return PhaseDuration(
      phase: json['phase']?.toString() ?? '',
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      durationText: json['durationText']?.toString() ?? '',
      ongoing: json['ongoing'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'durationSec': durationSec,
        'durationText': durationText,
        'ongoing': ongoing,
      };
}

class TodosSummary {
  final int total;
  final int completed;
  final int inProgress;
  final int notStarted;
  final double percent;

  const TodosSummary({
    required this.total,
    required this.completed,
    required this.inProgress,
    required this.notStarted,
    required this.percent,
  });

  factory TodosSummary.fromJson(Map<String, dynamic> json) {
    return TodosSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      inProgress: (json['inProgress'] as num?)?.toInt() ?? 0,
      notStarted: (json['notStarted'] as num?)?.toInt() ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'total': total,
        'completed': completed,
        'inProgress': inProgress,
        'notStarted': notStarted,
        'percent': percent,
      };
}

class ResourceSummary {
  final int? totalTokens;
  final double? totalCost;
  final int? totalElapsedSec;

  const ResourceSummary({
    this.totalTokens,
    this.totalCost,
    this.totalElapsedSec,
  });

  factory ResourceSummary.fromJson(Map<String, dynamic> json) {
    return ResourceSummary(
      totalTokens: (json['totalTokens'] as num?)?.toInt(),
      totalCost: (json['totalCost'] as num?)?.toDouble(),
      totalElapsedSec: (json['totalElapsedSec'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalTokens': totalTokens,
        'totalCost': totalCost,
        'totalElapsedSec': totalElapsedSec,
      };
}

class ArtifactInfo {
  final String path;
  final String? kind;
  final bool? exists;
  final bool? downloadable;

  const ArtifactInfo({
    required this.path,
    this.kind,
    this.exists,
    this.downloadable,
  });

  factory ArtifactInfo.fromJson(Map<String, dynamic> json) {
    return ArtifactInfo(
      path: json['path']?.toString() ?? '',
      kind: json['kind']?.toString(),
      exists: json['exists'] as bool?,
      downloadable: json['downloadable'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'kind': kind,
        'exists': exists,
        'downloadable': downloadable,
      };
}

class RetryRecord {
  final String? at;
  final String? agent;
  final int? attempts;
  final String? errorType;
  final bool? exhausted;

  const RetryRecord({
    this.at,
    this.agent,
    this.attempts,
    this.errorType,
    this.exhausted,
  });

  factory RetryRecord.fromJson(Map<String, dynamic> json) {
    return RetryRecord(
      at: json['at']?.toString(),
      agent: json['agent']?.toString(),
      attempts: (json['attempts'] as num?)?.toInt(),
      errorType: json['errorType']?.toString(),
      exhausted: json['exhausted'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'at': at,
        'agent': agent,
        'attempts': attempts,
        'errorType': errorType,
        'exhausted': exhausted,
      };
}

class RetrySummary {
  final int count;
  final List<RetryRecord> records;

  const RetrySummary({required this.count, required this.records});

  factory RetrySummary.fromJson(Map<String, dynamic> json) {
    return RetrySummary(
      count: (json['count'] as num?)?.toInt() ?? 0,
      records: (json['records'] as List<dynamic>? ?? [])
          .map((e) => RetryRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'count': count,
        'records': records.map((e) => e.toJson()).toList(),
      };
}

class TaskActivityData {
  final bool ok;
  final String? message;
  final String? error;
  final List<ActivityEntry>? activity;
  final List<String>? relatedAgents;
  final String? agentLabel;
  final String? lastActive;
  final List<PhaseDuration>? phaseDurations;
  final String? totalDuration;
  final TodosSummary? todosSummary;
  final ResourceSummary? resourceSummary;
  final List<ArtifactInfo>? artifacts;
  final RetrySummary? retrySummary;

  const TaskActivityData({
    required this.ok,
    this.message,
    this.error,
    this.activity,
    this.relatedAgents,
    this.agentLabel,
    this.lastActive,
    this.phaseDurations,
    this.totalDuration,
    this.todosSummary,
    this.resourceSummary,
    this.artifacts,
    this.retrySummary,
  });

  factory TaskActivityData.fromJson(Map<String, dynamic> json) {
    return TaskActivityData(
      ok: json['ok'] == true,
      message: json['message']?.toString(),
      error: json['error']?.toString(),
      activity: (json['activity'] as List<dynamic>?)
          ?.map((e) => ActivityEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      relatedAgents: (json['relatedAgents'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      agentLabel: json['agentLabel']?.toString(),
      lastActive: json['lastActive']?.toString(),
      phaseDurations: (json['phaseDurations'] as List<dynamic>?)
          ?.map((e) => PhaseDuration.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      totalDuration: json['totalDuration']?.toString(),
      todosSummary: json['todosSummary'] is Map<String, dynamic>
          ? TodosSummary.fromJson(json['todosSummary'] as Map<String, dynamic>)
          : null,
      resourceSummary: json['resourceSummary'] is Map<String, dynamic>
          ? ResourceSummary.fromJson(
              json['resourceSummary'] as Map<String, dynamic>,
            )
          : null,
      artifacts: (json['artifacts'] as List<dynamic>?)
          ?.map((e) => ArtifactInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      retrySummary: json['retrySummary'] is Map<String, dynamic>
          ? RetrySummary.fromJson(json['retrySummary'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'message': message,
        'error': error,
        'activity': activity?.map((e) => e.toJson()).toList(),
        'relatedAgents': relatedAgents,
        'agentLabel': agentLabel,
        'lastActive': lastActive,
        'phaseDurations': phaseDurations?.map((e) => e.toJson()).toList(),
        'totalDuration': totalDuration,
        'todosSummary': todosSummary?.toJson(),
        'resourceSummary': resourceSummary?.toJson(),
        'artifacts': artifacts?.map((e) => e.toJson()).toList(),
        'retrySummary': retrySummary?.toJson(),
      };
}

class SchedulerInfo {
  final int? retryCount;
  final int? escalationLevel;
  final String? lastDispatchStatus;
  final int? stallThresholdSec;
  final bool? enabled;
  final String? lastProgressAt;
  final String? lastDispatchAt;
  final String? lastDispatchAgent;
  final bool? autoRollback;

  const SchedulerInfo({
    this.retryCount,
    this.escalationLevel,
    this.lastDispatchStatus,
    this.stallThresholdSec,
    this.enabled,
    this.lastProgressAt,
    this.lastDispatchAt,
    this.lastDispatchAgent,
    this.autoRollback,
  });

  factory SchedulerInfo.fromJson(Map<String, dynamic> json) {
    return SchedulerInfo(
      retryCount: (json['retryCount'] as num?)?.toInt(),
      escalationLevel: (json['escalationLevel'] as num?)?.toInt(),
      lastDispatchStatus: json['lastDispatchStatus']?.toString(),
      stallThresholdSec: (json['stallThresholdSec'] as num?)?.toInt(),
      enabled: json['enabled'] as bool?,
      lastProgressAt: json['lastProgressAt']?.toString(),
      lastDispatchAt: json['lastDispatchAt']?.toString(),
      lastDispatchAgent: json['lastDispatchAgent']?.toString(),
      autoRollback: json['autoRollback'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'retryCount': retryCount,
        'escalationLevel': escalationLevel,
        'lastDispatchStatus': lastDispatchStatus,
        'stallThresholdSec': stallThresholdSec,
        'enabled': enabled,
        'lastProgressAt': lastProgressAt,
        'lastDispatchAt': lastDispatchAt,
        'lastDispatchAgent': lastDispatchAgent,
        'autoRollback': autoRollback,
      };
}

class SchedulerStateData {
  final bool ok;
  final String? error;
  final SchedulerInfo? scheduler;
  final int? stalledSec;

  const SchedulerStateData({
    required this.ok,
    this.error,
    this.scheduler,
    this.stalledSec,
  });

  factory SchedulerStateData.fromJson(Map<String, dynamic> json) {
    return SchedulerStateData(
      ok: json['ok'] == true,
      error: json['error']?.toString(),
      scheduler: json['scheduler'] is Map<String, dynamic>
          ? SchedulerInfo.fromJson(json['scheduler'] as Map<String, dynamic>)
          : null,
      stalledSec: (json['stalledSec'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'error': error,
        'scheduler': scheduler?.toJson(),
        'stalledSec': stalledSec,
      };
}
