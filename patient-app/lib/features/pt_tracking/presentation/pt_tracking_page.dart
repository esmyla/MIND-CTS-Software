/// lib/features/pt_tracking/presentation/pt_tracking_page.dart
///
/// Guided therapy exercises with per-day adherence tracking.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pt_exercises.dart';
import '../state/pt_tracking_provider.dart';

class PtTrackingPage extends ConsumerWidget {
  const PtTrackingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneAsync = ref.watch(ptCompletionProvider);
    final done = doneAsync.valueOrNull ?? const <String>{};
    final weekAsync = ref.watch(ptWeekAdherenceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PT Tracking'),
        actions: [
          if (done.isNotEmpty)
            IconButton(
              tooltip: "Reset today",
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: () =>
                  ref.read(ptCompletionProvider.notifier).resetToday(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TodayCard(
            completed: done.length,
            total: ptExercises.length,
            weekDays: weekAsync.valueOrNull ?? 0,
          ),
          const SizedBox(height: 20),
          Text('Exercises', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Work through these at the pace your clinician recommends.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          ...ptExercises.map(
            (e) => _ExerciseTile(
              exercise: e,
              done: done.contains(e.id),
              onTap: () => _open(context, ref, e),
            ),
          ),
          const SizedBox(height: 24),
          const _Disclaimer(),
        ],
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref, Exercise exercise) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _GuidedExerciseScreen(exercise: exercise),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.completed,
    required this.total,
    required this.weekDays,
  });

  final int completed;
  final int total;
  final int weekDays;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TODAY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    letterSpacing: 1.2,
                  )),
          const SizedBox(height: 6),
          Text('$completed of $total exercises',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.15),
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 15, color: cs.onPrimaryContainer),
              const SizedBox(width: 6),
              Text('Active $weekDays of the last 7 days',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer,
                      )),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List tile
// ---------------------------------------------------------------------------

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.done,
    required this.onTap,
  });

  final Exercise exercise;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minutes = (exercise.estimatedDuration.inSeconds / 60).ceil();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: done ? cs.secondaryContainer : cs.surfaceContainerHighest,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              done ? cs.secondary : cs.primary.withValues(alpha: 0.15),
          child: Icon(
            done ? Icons.check_rounded : exercise.category.icon,
            color: done ? cs.onSecondary : cs.primary,
          ),
        ),
        title: Text(exercise.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${exercise.category.label} · ${exercise.repetitions} reps · ~$minutes min',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These are general carpal tunnel exercises, not a personalised '
              'treatment plan. Follow the programme your clinician gives you, '
              'and stop any movement that causes pain, numbness, or tingling.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guided player
// ---------------------------------------------------------------------------

class _GuidedExerciseScreen extends ConsumerStatefulWidget {
  const _GuidedExerciseScreen({required this.exercise});

  final Exercise exercise;

  @override
  ConsumerState<_GuidedExerciseScreen> createState() =>
      _GuidedExerciseScreenState();
}

class _GuidedExerciseScreenState extends ConsumerState<_GuidedExerciseScreen> {
  bool _running = false;
  bool _finished = false;
  int _rep = 0;
  int _stepIndex = 0;
  int _secondsLeft = 0;
  Timer? _timer;

  Exercise get _e => widget.exercise;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _finished = false;
      _rep = 0;
      _stepIndex = 0;
      _secondsLeft = _e.steps.first.holdSeconds;
    });
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
        return;
      }
      _advance();
    });
  }

  void _advance() {
    final isLastStep = _stepIndex >= _e.steps.length - 1;
    final isLastRep = _rep >= _e.repetitions - 1;

    if (isLastStep && isLastRep) {
      _complete();
      return;
    }

    setState(() {
      if (isLastStep) {
        _rep++;
        _stepIndex = 0;
      } else {
        _stepIndex++;
      }
      _secondsLeft = _e.steps[_stepIndex].holdSeconds;
    });
  }

  Future<void> _complete() async {
    _timer?.cancel();
    setState(() {
      _running = false;
      _finished = true;
    });
    await ref.read(ptCompletionProvider.notifier).markComplete(_e.id);
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = _e.steps[_stepIndex];

    return Scaffold(
      appBar: AppBar(title: Text(_e.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_e.purpose,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            if (_e.caution != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: cs.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_e.caution!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            if (_finished)
              _CompletionPanel(onAgain: _start, exercise: _e)
            else ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _running
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      _running
                          ? 'Rep ${_rep + 1} of ${_e.repetitions} · step ${_stepIndex + 1} of ${_e.steps.length}'
                          : '${_e.repetitions} reps · ${_e.steps.length} steps each',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: _running
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(step.name,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: _running
                                      ? cs.onPrimaryContainer
                                      : cs.onSurface,
                                )),
                    const SizedBox(height: 10),
                    Text(step.detail,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _running
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                )),
                    if (_running) ...[
                      const SizedBox(height: 20),
                      Text('$_secondsLeft',
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimaryContainer,
                              )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!_running)
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start exercise'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                )
              else ...[
                OutlinedButton(
                  onPressed: _stop,
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: const Text('Pause'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _complete,
                  child: const Text('Mark done and finish'),
                ),
              ],
            ],

            const SizedBox(height: 28),
            Text('All steps', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ..._e.steps.asMap().entries.map((entry) {
              final active = _running && entry.key == _stepIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                      ),
                      child: Text('${entry.key + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: active ? cs.onPrimary : cs.onSurfaceVariant,
                          )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${entry.value.name} — ${entry.value.detail}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: active ? cs.onSurface : cs.onSurfaceVariant,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
                            ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel({required this.onAgain, required this.exercise});

  final VoidCallback onAgain;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, size: 48, color: cs.onSecondaryContainer),
          const SizedBox(height: 12),
          Text('${exercise.name} complete',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 6),
          Text('Logged for today.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSecondaryContainer)),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onAgain,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Do it again'),
          ),
        ],
      ),
    );
  }
}
