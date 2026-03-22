import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TabKey {
  edicts,
  monitor,
  officials,
  models,
  skills,
  sessions,
  memorials,
  templates,
  morning,
}

final activeTabProvider = StateProvider<TabKey>((_) => TabKey.edicts);

final modalWorkflowIdProvider = StateProvider<String?>((_) => null);

final countdownProvider = StateProvider<String?>((_) => null);

final tplCatFilterProvider = StateProvider<String?>((_) => null);

/// Shared query text used by the mobile task list search bar.
final mobileTaskSearchQueryProvider = StateProvider<String>((_) => '');

/// Newly created task id to be emphasized on the mobile task list.
final mobileFocusedTaskIdProvider = StateProvider<String?>((_) => null);

/// Shared state chip filter for mobile task list.
final mobileTaskStateFilterProvider = StateProvider<String?>((_) => null);
