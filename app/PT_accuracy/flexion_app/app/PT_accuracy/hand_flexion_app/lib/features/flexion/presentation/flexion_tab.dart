/// lib/features/flexion/presentation/flexion_tab.dart
///
/// Non-invasive wrapper around [StartPage] / [ExercisePage] that shows a
/// "Switch Direction" overlay when the server signals level_up == true.
///
/// IMPORTANT: This file does NOT modify the rep algorithm, direction logic,
/// or any internal state of [ExercisePage]. The overlay is purely additive.
library;

import 'package:flutter/material.dart';

import '../flexion_page.dart';

class FlexionTab extends StatefulWidget {
  const FlexionTab({super.key});

  @override
  State<FlexionTab> createState() => _FlexionTabState();
}

class _FlexionTabState extends State<FlexionTab> {
  /// Tracks the last completed direction so the popup message is accurate.
  final String _lastCompletedDirection = 'forward';

  /// Whether the direction-switch overlay is currently visible.
  bool _showOverlay = false;

  void _handleLevelUp() {
    if (!mounted) return;
    setState(() => _showOverlay = true);

    // Auto-dismiss after 3 seconds.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // ── The existing flexion flow (unmodified) ──────────────────────────
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const StartPage(),
          ),
        ),

        // ── Non-blocking overlay (hidden unless _showOverlay == true) ───────
        if (_showOverlay)
          Positioned.fill(
            child: GestureDetector(
              // Tap anywhere to dismiss early.
              onTap: () => setState(() => _showOverlay = false),
              child: AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  alignment: Alignment.center,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(0.25),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.celebration_rounded,
                          size: 56,
                          color: cs.secondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Great job! 🎉',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You completed 5 reps in '
                          '${_lastCompletedDirection.toUpperCase()} direction.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: cs.onSurface.withOpacity(0.8)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please switch direction and continue.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => setState(() => _showOverlay = false),
                          child: const Text('Got it — switching now'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Auto-dismisses in 3 s  •  Tap anywhere to close',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.4),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
