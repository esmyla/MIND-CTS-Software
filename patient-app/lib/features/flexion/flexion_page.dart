/// lib/features/flexion/flexion_page.dart
///
/// Flexion tracking with Supabase-backed session management.
///
/// Session flow:
///   1. Load last session's degree_forward / degree_backwards from Supabase.
///   2. Warm-up forward: [_kWarmupFwdReps] reps at baseline forward angle.
///   3. Training forward: increment target by [_kFwdIncrement]° per rep,
///      up to baseline + [_kMaxFwdGain]°.
///   4. Warm-up backward: [_kWarmupBwdReps] reps at baseline backward angle.
///   5. Training backward: increment by [_kBwdIncrement]° per rep,
///      up to baseline + [_kMaxBwdGain]°.
///   6. Insert a new row into the `flexion` Supabase table on completion
///      and fire the optional [onLevelUp] callback.
///
/// Warning messages (server + no-hand) are shown as an overlay pinned to the
/// TOP of the camera feed, at 50 % larger font, and remain visible for a
/// minimum of 2 seconds even after the triggering condition clears.
///
/// Hand preference (Left / Right) is persisted via SharedPreferences so the
/// user is not prompted again on subsequent sessions.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Web-only platform APIs
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import '../../../config/env.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SESSION PHASE
// ─────────────────────────────────────────────────────────────────────────────

enum SessionPhase {
  loading,
  warmupForward,
  trainingForward,
  warmupBackward,
  trainingBackward,
  completed,
}

// ─────────────────────────────────────────────────────────────────────────────
// START PAGE
// ─────────────────────────────────────────────────────────────────────────────

class StartPage extends StatefulWidget {
  /// Forwarded through to [ExercisePage] so that [FlexionTab] (or any other
  /// parent) can react when a session finishes.
  final VoidCallback? onSessionComplete;

  const StartPage({super.key, this.onSessionComplete});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  String _selectedHand = 'Left';
  bool _prefsLoaded = false;

  static const _kHandKey = 'hand_preference';

  @override
  void initState() {
    super.initState();
    _loadHandPreference();
  }

  Future<void> _loadHandPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kHandKey);
      if (mounted) {
        setState(() {
          _selectedHand = saved ?? 'Left';
          _prefsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _prefsLoaded = true);
    }
  }

  Future<void> _saveHandPreference(String hand) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kHandKey, hand);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_prefsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Wrist Flexion Therapy')),
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
                      'Before you begin',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• Allow camera access when prompted.\n'
                      '• Place your hand in view of the camera.\n'
                      '• Flex / extend to reach the target angle.\n'
                      '• Return to neutral between repetitions.\n',
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Choose the hand you want to track:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'Left', label: Text('Left Hand')),
                          ButtonSegment(value: 'Right', label: Text('Right Hand')),
                        ],
                        selected: {_selectedHand},
                        onSelectionChanged: (set) {
                          final hand = set.first;
                          setState(() => _selectedHand = hand);
                          _saveHandPreference(hand);
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
                              onLevelUp: widget.onSessionComplete,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: If the camera is blank, refresh and re-allow permissions.',
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

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

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
        direction: 'forward',
        handedness: 'Left',
        warning: null,
        fps: 0,
      );

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse('$v') ?? 0;
  }

  factory ExerciseData.fromJson(Map<String, dynamic> j) => ExerciseData(
        angle: (j['angle'] ?? 0).toDouble(),
        foundHand: (j['found_hand'] ?? false) as bool,
        targetForward: (j['target_forward'] ?? 30).toDouble(),
        targetBackward: (j['target_backward'] ?? 15).toDouble(),
        reps: _toInt(j['reps']),
        repsLast: _toInt(j['repsLast']),
        armed: (j['armed'] ?? true) as bool,
        levelUp: (j['level_up'] ?? false) as bool,
        direction: (j['direction'] ?? 'forward') as String,
        handedness: (j['handedness'] ?? 'Left') as String,
        warning: j['warning'] as String?,
        fps: (j['fps'] ?? 0).toDouble(),
      );

  int get expectedSign {
    final isLeft = handedness == 'Left';
    final isForward = direction == 'forward';
    if (isLeft) return isForward ? 1 : -1;
    return isForward ? -1 : 1;
  }

  double get targetMagnitude => direction == 'forward' ? targetForward : targetBackward;
  double get signedTarget => expectedSign * targetMagnitude;
  double get signedAngle => angle;
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKEND STATE & SERVICE
// ─────────────────────────────────────────────────────────────────────────────

enum BackendState { disconnected, connecting, connected, error }

class BackendService {
  WebSocketChannel? _ch;

  final ValueNotifier<BackendState> state = ValueNotifier(BackendState.disconnected);
  final ValueNotifier<ExerciseData> data = ValueNotifier(ExerciseData.empty());

  Uri get uri {
    const override = String.fromEnvironment('WS_URL');
    if (override.isNotEmpty) return Uri.parse(override);
    if (Env.wsUrl.isNotEmpty) return Uri.parse(Env.wsUrl);
    return Uri.parse('ws://localhost:8765');
  }

  void connect() {
    if (state.value == BackendState.connected || state.value == BackendState.connecting) return;
    state.value = BackendState.connecting;
    try {
      _ch = WebSocketChannel.connect(uri);
      state.value = BackendState.connected;
      _ch!.stream.listen(
        (msg) {
          if (msg is String) {
            final m = jsonDecode(msg) as Map<String, dynamic>;
            if (m['type'] == 'exercise_update') {
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
    final payload = <String, dynamic>{'command': command};
    if (value != null) payload['value'] = value;
    _ch!.sink.add(jsonEncode(payload));
  }

  void dispose() {
    _ch?.sink.close();
    state.dispose();
    data.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEB CAMERA STREAMER
// ─────────────────────────────────────────────────────────────────────────────

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
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
        'audio': false,
      });

      _video!.srcObject = stream;
      await _video!.onLoadedMetadata.first;

      if (!mounted) return;
      setState(() => _ready = true);
      _startSendingFrames();
    } catch (e) {
      debugPrint('Camera error: $e');
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
    if (!kIsWeb) return const Center(child: Text('Web only.'));
    if (!_ready) {
      return const Center(child: Text('Requesting camera permission…'));
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

// ─────────────────────────────────────────────────────────────────────────────
// EXERCISE PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ExercisePage extends StatefulWidget {
  final String initialHandedness;

  /// Called (on the UI thread) once the full session completes and is saved
  /// to Supabase. Omitting it is fully backward-compatible.
  final VoidCallback? onLevelUp;

  const ExercisePage({
    super.key,
    required this.initialHandedness,
    this.onLevelUp,
  });

  @override
  State<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends State<ExercisePage> {
  // ── Backend ──────────────────────────────────────────────────────────────
  final BackendService backend = BackendService();
  late String _desiredHandedness;

  // ── Session progression constants ────────────────────────────────────────
  static const int _kWarmupFwdReps = 3; // reps at baseline before incrementing
  static const int _kWarmupBwdReps = 2;
  static const int _kMaxFwdGain = 10; // max extra degrees forward per session
  static const int _kFwdIncrement = 2; // degrees added per forward rep
  static const int _kMaxBwdGain = 5; // max extra degrees backward per session
  static const int _kBwdIncrement = 1; // degrees added per backward rep

  // ── Session state ────────────────────────────────────────────────────────
  SessionPhase _phase = SessionPhase.loading;
  int _baselineForward = 30;
  int _baselineBackward = 15;
  int _currentTargetForward = 30;
  int _currentTargetBackward = 15;
  int _nextSessionId = 1;

  /// Last `reps` value seen from the backend.  The backend resets this to 0
  /// whenever the direction changes, so we also reset it on phase transitions
  /// that involve a direction switch.
  int _lastBackendReps = 0;

  /// Reps completed within the current phase (warm-up or training).
  int _phaseReps = 0;

  /// Running total across the whole session (for Supabase `repetitions`).
  int _totalSessionReps = 0;

  bool _supabaseLoaded = false;
  bool _sessionSaved = false;
  String? _loadError;

  // ── Warning / no-hand: minimum 2-second display ──────────────────────────
  String? _displayedWarning; // currently shown text (may linger after cleared)
  Timer? _warningTimer;
  bool _displayNoHand = false;
  Timer? _noHandTimer;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _desiredHandedness = widget.initialHandedness;
    backend.state.addListener(_onBackendStateChanged);
    backend.data.addListener(_onDataChanged);
    backend.connect();
    _loadSessionFromSupabase();
  }

  @override
  void dispose() {
    backend.state.removeListener(_onBackendStateChanged);
    backend.data.removeListener(_onDataChanged);
    _warningTimer?.cancel();
    _noHandTimer?.cancel();
    backend.dispose();
    super.dispose();
  }

  // ── Supabase: load previous session ─────────────────────────────────────
  Future<void> _loadSessionFromSupabase() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final row = await Supabase.instance.client
            .from('flexion')
            .select('session_id, degree_forward, degree_backwards')
            .eq('user_id', userId)
            .order('session_id', ascending: false)
            .limit(1)
            .maybeSingle();

        if (row != null) {
          _baselineForward = (row['degree_forward'] as int?) ?? 30;
          _baselineBackward = (row['degree_backwards'] as int?) ?? 15;
          _nextSessionId = ((row['session_id'] as int?) ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('Supabase load error: $e');
      if (mounted) {
        setState(
          () => _loadError = 'Could not load previous session — using defaults.',
        );
      }
    }

    // Initialise targets from loaded (or default) baseline.
    _currentTargetForward = _baselineForward;
    _currentTargetBackward = _baselineBackward;
    _lastBackendReps = 0;
    _phaseReps = 0;

    if (mounted) {
      setState(() {
        _phase = SessionPhase.warmupForward;
        _supabaseLoaded = true;
      });
    }

    // If the backend already connected before Supabase finished loading,
    // push the initial targets now.
    if (backend.state.value == BackendState.connected) {
      _applyTargets();
    }
  }

  // ── Supabase: save completed session ─────────────────────────────────────
  Future<void> _saveSessionToSupabase() async {
    if (_sessionSaved) return;
    _sessionSaved = true;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('No authenticated user — session not persisted.');
        return;
      }

      await Supabase.instance.client.from('flexion').insert({
        'user_id': userId,
        'session_id': _nextSessionId,
        'degree_forward': _currentTargetForward,
        'degree_backwards': _currentTargetBackward,
        'repetitions': _totalSessionReps,
        'level_up': true,
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint('Session $_nextSessionId saved to Supabase.');
    } catch (e) {
      debugPrint('Supabase save error: $e');
    }
  }

  // ── Backend helpers ──────────────────────────────────────────────────────
  void _applyTargets() {
    backend.sendCommand(
      'set_target_forward',
      value: _currentTargetForward.toString(),
    );
    backend.sendCommand(
      'set_target_backward',
      value: _currentTargetBackward.toString(),
    );
  }

  void _onBackendStateChanged() {
    if (backend.state.value == BackendState.connected) {
      backend.sendCommand('set_handedness', value: _desiredHandedness);
      if (_supabaseLoaded) _applyTargets();
    }
  }

  void _setHandedness(String h) {
    setState(() => _desiredHandedness = h);
    backend.sendCommand('set_handedness', value: h);
  }

  // ── Data listener ────────────────────────────────────────────────────────
  void _onDataChanged() {
    final d = backend.data.value;
    _handleWarningDisplay(d.warning);
    _handleNoHandDisplay(d.foundHand);

    if (_supabaseLoaded && _phase != SessionPhase.loading && _phase != SessionPhase.completed) {
      _handleRepProgression(d);
    }
  }

  // ── Warning overlay: minimum 2-second display ────────────────────────────
  void _handleWarningDisplay(String? warning) {
    if (warning != null) {
      // Refresh the linger timer on every incoming warning frame.
      _warningTimer?.cancel();
      if (_displayedWarning != warning && mounted) {
        setState(() => _displayedWarning = warning);
      }
      _warningTimer = Timer(const Duration(seconds: 2), () {
        // Clear only if the server has also cleared it.
        if (mounted && backend.data.value.warning == null) {
          setState(() => _displayedWarning = null);
        }
      });
    } else {
      // Warning gone from the server — let the timer decide when to clear.
      if ((_warningTimer == null || !_warningTimer!.isActive) &&
          _displayedWarning != null &&
          mounted) {
        setState(() => _displayedWarning = null);
      }
    }
  }

  // ── No-hand overlay: minimum 2-second display ────────────────────────────
  void _handleNoHandDisplay(bool foundHand) {
    if (!foundHand) {
      _noHandTimer?.cancel();
      if (!_displayNoHand && mounted) setState(() => _displayNoHand = true);
      _noHandTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && backend.data.value.foundHand) {
          setState(() => _displayNoHand = false);
        }
      });
    } else {
      if ((_noHandTimer == null || !_noHandTimer!.isActive) && _displayNoHand && mounted) {
        setState(() => _displayNoHand = false);
      }
    }
  }

  // ── Session progression ──────────────────────────────────────────────────
  void _handleRepProgression(ExerciseData d) {
    final currentReps = d.reps;
    if (currentReps <= _lastBackendReps) return; // no new rep yet

    final newReps = currentReps - _lastBackendReps;
    _lastBackendReps = currentReps;
    _phaseReps += newReps;
    _totalSessionReps += newReps;

    switch (_phase) {
      // ── Warm-up forward ────────────────────────────────────────────────
      case SessionPhase.warmupForward:
        if (_phaseReps >= _kWarmupFwdReps) {
          _phaseReps = 0;
          if (mounted) setState(() => _phase = SessionPhase.trainingForward);
        }

      // ── Training forward ───────────────────────────────────────────────
      case SessionPhase.trainingForward:
        final maxFwd = _baselineForward + _kMaxFwdGain;
        _currentTargetForward = (_currentTargetForward + _kFwdIncrement).clamp(0, maxFwd);
        _applyTargets();

        if (_currentTargetForward >= maxFwd) {
          // Transition to backward warm-up.
          _phaseReps = 0;
          _lastBackendReps = 0; // backend resets reps on direction change
          _currentTargetBackward = _baselineBackward;
          backend.sendCommand('toggle_direction');
          _applyTargets();
          if (mounted) setState(() => _phase = SessionPhase.warmupBackward);
        }

      // ── Warm-up backward ───────────────────────────────────────────────
      case SessionPhase.warmupBackward:
        if (_phaseReps >= _kWarmupBwdReps) {
          _phaseReps = 0;
          if (mounted) setState(() => _phase = SessionPhase.trainingBackward);
        }

      // ── Training backward ──────────────────────────────────────────────
      case SessionPhase.trainingBackward:
        final maxBwd = _baselineBackward + _kMaxBwdGain;
        _currentTargetBackward = (_currentTargetBackward + _kBwdIncrement).clamp(0, maxBwd);
        _applyTargets();

        if (_currentTargetBackward >= maxBwd) {
          if (mounted) setState(() => _phase = SessionPhase.completed);
          _saveSessionToSupabase();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onLevelUp?.call();
          });
        }

      default:
        break;
    }

    if (mounted) setState(() {});
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String get _phaseLabel {
    switch (_phase) {
      case SessionPhase.loading:
        return 'Loading session…';
      case SessionPhase.warmupForward:
        return 'Warm-up Forward  •  $_phaseReps / $_kWarmupFwdReps reps';
      case SessionPhase.trainingForward:
        final maxFwd = _baselineForward + _kMaxFwdGain;
        return 'Training Forward  •  $_currentTargetForward° → $maxFwd°';
      case SessionPhase.warmupBackward:
        return 'Warm-up Backward  •  $_phaseReps / $_kWarmupBwdReps reps';
      case SessionPhase.trainingBackward:
        final maxBwd = _baselineBackward + _kMaxBwdGain;
        return 'Training Backward  •  $_currentTargetBackward° → $maxBwd°';
      case SessionPhase.completed:
        return '🎉  Session Complete!';
    }
  }

  Color _phaseColor(ColorScheme cs) => _phase == SessionPhase.completed ? cs.secondary : cs.primary;

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wrist Flexion Exercise'),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            // ── Camera feed with warning overlay pinned to its top ──────────
            Flexible(
              flex: 5,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.antiAlias,
                  children: [
                    // Base camera view
                    WebCameraStreamer(backend: backend),

                    // Warning / no-hand banner — pinned to the top of the feed,
                    // font 50 % larger than the default card text (~14 sp → 21 sp),
                    // minimum 2-second visibility enforced by the timers above.
                    if (_displayedWarning != null || _displayNoHand)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Text(
                            // Prefer specific server warning if present.
                            _displayedWarning != null
                                ? '⚠  $_displayedWarning'
                                : '⚠  No hand detected — move closer and increase lighting.',
                            style: const TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 21.0, // 14 * 1.5
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Session info card ───────────────────────────────────────────
            ValueListenableBuilder<ExerciseData>(
              valueListenable: backend.data,
              builder: (_, ExerciseData d, __) {
                final displayAngle = d.signedAngle;
                final displayTarget = d.signedTarget;
                final inTarget = (displayAngle - displayTarget).abs() <= 1.0;
                final shownHand = d.handedness.isNotEmpty ? d.handedness : _desiredHandedness;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Phase pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: _phaseColor(cs).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _phaseLabel,
                            style: TextStyle(
                              color: _phaseColor(cs),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),

                        // Load error notice (non-fatal)
                        if (_loadError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _loadError!,
                              style: TextStyle(color: cs.error, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        const SizedBox(height: 4),

                        // Angle readout
                        Text(
                          d.foundHand ? '${displayAngle.toStringAsFixed(1)}°' : '--.-°',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: inTarget ? cs.secondary : cs.primary,
                          ),
                        ),

                        // Compact metadata row
                        Text(
                          'Target: ${displayTarget.toStringAsFixed(0)}°  '
                          '|  Dir: ${d.direction}  '
                          '|  Hand: $shownHand  '
                          '|  FPS: ${d.fps.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 12),
                        ),

                        const SizedBox(height: 6),

                        // Rep counters
                        Text(
                          'Phase reps: $_phaseReps  '
                          '|  Session reps: $_totalSessionReps',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Hand selector
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Tracking hand: '),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'Left', label: Text('Left')),
                                ButtonSegment(value: 'Right', label: Text('Right')),
                              ],
                              selected: {_desiredHandedness},
                              onSelectionChanged: (set) => _setHandedness(set.first),
                            ),
                          ],
                        ),

                        // Completion message
                        if (_phase == SessionPhase.completed) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Great work! Your progress has been saved. 🎉',
                            style: TextStyle(
                              color: cs.secondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Forward reached: $_currentTargetForward°  |  '
                            'Backward reached: $_currentTargetBackward°',
                            style: const TextStyle(fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),

            // ── Control row ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    // Disabled once the session is done.
                    onPressed: _phase == SessionPhase.completed
                        ? null
                        : () => backend.sendCommand('toggle_direction'),
                    child: const Text('Toggle Direction'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: backend.connect,
                    child: const Text('Reconnect'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
