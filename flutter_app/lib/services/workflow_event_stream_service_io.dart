import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_client.dart';
import 'workflow_event_stream_service.dart';

class _WorkflowEventStreamServiceIo implements WorkflowEventStreamService {
  _WorkflowEventStreamServiceIo({required this.apiClient});

  final ApiClient apiClient;
  HttpClient? _client;
  StreamSubscription<String>? _lineSub;
  bool _closed = false;

  @override
  Stream<WorkflowStreamSignal> connect(String workflowId) {
    _closed = false;
    final controller = StreamController<WorkflowStreamSignal>(
      onCancel: () {
        unawaited(dispose());
      },
    );

    unawaited(_run(controller, workflowId));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<WorkflowStreamSignal> controller,
    String workflowId,
  ) async {
    final dataLines = <String>[];

    void emitFrame() {
      if (dataLines.isEmpty) {
        return;
      }
      final dataRaw = dataLines.join('\n');
      dataLines.clear();
      try {
        final decoded = jsonDecode(dataRaw);
        if (decoded is! Map) {
          return;
        }
        final map = Map<String, dynamic>.from(decoded);
        final kind = (map['kind'] ?? '').toString();
        if (kind == 'connected') {
          controller.add(WorkflowStreamSignal.connected());
          return;
        }
        if (kind != 'event') {
          return;
        }
        final topic = (map['topic'] ?? '').toString();
        final eventType = (map['eventType'] ?? '').toString();
        if (topic.isNotEmpty || eventType.isNotEmpty) {
          controller.add(
            WorkflowStreamSignal.event(
              topic: topic,
              eventType: eventType,
            ),
          );
        }
      } catch (_) {
        // Ignore malformed event payload.
      }
    }

    try {
      _client = HttpClient();
      final uri = Uri.parse(
        apiClient.resolveUrl(
          '/api/workflows/${Uri.encodeComponent(workflowId)}/events/stream',
        ),
      );
      final request = await _client!.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'SSE connect failed: HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      _lineSub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (_closed) {
            return;
          }
          if (line.isEmpty) {
            emitFrame();
            return;
          }
          if (line.startsWith(':')) {
            return;
          }
          if (line.startsWith('event:')) {
            return;
          }
          if (line.startsWith('id:')) {
            return;
          }
          if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
            return;
          }
        },
        onDone: () {
          if (_closed || controller.isClosed) {
            return;
          }
          controller.add(
            WorkflowStreamSignal.disconnected(reason: 'stream_closed'),
          );
          controller.close();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_closed || controller.isClosed) {
            return;
          }
          controller.add(
            WorkflowStreamSignal.disconnected(reason: error.toString()),
          );
          controller.close();
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!controller.isClosed) {
        controller.add(WorkflowStreamSignal.disconnected(reason: e.toString()));
        await controller.close();
      }
    } finally {
      if (!_closed) {
        await dispose();
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    await _lineSub?.cancel();
    _lineSub = null;
    _client?.close(force: true);
    _client = null;
  }
}

WorkflowEventStreamService createWorkflowEventStreamService({
  required ApiClient apiClient,
}) {
  return _WorkflowEventStreamServiceIo(apiClient: apiClient);
}
