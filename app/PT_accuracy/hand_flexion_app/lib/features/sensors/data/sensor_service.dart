/// lib/features/sensors/data/sensor_service.dart
///
/// Client for the glove sensor bridge (`app/PT_accuracy/backend/sensor_ws_server.py`).
///
/// The glove is an ESP32 wired over USB. Flutter web cannot open a serial port,
/// so the bridge process owns the port and rebroadcasts each reading as JSON
/// over a WebSocket. This class is the read side of that socket.
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
// Model
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
        receivedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory SensorSample.fromJson(Map<String, dynamic> json) => SensorSample(
        ir: _toInt(json['ir']),
        bpm: _toInt(json['bpm']),
        tempC: _toDouble(json['temp_c']),
        fsr: _toInt(json['fsr']),
        fsrMax: _toInt(json['fsr_max'], fallback: 4095),
        fingerPresent: json['finger_present'] == true,
        connected: json['connected'] == true,
        stale: json['stale'] == true,
        source: (json['source'] as String?) ?? 'none',
        error: json['error'] as String?,
        receivedAt: DateTime.now(),
      );

  /// FSR as a 0..1 fraction of full scale, for progress bars.
  double get fsrFraction => fsrMax <= 0 ? 0 : (fsr / fsrMax).clamp(0.0, 1.0);

  /// True when the reading is synthetic, so the UI can say so plainly rather
  /// than presenting fake numbers as clinical data.
  bool get isSimulated => source == 'simulate';

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

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Maintains a WebSocket to the sensor bridge and exposes a sample stream.
///
/// Reconnects on its own: the bridge is a separate process a student may start
/// after the app, so "not running yet" has to be a recoverable state rather
/// than a dead end.
class SensorService {
  SensorService({String? url}) : _url = url ?? Env.sensorWsUrl;

  final String _url;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _controller = StreamController<SensorSample>.broadcast();

  /// Broadcast so Grip and Pinch can both listen without duplicating the socket.
  Stream<SensorSample> get stream => _controller.stream;

  SensorSample _last = SensorSample.empty();
  SensorSample get last => _last;

  static const _reconnectDelay = Duration(seconds: 3);

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
    } catch (e) {
      _scheduleReconnect('connect failed: $e');
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] != 'sensor_update') return;

      _last = SensorSample.fromJson(decoded);
      if (!_controller.isClosed) _controller.add(_last);
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
    if (!_controller.isClosed) _controller.add(_last);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
