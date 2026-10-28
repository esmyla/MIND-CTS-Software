/// lib/features/fsr_grip/presentation/fsr_grip_page.dart
///
/// Grip strength measurement from the glove's palm FSR.
///
/// A session is one five-second maximal hold. The stored value is the mean of
/// the strongest 60% of readings (`grip.fsr_palm`); when the patient has a
/// baseline, the ratio against it is stored alongside (`grip.r_fsr_palm`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sensors/data/hold_capture.dart';
import '../../sensors/presentation/hold_session_view.dart';
import '../../sensors/state/sensor_provider.dart';

class FsrGripPage extends ConsumerWidget {
  const FsrGripPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baselineAsync = ref.watch(baselineProvider);
    final repo = ref.watch(strengthRepositoryProvider);

    final baselineGrip = _asDouble(baselineAsync.valueOrNull?['base_grip']);
    final hasBaseline = baselineGrip != null && baselineGrip > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grip Strength'),
        actions: [
          IconButton(
            tooltip: 'Recalibrate baseline',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _confirmRecalibrate(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasBaseline) const _BaselinePrompt(),
          Expanded(
            child: HoldSessionView(
              title: hasBaseline ? 'Grip strength' : 'Baseline grip',
              instruction: hasBaseline
                  ? 'Wear the glove and squeeze your whole hand into a fist, '
                      'pressing into the palm sensor.'
                  : 'This first measurement becomes your baseline — every later '
                      'session is scored against it. Squeeze as hard as is '
                      'comfortable.',
              startLabel: hasBaseline ? 'Start hold' : 'Measure baseline',
              onComplete: (result) => _handleComplete(
                context: context,
                ref: ref,
                result: result,
                baselineGrip: hasBaseline ? baselineGrip : null,
              ),
            ),
          ),
          if (hasBaseline)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Baseline: ${baselineGrip.toStringAsFixed(1)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          if (!repo.canPersist)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _GuestNotice(),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------

  Future<void> _handleComplete({
    required BuildContext context,
    required WidgetRef ref,
    required HoldResult result,
    required double? baselineGrip,
  }) async {
    final repo = ref.read(strengthRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (!repo.canPersist) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Measured, but not saved — sign in to track progress.'),
      ));
      return;
    }

    // No baseline yet: this hold establishes it, and also counts as session 1.
    if (baselineGrip == null) {
      final ok = await repo.saveBaseline(baseGrip: result.value);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not save baseline.')),
        );
        return;
      }
      ref.invalidate(baselineProvider);
    }

    final effectiveBaseline = baselineGrip ?? result.value;
    final sessionId = await repo.saveGripSession(
      fsrPalm: result.value,
      ratio: result.ratioTo(effectiveBaseline),
    );

    ref.invalidate(strengthHistoryProvider('grip'));

    if (sessionId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save this session.')),
      );
      return;
    }

    final ratio = result.ratioTo(effectiveBaseline);
    messenger.showSnackBar(SnackBar(
      content: Text(
        baselineGrip == null
            ? 'Baseline set and session $sessionId saved.'
            : 'Session $sessionId saved — '
                '${((ratio ?? 1) * 100).toStringAsFixed(0)}% of baseline.',
      ),
    ));
  }

  Future<void> _confirmRecalibrate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recalibrate baseline?'),
        content: const Text(
          'Your next hold will replace the stored baseline. Past sessions keep '
          'the ratios they were saved with, so your history stays intact, but '
          'future sessions will be scored against the new value.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Recalibrate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo = ref.read(strengthRepositoryProvider);
    await repo.saveBaseline(baseGrip: 0); // 0 reads as "not calibrated"
    ref.invalidate(baselineProvider);
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

// ---------------------------------------------------------------------------

class _BaselinePrompt extends StatelessWidget {
  const _BaselinePrompt();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No baseline yet — your first hold sets it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestNotice extends StatelessWidget {
  const _GuestNotice();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      'Guest mode — measurements are shown but not saved.',
      textAlign: TextAlign.center,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: cs.onSurfaceVariant),
    );
  }
}
