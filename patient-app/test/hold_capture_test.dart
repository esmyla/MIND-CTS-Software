/// Tests for the strength aggregation shared by the Grip and Pinch tabs.
///
/// This is the number that lands in the database and that a clinician reads as
/// patient progress, so the edge cases matter more than the happy path.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:therapy_app/features/sensors/data/hold_capture.dart';

void main() {
  group('topSixtyPercentMean', () {
    test('returns 0 for no samples rather than NaN', () {
      // The Python original averaged an empty slice here and produced NaN,
      // which would have been written straight to the database.
      expect(topSixtyPercentMean([]), 0);
    });

    test('a single sample is its own mean', () {
      expect(topSixtyPercentMean([1500]), 1500);
    });

    test('averages only the strongest 60%', () {
      // 10 samples -> top 6 are 100..50, mean 75.
      final samples = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
      expect(topSixtyPercentMean(samples), 75);
    });

    test('ignores sample order', () {
      final ascending = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
      final shuffled = [70, 10, 100, 40, 90, 30, 60, 20, 80, 50];
      expect(
        topSixtyPercentMean(shuffled),
        topSixtyPercentMean(ascending),
      );
    });

    test('a weak release tail does not drag the score down', () {
      // A real hold: ramp up, sustain near 3000, then let go. The trailing
      // near-zero readings are exactly what the top-60% rule exists to discard.
      final hold = [
        400, 1200, 2400, 2900, 3000, 2950, 3010, 2980, 2900, 2850,
        1500, 600, 120, 40, 0,
      ];
      final score = topSixtyPercentMean(hold);
      expect(score, greaterThan(2400));
    });

    test('one spike cannot carry a weak hold', () {
      final weakWithSpike = [
        100, 110, 105, 95, 120, 115, 100, 90, 105, 4095,
      ];
      // The spike is one of six retained samples, not the whole story.
      expect(topSixtyPercentMean(weakWithSpike), lessThan(800));
    });

    test('keeps at least one sample when 60% rounds to zero', () {
      // floor(0.6 * 2) == 1, but floor(0.6 * 1) == 0 — the guard matters.
      expect(topSixtyPercentMean([800, 200]), 800);
    });
  });

  group('HoldResult', () {
    HoldResult make({double value = 1000, int samples = 50}) => HoldResult(
          value: value,
          peak: 1200,
          sampleCount: samples,
          duration: const Duration(seconds: 5),
        );

    test('ratioTo is null without a baseline', () {
      expect(make().ratioTo(null), isNull);
    });

    test('ratioTo is null for a zero or negative baseline', () {
      // Guards against divide-by-zero producing Infinity in the database.
      expect(make().ratioTo(0), isNull);
      expect(make().ratioTo(-5), isNull);
    });

    test('ratioTo divides by the baseline', () {
      expect(make(value: 1500).ratioTo(1000), closeTo(1.5, 1e-9));
    });

    test('a hold with too few readings is not usable', () {
      expect(make(samples: 3).isUsable, isFalse);
      expect(make(samples: 50).isUsable, isTrue);
    });
  });

  group('exertion and efficiency', () {
    HoldResult hold({double value = 1500, int? bpm}) => HoldResult(
          value: value,
          peak: 1800,
          sampleCount: 50,
          duration: const Duration(seconds: 5),
          bpmAvg: bpm,
        );

    test('exertion is null without a resting rate', () {
      expect(hold(bpm: 90).exertionAgainst(null), isNull);
      expect(hold(bpm: 90).exertionAgainst(0), isNull);
    });

    test('exertion is null when no heart rate was captured', () {
      // The firmware reports 0 whenever no finger is on the sensor, which is
      // normal during a grip — it must not be read as a real measurement.
      expect(hold(bpm: null).exertionAgainst(60), isNull);
      expect(hold(bpm: 0).exertionAgainst(60), isNull);
    });

    test('exertion is heart rate relative to rest', () {
      expect(hold(bpm: 90).exertionAgainst(60), closeTo(1.5, 1e-9));
    });

    test('efficiency needs BOTH baselines, not one', () {
      // A half-known score would be compared against scores that meant
      // something else entirely.
      expect(hold(bpm: 90).efficiencyScore(strengthBaseline: null, restingBpm: 60), isNull);
      expect(hold(bpm: null).efficiencyScore(strengthBaseline: 1000, restingBpm: 60), isNull);
      expect(hold(bpm: 90).efficiencyScore(strengthBaseline: 1000, restingBpm: null), isNull);
    });

    test('same force at a higher heart rate scores worse', () {
      final easy = hold(value: 1500, bpm: 70).efficiencyScore(
          strengthBaseline: 1000, restingBpm: 60)!;
      final strained = hold(value: 1500, bpm: 110).efficiencyScore(
          strengthBaseline: 1000, restingBpm: 60)!;
      expect(strained, lessThan(easy));
    });

    test('baseline force at baseline heart rate scores exactly 1.0', () {
      final score = hold(value: 1000, bpm: 60)
          .efficiencyScore(strengthBaseline: 1000, restingBpm: 60);
      expect(score, closeTo(1.0, 1e-9));
    });

    test('more force for the same effort scores above 1.0', () {
      final score = hold(value: 1400, bpm: 60)
          .efficiencyScore(strengthBaseline: 1000, restingBpm: 60);
      expect(score, greaterThan(1.0));
    });
  });

  group('HoldBuffer', () {
    test('ignores samples added before start', () {
      final buffer = HoldBuffer();
      buffer.add(999);
      expect(buffer.sampleCount, 0);
    });

    test('collects and scores a hold', () {
      final buffer = HoldBuffer()..start();
      for (final v in [100, 200, 300, 400, 500]) {
        buffer.add(v);
      }
      expect(buffer.sampleCount, 5);
      expect(buffer.peak, 500);

      final result = buffer.finish();
      // Top 60% of 5 samples is 3: 500, 400, 300 -> 400.
      expect(result.value, 400);
      expect(result.peak, 500);
      expect(result.sampleCount, 5);
    });

    test('ignores zero heart rates, which mean "no finger on the sensor"', () {
      final buffer = HoldBuffer()..start();
      buffer.add(100, bpm: 0);
      buffer.add(200, bpm: 0);
      final result = buffer.finish();
      expect(result.sampleCount, 2, reason: 'force samples still count');
      expect(result.bpmAvg, isNull);
      expect(result.bpmPeak, isNull);
    });

    test('averages only the heart rates that were real', () {
      final buffer = HoldBuffer()..start();
      buffer.add(100, bpm: 0);
      buffer.add(100, bpm: 80);
      buffer.add(100, bpm: 100);
      final result = buffer.finish();
      expect(result.bpmAvg, 90);
      expect(result.bpmPeak, 100);
    });

    test('start clears a previous hold', () {
      final buffer = HoldBuffer()..start();
      buffer.add(5000);
      buffer.start();
      buffer.add(10);
      expect(buffer.sampleCount, 1);
      expect(buffer.peak, 10);
    });
  });
}
