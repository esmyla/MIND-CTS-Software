/// lib/features/sensors/data/sensor_service.dart
///
/// Client for the glove sensor bridge (`app/PT_accuracy/backend/sensor_ws_server.py`).
///
/// The glove is an ESP32 wired over USB. Flutter web cannot open a serial port,
/// so the bridge process owns the port and rebroadcasts each reading as JSON
/// over a WebSocket. This class is the app's end of that socket.
///
/// Each patient has their own glove and their own bridge, so the app pairs with
/// a specific device: it lists what the bridge can see, the patient picks one,
/// and the choice is remembered by USB serial number so the same glove is
/// recognised after a replug.
///
/// Shared by the FSR Grip and Pinch tabs — both measure the same single FSR
/// channel, just under different instructions.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../config/env.dart';

// ---------------------------------------------------------------------------
// Device
// ---------------------------------------------------------------------------

/// A glove the bridge can attach to.
@immutable
class GloveDevice {
  /// Pairing key. The USB serial number when the board reports one, otherwise
  /// the device path — see [hasStableId].
  final String id;

  /// OS device path, e.g. /dev/cu.usbmodem1101.
  final String port;

  final String description;
  final String? manufacturer;

  /// False when the board reports no USB serial number, so the pairing is tied
  /// to the physical USB socket and breaks if the glove is moved.
  final bool hasStableId;

  /// The USB vendor matches a chip commonly used on ESP32 boards. A hint for
  /// ordering the list, never a filter — an unrecognised board is still valid.
  final bool likelyGlove;

  const GloveDevice({
    required this.id,
    required this.port,
    required this.description,
    required this.hasStableId,
    required this.likelyGlove,
    this.manufacturer,
  });

  factory GloveDevice.fromJson(Map<String, dynamic> json) => GloveDevice(
        id: (json['id'] ?? '').toString(),
        port: (json['port'] ?? '').toString(),
        description: (json['description'] ?? 'Unknown device').toString(),
        manufacturer: json['manufacturer'] as String?,
        hasStableId: json['stable_id'] == true,
        likelyGlove: json['likely_glove'] == true,
      );

  /// The bridge's built-in synthetic source, for demos without hardware.
  bool get isSimulated => id == 'simulated-glove';

  @override
  bool operator ==(Object other) => other is GloveDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ---------------------------------------------------------------------------
// Sample
// ---------------------------------------------------------------------------

/// One reading from the glove.
@immutable
class SensorSample {
  /// Raw IR from the MAX30102. Only meaningful for finger-presence detection.
  final int ir;

  /// Averaged beats per minute. Zero when no finger is on the sensor —
  /// the firmware zeroes `beatAvg` in that case, so treat 0 as "unknown",
  /// not as an actual heart rate.
  final int bpm;

  final double tempC;

  /// Raw FSR ADC reading. 12-bit on the ESP32-C6, so 0..[fsrMax].
  final int fsr;
  final int fsrMax;

  final bool fingerPresent;

  /// Whether the bridge currently has a live link to the glove.
  final bool connected;

  /// True when the bridge is up but the glove stopped sending.
  final bool stale;

  /// "serial" for real hardware, "simulate" for synthetic data.
  final String source;

  /// The glove this reading came from, or null when nothing is paired.
  final GloveDevice? device;

  /// How many sessions are attached to this bridge. Normally 1.
  final int viewers;

  final String? error;
  final DateTime receivedAt;

  const SensorSample({
    required this.ir,
    required this.bpm,
    required this.tempC,
    required this.fsr,
    required this.fsrMax,
    required this.fingerPresent,
    required this.connected,
    required this.stale,
    required this.source,
    required this.receivedAt,
    this.device,
    this.viewers = 1,
    this.error,
  });

  factory SensorSample.empty() => SensorSample(
        ir: 0,
        bpm: 0,
        tempC: 0,
        fsr: 0,
        fsrMax: 4095,
        fingerPresent: false,
        connected: false,
        stale: false,
        source: 'none',
        viewers: 0,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory SensorSample.fromJson(Map<String, dynamic> json) {
    final rawDevice = json['device'];
    return SensorSample(
      ir: _toInt(json['ir']),
      bpm: _toInt(json['bpm']),
      tempC: _toDouble(json['temp_c']),
      fsr: _toInt(json['fsr']),
      fsrMax: _toInt(json['fsr_max'], fallback: 4095),
      fingerPresent: json['finger_present'] == true,
      connected: json['connected'] == true,
      stale: json['stale'] == true,
      source: (json['source'] as String?) ?? 'none',
      device: rawDevice is Map<String, dynamic>
          ? GloveDevice.fromJson(rawDevice)
          : null,
      viewers: _toInt(json['viewers'], fallback: 1),
      error: json['error'] as String?,
      receivedAt: DateTime.now(),
    );
  }

  /// FSR as a 0..1 fraction of full scale, for progress bars.
  double get fsrFraction => fsrMax <= 0 ? 0 : (fsr / fsrMax).clamp(0.0, 1.0);

  /// True when the reading is synthetic, so the UI can say so plainly rather
  /// than presenting fake numbers as clinical data.
  bool get isSimulated => source == 'simulate';

  /// Another session is attached to this bridge, so a hold recorded now would
  /// be recorded by them too.
  bool get isShared => viewers > 1;

  static int _toInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static double _toDouble(dynamic v, {double fallback = 0}) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
}

/// What the bridge can currently see, and what it is attached to.
@immutable
class GloveInventory {
  final List<GloveDevice> devices;
  final String? pairedId;
  final bool simulated;

  const GloveInventory({
    this.devices = const [],
    this.pairedId,
    this.simulated = false,
  });
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Maintains a WebSocket to the sensor bridge and exposes its readings.
///
/// Reconnects on its own: the bridge is a separate process a patient may start
/// after the app, so "not running yet" has to be a recoverable state rather
/// than a dead end.
class SensorService {
  SensorService({String? url}) : _url = url ?? Env.sensorWsUrl;

  final String _url;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _samples = StreamController<SensorSample>.broadcast();
  final _inventory = StreamController<GloveInventory>.broadcast();

  /// Broadcast so Grip and Pinch can both listen without duplicating the socket.
  Stream<SensorSample> get stream => _samples.stream;

  /// Device list and current pairing, pushed whenever the bridge reports them.
  Stream<GloveInventory> get inventoryStream => _inventory.stream;

  SensorSample _last = SensorSample.empty();
  SensorSample get last => _last;

  GloveInventory _lastInventory = const GloveInventory();
  GloveInventory get lastInventory => _lastInventory;

  /// Pairing to re-apply once the socket is up. Set from stored preferences so
  /// a reconnect (or a bridge restart) restores the patient's own glove without
  /// asking again.
  String? _desiredDeviceId;

  static const _reconnectDelay = Duration(seconds: 3);

  bool get isConnected => _channel != null;

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (Object e) => _scheduleReconnect('socket error: $e'),
        onDone: () => _scheduleReconnect('socket closed'),
        cancelOnError: true,
      );
      // Re-apply a remembered pairing as soon as the link is back.
      if (_desiredDeviceId != null) {
        pair(_desiredDeviceId!);
      }
    } catch (e) {
      _scheduleReconnect('connect failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Commands
  // ------------------------------------------------------------------

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('[SensorService] send failed: $e');
    }
  }

  void listDevices() => _send({'command': 'list_devices'});

  /// Attach the bridge to [deviceId] and remember it for future reconnects.
  void pair(String deviceId) {
    _desiredDeviceId = deviceId;
    _send({'command': 'pair', 'device_id': deviceId});
  }

  void unpair() {
    _desiredDeviceId = null;
    _send({'command': 'unpair'});
  }

  /// Restore a pairing loaded from storage without immediately sending it —
  /// [connect] applies it once the socket opens.
  void restorePairing(String? deviceId) {
    _desiredDeviceId = deviceId;
    if (deviceId != null && isConnected) pair(deviceId);
  }

  // ------------------------------------------------------------------

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      switch (decoded['type']) {
        case 'sensor_update':
          _last = SensorSample.fromJson(decoded);
          if (!_samples.isClosed) _samples.add(_last);
          break;

        case 'device_list':
          final raw = decoded['devices'];
          _lastInventory = GloveInventory(
            devices: raw is List
                ? raw
                    .whereType<Map<String, dynamic>>()
                    .map(GloveDevice.fromJson)
                    .toList()
                : const [],
            pairedId: decoded['paired'] as String?,
            simulated: decoded['simulated'] == true,
          );
          if (!_inventory.isClosed) _inventory.add(_lastInventory);
          break;

        case 'pair_result':
          // A refused pairing means the glove is gone; drop the intent so we
          // do not keep re-requesting a device that is not there.
          if (decoded['ok'] != true) {
            debugPrint('[SensorService] pairing refused: ${decoded['error']}');
            _desiredDeviceId = null;
          }
          listDevices();
          break;
      }
    } catch (e) {
      // A malformed frame is not worth tearing the session down over — the
      // next one is 50 ms away. Keep the last good sample on screen.
      debugPrint('[SensorService] bad frame: $e');
    }
  }

  void _scheduleReconnect(String reason) {
    if (_disposed) return;
    debugPrint('[SensorService] $reason — retrying in ${_reconnectDelay.inSeconds}s');

    _sub?.cancel();
    _sub = null;
    _channel = null;

    // Surface the disconnect so the UI stops showing a stale live reading.
    _last = SensorSample.empty();
    if (!_samples.isClosed) _samples.add(_last);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _samples.close();
    _inventory.close();
  }
}
