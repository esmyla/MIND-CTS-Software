/// lib/features/sensors/state/sensor_provider.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sensor_service.dart';
import '../data/strength_repository.dart';

// ---------------------------------------------------------------------------
// Sensor bridge
// ---------------------------------------------------------------------------

/// Long-lived connection to the glove bridge.
///
/// One socket for the whole app: Grip and Pinch both read the same single FSR
/// channel, and opening a second connection would double the traffic for no
/// benefit. `keepAlive` so switching tabs mid-session doesn't drop the link.
final sensorServiceProvider = Provider<SensorService>((ref) {
  final service = SensorService()..connect();
  ref.onDispose(service.dispose);
  return service;
});

/// Live readings from the glove.
final sensorStreamProvider = StreamProvider<SensorSample>((ref) {
  final service = ref.watch(sensorServiceProvider);
  // Seed with the last known sample so a tab switch doesn't flash "waiting".
  return service.stream;
});

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

final strengthRepositoryProvider = Provider<StrengthRepository>((ref) {
  return const StrengthRepository();
});

/// The signed-in user's baseline row, or null if not yet calibrated.
///
/// Invalidate after writing a baseline so dependent screens recompute ratios.
final baselineProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  return ref.watch(strengthRepositoryProvider).fetchBaseline();
});

/// Session history for one table, oldest first.
final strengthHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, table) async {
  return ref.watch(strengthRepositoryProvider).fetchHistory(table);
});
