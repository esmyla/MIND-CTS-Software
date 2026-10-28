/// lib/features/pt_tracking/state/pt_tracking_provider.dart
///
/// Adherence state for the exercise library.
///
/// Storage lives behind [PtRepository]: Supabase when signed in, with the local
/// store as an offline cache. This file only coordinates.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pt_repository.dart';

final ptRepositoryProvider = Provider<PtRepository>((ref) {
  return const PtRepository();
});

// ---------------------------------------------------------------------------

class PtCompletionNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    return ref.watch(ptRepositoryProvider).completedOn(DateTime.now());
  }

  /// Record [exerciseId] as done today. Idempotent.
  ///
  /// [fully] is false when the patient finished early instead of completing
  /// every rep.
  Future<void> markComplete(String exerciseId, {bool fully = true}) async {
    final repo = ref.read(ptRepositoryProvider);

    // Optimistic: the local write inside markComplete has already succeeded by
    // the time any network call is attempted, so showing it immediately is
    // honest rather than hopeful.
    final current = state.valueOrNull ?? <String>{};
    state = AsyncData({...current, exerciseId});

    await repo.markComplete(exerciseId, fully: fully);
    ref.invalidate(ptWeekAdherenceProvider);
  }

  Future<void> resetToday() async {
    await ref.read(ptRepositoryProvider).resetToday();
    state = const AsyncData(<String>{});
    ref.invalidate(ptWeekAdherenceProvider);
  }
}

final ptCompletionProvider =
    AsyncNotifierProvider<PtCompletionNotifier, Set<String>>(
  PtCompletionNotifier.new,
);

/// How many of the last 7 days had at least one exercise completed.
final ptWeekAdherenceProvider = FutureProvider<int>((ref) async {
  return ref.watch(ptRepositoryProvider).activeDays(days: 7);
});
