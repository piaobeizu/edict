import 'workflow_candidate.dart';

class WorkflowAssemblyItem {
  final int order;
  final String nodeId;
  final String candidateId;
  final String role;
  final Map<String, dynamic> meta;

  const WorkflowAssemblyItem({
    required this.order,
    required this.nodeId,
    required this.candidateId,
    required this.role,
    required this.meta,
  });

  factory WorkflowAssemblyItem.fromJson(Map<String, dynamic> json) {
    return WorkflowAssemblyItem(
      order: (json['order'] as num?)?.toInt() ?? 0,
      nodeId: (json['nodeId'] ?? json['node_id'])?.toString() ?? '',
      candidateId: (json['candidateId'] ?? json['candidate_id'])?.toString() ?? '',
      role: json['role']?.toString() ?? 'primary',
      meta: (json['meta'] is Map)
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'order': order,
        'nodeId': nodeId,
        'candidateId': candidateId,
        'role': role,
        'meta': meta,
      };
}

class WorkflowAssembly {
  final String id;
  final String status;
  final String summary;
  final List<WorkflowAssemblyItem> items;
  final List<WorkflowArtifact> artifacts;

  const WorkflowAssembly({
    required this.id,
    required this.status,
    required this.summary,
    required this.items,
    required this.artifacts,
  });

  factory WorkflowAssembly.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List<dynamic>? ?? const <dynamic>[];
    final artifactsRaw = json['artifacts'] as List<dynamic>? ?? const <dynamic>[];
    return WorkflowAssembly(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      items: itemsRaw
          .whereType<Map>()
          .map((e) => WorkflowAssemblyItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      artifacts: artifactsRaw
          .whereType<Map>()
          .map((e) => WorkflowArtifact.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'summary': summary,
        'items': items.map((e) => e.toJson()).toList(),
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
      };
}
