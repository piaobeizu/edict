// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'api_client.dart';
import 'workflow_event_stream_service.dart';

class _WorkflowEventStreamServiceWeb implements WorkflowEventStreamService {
  _WorkflowEventStreamServiceWeb({required this.apiClient});

  final ApiClient apiClient;
  html.EventSource? _eventSource;
  StreamController<WorkflowStreamSignal>? _controller;
  StreamSubscription<html.Event>? _openSub;
  StreamSubscription<html.MessageEvent>? _messageSub;
  StreamSubscription<html.Event>? _errorSub;

  @override
  Stream<WorkflowStreamSignal> connect(String workflowId) {
    unawaited(dispose());
    _controller?.close();
    _controller = StreamController<WorkflowStreamSignal>(
      onCancel: () {
        unawaited(dispose());
      },
    );

    final url = apiClient.resolveUrl(
      '/api/workflows/${Uri.encodeComponent(workflowId)}/events/stream',
    );
    final source = html.EventSource(url);
    _eventSource = source;

    _openSub = source.onOpen.listen((_) {
      _controller?.add(WorkflowStreamSignal.connected());
    });

    _messageSub = source.onMessage.listen((message) {
      try {
        final raw = message.data;
        if (raw is! String || raw.isEmpty) {
          return;
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          return;
        }
        final eventMap = Map<String, dynamic>.from(decoded);
        final kind = (eventMap['kind'] ?? '').toString();
        if (kind == 'connected') {
          _controller?.add(WorkflowStreamSignal.connected());
          return;
        }
        final topic = (eventMap['topic'] ?? '').toString();
        final eventType = (eventMap['eventType'] ?? '').toString();
        if (kind != 'event' || (topic.isEmpty && eventType.isEmpty)) {
          return;
        }
        _controller?.add(
          WorkflowStreamSignal.event(topic: topic, eventType: eventType),
        );
      } catch (_) {
        // Ignore malformed payloads and keep stream alive.
      }
    });

    _errorSub = source.onError.listen((_) {
      _controller
          ?.add(WorkflowStreamSignal.disconnected(reason: 'stream_error'));
      _controller?.close();
      unawaited(dispose());
    });

    return _controller!.stream;
  }

  @override
  Future<void> dispose() async {
    await _openSub?.cancel();
    await _messageSub?.cancel();
    await _errorSub?.cancel();
    _openSub = null;
    _messageSub = null;
    _errorSub = null;
    _eventSource?.close();
    _eventSource = null;
  }
}

WorkflowEventStreamService createWorkflowEventStreamService({
  required ApiClient apiClient,
}) {
  return _WorkflowEventStreamServiceWeb(apiClient: apiClient);
}
