import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final notifyChannelsProvider =
    AsyncNotifierProvider<NotifyChannelsNotifier, NotifyChannelsResult>(
  NotifyChannelsNotifier.new,
);

class NotifyChannelsNotifier extends AsyncNotifier<NotifyChannelsResult> {
  @override
  Future<NotifyChannelsResult> build() async {
    final api = ref.read(apiClientProvider);
    return api.notifyChannels();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<NotifyChannelsResult>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.notifyChannels();
    });
  }
}
