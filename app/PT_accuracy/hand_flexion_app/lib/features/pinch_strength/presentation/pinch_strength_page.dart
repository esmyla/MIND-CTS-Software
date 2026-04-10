/// lib/features/pinch_strength/presentation/pinch_strength_page.dart
// TODO(pinch): Replace placeholder page with real pinch capture + analysis
//              when sensor inputs and the data protocol are defined.
library;

import 'package:flutter/material.dart';
import '../../../shared/widgets/wip_page.dart';

class PinchStrengthPage extends StatelessWidget {
  const PinchStrengthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WipPage(
      heading: 'PINCH STRENGTH.\nWORK IN PROGRESS.',
      description:
          'Pinch strength measurement is coming soon. '
          'This feature will track lateral and tip pinch force to help '
          'you monitor fine motor recovery alongside your wrist therapy.',
      icon: Icons.touch_app_rounded,
    );
  }
}
