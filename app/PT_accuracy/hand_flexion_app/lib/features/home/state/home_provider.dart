/// lib/features/home/state/home_provider.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

const _lastOpenKey = 'last_open_date';
const _streakKey = 'streak_days';
const _sessionDatesKey = 'session_dates'; // NEW: stores all YYYY-MM-DD strings

// ---------------------------------------------------------------------------
// Streak
// ---------------------------------------------------------------------------

class StreakNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    return _computeStreak();
  }

  Future<int> _computeStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateStr(DateTime.now());
    final lastOpen = prefs.getString(_lastOpenKey) ?? '';
    int streak = prefs.getInt(_streakKey) ?? 0;

    if (lastOpen == today) {
      // Already counted today; just return current streak.
      return streak;
    }

    final yesterday = _dateStr(DateTime.now().subtract(const Duration(days: 1)));
    if (lastOpen == yesterday) {
      // Consecutive day — increment streak.
      streak += 1;
    } else if (lastOpen.isEmpty) {
      streak = 1; // First ever open
    } else {
      // Streak broken
      streak = 1;
    }

    // Persist last open + streak
    await prefs.setString(_lastOpenKey, today);
    await prefs.setInt(_streakKey, streak);

    // NEW: also record today in the session history.
    final sessions = prefs.getStringList(_sessionDatesKey) ?? <String>[];
    if (!sessions.contains(today)) {
      sessions.add(today);
      await prefs.setStringList(_sessionDatesKey, sessions);
    }

    return streak;
  }

  String _dateStr(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}

final streakProvider = AsyncNotifierProvider<StreakNotifier, int>(
  StreakNotifier.new,
);

// ---------------------------------------------------------------------------
// Session history (dates you opened/used the app)
// ---------------------------------------------------------------------------

final sessionHistoryProvider = FutureProvider<Set<DateTime>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList(_sessionDatesKey) ?? const <String>[];
  return raw.map(DateTime.parse).toSet();
});

// ---------------------------------------------------------------------------
// Mock flexion chart data (7 sessions)
// NOTE: Now only used in guest mode from the UI.
// ---------------------------------------------------------------------------

class FlexionDataPoint {
  final int session;
  final double forwardAngle;
  final double backwardAngle;

  const FlexionDataPoint({
    required this.session,
    required this.forwardAngle,
    required this.backwardAngle,
  });
}

final mockFlexionChartProvider = Provider<List<FlexionDataPoint>>((ref) {
  return const [
    FlexionDataPoint(session: 1, forwardAngle: 25, backwardAngle: 12),
    FlexionDataPoint(session: 2, forwardAngle: 28, backwardAngle: 13),
    FlexionDataPoint(session: 3, forwardAngle: 30, backwardAngle: 14),
    FlexionDataPoint(session: 4, forwardAngle: 33, backwardAngle: 15),
    FlexionDataPoint(session: 5, forwardAngle: 35, backwardAngle: 17),
    FlexionDataPoint(session: 6, forwardAngle: 38, backwardAngle: 18),
    FlexionDataPoint(session: 7, forwardAngle: 40, backwardAngle: 20),
  ];
});

// ---------------------------------------------------------------------------
// Grip strength % improvement placeholder
// ---------------------------------------------------------------------------

final gripImprovementProvider = Provider<double>((ref) => 0.0);
