/// lib/features/flexion/flexion_page.dart
///
/// ORIGINAL flexion tracking code — class names and algorithm are UNCHANGED.
/// Only addition: optional [onLevelUp] callback on ExercisePage (backward
/// compatible — does not affect any existing behaviour when omitted).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web-only camera + platform view registry
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import '../../../config/env.dart';

/// ------------------------------
/// START SCREEN
/// ------------------------------
class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  String _selectedHand = "Left";

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Wrist Flexion Therapy")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Before you begin",
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "• Allow camera access when prompted.\n"
                      "• Place your hand in view of the camera.\n"
                      "• Flex/extend to reach the target.\n"
                      "• Return to neutral between repetitions.\n",
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Choose the hand you want to track:",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: "Left",
                            label: Text("Left Hand"),
                          ),
                          ButtonSegment(
                            value: "Right",
                            label: Text("Right Hand"),
                          ),
                        ],
                        selected: {_selectedHand},
                        onSelectionChanged: (set) {
                          setState(() => _selectedHand = set.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ExercisePage(
                              initialHandedness: _selectedHand,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Start"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tip: If the camera is blank, refresh and re-allow permissions.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.65),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ------------------------------
/// DATA MODEL
/// ------------------------------
class ExerciseData {
  final double angle;
  final bool foundHand;
  final double targetForward;
  final double targetBackward;
  final int reps;
  final int repsLast;
  final bool armed;
  final bool levelUp;
  final String direction;
  final String handedness;
  final String? warning;
  final double fps;

  const ExerciseData({
    required this.angle,
    required this.foundHand,
    required this.targetForward,
    required this.targetBackward,
    required this.reps,
    required this.repsLast,
    required this.armed,
    required this.levelUp,
    required this.direction,
    required this.handedness,
    required this.warning,
    required this.fps,
  });

  factory ExerciseData.empty() => const ExerciseData(
        angle: 0,
        foundHand: false,
        targetForward: 30,
        targetBackward: 15,
        reps: 0,
        repsLast: 0,
        armed: true,
        levelUp: false,
        direction: "forward",
        handedness: "Left",
        warning: null,
        fps: 0,
      );

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse("$v") ?? 0;
  }

  factory ExerciseData.fromJson(Map<String, dynamic> j) {
    return ExerciseData(
      angle: (j["angle"] ?? 0).toDouble(),
      foundHand: (j["found_hand"] ?? false) as bool,
      targetForward: (j["target_forward"] ?? 30).toDouble(),
      targetBackward: (j["target_backward"] ?? 15).toDouble(),
      reps: _toInt(j["reps"]),
      repsLast: _toInt(j["reps_last"]),
      armed: (j["armed"] ?? true) as bool,
      levelUp: (j["level_up"] ?? false) as bool,
      direction: (j["direction"] ?? "forward") as String,
      handedness: (j["handedness"] ?? "Left") as String,
      warning: j["warning"] as String?,
      fps: (j["fps"] ?? 0).toDouble(),
    );
  }

  int get expectedSign {
    final isLeft = handedness == "Left";
    final isForward = direction == "forward";
    if (isLeft) return isForward ? 1 : -1;
    return isForward ? -1 : 1;
  }

  double get targetMagnitude => direction == "forward" ? targetForward : targetBackward;
  double get signedTarget => expectedSign * targetMagnitude;
  double get signedAngle => angle;
}

enum BackendState { disconnected, connecting, connected, error }

/// ------------------------------
/// BACKEND SERVICE
/// ------------------------------
class BackendService {
  WebSocketChannel? _ch;

  final ValueNotifier<BackendState> state = ValueNotifier(BackendState.disconnected);
  final ValueNotifier<ExerciseData> data = ValueNotifier(ExerciseData.empty());

  Uri get uri {
    // Use compile-time WS_URL if set, else fall back to env config, else localhost.
    const override = String.fromEnvironment('WS_URL');
    if (override.isNotEmpty) return Uri.parse(override);
    if (Env.wsUrl.isNotEmpty) return Uri.parse(Env.wsUrl);
    return Uri.parse('ws://localhost:8765');
  }

  void connect() {
    if (state.value == BackendState.connected || state.value == BackendState.connecting) {
      return;
    }
    state.value = BackendState.connecting;

    try {
      _ch = WebSocketChannel.connect(uri);
      state.value = BackendState.connected;

      _ch!.stream.listen(
        (msg) {
          if (msg is String) {
            final m = jsonDecode(msg) as Map<String, dynamic>;
            if (m["type"] == "exercise_update") {
              data.value = ExerciseData.fromJson(m);
            }
          }
        },
        onError: (_) => state.value = BackendState.error,
        onDone: () => state.value = BackendState.disconnected,
      );
    } catch (_) {
      state.value = BackendState.error;
    }
  }

  void sendFrame(Uint8List jpegBytes) {
    if (_ch == null || state.value != BackendState.connected) return;
    _ch!.sink.add(jpegBytes);
  }

  void sendCommand(String command, {String? value}) {
    if (_ch == null || state.value != BackendState.connected) return;
    final payload = <String, dynamic>{"command": command};
    if (value != null) payload["value"] = value;
    _ch!.sink.add(jsonEncode(payload));
  }

  void dispose() {
    _ch?.sink.close();
    state.dispose();
    data.dispose();
  }
}

/// ------------------------------
/// WEB CAMERA STREAMER
/// ------------------------------
class WebCameraStreamer extends StatefulWidget {
  final BackendService backend;
  final int fps;

  const WebCameraStreamer({
    super.key,
    required this.backend,
    this.fps = 10,
  });

  @override
  State<WebCameraStreamer> createState() => _WebCameraStreamerState();
}

class _WebCameraStreamerState extends State<WebCameraStreamer> {
  html.VideoElement? _video;
  html.CanvasElement? _canvas;
  Timer? _timer;
  bool _ready = false;

  static int _viewCounter = 0;
  late final String _viewType = 'webcam-view-${_viewCounter++}';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _initCamera();
  }

  Future<void> _initCamera() async {
    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..style.objectFit = 'cover'
      ..style.width = '100%'
      ..style.height = '100%';

    _canvas = html.CanvasElement(width: 640, height: 480);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video!,
    );

    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        "video": {
          "facingMode": "user",
          "width": {"ideal": 640},
          "height": {"ideal": 480},
        },
        "audio": false,
      });

      _video!.srcObject = stream;
      await _video!.onLoadedMetadata.first;

      if (!mounted) return;
      setState(() => _ready = true);
      _startSendingFrames();
    } catch (e) {
      debugPrint("Camera error: $e");
      if (mounted) setState(() => _ready = false);
    }
  }

  void _startSendingFrames() {
    _timer?.cancel();
    final intervalMs = (1000 / widget.fps).round();

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_video == null || _canvas == null) return;
      if (widget.backend.state.value != BackendState.connected) return;
      if (_video!.videoWidth == 0 || _video!.videoHeight == 0) return;

      _canvas!
        ..width = _video!.videoWidth
        ..height = _video!.videoHeight;

      final ctx = _canvas!.context2D;
      ctx.drawImageScaled(_video!, 0, 0, _canvas!.width!, _canvas!.height!);

      final dataUrl = _canvas!.toDataUrl('image/jpeg', 0.75);
      final bytes = UriData.parse(dataUrl).contentAsBytes();
      widget.backend.sendFrame(bytes);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    final stream = _video?.srcObject;
    if (stream is html.MediaStream) {
      for (final t in stream.getTracks()) {
        t.stop();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const Center(child: Text("Web only."));
    if (!_ready) {
      return const Center(child: Text("Requesting camera permission..."));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}

/// ------------------------------
/// EXERCISE PAGE
/// ------------------------------
///
/// [onLevelUp] is an optional callback invoked whenever the server signals
/// that 5 reps have been completed and the direction changes.
/// Adding this parameter is backward-compatible — all existing callers that
/// omit it continue to function identically.
class ExercisePage extends StatefulWidget {
  final String initialHandedness;

  /// Optional hook. Called (on the UI thread, non-blocking) whenever the
  /// server emits level_up == true. Does NOT alter rep counting or direction
  /// logic in any way.
  final VoidCallback? onLevelUp;

  const ExercisePage({
    super.key,
    required this.initialHandedness,
    this.onLevelUp, // ← only addition to the public interface
  });

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends State<ExercisePage> {
  final BackendService backend = BackendService();
  late String _desiredHandedness;

  @override
  void initState() {
    super.initState();
    _desiredHandedness = widget.initialHandedness;

    backend.connect();
    backend.state.addListener(_onBackendStateChanged);
  }

  void _onBackendStateChanged() {
    if (backend.state.value == BackendState.connected) {
      backend.sendCommand("set_handedness", value: _desiredHandedness);
    }
  }

  @override
  void dispose() {
    backend.state.removeListener(_onBackendStateChanged);
    backend.dispose();
    super.dispose();
  }

  void _setHandedness(String h) {
    setState(() => _desiredHandedness = h);
    backend.sendCommand("set_handedness", value: h);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Wrist Flexion Exercise (Web)"),
        actions: [
          ValueListenableBuilder(
            valueListenable: backend.state,
            builder: (_, s, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(s.name)),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(child: WebCameraStreamer(backend: backend)),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: backend.data,
              builder: (_, ExerciseData d, __) {
                // ── Non-invasive onLevelUp hook ──────────────────────────────
                // Fires the callback when level_up is signalled by the server.
                // Does NOT touch reps, direction, or any internal state.
                if (d.levelUp) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.onLevelUp?.call();
                  });
                }
                // ─────────────────────────────────────────────────────────────

                final displayAngle = d.signedAngle;
                final displayTarget = d.signedTarget;
                final inTarget = (displayAngle - displayTarget).abs() <= 1.0;
                final shownHand = d.handedness.isNotEmpty ? d.handedness : _desiredHandedness;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          d.foundHand ? "${displayAngle.toStringAsFixed(1)}°" : "--.-°",
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: inTarget ? cs.secondary : cs.primary,
                          ),
                        ),
                        Text(
                          "Target: ${displayTarget.toStringAsFixed(0)}° | "
                          "Dir: ${d.direction} | Hand: $shownHand | "
                          "Armed: ${d.armed} | FPS: ${d.fps.toStringAsFixed(1)}",
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Reps: ${d.reps} (Last: ${d.repsLast})",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Tracking hand: "),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: "Left",
                                  label: Text("Left"),
                                ),
                                ButtonSegment(
                                  value: "Right",
                                  label: Text("Right"),
                                ),
                              ],
                              selected: {_desiredHandedness},
                              onSelectionChanged: (set) => _setHandedness(set.first),
                            ),
                          ],
                        ),
                        if (!d.foundHand) ...[
                          const SizedBox(height: 12),
                          Text(
                            "No hand detected. Move your hand closer and increase lighting.",
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (d.warning != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            d.warning!,
                            style: TextStyle(
                              color: cs.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (d.levelUp) ...[
                          const SizedBox(height: 12),
                          Text(
                            "LEVEL UP!",
                            style: TextStyle(
                              color: cs.secondary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => backend.sendCommand("toggle_direction"),
                    child: const Text("Toggle Direction"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => backend.sendCommand("level_up"),
                    child: const Text("Level Up"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: backend.connect,
              child: const Text("Reconnect"),
            ),
          ],
        ),
      ),
    );
  }
}
