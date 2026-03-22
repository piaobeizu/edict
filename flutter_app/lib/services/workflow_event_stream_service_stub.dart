import 'api_client.dart';
import 'workflow_event_stream_service.dart';

class _UnsupportedWorkflowEventStreamService
    implements WorkflowEventStreamService {
  @override
  Stream<WorkflowStreamSignal> connect(String workflowId) async* {
    yield WorkflowStreamSignal.disconnected(reason: 'unsupported_platform');
  }

  @override
  Future<void> dispose() async {}
}

WorkflowEventStreamService createWorkflowEventStreamService({
  required ApiClient apiClient,
}) {
  return _UnsupportedWorkflowEventStreamService();
}
