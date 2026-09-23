/// lib/features/pinch_strength/presentation/pinch_strength_page.dart
///
/// Pinch strength measurement.
///
/// The schema records two values per session — index-thumb (`it`) and
/// middle-thumb (`mt`) — but the current glove firmware
/// (`firmware/CTS_IC2.ino`) exposes a single FSR channel. So a session is two
/// sequential holds against the same sensor rather than two simultaneous
/// readings. If a two-sensor sketch lands later, only the capture flow here
/// changes; the stored shape is already correct.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sensors/data/hold_capture.dart';
import '../../sensors/presentation/hold_session_view.dart';
import '../../sensors/state/sensor_provider.dart';

// ---------------------------------------------------------------------------

enum _PinchStage { indexThumb, middleThumb, complete }

class PinchStrengthPage extends ConsumerStatefulWidget {
  const PinchStrengthPage({super.key});

  @override
  ConsumerState<PinchStrengthPage> createState() => _PinchStrengthPageState();
}

class _PinchStrengthPageState extends ConsumerState<PinchStrengthPage> {
  _PinchStage _stage = _PinchStage.indexThumb;

  HoldResult? _itResult;
  HoldResult? _mtResult;
  int? _savedSessionId;
  bool _saveFailed = false;

  @override
  Widget build(BuildContext context) {
    final baselineAsync = ref.watch(baselineProvider);
    final repo = ref.watch(strengthRepositoryProvider);

    final baseIt = _asDouble(baselineAsync.valueOrNull?['base_it']);
    final baseMt = _asDouble(baselineAsync.valueOrNull?['base_mt']);
    final hasBaseline =
        (baseIt != null && baseIt > 0) && (baseMt != null && baseMt > 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pinch Strength'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: switch (_stage) {
              _PinchStage.indexThumb => 0.0,
              _PinchStage.middleThumb => 0.5,
              _PinchStage.complete => 1.0,
            },
            minHeight: 4,
          ),
        ),
      ),
      body: Column(
        children: [
          _StageIndicator(stage: _stage, it: _itResult, mt: _mtResult),
          if (!hasBaseline) const _BaselineBanner(),
          Expanded(child: _buildStage(hasBaseline, baseIt, baseMt)),
          if (!repo.canPersist)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Guest mode — measurements are shown but not saved.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage(bool hasBaseline, double? baseIt, double? baseMt) {
    switch (_stage) {
      case _PinchStage.indexThumb:
        return HoldSessionView(
          key: const ValueKey('pinch-it'),
          title: 'Index-thumb pinch',
          instruction:
              'Pinch the sensor between your thumb and index finger, then '
              'squeeze steadily for the full countdown.',
          startLabel: 'Start index-thumb',
          onComplete: (result) async {
            setState(() {
              _itResult = result;
              _stage = _PinchStage.middleThumb;
            });
          },
        );

      case _PinchStage.middleThumb:
        return HoldSessionView(
          key: const ValueKey('pinch-mt'),
          title: 'Middle-thumb pinch',
          instruction:
              'Now move the sensor to your middle finger. Pinch between thumb '
              'and middle finger and hold.',
          startLabel: 'Start middle-thumb',
          onComplete: (result) async {
            setState(() => _mtResult = result);
            await _saveSession(baseIt: baseIt, baseMt: baseMt);
            if (mounted) setState(() => _stage = _PinchStage.complete);
          },
        );

      case _PinchStage.complete:
        return _Summary(
          it: _itResult,
          mt: _mtResult,
          baseIt: baseIt,
          baseMt: baseMt,
          sessionId: _savedSessionId,
          saveFailed: _saveFailed,
          onRestart: () => setState(() {
            _stage = _PinchStage.indexThumb;
            _itResult = null;
            _mtResult = null;
            _savedSessionId = null;
            _saveFailed = false;
          }),
        );
    }
  }

  // ------------------------------------------------------------------

  Future<void> _saveSession({double? baseIt, double? baseMt}) async {
    final it = _itResult;
    final mt = _mtResult;
    if (it == null || mt == null) return;

    final repo = ref.read(strengthRepositoryProvider);
    if (!repo.canPersist) return;

    // First session doubles as calibration, matching the Grip tab.
    final needsBaseline =
        !(baseIt != null && baseIt > 0 && baseMt != null && baseMt > 0);
    if (needsBaseline) {
      await repo.saveBaseline(baseIt: it.value, baseMt: mt.value);
      ref.invalidate(baselineProvider);
    }

    final effectiveIt = (baseIt != null && baseIt > 0) ? baseIt : it.value;
    final effectiveMt = (baseMt != null && baseMt > 0) ? baseMt : mt.value;

    final sessionId = await repo.savePinchSession(
      it: it.value,
      mt: mt.value,
      ratioIt: it.ratioTo(effectiveIt),
      ratioMt: mt.ratioTo(effectiveMt),
    );

    ref.invalidate(strengthHistoryProvider('pinch'));

    if (!mounted) return;
    setState(() {
      _savedSessionId = sessionId;
      _saveFailed = sessionId == null;
    });
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

class _StageIndicator extends StatelessWidget {
  const _StageIndicator({required this.stage, this.it, this.mt});

  final _PinchStage stage;
  final HoldResult? it;
  final HoldResult? mt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _StageChip(
              label: 'Index-thumb',
              value: it?.value,
              active: stage == _PinchStage.indexThumb,
              done: it != null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StageChip(
              label: 'Middle-thumb',
              value: mt?.value,
              active: stage == _PinchStage.middleThumb,
              done: mt != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.value,
    required this.active,
    required this.done,
  });

  final String label;
  final double? value;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = active
        ? cs.primaryContainer
        : done
            ? cs.secondaryContainer
            : cs.surfaceContainerHighest;
    final fg = active
        ? cs.onPrimaryContainer
        : done
            ? cs.onSecondaryContainer
            : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(done ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 14, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        )),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value == null ? '—' : value!.toStringAsFixed(1),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _BaselineBanner extends StatelessWidget {
  const _BaselineBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No pinch baseline yet — this session sets it.',
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

// ---------------------------------------------------------------------------

class _Summary extends StatelessWidget {
  const _Summary({
    required this.it,
    required this.mt,
    required this.baseIt,
    required this.baseMt,
    required this.sessionId,
    required this.saveFailed,
    required this.onRestart,
  });

  final HoldResult? it;
  final HoldResult? mt;
  final double? baseIt;
  final double? baseMt;
  final int? sessionId;
  final bool saveFailed;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 56, color: cs.primary),
          const SizedBox(height: 12),
          Text('Session complete',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            saveFailed
                ? 'Measured, but saving failed. Check your connection.'
                : sessionId != null
                    ? 'Saved as session $sessionId.'
                    : 'Measured (not saved).',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: saveFailed ? cs.error : cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _ResultRow(label: 'Index-thumb', result: it, baseline: baseIt),
          const SizedBox(height: 12),
          _ResultRow(label: 'Middle-thumb', result: mt, baseline: baseMt),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('New session'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.result, this.baseline});

  final String label;
  final HoldResult? result;
  final double? baseline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = result?.ratioTo(baseline);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  result == null
                      ? '—'
                      : '${result!.value.toStringAsFixed(1)} · peak ${result!.peak}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            ratio == null ? 'baseline' : '${(ratio * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
          ),
        ],
      ),
    );
  }
}
