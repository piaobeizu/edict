enum HeartbeatStatus { active, warn, stalled, unknown, idle }

HeartbeatStatus heartbeatStatusFromJson(String? value) {
  switch (value) {
    case 'active':
      return HeartbeatStatus.active;
    case 'warn':
      return HeartbeatStatus.warn;
    case 'stalled':
      return HeartbeatStatus.stalled;
    case 'idle':
      return HeartbeatStatus.idle;
    case 'unknown':
    default:
      return HeartbeatStatus.unknown;
  }
}

String heartbeatStatusToJson(HeartbeatStatus value) {
  switch (value) {
    case HeartbeatStatus.active:
      return 'active';
    case HeartbeatStatus.warn:
      return 'warn';
    case HeartbeatStatus.stalled:
      return 'stalled';
    case HeartbeatStatus.unknown:
      return 'unknown';
    case HeartbeatStatus.idle:
      return 'idle';
  }
}

enum TodoStatus { notStarted, inProgress, completed }

TodoStatus todoStatusFromJson(String? value) {
  switch (value) {
    case 'not-started':
    case 'notStarted':
      return TodoStatus.notStarted;
    case 'in-progress':
    case 'inProgress':
      return TodoStatus.inProgress;
    case 'completed':
      return TodoStatus.completed;
    default:
      return TodoStatus.notStarted;
  }
}

String todoStatusToJson(TodoStatus value) {
  switch (value) {
    case TodoStatus.notStarted:
      return 'not-started';
    case TodoStatus.inProgress:
      return 'in-progress';
    case TodoStatus.completed:
      return 'completed';
  }
}

class Heartbeat {
  final HeartbeatStatus status;
  final String label;

  const Heartbeat({required this.status, required this.label});

  factory Heartbeat.fromJson(Map<String, dynamic> json) {
    return Heartbeat(
      status: heartbeatStatusFromJson(json['status']?.toString()),
      label: json['label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': heartbeatStatusToJson(status),
      'label': label,
    };
  }
}

class FlowEntry {
  final String? at;
  final String? ts;
  final String from;
  final String to;
  final String? remark;
  final String? reason;

  const FlowEntry({
    this.at,
    this.ts,
    required this.from,
    required this.to,
    this.remark,
    this.reason,
  });

  factory FlowEntry.fromJson(Map<String, dynamic> json) {
    return FlowEntry(
      at: json['at']?.toString(),
      ts: json['ts']?.toString(),
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      remark: json['remark']?.toString(),
      reason: json['reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'at': at,
      'ts': ts,
      'from': from,
      'to': to,
      'remark': remark,
      'reason': reason,
    };
  }
}

class TodoItem {
  final String id;
  final String title;
  final TodoStatus status;
  final String? detail;

  const TodoItem({
    required this.id,
    required this.title,
    required this.status,
    this.detail,
  });

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      status: todoStatusFromJson(json['status']?.toString()),
      detail: json['detail']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'status': todoStatusToJson(status),
      'detail': detail,
    };
  }
}

class ToolCall {
  final String name;
  final String? inputPreview;

  const ToolCall({required this.name, this.inputPreview});

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      name: json['name']?.toString() ?? '',
      inputPreview: (json['input_preview'] ?? json['inputPreview'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'input_preview': inputPreview,
    };
  }
}

class DiffChanged {
  final String id;
  final String from;
  final String to;

  const DiffChanged({required this.id, required this.from, required this.to});

  factory DiffChanged.fromJson(Map<String, dynamic> json) {
    return DiffChanged(
      id: json['id']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': from,
      'to': to,
    };
  }
}

class DiffItem {
  final String id;
  final String title;

  const DiffItem({required this.id, required this.title});

  factory DiffItem.fromJson(Map<String, dynamic> json) {
    return DiffItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
    };
  }
}

class TodoDiff {
  final List<DiffChanged>? changed;
  final List<DiffItem>? added;
  final List<DiffItem>? removed;

  const TodoDiff({this.changed, this.added, this.removed});

  factory TodoDiff.fromJson(Map<String, dynamic> json) {
    return TodoDiff(
      changed: (json['changed'] as List<dynamic>?)
          ?.map((e) => DiffChanged.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      added: (json['added'] as List<dynamic>?)
          ?.map((e) => DiffItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      removed: (json['removed'] as List<dynamic>?)
          ?.map((e) => DiffItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'changed': changed?.map((e) => e.toJson()).toList(),
      'added': added?.map((e) => e.toJson()).toList(),
      'removed': removed?.map((e) => e.toJson()).toList(),
    };
  }
}

class ActivityEntry {
  final String kind;
  final dynamic at;
  final String? text;
  final String? thinking;
  final String? agent;
  final String? from;
  final String? to;
  final String? remark;
  final List<ToolCall>? tools;
  final String? tool;
  final String? output;
  final int? exitCode;
  final List<TodoItem>? items;
  final TodoDiff? diff;

  const ActivityEntry({
    required this.kind,
    this.at,
    this.text,
    this.thinking,
    this.agent,
    this.from,
    this.to,
    this.remark,
    this.tools,
    this.tool,
    this.output,
    this.exitCode,
    this.items,
    this.diff,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      kind: json['kind']?.toString() ?? '',
      at: json['at'],
      text: json['text']?.toString(),
      thinking: json['thinking']?.toString(),
      agent: json['agent']?.toString(),
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      remark: json['remark']?.toString(),
      tools: (json['tools'] as List<dynamic>?)
          ?.map((e) => ToolCall.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      tool: json['tool']?.toString(),
      output: json['output']?.toString(),
      exitCode: (json['exitCode'] as num?)?.toInt(),
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => TodoItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      diff: json['diff'] is Map<String, dynamic>
          ? TodoDiff.fromJson(json['diff'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'at': at,
      'text': text,
      'thinking': thinking,
      'agent': agent,
      'from': from,
      'to': to,
      'remark': remark,
      'tools': tools?.map((e) => e.toJson()).toList(),
      'tool': tool,
      'output': output,
      'exitCode': exitCode,
      'items': items?.map((e) => e.toJson()).toList(),
      'diff': diff?.toJson(),
    };
  }
}

class Task {
  final String id;
  final String title;
  final String state;
  final String org;
  final String now;
  final String eta;
  final String block;
  final String ac;
  final String output;
  final Heartbeat heartbeat;
  final List<FlowEntry> flowLog;
  final List<TodoItem> todos;
  final int reviewRound;
  final bool archived;
  final String? archivedAt;
  final String? updatedAt;
  final Map<String, dynamic>? sourceMeta;
  final List<ActivityEntry>? activity;
  final String? prevState;

  const Task({
    required this.id,
    required this.title,
    required this.state,
    required this.org,
    required this.now,
    required this.eta,
    required this.block,
    required this.ac,
    required this.output,
    required this.heartbeat,
    required this.flowLog,
    required this.todos,
    required this.reviewRound,
    required this.archived,
    this.archivedAt,
    this.updatedAt,
    this.sourceMeta,
    this.activity,
    this.prevState,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    // Helper: safely convert any map to Map<String, dynamic>
    Map<String, dynamic> safeMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return <String, dynamic>{};
    }

    List<T> safeList<T>(dynamic v, T Function(Map<String, dynamic>) mapper) {
      if (v is! List) return <T>[];
      return v.where((e) => e is Map).map((e) => mapper(safeMap(e))).toList();
    }

    final hb = json['heartbeat'];
    return Task(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      org: json['org']?.toString() ?? json['official']?.toString() ?? '',
      now: json['now']?.toString() ?? '',
      eta: json['eta']?.toString() ?? '-',
      block: json['block']?.toString() ?? '',
      ac: json['ac']?.toString() ?? '',
      output: json['output']?.toString() ?? '',
      heartbeat: hb is Map
          ? Heartbeat.fromJson(safeMap(hb))
          : const Heartbeat(status: HeartbeatStatus.unknown, label: ''),
      flowLog:
          safeList(json['flow_log'] ?? json['flowLog'], FlowEntry.fromJson),
      todos: safeList(json['todos'], TodoItem.fromJson),
      reviewRound:
          ((json['review_round'] ?? json['reviewRound']) as num?)?.toInt() ?? 0,
      archived: json['archived'] == true,
      archivedAt: (json['archivedAt'] ?? json['archived_at'])?.toString(),
      updatedAt: (json['updatedAt'] ??
              json['updated_at'] ??
              json['createdAt'] ??
              json['created_at'])
          ?.toString(),
      sourceMeta: json['sourceMeta'] is Map
          ? safeMap(json['sourceMeta'])
          : json['source_meta'] is Map
              ? safeMap(json['source_meta'])
              : null,
      activity: null, // Activity is loaded separately via taskActivity API
      prevState:
          (json['_prev_state'] ?? json['prevState'] ?? json['prev_state'])
              ?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'state': state,
      'org': org,
      'now': now,
      'eta': eta,
      'block': block,
      'ac': ac,
      'output': output,
      'heartbeat': heartbeat.toJson(),
      'flow_log': flowLog.map((e) => e.toJson()).toList(),
      'todos': todos.map((e) => e.toJson()).toList(),
      'review_round': reviewRound,
      'archived': archived,
      'archivedAt': archivedAt,
      'updatedAt': updatedAt,
      'sourceMeta': sourceMeta,
      'activity': activity?.map((e) => e.toJson()).toList(),
      '_prev_state': prevState,
    };
  }

  @override
  String toString() =>
      'Task(id: $id, title: $title, state: $state, archived: $archived)';
}
