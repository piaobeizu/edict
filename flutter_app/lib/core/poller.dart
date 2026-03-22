import 'dart:async';

typedef PollTask = Future<void> Function();

/// Small reusable polling loop with overlap protection.
class Poller {
  Poller({
    required this.interval,
    required this.task,
  });

  final Duration interval;
  final PollTask task;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  void start({bool runImmediately = false}) {
    if (_disposed || _timer != null) {
      return;
    }
    if (runImmediately) {
      unawaited(runNow());
    }
    _timer = Timer.periodic(interval, (_) {
      unawaited(runNow());
    });
  }

  Future<void> runNow() async {
    if (_disposed || _running) {
      return;
    }
    _running = true;
    try {
      await task();
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
