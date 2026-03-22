import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';

const Duration _syncHintTtl = Duration(seconds: 30);

class WorkflowProjectionSyncHint {
  final String workflowId;
  final String taskId;
  final DateTime startedAt;
  final int? baseProjectionVersion;

  const WorkflowProjectionSyncHint({
    required this.workflowId,
    required this.taskId,
    required this.startedAt,
    required this.baseProjectionVersion,
  });
}

class WorkflowProjectionSyncNotifier
    extends StateNotifier<Map<String, WorkflowProjectionSyncHint>> {
  WorkflowProjectionSyncNotifier()
      : super(const <String, WorkflowProjectionSyncHint>{});

  void markSyncing({
    required String workflowId,
    required String taskId,
    required int? baseProjectionVersion,
  }) {
    final next = <String, WorkflowProjectionSyncHint>{...state};
    final now = DateTime.now();
    next.removeWhere(
      (_, v) => now.difference(v.startedAt) > _syncHintTtl,
    );
    next[workflowId] = WorkflowProjectionSyncHint(
      workflowId: workflowId,
      taskId: taskId,
      startedAt: now,
      baseProjectionVersion: baseProjectionVersion,
    );
    state = next;
  }

  void clearWorkflow(String workflowId) {
    final next = <String, WorkflowProjectionSyncHint>{...state};
    next.remove(workflowId);
    state = next;
  }

  void reconcileWithTasks(List<Task> tasks) {
    if (state.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final byWorkflow = <String, Task>{};
    for (final task in tasks) {
      if (!isWorkflowV2Task(task)) {
        continue;
      }
      final workflowId = taskWorkflowId(task);
      if (workflowId.isEmpty) {
        continue;
      }
      byWorkflow[workflowId] = task;
    }

    final next = <String, WorkflowProjectionSyncHint>{};
    for (final entry in state.entries) {
      final hint = entry.value;
      if (now.difference(hint.startedAt) > _syncHintTtl) {
        continue;
      }
      final task = byWorkflow[hint.workflowId];
      if (task == null) {
        continue;
      }
      final base = hint.baseProjectionVersion;
      final current = task.projectionVersion;
      if (base != null && current != null && current > base) {
        continue;
      }
      next[entry.key] = hint;
    }
    if (next.length != state.length) {
      state = next;
    }
  }
}

final workflowProjectionSyncProvider = StateNotifierProvider<
    WorkflowProjectionSyncNotifier, Map<String, WorkflowProjectionSyncHint>>(
  (ref) => WorkflowProjectionSyncNotifier(),
);

bool shouldShowWorkflowProjectionSyncBadge({
  required Task task,
  required Map<String, WorkflowProjectionSyncHint> hints,
  DateTime? now,
}) {
  if (!isWorkflowV2Task(task)) {
    return false;
  }
  final workflowId = taskWorkflowId(task);
  final hint = hints[workflowId];
  if (hint == null) {
    return false;
  }
  final nowTime = now ?? DateTime.now();
  if (nowTime.difference(hint.startedAt) > _syncHintTtl) {
    return false;
  }
  final base = hint.baseProjectionVersion;
  final current = task.projectionVersion;
  if (base != null && current != null && current > base) {
    return false;
  }
  return true;
}

int compareTasksByWorkflowSyncHint({
  required Task left,
  required Task right,
  required Map<String, WorkflowProjectionSyncHint> hints,
  DateTime? now,
}) {
  final nowTime = now ?? DateTime.now();
  final leftHint = _activeHintForTask(task: left, hints: hints, now: nowTime);
  final rightHint = _activeHintForTask(task: right, hints: hints, now: nowTime);

  if (leftHint != null && rightHint == null) {
    return -1;
  }
  if (leftHint == null && rightHint != null) {
    return 1;
  }

  if (leftHint != null && rightHint != null) {
    final byHintStarted = rightHint.startedAt.compareTo(leftHint.startedAt);
    if (byHintStarted != 0) {
      return byHintStarted;
    }
  }

  final leftUpdated = _parseDateTime(left.updatedAt);
  final rightUpdated = _parseDateTime(right.updatedAt);
  final byUpdated = rightUpdated.compareTo(leftUpdated);
  if (byUpdated != 0) {
    return byUpdated;
  }
  return left.id.compareTo(right.id);
}

WorkflowProjectionSyncHint? _activeHintForTask({
  required Task task,
  required Map<String, WorkflowProjectionSyncHint> hints,
  required DateTime now,
}) {
  if (!isWorkflowV2Task(task)) {
    return null;
  }
  final workflowId = taskWorkflowId(task);
  if (workflowId.isEmpty) {
    return null;
  }
  final hint = hints[workflowId];
  if (hint == null) {
    return null;
  }
  if (now.difference(hint.startedAt) > _syncHintTtl) {
    return null;
  }
  final base = hint.baseProjectionVersion;
  final current = task.projectionVersion;
  if (base != null && current != null && current > base) {
    return null;
  }
  return hint;
}

DateTime _parseDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}
