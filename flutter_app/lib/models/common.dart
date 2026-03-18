class ActionResult {
  final bool ok;
  final String? message;
  final String? error;
  final String? taskId;

  const ActionResult({required this.ok, this.message, this.error, this.taskId});

  factory ActionResult.fromJson(Map<String, dynamic> json) {
    return ActionResult(
      ok: json['ok'] == true,
      message: json['message']?.toString(),
      error: json['error']?.toString(),
      taskId: (json['taskId'] ?? json['task_id'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'message': message,
        'error': error,
        'taskId': taskId,
      };
}

class ScanAction {
  final String taskId;
  final String action;
  final String? to;
  final String? toState;
  final int? stalledSec;

  const ScanAction({
    required this.taskId,
    required this.action,
    this.to,
    this.toState,
    this.stalledSec,
  });

  factory ScanAction.fromJson(Map<String, dynamic> json) {
    return ScanAction(
      taskId: json['taskId']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      to: json['to']?.toString(),
      toState: json['toState']?.toString(),
      stalledSec: (json['stalledSec'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'action': action,
        'to': to,
        'toState': toState,
        'stalledSec': stalledSec,
      };
}
