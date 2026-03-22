import 'package:flutter_test/flutter_test.dart';

import 'package:edict_app/models/common.dart';
import 'package:edict_app/models/task.dart';
import 'package:edict_app/models/workflow.dart';
import 'package:edict_app/models/workflow_assembly.dart';
import 'package:edict_app/models/workflow_candidate.dart';
import 'package:edict_app/models/workflow_decision.dart';
import 'package:edict_app/models/workflow_node.dart';
import 'package:edict_app/models/workflow_revision.dart';
import 'package:edict_app/models/workflow_timeline_event.dart';

void main() {
  group('Task', () {
    test('fromJson with full data including flowLog, todos, heartbeat', () {
      final json = <String, dynamic>{
        'id': 't1',
        'title': 'Task One',
        'state': 'running',
        'org': 'ops',
        'now': 'step-1',
        'eta': 'soon',
        'block': 'none',
        'ac': 'done',
        'output': 'hello',
        'heartbeat': {'status': 'active', 'label': 'healthy'},
        'flowLog': [
          {
            'at': '2026-01-01T00:00:00Z',
            'from': 'queued',
            'to': 'running',
            'remark': 'started',
          },
        ],
        'todos': [
          {
            'id': 'todo-1',
            'title': 'Do thing',
            'status': 'in-progress',
            'detail': 'details',
          },
        ],
        'reviewRound': 2,
        'archived': true,
        'archivedAt': '2026-01-01T00:10:00Z',
        'updatedAt': '2026-01-01T00:20:00Z',
        'sourceMeta': {
          'workflowId': 'wf-meta',
          'projectionVersion': 9,
        },
        '_prev_state': 'queued',
        'workflowId': 'wf-1',
        'projectionVersion': 3,
        'currentRevisionId': 'r2',
        'currentAssemblyId': 'a7',
        'pendingReviewCount': 4,
        'runningNodeCount': 5,
      };

      final task = Task.fromJson(json);

      expect(task.id, 't1');
      expect(task.heartbeat.status, HeartbeatStatus.active);
      expect(task.heartbeat.label, 'healthy');
      expect(task.flowLog, hasLength(1));
      expect(task.flowLog.first.from, 'queued');
      expect(task.todos, hasLength(1));
      expect(task.todos.first.status, TodoStatus.inProgress);
      expect(task.reviewRound, 2);
      expect(task.archived, isTrue);
      expect(task.workflowId, 'wf-1');
      expect(task.currentRevisionId, 'r2');
      expect(task.currentAssemblyId, 'a7');
      expect(task.pendingReviewCount, 4);
      expect(task.runningNodeCount, 5);

      final roundTrip = Task.fromJson(task.toJson());
      expect(roundTrip.toJson(), equals(task.toJson()));
    });

    test('fromJson with snake_case keys aliases fields correctly', () {
      final task = Task.fromJson(<String, dynamic>{
        'id': 't2',
        'title': 'Snake',
        'state': 'waiting',
        'official': 'team-x',
        'flow_log': [
          {'from': 'a', 'to': 'b'},
        ],
        'review_round': 7,
        'archived_at': '2026-01-02T00:00:00Z',
        'updated_at': '2026-01-02T00:01:00Z',
        'source_meta': {
          'projection_version': 11,
          'current_revision_id': 'rev-9',
          'current_assembly_id': 'asm-4',
          'pending_review_count': 2,
          'running_node_count': 3,
        },
        'workflow_id': 'wf-snake',
        'projection_version': 12,
        'current_revision_id': 'rev-top',
        'current_assembly_id': 'asm-top',
        'pending_review_count': 8,
        'running_node_count': 9,
        'prev_state': 'draft',
      });

      expect(task.org, 'team-x');
      expect(task.flowLog, hasLength(1));
      expect(task.reviewRound, 7);
      expect(task.archivedAt, '2026-01-02T00:00:00Z');
      expect(task.updatedAt, '2026-01-02T00:01:00Z');
      expect(task.workflowId, 'wf-snake');
      expect(task.projectionVersion, 12);
      expect(task.currentRevisionId, 'rev-top');
      expect(task.currentAssemblyId, 'asm-top');
      expect(task.pendingReviewCount, 8);
      expect(task.runningNodeCount, 9);
      expect(task.prevState, 'draft');
    });

    test('fromJson with minimal data applies defaults', () {
      final task = Task.fromJson(<String, dynamic>{});

      expect(task.id, '');
      expect(task.title, '');
      expect(task.eta, '-');
      expect(task.archived, isFalse);
      expect(task.heartbeat.status, HeartbeatStatus.unknown);
      expect(task.heartbeat.label, '');
      expect(task.flowLog, isEmpty);
      expect(task.todos, isEmpty);
      expect(task.reviewRound, 0);
      expect(task.sourceMeta, isNull);
      expect(task.workflowId, '');
      expect(task.pendingReviewCount, 0);
      expect(task.runningNodeCount, 0);
    });

    test('isWorkflowV2Task true when workflowId present', () {
      final task = Task.fromJson({'workflowId': 'wf-yes'});
      expect(isWorkflowV2Task(task), isTrue);
    });

    test('isWorkflowV2Task false when workflow id empty', () {
      final task = Task.fromJson({
        'workflowId': '   ',
        'sourceMeta': {'workflowId': '   '},
      });
      expect(isWorkflowV2Task(task), isFalse);
    });

    test('taskWorkflowId prefers top-level then sourceMeta fallback', () {
      final topLevelTask = Task.fromJson({
        'workflowId': 'wf-top',
        'sourceMeta': {'workflow_id': 'wf-meta'},
      });
      expect(taskWorkflowId(topLevelTask), 'wf-top');

      final fallbackTask = Task.fromJson({
        'sourceMeta': {'workflow_id': 'wf-meta-only'},
      });
      expect(taskWorkflowId(fallbackTask), 'wf-meta-only');
    });
  });

  group('Workflow', () {
    test('fromJson/toJson round-trip with all fields', () {
      final workflow = Workflow.fromJson({
        'id': 'w1',
        'taskId': 't1',
        'type': 'editorial',
        'title': 'Workflow 1',
        'goal': 'Ship',
        'state': 'running',
        'owner': 'alice',
        'currentRevisionId': 'r1',
        'currentAssemblyId': 'a1',
        'summaryOutput': 'summary',
      });

      final roundTrip = Workflow.fromJson(workflow.toJson());
      expect(roundTrip.toJson(), equals(workflow.toJson()));
    });

    test('fromJson supports snake_case keys', () {
      final workflow = Workflow.fromJson({
        'id': 'w2',
        'task_id': 't2',
        'type': 'generic',
        'title': 'Snake W',
        'goal': 'Goal',
        'state': 'done',
        'owner': 'bob',
        'current_revision_id': 'r2',
        'current_assembly_id': 'a2',
        'summary_output': 'ok',
      });

      expect(workflow.taskId, 't2');
      expect(workflow.currentRevisionId, 'r2');
      expect(workflow.currentAssemblyId, 'a2');
      expect(workflow.summaryOutput, 'ok');
    });
  });

  group('WorkflowGraph', () {
    test(
        'fromJson parses nested revisions/nodes/candidates/decisions/assemblies',
        () {
      final graph = WorkflowGraph.fromJson({
        'workflow': {
          'id': 'w1',
          'taskId': 't1',
          'type': 'generic',
          'title': 'W',
          'goal': 'G',
          'state': 'running',
          'owner': 'owner',
        },
        'revisions': [
          {
            'id': 'r1',
            'number': 1,
            'status': 'open',
            'createdBy': 'alice',
            'source': 'agent',
            'content': 'content',
            'changeSummary': 'summary',
            'parentRevisionId': '',
            'createdAt': '2026-01-01',
            'updatedAt': '2026-01-02',
          },
        ],
        'nodes': [
          {
            'id': 'n1',
            'revisionId': 'r1',
            'kind': 'draft',
            'state': 'running',
            'title': 'Node',
            'assignee': 'bob',
            'sequence': 1,
          },
        ],
        'candidates': [
          {
            'id': 'c1',
            'nodeId': 'n1',
            'status': 'ready',
            'provider': 'llm',
            'summary': 'candidate',
            'score': 0.9,
            'metrics': {'tokens': 100},
            'artifacts': [
              {
                'kind': 'text',
                'path': '/tmp/a.md',
                'mime': 'text/markdown',
                'previewUrl': 'https://example.com/a',
                'metadata': {'lang': 'en'},
              },
            ],
          },
        ],
        'decisions': [
          {
            'id': 'd1',
            'targetType': 'candidate',
            'targetId': 'c1',
            'action': 'approve',
            'actor': 'reviewer',
            'comment': 'looks good',
          },
        ],
        'assemblies': [
          {
            'id': 'a1',
            'status': 'ready',
            'summary': 'assembly',
            'items': [
              {
                'order': 1,
                'nodeId': 'n1',
                'candidateId': 'c1',
                'role': 'primary',
                'meta': {'section': 'intro'},
              },
            ],
            'artifacts': [
              {
                'kind': 'text',
                'path': '/tmp/out.md',
                'mime': 'text/markdown',
                'previewUrl': 'https://example.com/out',
                'metadata': {'size': 10},
              },
            ],
          },
        ],
      });

      expect(graph.workflow.id, 'w1');
      expect(graph.revisions, hasLength(1));
      expect(graph.nodes, hasLength(1));
      expect(graph.candidates, hasLength(1));
      expect(graph.decisions, hasLength(1));
      expect(graph.assemblies, hasLength(1));
      expect(graph.candidates.first.artifacts.first.previewUrl,
          'https://example.com/a');
      expect(graph.assemblies.first.items.first.candidateId, 'c1');
    });

    test('fromJson handles empty lists', () {
      final graph = WorkflowGraph.fromJson({
        'workflow': {'id': 'w-empty'},
        'revisions': <dynamic>[],
        'nodes': <dynamic>[],
        'candidates': <dynamic>[],
        'decisions': <dynamic>[],
        'assemblies': <dynamic>[],
      });

      expect(graph.revisions, isEmpty);
      expect(graph.nodes, isEmpty);
      expect(graph.candidates, isEmpty);
      expect(graph.decisions, isEmpty);
      expect(graph.assemblies, isEmpty);
    });

    test('fromJson filters non-Map list items via whereType', () {
      final graph = WorkflowGraph.fromJson({
        'workflow': {'id': 'w-filter'},
        'revisions': [
          {'id': 'r1'},
          'bad',
          123,
        ],
        'nodes': [
          {'id': 'n1'},
          true,
        ],
        'candidates': [
          {'id': 'c1'},
          null,
        ],
        'decisions': [
          {'id': 'd1'},
          42,
        ],
        'assemblies': [
          {'id': 'a1'},
          'skip',
        ],
      });

      expect(graph.revisions, hasLength(1));
      expect(graph.nodes, hasLength(1));
      expect(graph.candidates, hasLength(1));
      expect(graph.decisions, hasLength(1));
      expect(graph.assemblies, hasLength(1));
    });
  });

  group('WorkflowCreateResult', () {
    test('fromJson success case', () {
      final result = WorkflowCreateResult.fromJson({
        'ok': true,
        'workflow_id': 'wf-1',
        'task_id': 'task-1',
        'state': 'created',
        'message': 'created',
      });

      expect(result.ok, isTrue);
      expect(result.workflowId, 'wf-1');
      expect(result.taskId, 'task-1');
      expect(result.error, isNull);
    });

    test('fromJson failure case with error', () {
      final result = WorkflowCreateResult.fromJson({
        'ok': false,
        'error': 'invalid input',
      });

      expect(result.ok, isFalse);
      expect(result.error, 'invalid input');
    });
  });

  group('WorkflowNode', () {
    test('fromJson/toJson round-trip', () {
      final node = WorkflowNode.fromJson({
        'id': 'n1',
        'revisionId': 'r1',
        'kind': 'draft',
        'state': 'ready',
        'title': 'Node1',
        'assignee': 'alice',
        'sequence': 3,
      });
      final roundTrip = WorkflowNode.fromJson(node.toJson());
      expect(roundTrip.toJson(), equals(node.toJson()));
    });

    test('fromJson supports snake_case revision_id', () {
      final node = WorkflowNode.fromJson({'id': 'n2', 'revision_id': 'r2'});
      expect(node.revisionId, 'r2');
    });
  });

  group('WorkflowCandidate/WorkflowArtifact', () {
    test('WorkflowCandidate fromJson with artifacts', () {
      final candidate = WorkflowCandidate.fromJson({
        'id': 'c1',
        'node_id': 'n1',
        'status': 'ready',
        'provider': 'llm',
        'summary': 'sum',
        'score': 0.75,
        'metrics': {'latency_ms': 100},
        'artifacts': [
          {
            'kind': 'image',
            'path': '/tmp/p.png',
            'mime': 'image/png',
            'preview_url': 'https://example.com/p.png',
            'metadata': {'w': 10},
          },
        ],
      });

      expect(candidate.nodeId, 'n1');
      expect(candidate.artifacts, hasLength(1));
      expect(candidate.artifacts.first.previewUrl, 'https://example.com/p.png');
    });

    test('WorkflowCandidate fromJson with empty artifacts', () {
      final candidate = WorkflowCandidate.fromJson({'id': 'c2'});
      expect(candidate.artifacts, isEmpty);
    });

    test('WorkflowArtifact fromJson/toJson round-trip', () {
      final artifact = WorkflowArtifact.fromJson({
        'kind': 'text',
        'path': '/tmp/file.txt',
        'mime': 'text/plain',
        'previewUrl': 'https://example.com/file.txt',
        'metadata': {'size': 1},
      });
      final roundTrip = WorkflowArtifact.fromJson(artifact.toJson());
      expect(roundTrip.toJson(), equals(artifact.toJson()));
    });
  });

  group('WorkflowAssembly/WorkflowAssemblyItem', () {
    test('WorkflowAssembly fromJson with items and artifacts', () {
      final assembly = WorkflowAssembly.fromJson({
        'id': 'a1',
        'status': 'built',
        'summary': 'assembled',
        'items': [
          {
            'order': 2,
            'node_id': 'n1',
            'candidate_id': 'c1',
            'role': 'secondary',
            'meta': {'k': 'v'},
          },
        ],
        'artifacts': [
          {
            'kind': 'text',
            'path': '/tmp/out.md',
            'mime': 'text/markdown',
            'preview_url': 'https://example.com/out',
            'metadata': {'v': 1},
          },
        ],
      });

      expect(assembly.items, hasLength(1));
      expect(assembly.artifacts, hasLength(1));
      expect(assembly.items.first.nodeId, 'n1');
    });

    test('WorkflowAssemblyItem fromJson/toJson round-trip', () {
      final item = WorkflowAssemblyItem.fromJson({
        'order': 1,
        'nodeId': 'n2',
        'candidateId': 'c2',
        'role': 'primary',
        'meta': {'x': 2},
      });
      final roundTrip = WorkflowAssemblyItem.fromJson(item.toJson());
      expect(roundTrip.toJson(), equals(item.toJson()));
    });
  });

  group('WorkflowRevision', () {
    test('fromJson/toJson round-trip with snake_case aliases', () {
      final revision = WorkflowRevision.fromJson({
        'id': 'r1',
        'number': 4,
        'status': 'open',
        'created_by': 'alice',
        'source': 'agent',
        'content': 'body',
        'change_summary': 'changes',
        'parent_revision_id': 'r0',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-02',
      });

      expect(revision.createdBy, 'alice');
      expect(revision.changeSummary, 'changes');
      expect(revision.parentRevisionId, 'r0');

      final roundTrip = WorkflowRevision.fromJson(revision.toJson());
      expect(roundTrip.toJson(), equals(revision.toJson()));
    });
  });

  group('WorkflowDecision', () {
    test('fromJson/toJson round-trip', () {
      final decision = WorkflowDecision.fromJson({
        'id': 'd1',
        'targetType': 'candidate',
        'targetId': 'c1',
        'action': 'reject',
        'actor': 'reviewer',
        'comment': 'needs work',
      });

      final roundTrip = WorkflowDecision.fromJson(decision.toJson());
      expect(roundTrip.toJson(), equals(decision.toJson()));
    });
  });

  group('ActionResult', () {
    test('fromJson success with accepted/entryId', () {
      final result = ActionResult.fromJson({
        'ok': true,
        'accepted': true,
        'entry_id': 'e1',
        'task_id': 't1',
        'message': 'accepted',
      });

      expect(result.ok, isTrue);
      expect(result.accepted, isTrue);
      expect(result.entryId, 'e1');
      expect(result.taskId, 't1');
      expect(result.error, isNull);
    });

    test('fromJson failure with error', () {
      final result = ActionResult.fromJson({
        'ok': false,
        'error': 'boom',
      });

      expect(result.ok, isFalse);
      expect(result.error, 'boom');
    });
  });

  group('Heartbeat/Todo enum helpers', () {
    test('heartbeatStatusFromJson handles all values + unknown', () {
      expect(heartbeatStatusFromJson('active'), HeartbeatStatus.active);
      expect(heartbeatStatusFromJson('warn'), HeartbeatStatus.warn);
      expect(heartbeatStatusFromJson('stalled'), HeartbeatStatus.stalled);
      expect(heartbeatStatusFromJson('idle'), HeartbeatStatus.idle);
      expect(heartbeatStatusFromJson('unknown'), HeartbeatStatus.unknown);
      expect(heartbeatStatusFromJson('unexpected'), HeartbeatStatus.unknown);
      expect(heartbeatStatusFromJson(null), HeartbeatStatus.unknown);
    });

    test('todoStatusFromJson handles all values + unknown', () {
      expect(todoStatusFromJson('not-started'), TodoStatus.notStarted);
      expect(todoStatusFromJson('notStarted'), TodoStatus.notStarted);
      expect(todoStatusFromJson('in-progress'), TodoStatus.inProgress);
      expect(todoStatusFromJson('inProgress'), TodoStatus.inProgress);
      expect(todoStatusFromJson('completed'), TodoStatus.completed);
      expect(todoStatusFromJson('other'), TodoStatus.notStarted);
      expect(todoStatusFromJson(null), TodoStatus.notStarted);
    });

    test('heartbeatStatusToJson round-trip', () {
      for (final status in HeartbeatStatus.values) {
        final json = heartbeatStatusToJson(status);
        expect(heartbeatStatusFromJson(json), status);
      }
    });

    test('todoStatusToJson round-trip', () {
      for (final status in TodoStatus.values) {
        final json = todoStatusToJson(status);
        expect(todoStatusFromJson(json), status);
      }
    });
  });

  group('WorkflowTimelineEvent', () {
    test('fromJson parses fields and timelineKey getter', () {
      final event = WorkflowTimelineEvent.fromJson({
        'kind': 'decision',
        'id': 'd1',
        'at': '2026-01-03T00:00:00Z',
        'action': 'approve',
        'actor': 'reviewer',
        'target_type': 'candidate',
        'target_id': 'c1',
        'extra': 'raw-field',
      });

      expect(event.kind, 'decision');
      expect(event.targetType, 'candidate');
      expect(event.targetId, 'c1');
      expect(event.raw['extra'], 'raw-field');
      expect(event.timelineKey, 'decision:d1');
    });
  });
}
