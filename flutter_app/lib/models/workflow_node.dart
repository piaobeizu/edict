class WorkflowNode {
  final String id;
  final String revisionId;
  final String kind;
  final String state;
  final String title;
  final String assignee;
  final int sequence;

  const WorkflowNode({
    required this.id,
    required this.revisionId,
    required this.kind,
    required this.state,
    required this.title,
    required this.assignee,
    required this.sequence,
  });

  factory WorkflowNode.fromJson(Map<String, dynamic> json) {
    return WorkflowNode(
      id: json['id']?.toString() ?? '',
      revisionId: (json['revisionId'] ?? json['revision_id'])?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      assignee: json['assignee']?.toString() ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'revisionId': revisionId,
        'kind': kind,
        'state': state,
        'title': title,
        'assignee': assignee,
        'sequence': sequence,
      };
}
