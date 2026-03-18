import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final remoteSkillsProvider =
    AsyncNotifierProvider<RemoteSkillsNotifier, RemoteSkillsListResult>(
  RemoteSkillsNotifier.new,
);

class RemoteSkillsNotifier extends AsyncNotifier<RemoteSkillsListResult> {
  @override
  Future<RemoteSkillsListResult> build() async {
    final api = ref.read(apiClientProvider);
    return api.remoteSkillsList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<RemoteSkillsListResult>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.remoteSkillsList();
    });
  }
}
