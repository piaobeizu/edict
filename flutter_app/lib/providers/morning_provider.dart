import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'api_provider.dart';

final morningBriefProvider =
    AsyncNotifierProvider<MorningBriefNotifier, MorningBrief>(
  MorningBriefNotifier.new,
);

class MorningBriefNotifier extends AsyncNotifier<MorningBrief> {
  static const _pollInterval = Duration(seconds: 5);
  static const _maxPollAttempts = 24;

  @override
  Future<MorningBrief> build() async {
    final api = ref.read(apiClientProvider);
    return api.morningBrief();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<MorningBrief>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.morningBrief();
    });
  }

  Future<void> triggerRefreshAndPoll() async {
    final api = ref.read(apiClientProvider);
    final previousGeneratedAt = state.valueOrNull?.generatedAt;

    try {
      final result = await api.refreshMorning();
      if (!result.ok) {
        throw StateError(result.error ?? result.message ?? 'Failed to refresh morning brief');
      }

      for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
        final latest = await api.morningBrief();
        final generatedAt = latest.generatedAt;

        if (generatedAt != null &&
            generatedAt.isNotEmpty &&
            generatedAt != previousGeneratedAt) {
          state = AsyncData<MorningBrief>(latest);
          return;
        }

        if (attempt < _maxPollAttempts - 1) {
          await Future<void>.delayed(_pollInterval);
        }
      }

      final fallback = await api.morningBrief();
      state = AsyncData<MorningBrief>(fallback);
    } catch (error, stackTrace) {
      state = AsyncError<MorningBrief>(error, stackTrace);
    }
  }
}

final subConfigProvider =
    AsyncNotifierProvider<SubConfigNotifier, SubConfig>(SubConfigNotifier.new);

class SubConfigNotifier extends AsyncNotifier<SubConfig> {
  @override
  Future<SubConfig> build() async {
    final api = ref.read(apiClientProvider);
    return api.morningConfig();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<SubConfig>();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      return api.morningConfig();
    });
  }

  Future<ActionResult> save(SubConfig config) async {
    final api = ref.read(apiClientProvider);

    try {
      final result = await api.saveMorningConfig(config);
      if (result.ok) {
        state = AsyncData<SubConfig>(config);
      }
      return result;
    } catch (error, stackTrace) {
      state = AsyncError<SubConfig>(error, stackTrace);
      return ActionResult(ok: false, error: error.toString());
    }
  }
}
