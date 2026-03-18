import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final agentConfigProvider =
    AsyncNotifierProvider<AgentConfigNotifier, AgentConfig>(
  AgentConfigNotifier.new,
);

class AgentConfigNotifier extends AsyncNotifier<AgentConfig> {
  @override
  Future<AgentConfig> build() async {
    final api = ref.read(apiClientProvider);
    return api.agentConfig();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<AgentConfig>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.agentConfig();
    });
  }
}

final changeLogProvider = FutureProvider<List<ChangeLogEntry>>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.modelChangeLog();
});

final agentsStatusProvider =
    AsyncNotifierProvider<AgentsStatusNotifier, AgentsStatusData>(
  AgentsStatusNotifier.new,
);

class AgentsStatusNotifier extends AsyncNotifier<AgentsStatusData> {
  @override
  Future<AgentsStatusData> build() async {
    final api = ref.read(apiClientProvider);
    return api.agentsStatus();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<AgentsStatusData>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.agentsStatus();
    });
  }
}
