import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final officialsProvider =
    AsyncNotifierProvider<OfficialsNotifier, OfficialsData>(OfficialsNotifier.new);

class OfficialsNotifier extends AsyncNotifier<OfficialsData> {
  @override
  Future<OfficialsData> build() async {
    final api = ref.read(apiClientProvider);
    return api.officialsStats();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<OfficialsData>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.officialsStats();
    });
  }
}

final selectedOfficialProvider = StateProvider<String?>((_) => null);
