import '../models/task.dart';

class TaskEntryRoute {
  final String workflowId;
  final bool unresolved;

  const TaskEntryRoute._({
    required this.workflowId,
    required this.unresolved,
  });

  factory TaskEntryRoute.workflow(String workflowId) =>
      TaskEntryRoute._(workflowId: workflowId, unresolved: false);

  factory TaskEntryRoute.unresolved() =>
      const TaskEntryRoute._(workflowId: '', unresolved: true);
}

TaskEntryRoute resolveTaskEntryRoute(Task task) {
  final workflowId = taskWorkflowId(task);
  if (workflowId.isEmpty) {
    return TaskEntryRoute.unresolved();
  }
  return TaskEntryRoute.workflow(workflowId);
}
