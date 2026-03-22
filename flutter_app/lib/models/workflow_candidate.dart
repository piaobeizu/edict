class WorkflowArtifact {
  final String kind;
  final String path;
  final String mime;
  final String previewUrl;
  final Map<String, dynamic> metadata;

  const WorkflowArtifact({
    required this.kind,
    required this.path,
    required this.mime,
    required this.previewUrl,
    required this.metadata,
  });

  factory WorkflowArtifact.fromJson(Map<String, dynamic> json) {
    return WorkflowArtifact(
      kind: json['kind']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      mime: json['mime']?.toString() ?? '',
      previewUrl: (json['previewUrl'] ?? json['preview_url'])?.toString() ?? '',
      metadata: (json['metadata'] is Map)
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'path': path,
        'mime': mime,
        'previewUrl': previewUrl,
        'metadata': metadata,
      };
}

class WorkflowCandidate {
  final String id;
  final String nodeId;
  final String status;
  final String provider;
  final String summary;
  final double? score;
  final Map<String, dynamic> metrics;
  final List<WorkflowArtifact> artifacts;

  const WorkflowCandidate({
    required this.id,
    required this.nodeId,
    required this.status,
    required this.provider,
    required this.summary,
    required this.score,
    required this.metrics,
    required this.artifacts,
  });

  factory WorkflowCandidate.fromJson(Map<String, dynamic> json) {
    final artifactsRaw = json['artifacts'] as List<dynamic>? ?? const <dynamic>[];
    return WorkflowCandidate(
      id: json['id']?.toString() ?? '',
      nodeId: (json['nodeId'] ?? json['node_id'])?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble(),
      metrics: (json['metrics'] is Map)
          ? Map<String, dynamic>.from(json['metrics'] as Map)
          : <String, dynamic>{},
      artifacts: artifactsRaw
          .whereType<Map>()
          .map((e) => WorkflowArtifact.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nodeId': nodeId,
        'status': status,
        'provider': provider,
        'summary': summary,
        'score': score,
        'metrics': metrics,
        'artifacts': artifacts.map((e) => e.toJson()).toList(),
      };
}
