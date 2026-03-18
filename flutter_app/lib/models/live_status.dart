import 'task.dart';

class SyncStatus {
  final bool ok;
  final Map<String, dynamic> extra;

  const SyncStatus({required this.ok, this.extra = const {}});

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    final ok = map.remove('ok') == true;
    return SyncStatus(ok: ok, extra: map);
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        ...extra,
      };
}

class LiveStatus {
  final List<Task> tasks;
  final SyncStatus syncStatus;

  const LiveStatus({required this.tasks, required this.syncStatus});

  factory LiveStatus.fromJson(Map<String, dynamic> json) {
    final allTasks = <Task>[];

    // "tasks" can be a List OR a Map<id, task> OR empty {}
    final rawTasks = json['tasks'];
    if (rawTasks is List) {
      for (final e in rawTasks) {
        if (e is Map) {
          allTasks.add(Task.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    } else if (rawTasks is Map) {
      for (final e in rawTasks.values) {
        if (e is Map) {
          allTasks.add(Task.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    // "completed_tasks" is a Map<id, task>
    final rawCompleted = json['completed_tasks'];
    if (rawCompleted is Map) {
      for (final e in rawCompleted.values) {
        if (e is Map) {
          final task = Task.fromJson(Map<String, dynamic>.from(e));
          allTasks.add(task);
        }
      }
    } else if (rawCompleted is List) {
      for (final e in rawCompleted) {
        if (e is Map) {
          allTasks.add(Task.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    return LiveStatus(
      tasks: allTasks,
      syncStatus: const SyncStatus(ok: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'syncStatus': syncStatus.toJson(),
      };

  @override
  String toString() =>
      'LiveStatus(tasks: ${tasks.length}, syncOk: ${syncStatus.ok})';
}
