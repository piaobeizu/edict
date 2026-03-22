import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/poller.dart';
import '../models/workflow.dart';
import '../services/workflow_event_stream_service.dart';
import 'api_provider.dart' show apiClientProvider;
import 'workflow_provider.dart';

class PendingWorkflowMutation {
  final String id;
  final String eventType;
  final String? taskId;
  final String? targetType;
  final String? targetId;
  final DateTime startedAt;
  final DateTime? acceptedAt;
  final String status; // pending | confirmed | timed_out | failed

  const PendingWorkflowMutation({
    required this.id,
    required this.eventType,
    this.taskId,
    this.targetType,
    this.targetId,
    required this.startedAt,
    this.acceptedAt,
    required this.status,
  });

  PendingWorkflowMutation copyWith({
    String? status,
    DateTime? acceptedAt,
  }) {
    return PendingWorkflowMutation(
      id: id,
      eventType: eventType,
      taskId: taskId,
      targetType: targetType,
      targetId: targetId,
      startedAt: startedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      status: status ?? this.status,
    );
  }
}

class WorkflowEventsState {
  final bool connected;
  final bool dirty;
  final DateTime? lastEventAt;
  final String? lastEventType;
  final List<String> recentEventKeys;
  final Map<String, PendingWorkflowMutation> pendingMutations;

  const WorkflowEventsState({
    required this.connected,
    required this.dirty,
    required this.lastEventAt,
    required this.lastEventType,
    required this.recentEventKeys,
    required this.pendingMutations,
  });

  factory WorkflowEventsState.initial() => const WorkflowEventsState(
        connected: false,
        dirty: false,
        lastEventAt: null,
        lastEventType: null,
        recentEventKeys: <String>[],
        pendingMutations: <String, PendingWorkflowMutation>{},
      );

  WorkflowEventsState copyWith({
    bool? connected,
    bool? dirty,
    DateTime? lastEventAt,
    String? lastEventType,
    List<String>? recentEventKeys,
    Map<String, PendingWorkflowMutation>? pendingMutations,
  }) {
    return WorkflowEventsState(
      connected: connected ?? this.connected,
      dirty: dirty ?? this.dirty,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      lastEventType: lastEventType ?? this.lastEventType,
      recentEventKeys: recentEventKeys ?? this.recentEventKeys,
      pendingMutations: pendingMutations ?? this.pendingMutations,
    );
  }
}

final workflowEventsProvider = AsyncNotifierProviderFamily<
    WorkflowEventsNotifier, WorkflowEventsState, String>(
  WorkflowEventsNotifier.new,
);

class WorkflowEventsNotifier
    extends FamilyAsyncNotifier<WorkflowEventsState, String> {
  Poller? _fallbackPoller;
  Poller? _safetyPoller;
  Timer? _pendingCheckTimer;
  Timer? _reconnectTimer;
  StreamSubscription<WorkflowStreamSignal>? _streamSub;
  WorkflowEventStreamService? _streamService;
  late String _workflowId;
  bool _fallbackActive = false;

  @override
  Future<WorkflowEventsState> build(String arg) async {
    _workflowId = arg;
    _streamService = createWorkflowEventStreamService(
        apiClient: ref.read(apiClientProvider));

    // Initial phase: keep polling until SSE becomes healthy.
    _setFallbackPolling(true, runImmediately: true);
    // Even when SSE is healthy, keep a low-frequency safety reconcile.
    _safetyPoller = Poller(
      interval: const Duration(seconds: 30),
      task: () async {
        await _reconcileAll();
      },
    )..start();
    _connectStream();

    _pendingCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkPendingTimeout();
      if (_fallbackActive) {
        unawaited(_reconcileAll());
      }
    });

    ref.onDispose(() {
      _fallbackPoller?.dispose();
      _safetyPoller?.dispose();
      _pendingCheckTimer?.cancel();
      _reconnectTimer?.cancel();
      _streamSub?.cancel();
      unawaited(_streamService?.dispose() ?? Future<void>.value());
    });

    return WorkflowEventsState.initial().copyWith(connected: false);
  }

  void _setFallbackPolling(bool active, {bool runImmediately = false}) {
    _fallbackActive = active;
    if (active) {
      _fallbackPoller ??= Poller(
        interval: const Duration(seconds: 2),
        task: () async {
          await _reconcileAll();
        },
      );
      _fallbackPoller!.start(runImmediately: runImmediately);
      return;
    }
    _fallbackPoller?.dispose();
    _fallbackPoller = null;
  }

  void _connectStream() {
    _reconnectTimer?.cancel();
    _streamSub?.cancel();
    final streamService = _streamService;
    if (streamService == null) {
      _setFallbackPolling(true, runImmediately: true);
      return;
    }
    _streamSub = streamService.connect(_workflowId).listen(
      _handleStreamSignal,
      onError: (_) {
        _markDisconnected('sse:error');
        _scheduleReconnect();
      },
      onDone: () {
        _markDisconnected('sse:closed');
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _connectStream);
  }

  void _markDisconnected(String reason) {
    _setFallbackPolling(true, runImmediately: true);
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    final now = DateTime.now();
    state = AsyncData(
      current.copyWith(
        connected: false,
        dirty: true,
        lastEventAt: now,
        lastEventType: reason,
        recentEventKeys: _appendRecent(
          current.recentEventKeys,
          '$reason:${now.millisecondsSinceEpoch}',
        ),
      ),
    );
  }

  void _handleStreamSignal(WorkflowStreamSignal signal) {
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    final now = DateTime.now();
    if (signal.kind == 'connected') {
      _setFallbackPolling(false);
      state = AsyncData(
        current.copyWith(
          connected: true,
          lastEventAt: now,
          lastEventType: 'sse:connected',
          recentEventKeys: _appendRecent(
            current.recentEventKeys,
            'sse:connected:${now.millisecondsSinceEpoch}',
          ),
        ),
      );
      unawaited(_reconcileAll());
      return;
    }
    if (signal.kind == 'event') {
      final eventType = (signal.eventType ?? '').trim();
      final topic = (signal.topic ?? '').trim();
      final label = eventType.isNotEmpty
          ? 'sse:event:$eventType'
          : 'sse:event:${topic.isEmpty ? "unknown" : topic}';
      state = AsyncData(
        current.copyWith(
          connected: true,
          dirty: true,
          lastEventAt: now,
          lastEventType: label,
          recentEventKeys: _appendRecent(
            current.recentEventKeys,
            '$label:${now.millisecondsSinceEpoch}',
          ),
        ),
      );
      unawaited(_reconcileAll());
      return;
    }
    _markDisconnected(signal.reason ?? 'sse:disconnected');
  }

  void registerPendingMutation({
    required String mutationId,
    required String eventType,
    String? taskId,
    String? targetType,
    String? targetId,
  }) {
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    final pending = Map<String, PendingWorkflowMutation>.from(
      current.pendingMutations,
    );
    pending[mutationId] = PendingWorkflowMutation(
      id: mutationId,
      eventType: eventType,
      taskId: taskId,
      targetType: targetType,
      targetId: targetId,
      startedAt: DateTime.now(),
      acceptedAt: null,
      status: 'pending',
    );
    state = AsyncData(current.copyWith(pendingMutations: pending));
  }

  void clearFailedMutations({
    String? eventType,
    String? targetType,
    String? targetId,
  }) {
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    if (current.pendingMutations.isEmpty) {
      return;
    }
    final eventTypeLower = (eventType ?? '').toLowerCase();
    final targetTypeLower = (targetType ?? '').toLowerCase();
    final targetIdLower = (targetId ?? '').toLowerCase();
    final next = <String, PendingWorkflowMutation>{};
    for (final entry in current.pendingMutations.entries) {
      final mutation = entry.value;
      final isFailed = mutation.status == 'failed';
      final eventMatched = eventTypeLower.isEmpty ||
          mutation.eventType.toLowerCase() == eventTypeLower;
      final targetTypeMatched = targetTypeLower.isEmpty ||
          (mutation.targetType ?? '').toLowerCase() == targetTypeLower;
      final targetIdMatched = targetIdLower.isEmpty ||
          (mutation.targetId ?? '').toLowerCase() == targetIdLower;
      final shouldDrop =
          isFailed && eventMatched && targetTypeMatched && targetIdMatched;
      if (!shouldDrop) {
        next[entry.key] = mutation;
      }
    }
    if (next.length == current.pendingMutations.length) {
      return;
    }
    state = AsyncData(current.copyWith(pendingMutations: next));
  }

  Future<void> reconcileNow() async {
    await _reconcileAll();
  }

  void clearDirty() {
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    state = AsyncData(current.copyWith(dirty: false));
  }

  void _checkPendingTimeout() {
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    if (current.pendingMutations.isEmpty) {
      return;
    }
    var hasChange = false;
    final now = DateTime.now();
    final next = Map<String, PendingWorkflowMutation>.from(
      current.pendingMutations,
    );
    for (final entry in current.pendingMutations.entries) {
      final mutation = entry.value;
      if (mutation.status == 'pending' &&
          now.difference(mutation.startedAt) > const Duration(seconds: 30)) {
        hasChange = true;
        next[entry.key] = mutation.copyWith(status: 'timed_out');
        continue;
      }
      if (mutation.status == 'timed_out' &&
          now.difference(mutation.startedAt) > const Duration(seconds: 90)) {
        // Avoid keeping buttons blocked forever when backend events are lost.
        hasChange = true;
        next[entry.key] = mutation.copyWith(status: 'failed');
        continue;
      }
      if (mutation.status == 'failed' &&
          now.difference(mutation.startedAt) > const Duration(minutes: 3)) {
        hasChange = true;
        next.remove(entry.key);
      }
    }
    if (!hasChange) {
      return;
    }
    state = AsyncData(current.copyWith(pendingMutations: next, dirty: true));
    unawaited(_reconcileAll());
  }

  Future<void> _reconcileAll() async {
    final current = state.valueOrNull ?? WorkflowEventsState.initial();
    final nextPending = Map<String, PendingWorkflowMutation>.from(
      current.pendingMutations,
    );
    try {
      ref.invalidate(workflowSyncSnapshotProvider(_workflowId));
      final sync =
          await ref.read(workflowSyncSnapshotProvider(_workflowId).future);
      final summary = sync.workflow;
      final graph = sync.graph;
      for (final entry in current.pendingMutations.entries) {
        final mutation = entry.value;
        if (mutation.status != 'pending' &&
            mutation.status != 'timed_out' &&
            mutation.status != 'failed') {
          continue;
        }
        if (_isMutationConfirmedBySnapshot(
          mutation: mutation,
          workflowStateRaw: summary.state,
          graph: graph,
        )) {
          nextPending.remove(entry.key);
        }
      }
      final now = DateTime.now();
      final recent = _appendRecent(
        current.recentEventKeys,
        'poll:workflow.snapshot:${now.millisecondsSinceEpoch}',
      );
      state = AsyncData(
        current.copyWith(
          dirty: false,
          lastEventAt: now,
          lastEventType: 'poll:workflow.snapshot',
          recentEventKeys: recent,
          pendingMutations: nextPending,
        ),
      );
    } catch (_) {
      // Keep local pending state when snapshot fetch fails.
      final now = DateTime.now();
      final recent = _appendRecent(
        current.recentEventKeys,
        'poll:error:${now.millisecondsSinceEpoch}',
      );
      state = AsyncData(
        current.copyWith(
          dirty: true,
          lastEventAt: now,
          lastEventType: 'poll:error',
          recentEventKeys: recent,
          pendingMutations: nextPending,
        ),
      );
    }
  }

  bool _isMutationConfirmedBySnapshot({
    required PendingWorkflowMutation mutation,
    required String workflowStateRaw,
    required WorkflowGraph graph,
  }) {
    final mutationEvent = mutation.eventType.toLowerCase();
    final state = workflowStateRaw.toLowerCase();
    if (mutationEvent == 'workflow.v2.command.start_planning') {
      return state == 'planning' ||
          state == 'awaiting_plan_review' ||
          state == 'executing' ||
          state == 'awaiting_final_review' ||
          state == 'done';
    }
    if (mutationEvent == 'workflow.v2.command.submit_plan') {
      return state == 'awaiting_plan_review' ||
          state == 'executing' ||
          state == 'awaiting_final_review' ||
          state == 'done';
    }
    if (mutationEvent == 'workflow.v2.command.approve_plan') {
      return state == 'executing' ||
          state == 'awaiting_final_review' ||
          state == 'done';
    }
    if (mutationEvent == 'workflow.v2.command.reject_plan') {
      return state == 'planning';
    }
    if (mutationEvent == 'workflow.v2.command.rollback') {
      return state == 'planning';
    }
    if (mutationEvent == 'workflow.v2.command.stop') {
      return state == 'blocked';
    }
    if (mutationEvent == 'workflow.v2.command.cancel') {
      return state == 'cancelled';
    }
    if (mutationEvent == 'workflow.v2.command.resume') {
      return state == 'planning';
    }
    if (mutationEvent == 'workflow.v2.command.approve_assembly') {
      final targetAssemblyId = (mutation.targetId ?? '').trim();
      if (state == 'done') {
        return true;
      }
      if (targetAssemblyId.isEmpty) {
        return graph.assemblies
            .any((item) => item.status.toLowerCase() == 'approved');
      }
      return graph.assemblies.any(
        (item) =>
            item.id == targetAssemblyId &&
            item.status.toLowerCase() == 'approved',
      );
    }
    if (mutationEvent == 'workflow.v2.command.reject_assembly') {
      return state == 'executing';
    }
    if (mutationEvent == 'workflow.v2.command.node_progress') {
      final targetNodeId = (mutation.targetId ?? '').trim();
      if (targetNodeId.isEmpty) {
        return graph.nodes.any((item) => item.state.toLowerCase() != 'pending');
      }
      final node = graph.nodes.where((item) => item.id == targetNodeId);
      if (node.isEmpty) {
        return false;
      }
      return node.first.state.toLowerCase() != 'pending';
    }
    if (mutationEvent == 'workflow.v2.command.complete_candidate') {
      final targetCandidateId = (mutation.targetId ?? '').trim();
      if (targetCandidateId.isEmpty) {
        return graph.candidates.any(
          (item) => {'produced', 'approved', 'failed', 'rejected'}
              .contains(item.status.toLowerCase()),
        );
      }
      final candidate =
          graph.candidates.where((item) => item.id == targetCandidateId);
      if (candidate.isEmpty) {
        return false;
      }
      return {'produced', 'approved', 'failed', 'rejected'}
          .contains(candidate.first.status.toLowerCase());
    }
    if (mutationEvent == 'workflow.v2.command.select_candidate') {
      final targetCandidateId = (mutation.targetId ?? '').trim();
      if (targetCandidateId.isNotEmpty &&
          graph.candidates.any((item) =>
              item.id == targetCandidateId &&
              item.status.toLowerCase() == 'approved')) {
        return true;
      }
      return graph.decisions.any((item) =>
          item.action.toLowerCase() == 'select' &&
          item.targetType.toLowerCase() == 'candidate' &&
          (targetCandidateId.isEmpty || item.targetId == targetCandidateId));
    }
    if (mutationEvent == 'workflow.v2.command.regenerate_node') {
      final targetNodeId = (mutation.targetId ?? '').trim();
      if (targetNodeId.isEmpty) {
        return graph.candidates.isNotEmpty;
      }
      return graph.candidates.any((item) => item.nodeId == targetNodeId);
    }
    return false;
  }

  List<String> _appendRecent(List<String> current, String key) {
    final recent = <String>[...current, key];
    if (recent.length > 20) {
      recent.removeRange(0, recent.length - 20);
    }
    return recent;
  }
}
