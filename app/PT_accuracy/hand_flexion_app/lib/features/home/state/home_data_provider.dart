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
