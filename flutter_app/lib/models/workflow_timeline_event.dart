class WorkflowTimelineEvent {
  final String kind;
  final String id;
  final String at;
  final String action;
  final String actor;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> raw;

  const WorkflowTimelineEvent({
    required this.kind,
    required this.id,
    required this.at,
    required this.action,
    required this.actor,
    required this.targetType,
    required this.targetId,
    required this.raw,
  });

  factory WorkflowTimelineEvent.fromJson(Map<String, dynamic> json) {
    return WorkflowTimelineEvent(
      kind: json['kind']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      at: json['at']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      actor: json['actor']?.toString() ?? '',
      targetType: (json['targetType'] ?? json['target_type'])?.toString() ?? '',
      targetId: (json['targetId'] ?? json['target_id'])?.toString() ?? '',
      raw: Map<String, dynamic>.from(json),
    );
  }

  String get timelineKey {
    final k = kind.isEmpty ? 'event' : kind;
    final i = id.isEmpty ? at : id;
    return '$k:$i';
  }
}
