import 'task.dart';

class ParticipatedEdict {
  final String id;
  final String title;
  final String state;

  const ParticipatedEdict({
    required this.id,
    required this.title,
    required this.state,
  });

  factory ParticipatedEdict.fromJson(Map<String, dynamic> json) {
    return ParticipatedEdict(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'state': state,
      };
}

class OfficialInfo {
  final String id;
  final String label;
  final String emoji;
  final String role;
  final String rank;
  final String model;
  final String modelShort;
  final int tokensIn;
  final int tokensOut;
  final int cacheRead;
  final int cacheWrite;
  final double costCny;
  final double costUsd;
  final int sessions;
  final int messages;
  final int tasksDone;
  final int tasksActive;
  final int flowParticipations;
  final double meritScore;
  final int meritRank;
  final String lastActive;
  final Heartbeat heartbeat;
  final List<ParticipatedEdict> participatedEdicts;

  const OfficialInfo({
    required this.id,
    required this.label,
    required this.emoji,
    required this.role,
    required this.rank,
    required this.model,
    required this.modelShort,
    required this.tokensIn,
    required this.tokensOut,
    required this.cacheRead,
    required this.cacheWrite,
    required this.costCny,
    required this.costUsd,
    required this.sessions,
    required this.messages,
    required this.tasksDone,
    required this.tasksActive,
    required this.flowParticipations,
    required this.meritScore,
    required this.meritRank,
    required this.lastActive,
    required this.heartbeat,
    required this.participatedEdicts,
  });

  factory OfficialInfo.fromJson(Map<String, dynamic> json) {
    return OfficialInfo(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      rank: json['rank']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      modelShort: (json['model_short'] ?? json['modelShort'])?.toString() ?? '',
      tokensIn: ((json['tokens_in'] ?? json['tokensIn']) as num?)?.toInt() ?? 0,
      tokensOut: ((json['tokens_out'] ?? json['tokensOut']) as num?)?.toInt() ?? 0,
      cacheRead: ((json['cache_read'] ?? json['cacheRead']) as num?)?.toInt() ?? 0,
      cacheWrite: ((json['cache_write'] ?? json['cacheWrite']) as num?)?.toInt() ?? 0,
      costCny: ((json['cost_cny'] ?? json['costCny']) as num?)?.toDouble() ?? 0,
      costUsd: ((json['cost_usd'] ?? json['costUsd']) as num?)?.toDouble() ?? 0,
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      messages: (json['messages'] as num?)?.toInt() ?? 0,
      tasksDone: ((json['tasks_done'] ?? json['tasksDone']) as num?)?.toInt() ?? 0,
      tasksActive:
          ((json['tasks_active'] ?? json['tasksActive']) as num?)?.toInt() ?? 0,
      flowParticipations:
          ((json['flow_participations'] ?? json['flowParticipations']) as num?)
                  ?.toInt() ??
              0,
      meritScore:
          ((json['merit_score'] ?? json['meritScore']) as num?)?.toDouble() ?? 0,
      meritRank: ((json['merit_rank'] ?? json['meritRank']) as num?)?.toInt() ??
          0,
      lastActive: (json['last_active'] ?? json['lastActive'])?.toString() ?? '',
      heartbeat: json['heartbeat'] is Map<String, dynamic>
          ? Heartbeat.fromJson(json['heartbeat'] as Map<String, dynamic>)
          : const Heartbeat(status: HeartbeatStatus.unknown, label: ''),
      participatedEdicts: ((json['participated_edicts'] ??
                  json['participatedEdicts']) as List<dynamic>? ??
              [])
          .map((e) => ParticipatedEdict.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'emoji': emoji,
        'role': role,
        'rank': rank,
        'model': model,
        'model_short': modelShort,
        'tokens_in': tokensIn,
        'tokens_out': tokensOut,
        'cache_read': cacheRead,
        'cache_write': cacheWrite,
        'cost_cny': costCny,
        'cost_usd': costUsd,
        'sessions': sessions,
        'messages': messages,
        'tasks_done': tasksDone,
        'tasks_active': tasksActive,
        'flow_participations': flowParticipations,
        'merit_score': meritScore,
        'merit_rank': meritRank,
        'last_active': lastActive,
        'heartbeat': heartbeat.toJson(),
        'participated_edicts': participatedEdicts.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() =>
      'OfficialInfo(id: $id, label: $label, tasksDone: $tasksDone, costCny: $costCny)';
}

class OfficialsTotals {
  final int tasksDone;
  final double costCny;

  const OfficialsTotals({required this.tasksDone, required this.costCny});

  factory OfficialsTotals.fromJson(Map<String, dynamic> json) {
    return OfficialsTotals(
      tasksDone: ((json['tasks_done'] ?? json['tasksDone']) as num?)?.toInt() ??
          0,
      costCny: ((json['cost_cny'] ?? json['costCny']) as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'tasks_done': tasksDone,
        'cost_cny': costCny,
      };
}

class OfficialsData {
  final List<OfficialInfo> officials;
  final OfficialsTotals totals;
  final String topOfficial;

  const OfficialsData({
    required this.officials,
    required this.totals,
    required this.topOfficial,
  });

  factory OfficialsData.fromJson(Map<String, dynamic> json) {
    return OfficialsData(
      officials: (json['officials'] as List<dynamic>? ?? [])
          .map((e) => OfficialInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      totals: json['totals'] is Map<String, dynamic>
          ? OfficialsTotals.fromJson(json['totals'] as Map<String, dynamic>)
          : const OfficialsTotals(tasksDone: 0, costCny: 0),
      topOfficial: (json['top_official'] ?? json['topOfficial'])?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'officials': officials.map((e) => e.toJson()).toList(),
        'totals': totals.toJson(),
        'top_official': topOfficial,
      };
}
