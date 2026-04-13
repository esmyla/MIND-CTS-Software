import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'dart:math';

// ─── COLORS ─────────────────────────────────────a──────────────────────────────
const kBg        = Color(0xFFF8F6F2);
const kSurface   = Color(0xFFFFFFFF);
const kAlt       = Color(0xFFF0EDE8);
const kBorder    = Color(0xFFD9D4CC);
const kText      = Color(0xFF1A1A1A);
const kTextSub   = Color(0xFF6B6560);
const kTextLight = Color(0xFF9E9990);
const kAccent    = Color(0xFF1A1A1A);
const kSuccess   = Color(0xFF4A7C59);

// ─── TEXT STYLES ──────────────────────────────────────────────────────────────
TextStyle kDisplay(double size) => GoogleFonts.playfairDisplay(
    fontSize: size, fontWeight: FontWeight.w600, color: kText, letterSpacing: -0.5);

TextStyle kBody([Color? color]) => GoogleFonts.dmSans(
    fontSize: 15, fontWeight: FontWeight.w400, color: color ?? kText, height: 1.6);

TextStyle kSmall([Color? color]) => GoogleFonts.dmSans(
    fontSize: 13, fontWeight: FontWeight.w400, color: color ?? kTextSub, height: 1.5);

TextStyle kLabel() => GoogleFonts.dmSans(
    fontSize: 11, fontWeight: FontWeight.w500, color: kTextLight, letterSpacing: 0.8);

TextStyle kBtn([Color? color]) => GoogleFonts.dmSans(
    fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: color ?? Colors.white);

// ─── LOCAL DATA STORE (swap for Supabase later) ───────────────────────────────
class AppData {
  static String uuid = '';

  static List<Map<String, dynamic>> sessions = [];
  // Each session: { 'date': DateTime, 'maxIT': double, 'maxMT': double,
  //                 'ratioIT': double, 'ratioMT': double }

  static List<Map<String, dynamic>> tasks = [
    {'id': '1', 'title': 'Complete pinch exercise', 'done': false},
    {'id': '2', 'title': 'Log today\'s session',    'done': false},
    {'id': '3', 'title': 'Review progress chart',   'done': false},
  ];

  static double? baseIT;
  static double? baseMT;

  static double get journeyProgress {
    if (sessions.isEmpty) return 0.0;
    final last = sessions.last;
    final it = (last['ratioIT'] as double? ?? 0);
    final mt = (last['ratioMT'] as double? ?? 0);
    return ((it + mt) / 2).clamp(0.0, 1.0);
  }

  // Mirrors Python: sort descending, take top 60%, return mean
  static double topMean(List<double> vals) {
    if (vals.isEmpty) return 0;
    final s = List<double>.from(vals)..sort((a, b) => b.compareTo(a));
    final n = max(1, (0.6 * s.length).floor());
    final top = s.sublist(0, n);
    return top.reduce((a, b) => a + b) / top.length;
  }
}

// ─── REUSABLE WIDGETS ─────────────────────────────────────────────────────────
class PinchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PinchAppBar({super.key});
  @override Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: kBg, elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: kText, size: 20),
        onPressed: () {},
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CircleAvatar(radius: 18, backgroundColor: kAlt,
              child: const Icon(Icons.person_outline, color: kTextSub, size: 18)),
        ),
      ],
    );
  }
}

class NavRow extends StatelessWidget {
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool showPrev;
  final bool showNext;
  final String nextLabel;
  const NavRow({super.key, this.onPrev, this.onNext,
      this.showPrev = true, this.showNext = true, this.nextLabel = 'NEXT'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Row(children: [
        if (showPrev) Expanded(child: OutlinedButton(
          onPressed: onPrev,
          style: OutlinedButton.styleFrom(
            foregroundColor: kText, side: const BorderSide(color: kBorder),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: Text('PREVIOUS', style: kBtn(kText)),
        )),
        if (showPrev && showNext) const SizedBox(width: 12),
        if (showNext) Expanded(child: ElevatedButton(
          onPressed: onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccent, elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: Text(nextLabel, style: kBtn()),
        )),
      ]),
    );
  }
}

// ─── ENTRY POINT ──────────────────────────────────────────────────────────────
void main() => runApp(const PinchTrackerApp());

class PinchTrackerApp extends StatelessWidget {
  const PinchTrackerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pinch Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: kBg, useMaterial3: false),
      home: const IntroScreen(),
    );
  }
}


// ─── INTRO SCREEN (Frames 11–15) ──────────────────────────────────────────────
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pageCtrl = PageController();
  final _stepCtrl = PageController();
  int _page = 0;
  int _stepPage = 0;
  int _reps = 0;

  final _steps = const [
    ('Index–Thumb Pinch',  'Hold hand in relaxed open position and bring index finger to touch thumb tip.'),
    ('Middle–Thumb Pinch', 'Hold hand in relaxed open position and bring middle finger to touch thumb tip.'),
    ('Hold & Squeeze',     'Hold pinch position and apply maximum force for 10 seconds.'),
    ('Release & Rest',     'Open hand and relax fingers between reps.'),
  ];

  void _next() {
    if (_page < 4) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MeasurementScreen()));
    }
  }

  void _prev() {
    if (_page == 0) Navigator.pop(context);
    else _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: const PinchAppBar(),
      body: Column(children: [
        Expanded(child: PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _page = i),
          children: [_p11(), _p12(), _p13(), _p14(), _p15()],
        )),
        _dots(),
        // Page 4 (ready/BEGIN) has its own button, hide NEXT there
        if (_page < 4) NavRow(onPrev: _page==0 ? null:_prev, onNext: _next,
        showPrev: _page!=0,
        )
        else NavRow(onPrev: _prev, showNext: false),
      ]),
    );
  }

  // Frame 11 — Welcome
  Widget _p11() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Welcome to\nyour session.', style: kDisplay(26)),
      const SizedBox(height: 28),
      _card('When you click on NEXT you will start the introduction to training '
          'to strengthen your muscles and aid in your carpal tunnel recovery process.'),
      const SizedBox(height: 20),
      Row(children: [
        _chip(Icons.timer_outlined, '10 sec'),
        const SizedBox(width: 10),
        _chip(Icons.repeat, '3 reps'),
        const SizedBox(width: 10),
        _chip(Icons.fitness_center_outlined, 'Pinch'),
      ]),
    ]),
  );

  // Frame 12 — Exercise steps carousel
  Widget _p12() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Exercise Steps', style: kDisplay(22)),
      const SizedBox(height: 6),
      Text('Swipe or use arrows', style: kSmall()),
      const SizedBox(height: 16),
      Expanded(child: PageView.builder(
        controller: _stepCtrl,
        onPageChanged: (i) => setState(() => _stepPage = i),
        itemCount: _steps.length,
        itemBuilder: (_, i) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: kSurface,
              border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Expanded(child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kAlt,
                  border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(6)),
              child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.pan_tool_outlined, size: 44, color: kTextLight),
                const SizedBox(height: 8),
                Text('IMAGE OF EXERCISE\nSTEP ${i + 1}',
                    textAlign: TextAlign.center, style: kLabel()),
              ])),
            )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_steps[i].$1, style: kBody().copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_steps[i].$2, style: kSmall()),
              ]),
            ),
          ]),
        ),
      )),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _arrow(Icons.chevron_left, _stepPage > 0
            ? () { _stepCtrl.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut); setState(() => _stepPage--); }
            : null),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${_stepPage + 1} / ${_steps.length}', style: kSmall())),
        _arrow(Icons.chevron_right, _stepPage < _steps.length - 1
            ? () { _stepCtrl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut); setState(() => _stepPage++); }
            : null),
      ]),
      const SizedBox(height: 12),
    ]),
  );

  // Frame 13 — Self assess
  Widget _p13() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Begin Measurments!', style: kDisplay(26)),
      const SizedBox(height: 28),
      _card("Now that you know how to do the exercise, let's record. First, pinch your index finger and thumb together 3 times for 10 seconds each. Then, repeat the same process with your middle finger and thumb. "),
      const SizedBox(height: 24),
      Text('REPETITIONS', style: kLabel()),
      const SizedBox(height: 10),
      Row(children: List.generate(3, (i) {
        final done = i < _reps;
        return GestureDetector(
          onTap: () => setState(() => _reps = done ? i : i + 1),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: done ? kAccent : kSurface,
              border: Border.all(color: done ? kAccent : kBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(child: Text('${i + 1}',
                style: kBody(done ? Colors.white : kTextSub)
                    .copyWith(fontWeight: FontWeight.w600))),
          ),
        );
      })),
      const SizedBox(height: 10),
      Text(_reps == 3 ? 'All reps complete! Tap NEXT.' : 'Tap each box as you complete the rep.',
          style: kSmall(_reps == 3 ? kSuccess : kTextSub)),
    ]),
  );

  // Frame 14 — Baseline info
  Widget _p14() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Calculating\nyour baseline.', style: kDisplay(26)),
      const SizedBox(height: 28),
      _card('After completing this task we will calculate your baseline repetitions '
          'and you will begin your journey towards recovery.'),
      const SizedBox(height: 20),
      _infoRow(Icons.touch_app_outlined, 'Index–Thumb (IT)',
          'Maximum pinch force between your index finger and thumb.'),
      const SizedBox(height: 12),
      _infoRow(Icons.back_hand_outlined, 'Middle–Thumb (MT)',
          'Maximum pinch force between your middle finger and thumb.'),
    ]),
  );

  // Frame 15 — Ready / BEGIN
  Widget _p15() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("When you're\nready to begin.", style: kDisplay(26)),
      const SizedBox(height: 28),
      _card('Click BEGIN when you are ready to complete the baseline measurement. '
          'Make sure your sensor device is attached and connected.'),
      const SizedBox(height: 36),
      Row(children: [
        Container(width: 24, height: 1, color: kTextSub),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward, size: 14, color: kTextSub),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MeasurementScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: kSurface,
              border: Border.all(color: kAccent, width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('BEGIN', style: kBtn(kText)),
          ),
        ),
      ]),
    ]),
  );

  // Helpers
  Widget _card(String text) => Container(
    width: double.infinity, padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: kSurface,
        border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: kBody()),
  );

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: kAlt,
        border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(4)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: kTextSub),
      const SizedBox(width: 5),
      Text(label, style: kSmall()),
    ]),
  );

  Widget _infoRow(IconData icon, String title, String sub) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: kAlt,
        border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      Container(width: 34, height: 34,
          decoration: BoxDecoration(color: kSurface,
              border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(4)),
          child: Icon(icon, size: 16, color: kTextSub)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: kSmall(kText).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(sub, style: kSmall()),
      ])),
    ]),
  );

  Widget _arrow(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width: 34, height: 34,
        decoration: BoxDecoration(
            color: onTap != null ? kSurface : kAlt,
            border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(4)),
        child: Icon(icon, size: 18, color: onTap != null ? kText : kTextLight)),
  );

  Widget _dots() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (i) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _page ? 20 : 6, height: 6,
          decoration: BoxDecoration(
              color: i == _page ? kAccent : kBorder,
              borderRadius: BorderRadius.circular(3)),
        ))),
  );
}

// ─── MEASUREMENT SCREEN ───────────────────────────────────────────────────────
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});
  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

enum PinchType { indexThumb, middleThumb }
enum Phase { announce, measuring, rest }

class _MeasurementScreenState extends State<MeasurementScreen> {
  static const int trialsPerType = 3;
  static const int measureSec = 10;
  static const int restSec = 3;

  PinchType _type = PinchType.indexThumb;
  Phase _phase = Phase.announce;
  int _trial = 1;

  final List<double> _currentVals = [];
  final List<double> _itTrials = [];
  final List<double> _mtTrials = [];

  double _lastIndex = 0;
  double _lastMiddle = 0;

  DateTime _phaseStart = DateTime.now();
  late Timer _heartbeat;
  late Timer _sensorTimer;

  @override
  void initState() {
    super.initState();

    // Heartbeat drives UI + phase timing
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _tick();
    });

    // Fake sensor stream (replace later)
    _sensorTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
      final r = Random();
      _lastIndex = 40 + r.nextDouble() * 70;
      _lastMiddle = 35 + r.nextDouble() * 70;

      if (_phase == Phase.measuring) {
        _currentVals.add(
          _type == PinchType.indexThumb ? _lastIndex : _lastMiddle,
        );
      }
    });
  }

  void _tick() {
    final elapsed =
        DateTime.now().difference(_phaseStart).inSeconds;

    switch (_phase) {
      case Phase.announce:
        if (elapsed >= 1) _startMeasuring();
        break;

      case Phase.measuring:
        if (elapsed >= measureSec) _finishTrial();
        break;

      case Phase.rest:
        if (elapsed >= restSec) _startNextTrial();
        break;
    }

    setState(() {});
  }

  void _startMeasuring() {
    _phase = Phase.measuring;
    _phaseStart = DateTime.now();
    _currentVals.clear();
  }

  void _finishTrial() {
    final val = _currentVals.isEmpty
        ? 0.0
        : AppData.topMean(_currentVals);

    if (_type == PinchType.indexThumb) {
      _itTrials.add(val);
    } else {
      _mtTrials.add(val);
    }

    _phase = Phase.rest;
    _phaseStart = DateTime.now();
  }

  void _startNextTrial() {
    if (_trial < trialsPerType) {
      _trial++;
      _phase = Phase.announce;
      _phaseStart = DateTime.now();
      return;
    }

    if (_type == PinchType.indexThumb) {
      _type = PinchType.middleThumb;
      _trial = 1;
      _phase = Phase.announce;
      _phaseStart = DateTime.now();
      return;
    }

    _endSession();
  }

  void _endSession() {
    _heartbeat.cancel();
    _sensorTimer.cancel();

    final avgIT =
        _itTrials.reduce((a, b) => a + b) / _itTrials.length;
    final avgMT =
        _mtTrials.reduce((a, b) => a + b) / _mtTrials.length;

    AppData.baseIT ??= avgIT;
    AppData.baseMT ??= avgMT;

    final ratioIT = avgIT / AppData.baseIT!;
    final ratioMT = avgMT / AppData.baseMT!;

    AppData.sessions.add({
      'date': DateTime.now(),
      'maxIT': avgIT,
      'maxMT': avgMT,
      'ratioIT': ratioIT,
      'ratioMT': ratioMT,
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CompletionScreen(
          maxIT: avgIT,
          maxMT: avgMT,
          ratioIT: ratioIT,
          ratioMT: ratioMT,
        ),
      ),
    );
  }

  int get _elapsed =>
      DateTime.now().difference(_phaseStart).inSeconds;

  @override
  void dispose() {
    _heartbeat.cancel();
    _sensorTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: const PinchAppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_phase == Phase.announce) {
      return Text(
        '${_type == PinchType.indexThumb ? "Index–Thumb" : "Middle–Thumb"}\n'
        'Trial $_trial starting…',
        textAlign: TextAlign.center,
        style: kDisplay(28),
      );
    }

    if (_phase == Phase.rest) {
      return Text(
        'Rest\n${restSec - _elapsed}s',
        textAlign: TextAlign.center,
        style: kDisplay(28),
      );
    }

    // Measuring
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _type == PinchType.indexThumb
              ? 'Index–Thumb Pinch'
              : 'Middle–Thumb Pinch',
          style: kDisplay(22),
        ),
        const SizedBox(height: 8),
        Text(
          'Trial $_trial of $trialsPerType',
          style: kSmall(),
        ),
        const SizedBox(height: 24),
        Text(
          'Time left: ${measureSec - _elapsed}s',
          style: kBody(),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _elapsed / measureSec,
          minHeight: 10,
        ),
        const SizedBox(height: 32),
        Text(
          (_type == PinchType.indexThumb
                  ? _lastIndex
                  : _lastMiddle)
              .toStringAsFixed(1),
          style: kDisplay(36),
        ),
      ],
    );
  }
}

// ─── COMPLETION SCREEN ────────────────────────────────────────────────────────
// ─── COMPLETION SCREEN ────────────────────────────────────────────────────────
class CompletionScreen extends StatelessWidget {
  final double maxIT, maxMT, ratioIT, ratioMT;
  const CompletionScreen({
    super.key,
    required this.maxIT,
    required this.maxMT,
    required this.ratioIT,
    required this.ratioMT,
  });

  String get _itPct => '${(ratioIT * 100).toStringAsFixed(1)}%';
  String get _mtPct => '${(ratioMT * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: const PinchAppBar(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have just completed\nyour baseline testing!',
              style: kDisplay(26),
            ),
            const SizedBox(height: 8),
            Text(
              'This baseline will be used to track your progress over time.',
              style: kBody(kTextSub),
            ),
            const SizedBox(height: 32),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kSurface,
                border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SESSION RESULTS', style: kLabel()),
                  const SizedBox(height: 16),
                  _row('Index–Thumb (IT)', maxIT, _itPct),
                  const Divider(height: 24, color: kBorder),
                  _row('Middle–Thumb (MT)', maxMT, _mtPct),
                ],
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const IntroScreen()),
                  (_) => false,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text('BACK TO HOME', style: kBtn()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double raw, String pct) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: kSmall(kText).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Max force: ${raw.toStringAsFixed(1)}',
                style: kSmall(),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kAlt,
              border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              pct,
              style: kBody().copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
}
