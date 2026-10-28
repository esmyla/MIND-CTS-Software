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

  /// Mean heart rate during the hold, or null if no finger was on the sensor.
  ///
  /// The MAX30102 only reports a usable rate when a finger is covering it, and
  /// the firmware zeroes the value otherwise, so "no reading" is a completely
  /// normal outcome for a grip session. Null rather than 0: a stored 0 would
  /// read as bradycardia.
  final int? bpmAvg;

  /// Highest heart rate seen during the hold.
  final int? bpmPeak;

  const HoldResult({
    required this.value,
    required this.peak,
    required this.sampleCount,
    required this.duration,
    this.bpmAvg,
    this.bpmPeak,
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

  /// How hard the patient's cardiovascular system worked, relative to their own
  /// resting rate. 1.0 means the hold cost them nothing measurable.
  double? exertionAgainst(int? restingBpm) {
    if (restingBpm == null || restingBpm <= 0) return null;
    final avg = bpmAvg;
    if (avg == null || avg <= 0) return null;
    return avg / restingBpm;
  }

  /// Strength per unit of exertion — the combined measure asked for in
  /// `Research/SoftwareGoals.md`.
  ///
  /// Strength ratio divided by exertion ratio. Above 1.0 means the patient is
  /// producing more force than baseline for proportionally less cardiovascular
  /// cost, which is what recovery should look like; the same force at a higher
  /// heart rate scores lower, which is the point of combining them at all.
  ///
  /// Null unless BOTH baselines exist. A half-known score would be read as a
  /// real one and quietly compared against scores that meant something else.
  ///
  /// Deliberately computed, never stored: the right definition is still a
  /// clinical question, and a stored score silently becomes wrong when the
  /// definition changes.
  double? efficiencyScore({double? strengthBaseline, int? restingBpm}) {
    final strength = ratioTo(strengthBaseline);
    final exertion = exertionAgainst(restingBpm);
    if (strength == null || exertion == null || exertion <= 0) return null;
    return strength / exertion;
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
  final List<int> _bpm = [];
  DateTime? _startedAt;

  void start() {
    _samples.clear();
    _bpm.clear();
    _startedAt = DateTime.now();
  }

  /// Record one reading. [bpm] is ignored when it is null or 0, which is what
  /// the firmware reports whenever no finger is on the heart-rate sensor.
  void add(int value, {int? bpm}) {
    if (_startedAt == null) return;
    _samples.add(value);
    if (bpm != null && bpm > 0) _bpm.add(bpm);
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
      bpmAvg: _bpm.isEmpty
          ? null
          : (_bpm.reduce((a, b) => a + b) / _bpm.length).round(),
      bpmPeak: _bpm.isEmpty ? null : _bpm.reduce((a, b) => a > b ? a : b),
    );
    _startedAt = null;
    return result;
  }
}
