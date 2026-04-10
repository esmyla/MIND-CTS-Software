/// lib/shared/widgets/wip_page.dart
///
/// Reusable "Work In Progress" placeholder page used by FSR Grip,
/// PT Tracking, and Pinch Strength tabs.
library;

import 'package:flutter/material.dart';

class WipPage extends StatelessWidget {
  /// The exact heading text required by the spec (e.g. "FSR GRIP STRENGTH PAGE.
  /// WORK IN PROGRESS").
  final String heading;

  /// Short description shown beneath the heading.
  final String description;

  /// Icon representing the feature.
  final IconData icon;

  const WipPage({
    super.key,
    required this.heading,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 32),

              // Spec-required heading
              Text(
                heading,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                description,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.65),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Disabled CTA indicating future capability
              const FilledButton.tonal(
                onPressed: null, // intentionally disabled
                child: Text('Coming Soon'),
              ),
              const SizedBox(height: 12),
              Text(
                'This feature is under active development.\n'
                'Check back for updates!',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.4),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
