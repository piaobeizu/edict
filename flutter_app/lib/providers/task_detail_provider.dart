import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';
import 'live_status_provider.dart';

final taskActivityProvider = AsyncNotifierProviderFamily<
    TaskActivityNotifier,
    TaskActivityData,
    String>(TaskActivityNotifier.new);

class TaskActivityNotifier extends FamilyAsyncNotifier<TaskActivityData, String> {
  Timer? _pollTimer;
  late String _taskId;

  @override
  Future<TaskActivityData> build(String arg) async {
    _taskId = arg;

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_canPollTask()) {
        unawaited(_refreshSilently());
      }
    });

    ref.onDispose(() {
      _pollTimer?.cancel();
    });

    return _fetch();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<TaskActivityData>();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> _refreshSilently() async {
    try {
      final next = await _fetch();
      state = AsyncData<TaskActivityData>(next);
    } catch (_) {
      // Keep previous value during background polling failures.
    }
  }

  Future<TaskActivityData> _fetch() async {
    final api = ref.read(apiClientProvider);
    return api.taskActivity(_taskId);
  }

  bool _canPollTask() {
    final task = ref.read(taskByIdProvider(_taskId));
    if (task == null) {
      return true;
    }
    return !_isTerminalState(task.state);
  }
}

final schedulerStateProvider = AsyncNotifierProviderFamily<
    SchedulerStateNotifier,
    SchedulerStateData,
    String>(SchedulerStateNotifier.new);

class SchedulerStateNotifier
    extends FamilyAsyncNotifier<SchedulerStateData, String> {
  Timer? _pollTimer;
  late String _taskId;

  @override
  Future<SchedulerStateData> build(String arg) async {
    _taskId = arg;

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_canPollTask()) {
        unawaited(_refreshSilently());
      }
    });

    ref.onDispose(() {
      _pollTimer?.cancel();
    });

    return _fetch();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<SchedulerStateData>();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> _refreshSilently() async {
    try {
      final next = await _fetch();
      state = AsyncData<SchedulerStateData>(next);
    } catch (_) {
      // Keep previous value during background polling failures.
    }
  }

  Future<SchedulerStateData> _fetch() async {
    final api = ref.read(apiClientProvider);
    return api.schedulerState(_taskId);
  }

  bool _canPollTask() {
    final task = ref.read(taskByIdProvider(_taskId));
    if (task == null) {
      return true;
    }
    return !_isTerminalState(task.state);
  }
}

bool _isTerminalState(String state) {
  return state == 'Done' || state == 'Cancelled';
}
