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

final modalTaskIdProvider = StateProvider<String?>((_) => null);

final countdownProvider = StateProvider<String?>((_) => null);

final tplCatFilterProvider = StateProvider<String?>((_) => null);
