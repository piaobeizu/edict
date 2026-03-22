import 'workflow_decision.dart';
import 'workflow_node.dart';
import 'workflow_revision.dart';
import 'workflow_candidate.dart';
import 'workflow_assembly.dart';
import 'workflow_timeline_event.dart';

class Workflow {
  final String id;
  final String taskId;
  final String type;
  final String title;
  final String goal;
  final String state;
  final String owner;
  final String? currentRevisionId;
  final String? currentAssemblyId;
  final String? summaryOutput;

  const Workflow({
    required this.id,
    required this.taskId,
    required this.type,
    required this.title,
    required this.goal,
    required this.state,
    required this.owner,
    this.currentRevisionId,
    this.currentAssemblyId,
    this.summaryOutput,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      id: json['id']?.toString() ?? '',
      taskId: (json['taskId'] ?? json['task_id'])?.toString() ?? '',
      type: json['type']?.toString() ?? 'generic',
      title: json['title']?.toString() ?? '',
      goal: json['goal']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      owner: json['owner']?.toString() ?? '',
      currentRevisionId:
          (json['currentRevisionId'] ?? json['current_revision_id'])
              ?.toString(),
      currentAssemblyId:
          (json['currentAssemblyId'] ?? json['current_assembly_id'])
              ?.toString(),
      summaryOutput:
          (json['summaryOutput'] ?? json['summary_output'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'type': type,
        'title': title,
        'goal': goal,
        'state': state,
        'owner': owner,
        'currentRevisionId': currentRevisionId,
        'currentAssemblyId': currentAssemblyId,
        'summaryOutput': summaryOutput,
      };
}

class WorkflowGraph {
  final Workflow workflow;
  final List<WorkflowRevision> revisions;
  final List<WorkflowNode> nodes;
  final List<WorkflowCandidate> candidates;
  final List<WorkflowDecision> decisions;
  final List<WorkflowAssembly> assemblies;

  const WorkflowGraph({
    required this.workflow,
    required this.revisions,
    required this.nodes,
    required this.candidates,
    required this.decisions,
    required this.assemblies,
  });

  factory WorkflowGraph.fromJson(Map<String, dynamic> json) {
    final workflowMap = (json['workflow'] is Map)
        ? Map<String, dynamic>.from(json['workflow'] as Map)
        : <String, dynamic>{};
    final revisionsRaw =
        json['revisions'] as List<dynamic>? ?? const <dynamic>[];
    final nodesRaw = json['nodes'] as List<dynamic>? ?? const <dynamic>[];
    final decisionsRaw =
        json['decisions'] as List<dynamic>? ?? const <dynamic>[];
    final candidatesRaw =
        json['candidates'] as List<dynamic>? ?? const <dynamic>[];
    final assembliesRaw =
        json['assemblies'] as List<dynamic>? ?? const <dynamic>[];

    return WorkflowGraph(
      workflow: Workflow.fromJson(workflowMap),
      revisions: revisionsRaw
          .whereType<Map>()
          .map((e) => WorkflowRevision.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      nodes: nodesRaw
          .whereType<Map>()
          .map((e) => WorkflowNode.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      candidates: candidatesRaw
          .whereType<Map>()
          .map((e) => WorkflowCandidate.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      decisions: decisionsRaw
          .whereType<Map>()
          .map((e) => WorkflowDecision.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      assemblies: assembliesRaw
          .whereType<Map>()
          .map((e) => WorkflowAssembly.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class WorkflowSyncSnapshot {
  final Workflow workflow;
  final WorkflowGraph graph;
  final List<WorkflowTimelineEvent> timeline;

  const WorkflowSyncSnapshot({
    required this.workflow,
    required this.graph,
    required this.timeline,
  });
}

class WorkflowCreateResult {
  final bool ok;
  final String workflowId;
  final String taskId;
  final String state;
  final String? message;
  final String? error;

  const WorkflowCreateResult({
    required this.ok,
    required this.workflowId,
    required this.taskId,
    required this.state,
    this.message,
    this.error,
  });

  factory WorkflowCreateResult.fromJson(Map<String, dynamic> json) {
    return WorkflowCreateResult(
      ok: json['ok'] == true,
      workflowId: (json['workflowId'] ?? json['workflow_id'])?.toString() ?? '',
      taskId: (json['taskId'] ?? json['task_id'])?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      message: json['message']?.toString(),
      error: json['error']?.toString(),
    );
  }
}
