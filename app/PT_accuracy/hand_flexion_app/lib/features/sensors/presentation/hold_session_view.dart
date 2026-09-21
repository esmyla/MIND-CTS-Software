/// lib/features/sensors/presentation/hold_session_view.dart
///
/// Shared UI for a guided "squeeze and hold" measurement.
///
/// Grip and Pinch are the same interaction against the same single FSR channel
/// — only the instructions and where the result is stored differ. This widget
/// owns the countdown, the live gauge, and the capture clock; the host page
/// decides what a finished hold means.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hold_capture.dart';
import '../data/sensor_service.dart';
import '../state/sensor_provider.dart';

// ---------------------------------------------------------------------------
// Phases
// ---------------------------------------------------------------------------

enum HoldPhase { idle, countdown, capturing, done }

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class HoldSessionView extends ConsumerStatefulWidget {
  const HoldSessionView({
    super.key,
    required this.title,
    required this.instruction,
    required this.onComplete,
    this.startLabel = 'Start hold',
    this.holdDuration = const Duration(seconds: 5),
    this.countdown = const Duration(seconds: 3),
  });

  /// Short heading, e.g. "Grip strength" or "Index-thumb pinch".
  final String title;

  /// What the patient should physically do.
  final String instruction;

  /// Called once a hold finishes. The host persists and advances.
  final Future<void> Function(HoldResult result) onComplete;

  final String startLabel;
  final Duration holdDuration;
  final Duration countdown;

  @override
  ConsumerState<HoldSessionView> createState() => _HoldSessionViewState();
}

class _HoldSessionViewState extends ConsumerState<HoldSessionView> {
  final _buffer = HoldBuffer();

  HoldPhase _phase = HoldPhase.idle;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  HoldResult? _result;
  bool _saving = false;

  static const _tick = Duration(milliseconds: 100);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Capture flow
  // ------------------------------------------------------------------

  void _begin() {
    setState(() {
      _phase = HoldPhase.countdown;
      _elapsed = Duration.zero;
      _result = null;
    });
    _runTimer(widget.countdown, onDone: _startCapture);
  }

  void _startCapture() {
    _buffer.start();
    setState(() {
      _phase = HoldPhase.capturing;
      _elapsed = Duration.zero;
    });
    _runTimer(widget.holdDuration, onDone: _finishCapture);
  }

  /// Drives both the countdown and the capture window off one ticker.
  void _runTimer(Duration total, {required VoidCallback onDone}) {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Sample on every tick while capturing. Reading the service's cached
      // `last` rather than subscribing keeps sampling at a steady 10 Hz
      // regardless of how fast the bridge pushes.
      if (_phase == HoldPhase.capturing) {
        final sample = ref.read(sensorServiceProvider).last;
        if (sample.connected) _buffer.add(sample.fsr);
      }

      setState(() => _elapsed += _tick);

      if (_elapsed >= total) {
        timer.cancel();
        onDone();
      }
    });
  }

  Future<void> _finishCapture() async {
    final result = _buffer.finish();
    setState(() {
      _result = result;
      _phase = HoldPhase.done;
    });

    if (!result.isUsable) return; // host is not told about a junk hold

    setState(() => _saving = true);
    try {
      await widget.onComplete(result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _phase = HoldPhase.idle;
      _elapsed = Duration.zero;
      _result = null;
    });
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sampleAsync = ref.watch(sensorStreamProvider);
    final sample = sampleAsync.valueOrNull ?? SensorSample.empty();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConnectionBanner(sample: sample),
          const SizedBox(height: 16),

          Text(widget.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: 6),
          Text(widget.instruction,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),

          _ForceGauge(
            sample: sample,
            phase: _phase,
            highlight: _phase == HoldPhase.capturing,
          ),
          const SizedBox(height: 24),

          _PhasePanel(
            phase: _phase,
            elapsed: _elapsed,
            countdown: widget.countdown,
            holdDuration: widget.holdDuration,
            result: _result,
            saving: _saving,
          ),
          const SizedBox(height: 24),

          if (_phase == HoldPhase.idle)
            FilledButton.icon(
              onPressed: sample.connected ? _begin : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(widget.startLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),

          if (_phase == HoldPhase.countdown || _phase == HoldPhase.capturing)
            OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Cancel'),
            ),

          if (_phase == HoldPhase.done)
            FilledButton.icon(
              onPressed: _saving ? null : _reset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Measure again'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection banner
// ---------------------------------------------------------------------------

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.sample});

  final SensorSample sample;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String text;

    if (!sample.connected) {
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
      icon = Icons.usb_off_rounded;
      text = 'Glove not connected. Start the sensor bridge, then plug in the glove.';
    } else if (sample.isSimulated) {
      bg = cs.tertiaryContainer;
      fg = cs.onTertiaryContainer;
      icon = Icons.science_rounded;
      text = 'Simulated data — not a real measurement.';
    } else {
      bg = cs.secondaryContainer;
      fg = cs.onSecondaryContainer;
      icon = Icons.usb_rounded;
      text = 'Glove connected.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: fg, fontWeight: FontWeight.w500)),
          ),
          if (sample.connected && sample.bpm > 0) ...[
            const SizedBox(width: 8),
            Icon(Icons.favorite_rounded, size: 14, color: fg),
            const SizedBox(width: 4),
            Text('${sample.bpm}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Force gauge
// ---------------------------------------------------------------------------

class _ForceGauge extends StatelessWidget {
  const _ForceGauge({
    required this.sample,
    required this.phase,
    required this.highlight,
  });

  final SensorSample sample;
  final HoldPhase phase;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = sample.connected ? sample.fsrFraction : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? cs.primary : cs.outlineVariant,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text('FORCE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.2,
                  )),
          const SizedBox(height: 8),
          // Raw ADC, labelled as such. The glove is not calibrated to newtons
          // or kilograms, so presenting a force unit would be a false claim.
          Text(
            sample.connected ? '${sample.fsr}' : '—',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight ? cs.primary : cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          Text('raw sensor units (0–${sample.fsrMax})',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              // Short enough to feel live, long enough not to strobe at 20 Hz.
              duration: const Duration(milliseconds: 120),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 14,
                backgroundColor: cs.surfaceContainerHighest,
                color: highlight ? cs.primary : cs.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase panel
// ---------------------------------------------------------------------------

class _PhasePanel extends StatelessWidget {
  const _PhasePanel({
    required this.phase,
    required this.elapsed,
    required this.countdown,
    required this.holdDuration,
    required this.result,
    required this.saving,
  });

  final HoldPhase phase;
  final Duration elapsed;
  final Duration countdown;
  final Duration holdDuration;
  final HoldResult? result;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    switch (phase) {
      case HoldPhase.idle:
        return Text(
          'Press start, then squeeze as hard as is comfortable and hold until '
          'the timer finishes.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        );

      case HoldPhase.countdown:
        final remaining = (countdown - elapsed).inMilliseconds / 1000;
        return Column(
          children: [
            Text('Get ready', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              remaining.ceil().clamp(0, 99).toString(),
              style: textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ],
        );

      case HoldPhase.capturing:
        final remaining = (holdDuration - elapsed).inMilliseconds / 1000;
        final progress =
            (elapsed.inMilliseconds / holdDuration.inMilliseconds).clamp(0.0, 1.0);
        return Column(
          children: [
            Text('SQUEEZE AND HOLD',
                style: textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                )),
            const SizedBox(height: 12),
            Text('${remaining.clamp(0, 99).toStringAsFixed(1)}s',
                style: textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        );

      case HoldPhase.done:
        final r = result;
        if (r == null) return const SizedBox.shrink();

        if (!r.isUsable) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
                const SizedBox(height: 8),
                Text(
                  'Not enough sensor data to score this hold '
                  '(${r.sampleCount} readings). Nothing was saved — check the '
                  'glove connection and try again.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onErrorContainer),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text('RESULT',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                    letterSpacing: 1.2,
                  )),
              const SizedBox(height: 8),
              Text(r.value.toStringAsFixed(1),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSecondaryContainer,
                  )),
              Text('mean of strongest 60% · peak ${r.peak}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onSecondaryContainer)),
              if (saving) ...[
                const SizedBox(height: 14),
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        );
    }
  }
}
