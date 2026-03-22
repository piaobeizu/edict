class WorkflowRevision {
  final String id;
  final int number;
  final String status;
  final String createdBy;
  final String source;
  final String content;
  final String changeSummary;
  final String parentRevisionId;
  final String createdAt;
  final String updatedAt;

  const WorkflowRevision({
    required this.id,
    required this.number,
    required this.status,
    required this.createdBy,
    required this.source,
    required this.content,
    required this.changeSummary,
    required this.parentRevisionId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkflowRevision.fromJson(Map<String, dynamic> json) {
    return WorkflowRevision(
      id: json['id']?.toString() ?? '',
      number: (json['number'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '',
      createdBy: (json['createdBy'] ?? json['created_by'])?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      changeSummary:
          (json['changeSummary'] ?? json['change_summary'])?.toString() ?? '',
      parentRevisionId:
          (json['parentRevisionId'] ?? json['parent_revision_id'])?.toString() ??
              '',
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      updatedAt: (json['updatedAt'] ?? json['updated_at'])?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'status': status,
        'createdBy': createdBy,
        'source': source,
        'content': content,
        'changeSummary': changeSummary,
        'parentRevisionId': parentRevisionId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
