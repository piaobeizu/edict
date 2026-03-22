import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../models/models.dart';
import 'api_provider.dart';
import 'workflow_projection_sync_provider.dart';

enum TaskListFilter { active, archived, all }

final liveStatusProvider =
    AsyncNotifierProvider<LiveStatusNotifier, LiveStatus>(LiveStatusNotifier.new);

class LiveStatusNotifier extends AsyncNotifier<LiveStatus> {
  Timer? _pollTimer;

  @override
  Future<LiveStatus> build() async {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refresh(silent: true));
    });

    ref.onDispose(() {
      _pollTimer?.cancel();
    });

    return _fetchLiveStatus();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      state = const AsyncLoading<LiveStatus>();
    }

    try {
      final data = await _fetchLiveStatus();
      state = AsyncData<LiveStatus>(data);
    } catch (error, stackTrace) {
      if (!silent) {
        state = AsyncError<LiveStatus>(error, stackTrace);
      }
    }
  }

  Future<LiveStatus> _fetchLiveStatus() async {
    final api = ref.read(apiClientProvider);
    final data = await api.liveStatus();
    final normalized = _normalizeLiveStatus(data);
    ref
        .read(workflowProjectionSyncProvider.notifier)
        .reconcileWithTasks(normalized.tasks);
    return normalized;
  }
}

final edictFilterProvider =
    StateProvider<TaskListFilter>((_) => TaskListFilter.active);

final sessFilterProvider =
    StateProvider<TaskListFilter>((_) => TaskListFilter.active);

final filteredEdictsProvider = Provider<List<Task>>((ref) {
  final filter = ref.watch(edictFilterProvider);
  final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
  if (liveStatus == null) {
    return const <Task>[];
  }

  final edicts = liveStatus.tasks.where(_isEdictTask);
  final filtered = edicts.where((task) => _matchesFilter(task, filter)).toList();
  filtered.sort(_taskSortComparator);
  return filtered;
});

final filteredSessionsProvider = Provider<List<Task>>((ref) {
  final filter = ref.watch(sessFilterProvider);
  final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
  if (liveStatus == null) {
    return const <Task>[];
  }

  final sessions = liveStatus.tasks.where((task) => !_isEdictTask(task));
  final filtered = sessions.where((task) => _matchesFilter(task, filter)).toList();
  filtered.sort(_taskSortComparator);
  return filtered;
});

final taskByIdProvider = Provider.family<Task?, String>((ref, id) {
  final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
  if (liveStatus == null) {
    return null;
  }

  for (final task in liveStatus.tasks) {
    if (task.id == id) {
      return task;
    }
  }
  return null;
});

final edictCountProvider = Provider<int>((ref) {
  return ref.watch(filteredEdictsProvider).length;
});

final sessionCountProvider = Provider<int>((ref) {
  return ref.watch(filteredSessionsProvider).length;
});

final activeCountProvider = Provider<int>((ref) {
  final liveStatus = ref.watch(liveStatusProvider).valueOrNull;
  if (liveStatus == null) {
    return 0;
  }

  return liveStatus.tasks
      .where((task) => !task.archived && !_isTerminalState(task.state))
      .length;
});

final syncStatusProvider = Provider<SyncStatus?>((ref) {
  return ref.watch(liveStatusProvider).valueOrNull?.syncStatus;
});

LiveStatus _normalizeLiveStatus(LiveStatus source) {
  final deduped = <String, Task>{};

  for (final task in source.tasks) {
    final existing = deduped[task.id];
    if (existing == null) {
      deduped[task.id] = task;
      continue;
    }

    final incomingAt = _parseUpdatedAt(task.updatedAt);
    final currentAt = _parseUpdatedAt(existing.updatedAt);
    if (incomingAt.isAfter(currentAt)) {
      deduped[task.id] = task;
    }
  }

  final merged = deduped.values.toList();
  final active = <Task>[];
  final completed = <Task>[];

  for (final task in merged) {
    if (_isTerminalState(task.state) || task.archived) {
      completed.add(task);
    } else {
      active.add(task);
    }
  }

  return LiveStatus(
    tasks: <Task>[...active, ...completed],
    syncStatus: source.syncStatus,
  );
}

bool _isEdictTask(Task task) {
  final sourceMeta = task.sourceMeta ?? const <String, dynamic>{};

  final isEdictFlag = sourceMeta['isEdict'];
  if (isEdictFlag is bool) {
    return isEdictFlag;
  }

  final type = (sourceMeta['type'] ?? sourceMeta['taskType'] ?? sourceMeta['kind'])
      ?.toString()
      .toLowerCase();
  if (type == 'edict') {
    return true;
  }
  if (type == 'session') {
    return false;
  }

  final id = task.id.toLowerCase();
  if (id.startsWith('sess:') || id.startsWith('session-') || id.startsWith('sess_')) {
    return false;
  }

  final org = task.org.toLowerCase();
  if (org.contains('session')) {
    return false;
  }

  return true;
}

bool _matchesFilter(Task task, TaskListFilter filter) {
  switch (filter) {
    case TaskListFilter.active:
      return !task.archived;
    case TaskListFilter.archived:
      return task.archived;
    case TaskListFilter.all:
      return true;
  }
}

int _taskSortComparator(Task a, Task b) {
  final aOrder = kStateOrder[a.state] ?? 999;
  final bOrder = kStateOrder[b.state] ?? 999;
  if (aOrder != bOrder) {
    return aOrder.compareTo(bOrder);
  }

  final aUpdated = _parseUpdatedAt(a.updatedAt);
  final bUpdated = _parseUpdatedAt(b.updatedAt);
  return bUpdated.compareTo(aUpdated);
}

DateTime _parseUpdatedAt(String? value) {
  if (value == null || value.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

bool _isTerminalState(String state) {
  return state == 'Done' || state == 'Cancelled';
}
