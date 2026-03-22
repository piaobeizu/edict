class WorkflowDecision {
  final String id;
  final String targetType;
  final String targetId;
  final String action;
  final String actor;
  final String comment;

  const WorkflowDecision({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.action,
    required this.actor,
    required this.comment,
  });

  factory WorkflowDecision.fromJson(Map<String, dynamic> json) {
    return WorkflowDecision(
      id: json['id']?.toString() ?? '',
      targetType: (json['targetType'] ?? json['target_type'])?.toString() ?? '',
      targetId: (json['targetId'] ?? json['target_id'])?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      actor: json['actor']?.toString() ?? '',
      comment: json['comment']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetType': targetType,
        'targetId': targetId,
        'action': action,
        'actor': actor,
        'comment': comment,
      };
}
