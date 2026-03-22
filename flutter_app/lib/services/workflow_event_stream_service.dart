import 'workflow_event_stream_service_stub.dart'
    if (dart.library.html) 'workflow_event_stream_service_web.dart'
    if (dart.library.io) 'workflow_event_stream_service_io.dart' as impl;

import 'api_client.dart';

class WorkflowStreamSignal {
  final String kind; // connected | event | disconnected
  final String? topic;
  final String? eventType;
  final String? reason;

  const WorkflowStreamSignal._(
    this.kind, {
    this.topic,
    this.eventType,
    this.reason,
  });

  factory WorkflowStreamSignal.connected() =>
      const WorkflowStreamSignal._('connected');

  factory WorkflowStreamSignal.event({
    required String topic,
    required String eventType,
  }) =>
      WorkflowStreamSignal._(
        'event',
        topic: topic,
        eventType: eventType,
      );

  factory WorkflowStreamSignal.disconnected({String? reason}) =>
      WorkflowStreamSignal._('disconnected', reason: reason);
}

abstract class WorkflowEventStreamService {
  Stream<WorkflowStreamSignal> connect(String workflowId);
  Future<void> dispose();
}

WorkflowEventStreamService createWorkflowEventStreamService({
  required ApiClient apiClient,
}) {
  return impl.createWorkflowEventStreamService(apiClient: apiClient);
}
