import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum _SocketTarget { global, task }

class WebSocketService {
  WebSocketService({String? wsBaseUrl}) : _wsBaseUrl = wsBaseUrl ?? _defaultWsBaseUrl();

  final String _wsBaseUrl;
  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  _SocketTarget? _target;
  String? _taskId;
  int _reconnectAttempts = 0;
  bool _manualDisconnect = false;
  bool _disposed = false;
  DateTime _lastPongAt = DateTime.now();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  Future<void> connectGlobal() async {
    _target = _SocketTarget.global;
    _taskId = null;
    _manualDisconnect = false;
    await _openConnection();
  }

  Future<void> connectTask(String taskId) async {
    _target = _SocketTarget.task;
    _taskId = taskId;
    _manualDisconnect = false;
    await _openConnection();
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _closeConnection();
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _eventsController.close();
  }

  Future<void> _openConnection() async {
    await _closeConnection();

    if (_disposed || _target == null) {
      return;
    }

    final uri = _target == _SocketTarget.global
        ? _buildUri('/ws')
        : _buildUri('/ws/task/${Uri.encodeComponent(_taskId!)}');

    _channel = WebSocketChannel.connect(uri);
    _lastPongAt = DateTime.now();

    _subscription = _channel!.stream.listen(
      _onData,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );

    _reconnectAttempts = 0;
    _startKeepalive();
  }

  void _onData(dynamic raw) {
    _lastPongAt = DateTime.now();

    final event = _decodeEvent(raw);
    if (event == null) {
      return;
    }

    final type = event['type'];
    if (type == 'pong') {
      return;
    }

    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  Map<String, dynamic>? _decodeEvent(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return <String, dynamic>{'type': 'message', 'data': raw};
      }
    }

    return null;
  }

  void _startKeepalive() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_channel == null) {
        return;
      }

      final staleFor = DateTime.now().difference(_lastPongAt);
      if (staleFor > const Duration(seconds: 90)) {
        _forceReconnect();
        return;
      }

      try {
        _channel!.sink.add(
          jsonEncode(
            <String, dynamic>{
              'type': 'ping',
              'ts': DateTime.now().toIso8601String(),
            },
          ),
        );
      } catch (_) {
        _forceReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || _target == null) {
      return;
    }

    if (_reconnectTimer != null) {
      return;
    }

    final exp = _reconnectAttempts < 5 ? _reconnectAttempts : 5;
    final delaySeconds = (1 << exp).clamp(1, 30);
    _reconnectAttempts += 1;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_disposed || _manualDisconnect) {
        return;
      }
      await _openConnection();
    });
  }

  void _forceReconnect() {
    unawaited(_closeConnection());
    _scheduleReconnect();
  }

  Future<void> _closeConnection() async {
    _pingTimer?.cancel();
    _pingTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {
      // Ignore close errors.
    }
    _channel = null;
  }

  Uri _buildUri(String path) {
    final base = Uri.parse(_wsBaseUrl);
    return base.resolve(path);
  }

  static String _defaultWsBaseUrl() {
    if (kIsWeb) {
      final base = Uri.base;
      final scheme = base.scheme == 'https' ? 'wss' : 'ws';
      final host = base.hasPort ? '${base.host}:${base.port}' : base.host;
      return '$scheme://$host';
    }

    return 'ws://localhost:8001';
  }
}
