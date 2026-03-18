import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/websocket_service.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
