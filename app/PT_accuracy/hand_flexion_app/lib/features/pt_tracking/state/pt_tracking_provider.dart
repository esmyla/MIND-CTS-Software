/// lib/features/pt_tracking/state/pt_tracking_provider.dart
///
/// Adherence tracking for the exercise library.
///
/// Stored locally with `shared_preferences` rather than in Supabase: there is
/// no table for exercise completions yet, and inventing one from the client
/// would put schema decisions in the wrong place. The storage is behind this
/// provider, so moving it server-side later is a change here and nowhere else.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keyed `pt_done_<yyyy-MM-dd>` -> list of exercise ids completed that day.
String _dayKey(DateTime day) =>
    'pt_done_${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------

class PtCompletionNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_dayKey(DateTime.now())) ?? const <String>[])
        .toSet();
  }

  /// Record [exerciseId] as done today. Idempotent.
  Future<void> markComplete(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dayKey(DateTime.now());
    final done = (prefs.getStringList(key) ?? const <String>[]).toSet();

    if (done.add(exerciseId)) {
      await prefs.setStringList(key, done.toList());
    }
    state = AsyncData(done);
  }

  /// Clear today's completions — used by the "reset today" action.
  Future<void> resetToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dayKey(DateTime.now()));
    state = const AsyncData(<String>{});
  }
}

final ptCompletionProvider =
    AsyncNotifierProvider<PtCompletionNotifier, Set<String>>(
  PtCompletionNotifier.new,
);

/// How many of the last 7 days had at least one exercise completed.
final ptWeekAdherenceProvider = FutureProvider<int>((ref) async {
  // Depend on today's completions so finishing an exercise refreshes this.
  ref.watch(ptCompletionProvider);

  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now();

  var days = 0;
  for (var i = 0; i < 7; i++) {
    final day = today.subtract(Duration(days: i));
    final done = prefs.getStringList(_dayKey(day)) ?? const <String>[];
    if (done.isNotEmpty) days++;
  }
  return days;
});
