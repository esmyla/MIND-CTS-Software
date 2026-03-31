/// lib/features/flexion/presentation/flexion_tab.dart
///
/// Non-invasive wrapper around [StartPage] that shows a full-screen
/// "Session Complete" overlay when [ExercisePage] signals completion.
///
/// Callback chain:
///   FlexionTab._handleSessionComplete
///     → StartPage.onSessionComplete
///       → ExercisePage.onLevelUp
///         → fires after Supabase row is inserted
library;

import 'package:flutter/material.dart';

import '../flexion_page.dart';

class FlexionTab extends StatefulWidget {
  const FlexionTab({super.key});

  @override
  State<FlexionTab> createState() => _FlexionTabState();
}

class _FlexionTabState extends State<FlexionTab> {
  bool _showCompletion = false;

  void _handleSessionComplete() {
    if (!mounted) return;
    setState(() => _showCompletion = true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // ── Flexion flow (StartPage → ExercisePage) ─────────────────────────
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => StartPage(
              onSessionComplete: _handleSessionComplete,
            ),
          ),
        ),

        // ── Session-complete overlay ─────────────────────────────────────────
        if (_showCompletion)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showCompletion = false),
              child: AnimatedOpacity(
                opacity: _showCompletion ? 1.0 : 0.0,
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
                          'Session Complete! 🎉',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You completed your full forward and backward '
                          'flexion session. Your progress has been saved.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: cs.onSurface.withOpacity(0.8),
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keep it up — see you next session!',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => setState(() => _showCompletion = false),
                          child: const Text('Done'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap anywhere to close',
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
