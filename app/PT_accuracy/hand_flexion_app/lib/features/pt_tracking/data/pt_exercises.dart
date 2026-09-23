/// lib/features/pt_tracking/data/pt_exercises.dart
///
/// The carpal-tunnel exercise library.
///
/// These are the standard conservative-management exercises for CTS — tendon
/// glides, median nerve glides, and wrist flexor/extensor stretches — as
/// described in the AAOS and MedlinePlus therapeutic exercise programmes linked
/// from `Research/CTS Therapies/therapies.md`. Wording here is our own.
///
/// Not medical advice, and not a prescription: a clinician decides which of
/// these a given patient should do and how often. The app's job is to make the
/// prescribed ones easy to perform correctly and to record that they happened.
library;

import 'package:flutter/material.dart';

enum ExerciseCategory { tendonGlide, nerveGlide, stretch, mobility, strength }

extension ExerciseCategoryLabel on ExerciseCategory {
  String get label => switch (this) {
        ExerciseCategory.tendonGlide => 'Tendon glide',
        ExerciseCategory.nerveGlide => 'Nerve glide',
        ExerciseCategory.stretch => 'Stretch',
        ExerciseCategory.mobility => 'Mobility',
        ExerciseCategory.strength => 'Strength',
      };

  IconData get icon => switch (this) {
        ExerciseCategory.tendonGlide => Icons.back_hand_outlined,
        ExerciseCategory.nerveGlide => Icons.timeline_rounded,
        ExerciseCategory.stretch => Icons.open_in_full_rounded,
        ExerciseCategory.mobility => Icons.rotate_right_rounded,
        ExerciseCategory.strength => Icons.fitness_center_rounded,
      };
}

/// One step within an exercise, held for [holdSeconds].
class ExerciseStep {
  final String name;
  final String detail;
  final int holdSeconds;

  const ExerciseStep({
    required this.name,
    required this.detail,
    this.holdSeconds = 5,
  });
}

class Exercise {
  final String id;
  final String name;
  final ExerciseCategory category;

  /// Why a CTS patient does this one.
  final String purpose;

  final List<ExerciseStep> steps;

  /// How many times to run the full step sequence.
  final int repetitions;

  /// Shown as a caution before starting.
  final String? caution;

  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.purpose,
    required this.steps,
    this.repetitions = 3,
    this.caution,
  });

  /// Rough time for one full pass, used for the "about N min" label.
  Duration get estimatedDuration {
    final perRep = steps.fold<int>(0, (sum, s) => sum + s.holdSeconds + 2);
    return Duration(seconds: perRep * repetitions);
  }
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

const ptExercises = <Exercise>[
  Exercise(
    id: 'tendon_glide',
    name: 'Tendon glides',
    category: ExerciseCategory.tendonGlide,
    purpose:
        'Moves the finger tendons through their full range inside the carpal '
        'tunnel, which helps stop them sticking to surrounding tissue.',
    repetitions: 5,
    steps: [
      ExerciseStep(
        name: 'Straight',
        detail: 'Fingers straight out, wrist neutral.',
      ),
      ExerciseStep(
        name: 'Hook fist',
        detail:
            'Bend the top two knuckles of each finger, keeping the base '
            'knuckles straight. Fingertips touch the top of your palm.',
      ),
      ExerciseStep(
        name: 'Full fist',
        detail: 'Curl all the way into a fist, thumb resting outside.',
      ),
      ExerciseStep(
        name: 'Tabletop',
        detail:
            'Bend at the base knuckles only, fingers straight and flat like a '
            'tabletop.',
      ),
      ExerciseStep(
        name: 'Straight fist',
        detail:
            'Bend the base and middle knuckles, keeping fingertips straight. '
            'Fingertips touch the base of your palm.',
      ),
    ],
  ),
  Exercise(
    id: 'median_nerve_glide',
    name: 'Median nerve glide',
    category: ExerciseCategory.nerveGlide,
    purpose:
        'Gently mobilises the median nerve — the one compressed in carpal '
        'tunnel syndrome — so it slides freely rather than tethering.',
    repetitions: 3,
    caution:
        'Stop immediately if you feel tingling, numbness, or shooting pain. '
        'This should feel like a light stretch, never a nerve zap.',
    steps: [
      ExerciseStep(
        name: 'Fist, thumb in',
        detail: 'Make a gentle fist with your thumb tucked inside the fingers.',
      ),
      ExerciseStep(
        name: 'Open hand',
        detail: 'Straighten fingers and thumb, keeping the wrist neutral.',
      ),
      ExerciseStep(
        name: 'Wrist back',
        detail: 'Fingers straight, bend the wrist back toward your forearm.',
      ),
      ExerciseStep(
        name: 'Thumb out',
        detail: 'Hold the wrist back and move the thumb away from the palm.',
      ),
      ExerciseStep(
        name: 'Forearm turn',
        detail:
            'Keep that position and rotate the forearm so the palm faces up.',
      ),
      ExerciseStep(
        name: 'Gentle thumb stretch',
        detail:
            'With the other hand, draw the thumb back a little further. Very '
            'light pressure.',
        holdSeconds: 8,
      ),
    ],
  ),
  Exercise(
    id: 'wrist_flexor_stretch',
    name: 'Wrist flexor stretch',
    category: ExerciseCategory.stretch,
    purpose:
        'Lengthens the forearm muscles on the palm side, easing the tension '
        'that pulls across the wrist.',
    repetitions: 3,
    steps: [
      ExerciseStep(
        name: 'Extend the arm',
        detail: 'Straighten one arm in front of you, palm facing up.',
        holdSeconds: 3,
      ),
      ExerciseStep(
        name: 'Draw the hand down',
        detail:
            'With the other hand, pull the fingers gently down and back until '
            'you feel a stretch along the inside of the forearm.',
        holdSeconds: 20,
      ),
    ],
  ),
  Exercise(
    id: 'wrist_extensor_stretch',
    name: 'Wrist extensor stretch',
    category: ExerciseCategory.stretch,
    purpose:
        'The counterpart to the flexor stretch, for the muscles along the back '
        'of the forearm.',
    repetitions: 3,
    steps: [
      ExerciseStep(
        name: 'Extend the arm',
        detail: 'Straighten one arm in front of you, palm facing down.',
        holdSeconds: 3,
      ),
      ExerciseStep(
        name: 'Draw the hand down',
        detail:
            'Gently press the back of the hand down until you feel a stretch '
            'along the top of the forearm.',
        holdSeconds: 20,
      ),
    ],
  ),
  Exercise(
    id: 'wrist_rom',
    name: 'Wrist range of motion',
    category: ExerciseCategory.mobility,
    purpose:
        'Keeps the joint moving freely through flexion, extension, and side to '
        'side. Pairs with the Flexion tab, which measures the same movement.',
    repetitions: 4,
    steps: [
      ExerciseStep(name: 'Flex down', detail: 'Bend the wrist forward, fingers relaxed.'),
      ExerciseStep(name: 'Extend back', detail: 'Bend the wrist back toward the forearm.'),
      ExerciseStep(name: 'Toward the thumb', detail: 'Tilt the hand toward the thumb side.'),
      ExerciseStep(name: 'Toward the little finger', detail: 'Tilt the hand the other way.'),
    ],
  ),
  Exercise(
    id: 'thumb_opposition',
    name: 'Thumb opposition',
    category: ExerciseCategory.strength,
    purpose:
        'Works the thenar muscles at the base of the thumb, which weaken when '
        'the median nerve is compressed. Complements the Pinch tab.',
    repetitions: 3,
    steps: [
      ExerciseStep(name: 'Thumb to index', detail: 'Touch thumb to index fingertip, forming an O.'),
      ExerciseStep(name: 'Thumb to middle', detail: 'Touch thumb to middle fingertip.'),
      ExerciseStep(name: 'Thumb to ring', detail: 'Touch thumb to ring fingertip.'),
      ExerciseStep(name: 'Thumb to little', detail: 'Touch thumb to little fingertip.'),
    ],
  ),
];
