/// lib/features/sensors/data/strength_repository.dart
///
/// Supabase persistence for the glove-based strength measurements
/// (Grip and Pinch).
///
/// All writes happen here, from the Flutter app, as the signed-in user. The
/// Python sensor bridge deliberately does not touch the database: it connects
/// with the anon key and no user JWT, so its inserts are rejected by row-level
/// security with `42501`. Routing writes through the app means the user's own
/// JWT applies and RLS does the right thing.
///
/// Verified schema (2026-09-21):
///   grip      id, user_id, session_id, fsr_palm, r_fsr_palm, created_at
///   pinch     id, user_id, session_id, it, mt, r_it, r_mt, created_at
///   baseline  user_id, base_it, base_mt, base_grip, base_flex_deg,
///             base_rep_count, created_at
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/env.dart';

class StrengthRepository {
  const StrengthRepository();

  SupabaseClient? get _client =>
      Env.featureAuth ? Supabase.instance.client : null;

  String? get currentUserId => _client?.auth.currentUser?.id;

  /// True when we can actually persist: Supabase configured and a real user
  /// signed in. Guest sessions measure fine but are not stored.
  bool get canPersist => _client != null && currentUserId != null;

  // ------------------------------------------------------------------
  // Session numbering
  // ------------------------------------------------------------------

  /// Next `session_id` for this user in [table].
  ///
  /// Per-user and per-table, matching how the existing flexion code numbers
  /// sessions. RLS already restricts the query to the caller's own rows, but
  /// the explicit `user_id` filter keeps the intent obvious.
  Future<int> nextSessionId(String table) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return 1;

    try {
      final rows = await client
          .from(table)
          .select('session_id')
          .eq('user_id', userId)
          .order('session_id', ascending: false)
          .limit(1);

      if (rows.isEmpty) return 1;
      final latest = rows.first['session_id'];
      if (latest is int) return latest + 1;
      if (latest is num) return latest.toInt() + 1;
      return 1;
    } catch (e) {
      debugPrint('[StrengthRepository] nextSessionId($table) failed: $e');
      // Falling back to 1 would silently collide with an existing session.
      // Use a timestamp-derived id so the row still lands and stays orderable.
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
  }

  // ------------------------------------------------------------------
  // Baseline
  // ------------------------------------------------------------------

  /// The user's baseline row, or null if they have not been calibrated yet.
  Future<Map<String, dynamic>?> fetchBaseline() async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return null;

    try {
      final rows = await client
          .from('baseline')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('[StrengthRepository] fetchBaseline failed: $e');
      return null;
    }
  }

  /// Write (or overwrite) baseline values.
  ///
  /// Only the supplied fields are sent, so calibrating grip does not clobber an
  /// existing pinch baseline.
  Future<bool> saveBaseline({
    double? baseGrip,
    double? baseIt,
    double? baseMt,
  }) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return false;

    final payload = <String, dynamic>{
      'user_id': userId,
      if (baseGrip != null) 'base_grip': baseGrip,
      if (baseIt != null) 'base_it': baseIt,
      if (baseMt != null) 'base_mt': baseMt,
    };

    try {
      final existing = await fetchBaseline();
      if (existing == null) {
        await client.from('baseline').insert(payload);
      } else {
        await client.from('baseline').update(payload).eq('user_id', userId);
      }
      return true;
    } catch (e) {
      debugPrint('[StrengthRepository] saveBaseline failed: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Insert with primary-key retry
  // ------------------------------------------------------------------

  /// Postgres error code for a unique-constraint violation.
  static const _uniqueViolation = '23505';

  /// Insert [payload] into [table], retrying on a primary-key collision.
  ///
  /// The dummy CSVs were imported with explicit `id` values without advancing
  /// each table's identity sequence, so `nextval()` starts back at 1 and
  /// collides with imported rows. `nextval()` is non-transactional, so every
  /// failed attempt still moves the sequence forward and a retry gets past the
  /// occupied range.
  ///
  /// This is a safety net, not the fix — the sequences should be reset with
  /// `setval()` in the database. Keeping it means a fresh import can never
  /// silently cost a patient their session.
  Future<bool> _insertWithPkRetry(
    String table,
    Map<String, dynamic> payload, {
    int maxAttempts = 5,
  }) async {
    final client = _client;
    if (client == null) return false;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await client.from(table).insert(payload);
        if (attempt > 1) {
          debugPrint('[StrengthRepository] $table insert succeeded on attempt $attempt');
        }
        return true;
      } on PostgrestException catch (e) {
        if (e.code != _uniqueViolation || attempt == maxAttempts) {
          debugPrint('[StrengthRepository] $table insert failed: $e');
          return false;
        }
        // Sequence is behind the imported rows — let it catch up.
      } catch (e) {
        debugPrint('[StrengthRepository] $table insert failed: $e');
        return false;
      }
    }
    return false;
  }

  // ------------------------------------------------------------------
  // Sessions
  // ------------------------------------------------------------------

  /// Persist one grip session. Returns the `session_id` written, or null.
  Future<int?> saveGripSession({
    required double fsrPalm,
    required double? ratio,
  }) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return null;

    final sessionId = await nextSessionId('grip');
    final ok = await _insertWithPkRetry('grip', {
      'user_id': userId,
      'session_id': sessionId,
      'fsr_palm': fsrPalm,
      // Null rather than 0 when there is no baseline: 0 would read as
      // "measured, and the patient scored nothing".
      'r_fsr_palm': ratio,
    });
    return ok ? sessionId : null;
  }

  /// Persist one pinch session — index-thumb and middle-thumb together.
  Future<int?> savePinchSession({
    required double it,
    required double mt,
    required double? ratioIt,
    required double? ratioMt,
  }) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return null;

    final sessionId = await nextSessionId('pinch');
    final ok = await _insertWithPkRetry('pinch', {
      'user_id': userId,
      'session_id': sessionId,
      'it': it,
      'mt': mt,
      'r_it': ratioIt,
      'r_mt': ratioMt,
    });
    return ok ? sessionId : null;
  }

  // ------------------------------------------------------------------
  // History (for Home + trend charts)
  // ------------------------------------------------------------------

  /// Recent rows for [table], oldest first, so charts read left to right.
  Future<List<Map<String, dynamic>>> fetchHistory(
    String table, {
    int limit = 30,
  }) async {
    final client = _client;
    final userId = currentUserId;
    if (client == null || userId == null) return const [];

    try {
      final rows = await client
          .from(table)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows).reversed.toList();
    } catch (e) {
      debugPrint('[StrengthRepository] fetchHistory($table) failed: $e');
      return const [];
    }
  }
}
