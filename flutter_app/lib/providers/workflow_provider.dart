import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final workflowSyncSnapshotProvider =
    FutureProvider.family<WorkflowSyncSnapshot, String>(
  (ref, workflowId) async {
    final api = ref.read(apiClientProvider);
    return api.workflowSyncSnapshot(workflowId);
  },
);

final workflowSummaryProvider = FutureProvider.family<Workflow, String>(
  (ref, workflowId) async {
    final sync =
        await ref.watch(workflowSyncSnapshotProvider(workflowId).future);
    return sync.workflow;
  },
);

final workflowGraphProvider = FutureProvider.family<WorkflowGraph, String>(
  (ref, workflowId) async {
    final sync =
        await ref.watch(workflowSyncSnapshotProvider(workflowId).future);
    return sync.graph;
  },
);

final workflowTimelineProvider =
    FutureProvider.family<List<WorkflowTimelineEvent>, String>(
  (ref, workflowId) async {
    final sync =
        await ref.watch(workflowSyncSnapshotProvider(workflowId).future);
    return sync.timeline;
  },
);
