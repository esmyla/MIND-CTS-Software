/// lib/features/home/state/home_data_provider.dart
///
/// Real dashboard data, read from Supabase.
///
/// Replaces the mock providers in `home_provider.dart` for signed-in users.
/// The mocks stay for guest mode, where there is no user and nothing to read.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sensors/state/sensor_provider.dart';
import 'home_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

// ---------------------------------------------------------------------------
// Flexion trend
// ---------------------------------------------------------------------------

/// The user's flexion sessions as chart points, oldest first.
final realFlexionChartProvider =
    FutureProvider<List<FlexionDataPoint>>((ref) async {
  final rows = await ref.watch(strengthHistoryProvider('flexion').future);

  var index = 0;
  return rows.map((row) {
    index++;
    return FlexionDataPoint(
      session: _asDouble(row['session_id'])?.toInt() ?? index,
      forwardAngle: _asDouble(row['degree_forward']) ?? 0,
      // Note the plural — the column really is `degree_backwards`. The Python
      // backend used the singular for months and silently wrote nothing.
      backwardAngle: _asDouble(row['degree_backwards']) ?? 0,
    );
  }).toList();
});

// ---------------------------------------------------------------------------
// Grip improvement
// ---------------------------------------------------------------------------

/// Percentage change in grip strength against the patient's baseline.
///
/// Reads the stored `r_fsr_palm` ratio rather than recomputing, so the figure
/// on the dashboard matches what was recorded at the time of the session.
/// Null when there are no sessions, or none with a baseline to compare to.
final realGripImprovementProvider = FutureProvider<double?>((ref) async {
  final rows = await ref.watch(strengthHistoryProvider('grip').future);
  if (rows.isEmpty) return null;

  for (final row in rows.reversed) {
    final ratio = _asDouble(row['r_fsr_palm']);
    if (ratio != null && ratio > 0) {
      return (ratio - 1.0) * 100.0;
    }
  }
  return null;
});

/// Latest absolute grip reading, for the card subtitle.
final latestGripValueProvider = FutureProvider<double?>((ref) async {
  final rows = await ref.watch(strengthHistoryProvider('grip').future);
  if (rows.isEmpty) return null;
  return _asDouble(rows.last['fsr_palm']);
});

// ---------------------------------------------------------------------------
// Strength per unit of exertion
// ---------------------------------------------------------------------------

/// The latest grip session's strength-to-exertion score, as a percentage.
///
/// 100% means the patient produced their baseline force at their baseline
/// heart rate. Above 100% is more force for proportionally less cardiovascular
/// cost, which is what recovery looks like.
///
/// Null until there is a session carrying BOTH a baseline-relative strength
/// ratio and a heart rate measured against a known resting rate. Shown as
/// "needs heart rate" rather than a number, because a half-computed score would
/// be read as a real one.
final exertionScoreProvider = FutureProvider<double?>((ref) async {
  final rows = await ref.watch(strengthHistoryProvider('grip').future);
  if (rows.isEmpty) return null;

  final baseline = await ref.watch(baselineProvider.future);
  final restingBpm = _asDouble(baseline?['base_bpm_rest'])?.round();
  if (restingBpm == null || restingBpm <= 0) return null;

  for (final row in rows.reversed) {
    final strengthRatio = _asDouble(row['r_fsr_palm']);
    final bpm = _asDouble(row['bpm_avg']);
    if (strengthRatio == null || strengthRatio <= 0) continue;
    if (bpm == null || bpm <= 0) continue;

    final exertion = bpm / restingBpm;
    if (exertion <= 0) continue;
    return (strengthRatio / exertion) * 100.0;
  }
  return null;
});

// ---------------------------------------------------------------------------
// Session dates
// ---------------------------------------------------------------------------

/// Dates on which the user recorded any session, across all three modalities.
///
/// Drives the dashboard calendar. Falls back to the local `shared_preferences`
/// history in guest mode, where nothing is stored server-side.
final realSessionDatesProvider = FutureProvider<Set<DateTime>>((ref) async {
  final tables = ['flexion', 'grip', 'pinch'];
  final dates = <DateTime>{};

  for (final table in tables) {
    final rows = await ref.watch(strengthHistoryProvider(table).future);
    for (final row in rows) {
      final raw = row['created_at'];
      if (raw is! String) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      // Normalise to local midnight so the calendar matches by day.
      final local = parsed.toLocal();
      dates.add(DateTime(local.year, local.month, local.day));
    }
  }

  return dates;
});

// ---------------------------------------------------------------------------
// Progress and the next target
// ---------------------------------------------------------------------------

/// A patient-facing goal: beat your own best, not a population norm.
///
/// Carpal tunnel recovery is individual, and there is no clinically meaningful
/// absolute grip number this app could hold someone to. Their own best session
/// is a target they can actually act on — and one that moves as they improve.
class NextTarget {
  /// Best single session so far, in sensor units.
  final double best;

  /// Latest session, for "how close am I".
  final double latest;

  /// Target to beat: a little above their best.
  final double target;

  /// How close the latest session came, 0..1.
  final double progress;

  /// True when the latest session set a new best.
  final bool isPersonalBest;

  const NextTarget({
    required this.best,
    required this.latest,
    required this.target,
    required this.progress,
    required this.isPersonalBest,
  });
}

/// Next grip target, or null until there is a session to build one from.
final gripTargetProvider = FutureProvider<NextTarget?>((ref) async {
  final rows = await ref.watch(strengthHistoryProvider('grip').future);
  final values = rows
      .map((r) => _asDouble(r['fsr_palm']))
      .whereType<double>()
      .where((v) => v > 0)
      .toList();
  if (values.isEmpty) return null;

  final best = values.reduce((a, b) => a > b ? a : b);
  final latest = values.last;

  // 5% above their best: far enough to be worth aiming at, close enough that a
  // good day reaches it. A target nobody hits stops being motivating and
  // starts being discouraging.
  final target = best * 1.05;

  return NextTarget(
    best: best,
    latest: latest,
    target: target,
    progress: (latest / target).clamp(0.0, 1.0),
    isPersonalBest: latest >= best,
  );
});

/// The last few sessions across every modality, newest first.
final recentSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final grip = await ref.watch(strengthHistoryProvider('grip').future);
  final pinch = await ref.watch(strengthHistoryProvider('pinch').future);
  final flexion = await ref.watch(strengthHistoryProvider('flexion').future);

  final all = <Map<String, dynamic>>[
    for (final r in grip)
      {'kind': 'Grip', 'at': r['created_at'], 'ratio': _asDouble(r['r_fsr_palm']),
       'detail': '${(_asDouble(r['fsr_palm']) ?? 0).round()} units'},
    for (final r in pinch)
      {'kind': 'Pinch', 'at': r['created_at'], 'ratio': _asDouble(r['r_it']),
       'detail': 'IT ${(_asDouble(r['it']) ?? 0).round()} · MT ${(_asDouble(r['mt']) ?? 0).round()}'},
    for (final r in flexion)
      {'kind': 'Flexion', 'at': r['created_at'], 'ratio': null,
       'detail': '${_asDouble(r['degree_forward'])?.round() ?? '—'}° · '
                 '${_asDouble(r['repetitions'])?.round() ?? '—'} reps'},
  ];

  all.sort((a, b) {
    final x = DateTime.tryParse(a['at']?.toString() ?? '');
    final y = DateTime.tryParse(b['at']?.toString() ?? '');
    if (x == null || y == null) return 0;
    return y.compareTo(x);
  });
  return all.take(8).toList();
});
