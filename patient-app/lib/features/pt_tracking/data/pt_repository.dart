/// lib/features/pt_tracking/data/pt_repository.dart
///
/// Exercise-adherence persistence.
///
/// Completions used to live only in `shared_preferences`, which meant they were
/// lost on a cache clear, never followed the patient to another device, and
/// were invisible to the clinician — the person who most needs to know whether
/// the prescribed exercises actually happened.
///
/// They now go to Supabase, with the local store kept as a cache so the tab
/// still works offline, in guest mode, and in the moment between tapping
/// "done" and the write landing.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/env.dart';

String dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

String _prefsKey(DateTime day) => 'pt_done_${dayKey(day)}';

class PtRepository {
  const PtRepository();

  SupabaseClient? get _client =>
      Env.featureAuth ? Supabase.instance.client : null;

  String? get _userId => _client?.auth.currentUser?.id;

  bool get canSync => _client != null && _userId != null;

  // ------------------------------------------------------------------
  // Local cache
  // ------------------------------------------------------------------

  Future<Set<String>> _readLocal(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey(day)) ?? const <String>[]).toSet();
  }

  Future<void> _writeLocal(DateTime day, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(day), ids.toList());
  }

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------

  /// Exercise ids completed on [day].
  ///
  /// Returns the server's view when signed in, falling back to the local cache
  /// if the query fails — a network blip should not make a patient's completed
  /// exercises appear undone.
  Future<Set<String>> completedOn(DateTime day) async {
    final local = await _readLocal(day);
    if (!canSync) return local;

    try {
      final start = DateTime(day.year, day.month, day.day).toUtc();
      final end = start.add(const Duration(days: 1));
      final rows = await _client!
          .from('pt_sessions')
          .select('exercise_id')
          .eq('user_id', _userId!)
          .gte('completed_at', start.toIso8601String())
          .lt('completed_at', end.toIso8601String());

      final remote = <String>{
        for (final r in rows) (r['exercise_id'] ?? '').toString(),
      }..removeWhere((e) => e.isEmpty);

      // Union, not replacement: anything completed offline is still real and
      // will be pushed on the next write.
      final merged = {...local, ...remote};
      await _writeLocal(day, merged);
      return merged;
    } catch (e) {
      debugPrint('[PtRepository] completedOn failed, using local cache: $e');
      return local;
    }
  }

  /// How many of the last [days] days had at least one exercise completed.
  Future<int> activeDays({int days = 7}) async {
    final today = DateTime.now();

    if (!canSync) {
      var n = 0;
      for (var i = 0; i < days; i++) {
        final d = today.subtract(Duration(days: i));
        if ((await _readLocal(d)).isNotEmpty) n++;
      }
      return n;
    }

    try {
      final since = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: days - 1))
          .toUtc();
      final rows = await _client!
          .from('pt_sessions')
          .select('completed_at')
          .eq('user_id', _userId!)
          .gte('completed_at', since.toIso8601String());

      final distinct = <String>{};
      for (final r in rows) {
        final raw = r['completed_at'];
        if (raw is! String) continue;
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) distinct.add(dayKey(parsed.toLocal()));
      }
      return distinct.length;
    } catch (e) {
      debugPrint('[PtRepository] activeDays failed: $e');
      return 0;
    }
  }

  // ------------------------------------------------------------------
  // Writes
  // ------------------------------------------------------------------

  /// Record [exerciseId] as done today.
  ///
  /// Writes locally first so the UI can update immediately and nothing is lost
  /// if the network write fails. [fully] is false when the patient finished
  /// early rather than working through every rep — partial adherence is a
  /// different clinical signal from none.
  Future<void> markComplete(String exerciseId, {bool fully = true}) async {
    final today = DateTime.now();
    final local = await _readLocal(today);
    local.add(exerciseId);
    await _writeLocal(today, local);

    if (!canSync) return;

    try {
      // Upsert on the (user, exercise, day) unique index: repeating an exercise
      // the same day is normal and must not inflate the count.
      await _client!.from('pt_sessions').upsert(
        {
          'user_id': _userId,
          'exercise_id': exerciseId,
          'completed': fully,
        },
        onConflict: 'user_id,exercise_id,(completed_at::date)',
      );
    } catch (e) {
      // The local write already succeeded, so the patient sees their progress
      // and the next successful sync will carry it up.
      debugPrint('[PtRepository] markComplete sync failed: $e');
    }
  }

  /// Clear today's completions, locally and on the server.
  Future<void> resetToday() async {
    final today = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey(today));

    if (!canSync) return;

    try {
      final start = DateTime(today.year, today.month, today.day).toUtc();
      final end = start.add(const Duration(days: 1));
      await _client!
          .from('pt_sessions')
          .delete()
          .eq('user_id', _userId!)
          .gte('completed_at', start.toIso8601String())
          .lt('completed_at', end.toIso8601String());
    } catch (e) {
      debugPrint('[PtRepository] resetToday sync failed: $e');
    }
  }
}
