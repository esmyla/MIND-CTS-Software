/// lib/features/sensors/state/sensor_provider.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sensor_service.dart';
import '../data/strength_repository.dart';

// ---------------------------------------------------------------------------
// Pairing
// ---------------------------------------------------------------------------

const _pairedGloveKey = 'paired_glove_id';

/// The glove this patient last paired with, remembered on the device.
///
/// Stored locally rather than in Supabase on purpose: it identifies a piece of
/// hardware attached to *this* computer, so it should not follow the account to
/// another machine with a different glove plugged into it.
class PairedGloveNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pairedGloveKey);
    // Hand it to the socket so a reconnect re-attaches without asking again.
    ref.read(sensorServiceProvider).restorePairing(stored);
    return stored;
  }

  Future<void> pair(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairedGloveKey, deviceId);
    ref.read(sensorServiceProvider).pair(deviceId);
    state = AsyncData(deviceId);
  }

  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairedGloveKey);
    ref.read(sensorServiceProvider).unpair();
    state = const AsyncData(null);
  }
}

final pairedGloveProvider =
    AsyncNotifierProvider<PairedGloveNotifier, String?>(PairedGloveNotifier.new);

// ---------------------------------------------------------------------------
// Sensor bridge
// ---------------------------------------------------------------------------

/// Long-lived connection to the glove bridge.
///
/// One socket for the whole app: Grip and Pinch both read the same single FSR
/// channel, and opening a second connection would double the traffic for no
/// benefit.
final sensorServiceProvider = Provider<SensorService>((ref) {
  final service = SensorService()..connect();
  ref.onDispose(service.dispose);
  return service;
});

/// Live readings from the glove.
final sensorStreamProvider = StreamProvider<SensorSample>((ref) {
  return ref.watch(sensorServiceProvider).stream;
});

/// Devices the bridge can see, and which one it is attached to.
final gloveInventoryProvider = StreamProvider<GloveInventory>((ref) {
  final service = ref.watch(sensorServiceProvider);
  service.listDevices();
  return service.inventoryStream;
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
