import 'package:edict_app/core/utils.dart';
import 'package:edict_app/core/workflow_entry.dart';
import 'package:edict_app/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({
  String id = 'JJC-001',
  String state = 'Doing',
  int reviewRound = 0,
  bool archived = false,
  String workflowId = '',
  Map<String, dynamic>? sourceMeta,
}) {
  return Task(
    id: id,
    title: 'test',
    state: state,
    org: '',
    now: '',
    eta: '',
    block: '',
    ac: '',
    output: '',
    heartbeat: const Heartbeat(status: HeartbeatStatus.active, label: ''),
    flowLog: const [],
    todos: const [],
    reviewRound: reviewRound,
    archived: archived,
    workflowId: workflowId,
    sourceMeta: sourceMeta,
  );
}

void main() {
  group('isEdict', () {
    test('returns true for JJC- prefix case-insensitive', () {
      expect(isEdict(_task(id: 'JJC-001')), isTrue);
      expect(isEdict(_task(id: 'jjc-002')), isTrue);
    });

    test('returns false for non-JJC prefixes', () {
      expect(isEdict(_task(id: 'OC-abc-001')), isFalse);
      expect(isEdict(_task(id: 'MC-001')), isFalse);
    });
  });

  group('isSession', () {
    test('returns true for OC-/MC- prefixes', () {
      expect(isSession(_task(id: 'OC-hubu-001')), isTrue);
      expect(isSession(_task(id: 'MC-001')), isTrue);
    });

    test('returns false for non-session ids', () {
      expect(isSession(_task(id: 'JJC-001')), isFalse);
    });
  });

  group('isArchived', () {
    test('returns true when archived is true', () {
      expect(isArchived(_task(archived: true, state: 'Doing')), isTrue);
    });

    test('returns true for Done/Cancelled states', () {
      expect(isArchived(_task(archived: false, state: 'Done')), isTrue);
      expect(isArchived(_task(archived: false, state: 'Cancelled')), isTrue);
    });

    test('returns false otherwise', () {
      expect(isArchived(_task(archived: false, state: 'Doing')), isFalse);
    });
  });

  group('stateLabel', () {
    test('returns mapped labels and formatted review states', () {
      expect(stateLabel(_task(state: 'Doing')), '执行中');
      expect(stateLabel(_task(state: 'Done')), '已完成');
      expect(stateLabel(_task(state: 'Menxia', reviewRound: 2)), '门下审议（第2轮）');
      expect(stateLabel(_task(state: 'Zhongshu', reviewRound: 1)), '中书修订（第1轮）');
      expect(stateLabel(_task(state: 'YuLan')), '👑 待御批');
    });

    test('falls back to raw state for unknown values', () {
      expect(stateLabel(_task(state: 'UnknownState')), 'UnknownState');
    });
  });

  group('timeAgo', () {
    test('returns empty string for null/empty/invalid values', () {
      expect(timeAgo(null), '');
      expect(timeAgo(''), '');
      expect(timeAgo('not-a-date'), '');
    });

    test('returns 刚刚 for current timestamp', () {
      final nowIso = DateTime.now().toIso8601String();
      expect(timeAgo(nowIso), '刚刚');
    });
  });

  group('escHtml', () {
    test('escapes HTML special characters', () {
      expect(escHtml('<script>'), '&lt;script&gt;');
      expect(escHtml('a&b'), 'a&amp;b');
      expect(escHtml('"hello"'), '&quot;hello&quot;');
    });
  });

  group('getPipeStatus', () {
    test('marks Doing stage as active with prior done and later pending', () {
      final pipe = getPipeStatus(_task(state: 'Doing'));
      expect(pipe, hasLength(9));

      for (var i = 0; i <= 5; i++) {
        expect(pipe[i].status, PipeNodeStatus.done,
            reason: 'index $i should be done');
      }
      expect(pipe[6].status, PipeNodeStatus.active);
      expect(pipe[7].status, PipeNodeStatus.pending);
      expect(pipe[8].status, PipeNodeStatus.pending);
    });

    test('marks Done stage as active and all previous stages done', () {
      final pipe = getPipeStatus(_task(state: 'Done'));
      expect(pipe, hasLength(9));

      for (var i = 0; i <= 7; i++) {
        expect(pipe[i].status, PipeNodeStatus.done,
            reason: 'index $i should be done');
      }
      expect(pipe[8].status, PipeNodeStatus.active);
    });
  });

  group('resolveTaskEntryRoute', () {
    test('uses top-level workflowId when present', () {
      final route = resolveTaskEntryRoute(_task(workflowId: 'wf-1'));
      expect(route.workflowId, 'wf-1');
      expect(route.unresolved, isFalse);
    });

    test('returns unresolved when workflowId is empty and sourceMeta missing',
        () {
      final route = resolveTaskEntryRoute(_task(workflowId: ''));
      expect(route.workflowId, '');
      expect(route.unresolved, isTrue);
    });

    test('uses workflowId from sourceMeta when top-level is empty', () {
      final route = resolveTaskEntryRoute(
        _task(workflowId: '', sourceMeta: {'workflowId': 'wf-meta'}),
      );
      expect(route.workflowId, 'wf-meta');
      expect(route.unresolved, isFalse);
    });
  });
}
