/// lib/features/pt_tracking/presentation/pt_tracking_page.dart
// TODO(pt): Implement median nerve dexterity routines and tracking after
//           the clinical protocol is finalized.
library;

import 'package:flutter/material.dart';
import '../../../shared/widgets/wip_page.dart';

class PtTrackingPage extends StatelessWidget {
  const PtTrackingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WipPage(
      heading: 'PHYSICAL THERAPY TRACKING.\nWORK IN PROGRESS.',
      description:
          'Comprehensive physical therapy session tracking is coming soon. '
          'This feature will log your therapy protocols, track adherence, '
          'and provide progress reports for you and your therapist.',
      icon: Icons.assignment_rounded,
    );
  }
}
