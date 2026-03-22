import 'package:dio/dio.dart';
import 'package:edict_app/models/common.dart';
import 'package:edict_app/models/task.dart';
import 'package:edict_app/models/workflow.dart';
import 'package:edict_app/models/workflow_assembly.dart';
import 'package:edict_app/models/workflow_candidate.dart';
import 'package:edict_app/models/workflow_decision.dart';
import 'package:edict_app/models/workflow_node.dart';
import 'package:edict_app/models/workflow_revision.dart';
import 'package:edict_app/services/api_client.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

Task makeTask({
  String id = 'JJC-001',
  String title = '测试诏令',
  String state = 'Doing',
  String org = '工部',
  String now = '',
  String eta = '-',
  String block = '',
  String ac = '',
  String output = '',
  Heartbeat heartbeat =
      const Heartbeat(status: HeartbeatStatus.active, label: '1m'),
  List<FlowEntry> flowLog = const <FlowEntry>[],
  List<TodoItem> todos = const <TodoItem>[],
  int reviewRound = 0,
  bool archived = false,
  String workflowId = 'wf-001',
  String? archivedAt,
  String? updatedAt,
  Map<String, dynamic>? sourceMeta,
  List<ActivityEntry>? activity,
  String? prevState,
  int? projectionVersion,
  String? currentRevisionId,
  String? currentAssemblyId,
  int pendingReviewCount = 0,
  int runningNodeCount = 0,
}) {
  return Task(
    id: id,
    title: title,
    state: state,
    org: org,
    now: now,
    eta: eta,
    block: block,
    ac: ac,
    output: output,
    heartbeat: heartbeat,
    flowLog: flowLog,
    todos: todos,
    reviewRound: reviewRound,
    archived: archived,
    archivedAt: archivedAt,
    updatedAt: updatedAt,
    sourceMeta: sourceMeta,
    activity: activity,
    prevState: prevState,
    workflowId: workflowId,
    projectionVersion: projectionVersion,
    currentRevisionId: currentRevisionId,
    currentAssemblyId: currentAssemblyId,
    pendingReviewCount: pendingReviewCount,
    runningNodeCount: runningNodeCount,
  );
}

Workflow makeWorkflow({
  String id = 'wf-001',
  String taskId = 'JJC-001',
  String type = 'generic',
  String title = '测试',
  String goal = 'E2E',
  String state = 'executing',
  String owner = 'tester',
  String? currentRevisionId,
  String? currentAssemblyId,
  String? summaryOutput,
}) {
  return Workflow(
    id: id,
    taskId: taskId,
    type: type,
    title: title,
    goal: goal,
    state: state,
    owner: owner,
    currentRevisionId: currentRevisionId,
    currentAssemblyId: currentAssemblyId,
    summaryOutput: summaryOutput,
  );
}

WorkflowGraph makeWorkflowGraph({
  Workflow? workflow,
  List<WorkflowRevision> revisions = const <WorkflowRevision>[],
  List<WorkflowNode> nodes = const <WorkflowNode>[],
  List<WorkflowCandidate> candidates = const <WorkflowCandidate>[],
  List<WorkflowDecision> decisions = const <WorkflowDecision>[],
  List<WorkflowAssembly> assemblies = const <WorkflowAssembly>[],
}) {
  return WorkflowGraph(
    workflow: workflow ?? makeWorkflow(),
    revisions: revisions,
    nodes: nodes,
    candidates: candidates,
    decisions: decisions,
    assemblies: assemblies,
  );
}

WorkflowCandidate makeCandidate({
  String id = 'cand-001',
  String nodeId = 'node-001',
  String status = 'produced',
  String provider = 'mock',
  String summary = 'candidate summary',
  double? score = 0.9,
  Map<String, dynamic> metrics = const <String, dynamic>{},
  List<WorkflowArtifact> artifacts = const <WorkflowArtifact>[],
}) {
  return WorkflowCandidate(
    id: id,
    nodeId: nodeId,
    status: status,
    provider: provider,
    summary: summary,
    score: score,
    metrics: metrics,
    artifacts: artifacts,
  );
}

WorkflowNode makeNode({
  String id = 'node-001',
  String revisionId = 'rev-001',
  String kind = 'generate',
  String state = 'pending',
  String title = '测试节点',
  String assignee = 'tester',
  int sequence = 1,
}) {
  return WorkflowNode(
    id: id,
    revisionId: revisionId,
    kind: kind,
    state: state,
    title: title,
    assignee: assignee,
    sequence: sequence,
  );
}

WorkflowRevision makeRevision({
  String id = 'rev-001',
  int number = 1,
  String status = 'approved',
  String createdBy = 'tester',
  String source = 'manual',
  String content = 'revision content',
  String changeSummary = 'initial revision',
  String parentRevisionId = '',
  String createdAt = '2024-01-01T00:00:00Z',
  String updatedAt = '2024-01-01T00:00:00Z',
}) {
  return WorkflowRevision(
    id: id,
    number: number,
    status: status,
    createdBy: createdBy,
    source: source,
    content: content,
    changeSummary: changeSummary,
    parentRevisionId: parentRevisionId,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

WorkflowAssembly makeAssembly({
  String id = 'asm-001',
  String status = 'pending_review',
  String summary = 'assembly summary',
  List<WorkflowAssemblyItem> items = const <WorkflowAssemblyItem>[],
  List<WorkflowArtifact> artifacts = const <WorkflowArtifact>[],
}) {
  return WorkflowAssembly(
    id: id,
    status: status,
    summary: summary,
    items: items,
    artifacts: artifacts,
  );
}

ActionResult makeActionResult({
  bool ok = true,
  bool? accepted,
  String? entryId,
  String? message,
  String? error,
  String? taskId,
}) {
  return ActionResult(
    ok: ok,
    accepted: accepted,
    entryId: entryId,
    message: message,
    error: error,
    taskId: taskId,
  );
}
