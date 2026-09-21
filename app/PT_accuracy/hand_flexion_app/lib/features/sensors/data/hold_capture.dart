/// lib/features/sensors/data/hold_capture.dart
///
/// Aggregation for a timed "squeeze and hold" measurement.
///
/// Shared by the Grip and Pinch tabs so both report strength the same way.
library;

// ---------------------------------------------------------------------------
// Aggregation
// ---------------------------------------------------------------------------

/// Mean of the strongest 60% of [samples].
///
/// This is the metric the team already settled on in `grip_s.py` and
/// `pinch_s.py`: sort descending, keep the top 60%, average those. It reports
/// sustained effort rather than a single spike, so one twitchy reading can't
/// inflate a session, while the weak ramp-up and release at the edges of the
/// hold don't drag the number down either.
///
/// Returns 0 for an empty list.
double topSixtyPercentMean(List<int> samples) {
  if (samples.isEmpty) return 0;

  final sorted = [...samples]..sort((a, b) => b.compareTo(a));

  // The Python used int(0.6 * n), which yields 0 for n < 2 and then averages an
  // empty slice (NaN). Keep at least one sample so a short hold degrades to
  // "the peak" instead of producing garbage.
  final take = (sorted.length * 0.6).floor().clamp(1, sorted.length);

  var sum = 0;
  for (var i = 0; i < take; i++) {
    sum += sorted[i];
  }
  return sum / take;
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

/// Outcome of one completed hold.
class HoldResult {
  /// Mean of the strongest 60% of the hold — the value stored as `fsr_palm`,
  /// `it`, or `mt`.
  final double value;

  /// Highest single reading, shown to the user as feedback but not stored.
  final int peak;

  final int sampleCount;
  final Duration duration;

  const HoldResult({
    required this.value,
    required this.peak,
    required this.sampleCount,
    required this.duration,
  });

  /// A hold with almost no data behind it — the glove dropped out mid-capture,
  /// or the bridge was not actually streaming. Callers should refuse to save.
  bool get isUsable => sampleCount >= 10;

  /// Strength relative to a baseline, stored in the `r_`-prefixed columns.
  ///
  /// Null when there is no baseline yet, or the baseline is zero/negative
  /// (which would make the ratio meaningless rather than merely large).
  double? ratioTo(double? baseline) {
    if (baseline == null || baseline <= 0) return null;
    return value / baseline;
  }
}

// ---------------------------------------------------------------------------
// Buffer
// ---------------------------------------------------------------------------

/// Collects sensor readings for the duration of a hold.
///
/// Deliberately not a timer or a state machine — the page owns the countdown
/// and the clock. This just accumulates and reports.
class HoldBuffer {
  final List<int> _samples = [];
  DateTime? _startedAt;

  void start() {
    _samples.clear();
    _startedAt = DateTime.now();
  }

  void add(int value) {
    if (_startedAt == null) return;
    _samples.add(value);
  }

  int get sampleCount => _samples.length;

  /// Highest reading so far, for live feedback during the hold.
  int get peak => _samples.isEmpty ? 0 : _samples.reduce((a, b) => a > b ? a : b);

  HoldResult finish() {
    final result = HoldResult(
      value: topSixtyPercentMean(_samples),
      peak: peak,
      sampleCount: _samples.length,
      duration: _startedAt == null
          ? Duration.zero
          : DateTime.now().difference(_startedAt!),
    );
    _startedAt = null;
    return result;
  }
}
