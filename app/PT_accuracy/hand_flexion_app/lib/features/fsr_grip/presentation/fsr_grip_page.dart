/// lib/features/fsr_grip/presentation/fsr_grip_page.dart
// TODO(fsr): Replace placeholder page with real FSR capture + analysis
//            when server endpoints and BLE/WebSocket protocol are confirmed.
library;

import 'package:flutter/material.dart';
import '../../../shared/widgets/wip_page.dart';

class FsrGripPage extends StatelessWidget {
  const FsrGripPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WipPage(
      heading: 'FSR GRIP STRENGTH PAGE.\nWORK IN PROGRESS.',
      description:
          'Force-sensitive resistor grip strength tracking is coming soon. '
          'This feature will measure and track your grip force over time '
          'to complement your wrist flexion therapy.',
      icon: Icons.stacked_line_chart_rounded,
    );
  }
}
