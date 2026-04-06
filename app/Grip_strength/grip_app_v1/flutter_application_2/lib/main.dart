import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grip Recovery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home:         (_) => const HomeScreen(),
        AppRoutes.intro:        (_) => const IntroScreen(),
        AppRoutes.exercise:     (_) => const ExerciseScreen(),
        AppRoutes.perform:      (_) => const PerformScreen(),
        AppRoutes.baseline:     (_) => const BaselineScreen(),
        AppRoutes.beginMeasure: (_) => const BeginMeasureScreen(),
        AppRoutes.measuring:    (_) => const MeasuringScreen(),
        AppRoutes.complete:     (_) => const CompleteScreen(),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ROUTES
// ─────────────────────────────────────────────────────────────────────────────
class AppRoutes {
  static const home         = '/';
  static const intro        = '/intro';
  static const exercise     = '/exercise';
  static const perform      = '/perform';
  static const baseline     = '/baseline';
  static const beginMeasure = '/begin-measure';
  static const measuring    = '/measuring';
  static const complete     = '/complete';
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
  static const bg          = Color(0xFF0F1117);
  static const surface     = Color(0xFF1A1D27);
  static const accent      = Color(0xFF6C63FF);
  static const accentLight = Color(0xFF9D97FF);
  static const text        = Color(0xFFE8E8F0);
  static const textMuted   = Color(0xFF6B6E85);
  static const success     = Color(0xFF4ECCA3);
  static const warning     = Color(0xFFFFB347);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SESSION MODEL
//  Supabase-ready: await supabase.from('sessions').insert(session.toJson());
// ─────────────────────────────────────────────────────────────────────────────
class Session {
  final String   id;
  final DateTime startedAt;
  final double?  gripStrengthKg; // populated by sensor later
  final String   status;

  Session({
    required this.id,
    required this.startedAt,
    this.gripStrengthKg,
    this.status = 'completed',
  });

  Map<String, dynamic> toJson() => {
    'id':               id,
    'started_at':       startedAt.toIso8601String(),
    'grip_strength_kg': gripStrengthKg,
    'status':           status,
  };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    id:             j['id'],
    startedAt:      DateTime.parse(j['started_at']),
    gripStrengthKg: j['grip_strength_kg']?.toDouble(),
    status:         j['status'] ?? 'completed',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOCAL STORAGE  (swap save() for Supabase insert when ready)
// ─────────────────────────────────────────────────────────────────────────────
class SessionStorage {
  static const _key = 'sessions_v1';

  static Future<List<Session>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) => Session.fromJson(jsonDecode(e)))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  static Future<void> save(Session s) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(s.toJson()));
    await prefs.setStringList(_key, raw);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class AppScaffold extends StatelessWidget {
  final Widget child;
  final bool showBack;
  const AppScaffold({super.key, required this.child, this.showBack = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.menu, color: AppColors.textMuted, size: 22),
                  const Spacer(),
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Icon(Icons.person_outline,
                        color: AppColors.textMuted, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class NavButtons extends StatelessWidget {
  final String?       prevLabel;
  final String?       nextLabel;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool          nextLoading;

  const NavButtons({
    super.key,
    this.prevLabel   = 'PREVIOUS',
    this.nextLabel   = 'NEXT',
    this.onPrev,
    this.onNext,
    this.nextLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Row(
        children: [
          if (onPrev != null)
            OutlinedButton(
              onPressed: onPrev,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: BorderSide(color: AppColors.textMuted.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
              child: Text(prevLabel!,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
          const Spacer(),
          if (onNext != null)
            ElevatedButton(
              onPressed: nextLoading ? null : onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.accent.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                elevation: 0,
              ),
              child: nextLoading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(nextLabel!,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

Widget placeholderImage({double height = 180, String label = 'IMAGE'}) {
  return Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined,
              color: AppColors.textMuted, size: 36),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  letterSpacing: 1)),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 10 — HOME
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DateTime _today = DateTime.now();
  late DateTime  _displayedMonth;
  List<Session>  _sessions = [];

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(_today.year, _today.month);
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final s = await SessionStorage.load();
    setState(() => _sessions = s);
  }

  int get _daysInMonth =>
      DateUtils.getDaysInMonth(_displayedMonth.year, _displayedMonth.month);
  int get _firstWeekday =>
      DateTime(_displayedMonth.year, _displayedMonth.month, 1).weekday % 7;

  bool _isToday(int d) =>
      _today.year  == _displayedMonth.year  &&
      _today.month == _displayedMonth.month &&
      _today.day   == d;

  bool _hasSession(int day) {
    final d = DateTime(_displayedMonth.year, _displayedMonth.month, day);
    return _sessions.any((s) =>
        s.startedAt.year  == d.year  &&
        s.startedAt.month == d.month &&
        s.startedAt.day   == d.day);
  }

  String _monthLabel(DateTime d) {
    const m = ['January','February','March','April','May','June',
               'July','August','September','October','November','December'];
    return '${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showBack: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hi! How are you doing today?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)),
            const SizedBox(height: 20),
            _buildCalendar(),
            const SizedBox(height: 24),
            _buildToDoList(),
            const SizedBox(height: 24),
            _buildJourneyBar(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.intro)
                        .then((_) => _loadSessions()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Start Session',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    const weekdays = ['S','M','T','W','T','F','S'];
    final cells    = <Widget>[];

    for (int i = 0; i < _firstWeekday; i++) cells.add(const SizedBox());
    for (int day = 1; day <= _daysInMonth; day++) {
      final today      = _isToday(day);
      final hasSession = _hasSession(day);
      cells.add(AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: today ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Text('$day',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: today ? FontWeight.w700 : FontWeight.w400,
                    color: today ? Colors.white : AppColors.text)),
            if (hasSession && !today)
              Positioned(
                bottom: 3,
                child: Container(
                  width: 3, height: 3,
                  decoration: const BoxDecoration(
                      color: AppColors.accentLight,
                      shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => setState(() => _displayedMonth =
                  DateTime(_displayedMonth.year, _displayedMonth.month - 1)),
              icon: const Icon(Icons.chevron_left,
                  color: AppColors.textMuted, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            Text(_monthLabel(_displayedMonth),
                style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            IconButton(
              onPressed: () => setState(() => _displayedMonth =
                  DateTime(_displayedMonth.year, _displayedMonth.month + 1)),
              icon: const Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: weekdays.map((d) => Expanded(
            child: Center(
              child: Text(d,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ]),
    );
  }

  Widget _buildToDoList() {
    const todos = [
      'Complete grip exercise',
      'Review progress',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('To Do List:',
            style: TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ...todos.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.textMuted.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 10),
            Text(t,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13)),
          ]),
        )),
      ],
    );
  }

  Widget _buildJourneyBar() {
    final progress =
        _sessions.isEmpty ? 0.0 : (_sessions.length / 20.0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Journey',
            style: TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: AppColors.surface,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
        const SizedBox(height: 6),
        Text('${_sessions.length} sessions completed',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 11 — INTRO
// ─────────────────────────────────────────────────────────────────────────────
class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.fitness_center,
                      color: AppColors.accentLight, size: 32),
                ),
                const SizedBox(height: 28),
                const Text('Grip Strength Training',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        letterSpacing: -0.3)),
                const SizedBox(height: 16),
                const Text(
                  'When you click on NEXT you will start the introduction to training to strengthen your muscles and aid in your carpal tunnel recovery process.',
                  style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textMuted,
                      height: 1.6),
                ),
                const SizedBox(height: 24),
                _infoRow(Icons.timer_outlined, 'Takes about 5–10 minutes'),
                const SizedBox(height: 12),
                _infoRow(Icons.show_chart, 'Results saved to your profile'),
                const SizedBox(height: 12),
                _infoRow(Icons.sensors,
                    'Sensor connection coming in a future update'),
              ],
            ),
          ),
        ),
        NavButtons(
          onPrev: () => Navigator.pop(context),
          onNext: () => Navigator.pushNamed(context, AppRoutes.exercise),
        ),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, color: AppColors.accentLight, size: 18),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 12 — EXERCISE STEPS
// ─────────────────────────────────────────────────────────────────────────────
class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});
  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  int _step = 0;

  final List<Map<String, String>> _steps = [
    {
      'title': 'Start Position',
      'desc':  'Hold your hand in a relaxed open position, fingers extended and palm facing up.',
      'asset': '',
    },
    {
      'title': 'Begin Grip',
      'desc':  'Slowly curl your fingers inward toward your palm, starting from the fingertips.',
      'asset': '',
    },
    {
      'title': 'Full Grip',
      'desc':  'Squeeze your hand into a firm fist. Hold for 2 seconds.',
      'asset': '',
    },
    {
      'title': 'Release',
      'desc':  'Slowly open your hand back to the starting position. That is one repetition.',
      'asset': '',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return AppScaffold(
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(_steps.length, (i) => Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _step ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _step
                          ? AppColors.accent
                          : AppColors.textMuted.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )),
                ),
                const SizedBox(height: 20),
                Text('Step ${_step + 1} of ${_steps.length}',
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(step['title']!,
                    style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                step['asset']!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(step['asset']!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover),
                      )
                    : placeholderImage(
                        height: 200,
                        label: 'GRIP STEP ${_step + 1} IMAGE'),
                const SizedBox(height: 20),
                Text(step['desc']!,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                        height: 1.6)),
              ],
            ),
          ),
        ),
        NavButtons(
          onPrev: _step > 0
              ? () => setState(() => _step--)
              : () => Navigator.pop(context),
          nextLabel: _step < _steps.length - 1 ? 'NEXT' : 'GOT IT',
          onNext: _step < _steps.length - 1
              ? () => setState(() => _step++)
              : () => Navigator.pushNamed(context, AppRoutes.perform),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 13 — PERFORM
// ─────────────────────────────────────────────────────────────────────────────
class PerformScreen extends StatelessWidget {
  const PerformScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.back_hand_outlined,
                      color: AppColors.warning, size: 32),
                ),
                const SizedBox(height: 28),
                const Text('Now You Try It',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 16),
                const Text(
                  'Now that you know how to do the exercise, let\'s record where you are right now.',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You will be asked to grip as hard as you can for 10 seconds, 3 times.',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 32),
                _badge('3', 'repetitions'),
                const SizedBox(height: 12),
                _badge('10', 'seconds each'),
              ],
            ),
          ),
        ),
        NavButtons(
          onPrev: () => Navigator.pop(context),
          onNext: () => Navigator.pushNamed(context, AppRoutes.baseline),
        ),
      ]),
    );
  }

  Widget _badge(String num, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(num,
          style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.accent)),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 14 — BASELINE INFO
// ─────────────────────────────────────────────────────────────────────────────
class BaselineScreen extends StatelessWidget {
  const BaselineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.analytics_outlined,
                      color: AppColors.success, size: 32),
                ),
                const SizedBox(height: 28),
                const Text('Baseline Measurement',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 16),
                const Text(
                  'After completing this task we will calculate your baseline grip strength and you will begin your journey towards recovery.',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 32),
                _metricCard('Grip Strength', 'kg', Icons.compress),
              ],
            ),
          ),
        ),
        NavButtons(
          onPrev: () => Navigator.pop(context),
          onNext: () => Navigator.pushNamed(context, AppRoutes.beginMeasure),
        ),
      ]),
    );
  }

  Widget _metricCard(String label, String unit, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Row(children: [
      Icon(icon, color: AppColors.accentLight, size: 20),
      const SizedBox(width: 12),
      Text(label,
          style: const TextStyle(color: AppColors.text, fontSize: 14)),
      const Spacer(),
      Text('— $unit',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 15 — BEGIN MEASURE
// ─────────────────────────────────────────────────────────────────────────────
class BeginMeasureScreen extends StatelessWidget {
  const BeginMeasureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ready to Measure',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 16),
                const Text(
                  'You will complete 3 reps. For each rep, get ready when prompted then grip as hard as you can for 10 seconds.',
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.warning.withOpacity(0.2)),
                  ),
                  child: Row(children: const [
                    Icon(Icons.sensors, color: AppColors.warning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sensor not connected — running in simulation mode.',
                        style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        NavButtons(
          onPrev: () => Navigator.pop(context),
          nextLabel: 'BEGIN',
          onNext: () => Navigator.pushNamed(context, AppRoutes.measuring),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 16 — MEASURING
//  Flow per rep: "Ready..." → "Set..." → "GRIP!" → 10s countdown → rest
// ─────────────────────────────────────────────────────────────────────────────
enum _Phase { ready, set, grip, countdown, rest, done }

class MeasuringScreen extends StatefulWidget {
  const MeasuringScreen({super.key});
  @override
  State<MeasuringScreen> createState() => _MeasuringScreenState();
}

class _MeasuringScreenState extends State<MeasuringScreen> {
  static const _totalReps      = 3;
  static const _countdownSecs  = 10;
  static const _restSecs       = 3;

  int     _currentRep = 1;
  _Phase  _phase      = _Phase.ready;
  int     _seconds    = _countdownSecs;
  Timer?  _timer;

  // Simulated grip values per rep — replace with real sensor data
  final List<double> _repResults = [];

  @override
  void initState() {
    super.initState();
    _startReadyPhase();
  }

  // ── Phase controllers ────────────────────────────────────────────────────

  void _startReadyPhase() {
    setState(() => _phase = _Phase.ready);
    _timer = Timer(const Duration(seconds: 2), _startSetPhase);
  }

  void _startSetPhase() {
    setState(() => _phase = _Phase.set);
    _timer = Timer(const Duration(seconds: 2), _startGripPhase);
  }

  void _startGripPhase() {
    setState(() { _phase = _Phase.grip; });
    _timer = Timer(const Duration(milliseconds: 800), _startCountdown);
  }

  void _startCountdown() {
    setState(() { _phase = _Phase.countdown; _seconds = _countdownSecs; });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) {
        t.cancel();
        _endRep();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  void _endRep() {
    // ── SENSOR HOOK-IN: replace mock with real sensor value ──────────────
    // e.g. final gripValue = await sensorService.getGripStrength();
    final mockValue = 10.0 + (_currentRep * 1.5) +
        (DateTime.now().millisecond % 10) * 0.2;
    _repResults.add(mockValue);

    if (_currentRep >= _totalReps) {
      _finishAllReps();
    } else {
      setState(() { _phase = _Phase.rest; _seconds = _restSecs; });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_seconds <= 1) {
          t.cancel();
          setState(() => _currentRep++);
          _startReadyPhase();
        } else {
          setState(() => _seconds--);
        }
      });
    }
  }

  Future<void> _finishAllReps() async {
    final avg = _repResults.reduce((a, b) => a + b) / _repResults.length;

    final session = Session(
      id:             DateTime.now().millisecondsSinceEpoch.toString(),
      startedAt:      DateTime.now(),
      gripStrengthKg: avg,
      status:         'completed',
    );

    await SessionStorage.save(session);

    // ── SUPABASE HOOK-IN: uncomment when ready ───────────────────────────
    // await supabase.from('sessions').insert(session.toJson());

    setState(() => _phase = _Phase.done);
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showBack: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: _phase == _Phase.done
            ? _buildDone(context)
            : _buildActive(),
      ),
    );
  }

  Widget _buildActive() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rep indicator at top
        _buildRepIndicator(),
        const SizedBox(height: 48),
        // Main phase display
        _buildPhaseDisplay(),
        const SizedBox(height: 48),
        // Instruction text
        Text(_phaseInstruction(),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 15, height: 1.5)),
      ],
    );
  }

  Widget _buildRepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalReps, (i) {
        final done    = i < _currentRep - 1;
        final current = i == _currentRep - 1;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: done
                ? AppColors.success
                : current
                    ? AppColors.accent
                    : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: current
                  ? AppColors.accentLight
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: current
                            ? Colors.white
                            : AppColors.textMuted)),
          ),
        );
      }),
    );
  }

  Widget _buildPhaseDisplay() {
    switch (_phase) {
      case _Phase.ready:
        return _bigLabel('Ready...', AppColors.textMuted);
      case _Phase.set:
        return _bigLabel('Set...', AppColors.warning);
      case _Phase.grip:
        return _bigLabel('GRIP!', AppColors.accent);
      case _Phase.countdown:
        return _countdownRing();
      case _Phase.rest:
        return _restDisplay();
      case _Phase.done:
        return const SizedBox.shrink();
    }
  }

  Widget _bigLabel(String text, Color color) {
    return Text(text,
        style: TextStyle(
            fontSize: 52,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -1));
  }

  Widget _countdownRing() {
    return SizedBox(
      width: 160, height: 160,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: _seconds / _countdownSecs,
            strokeWidth: 12,
            backgroundColor: AppColors.surface,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_seconds',
              style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text)),
          const Text('seconds',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }

  Widget _restDisplay() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.pause_circle_outline,
          color: AppColors.success, size: 64),
      const SizedBox(height: 16),
      Text('Rest — $_seconds',
          style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.success)),
    ]);
  }

  String _phaseInstruction() {
    switch (_phase) {
      case _Phase.ready:   return 'Rep $_currentRep of $_totalReps — get in position';
      case _Phase.set:     return 'Prepare to squeeze as hard as you can';
      case _Phase.grip:    return 'Squeeze now!';
      case _Phase.countdown: return 'Hold your grip — keep squeezing!';
      case _Phase.rest:    return 'Good work! Rest before the next rep';
      case _Phase.done:    return '';
    }
  }

  // ── Done screen ──────────────────────────────────────────────────────────

  Widget _buildDone(BuildContext context) {
    final avg = _repResults.isEmpty
        ? 0.0
        : _repResults.reduce((a, b) => a + b) / _repResults.length;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 64),
        const SizedBox(height: 20),
        const Text('All 3 Reps Complete!',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text)),
        const SizedBox(height: 28),
        // Per-rep breakdown
        ...List.generate(_repResults.length, (i) =>
            _resultRow('Rep ${i + 1}',
                '${_repResults[i].toStringAsFixed(1)} kg')),
        const SizedBox(height: 8),
        _resultRow('Average', '${avg.toStringAsFixed(1)} kg',
            highlight: true),
        const SizedBox(height: 36),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.complete),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('See Results',
                style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(String label, String value, {bool highlight = false}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.accent.withOpacity(0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight
                ? AppColors.accent.withOpacity(0.4)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: highlight ? AppColors.accentLight : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.w400)),
            Text(value,
                style: TextStyle(
                    color: highlight ? AppColors.accentLight : AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  FRAME 17 — COMPLETE
// ─────────────────────────────────────────────────────────────────────────────
class CompleteScreen extends StatelessWidget {
  const CompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showBack: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_outlined,
                  color: AppColors.success, size: 44),
            ),
            const SizedBox(height: 32),
            const Text(
              'You have just completed your baseline testing!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  height: 1.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'Congratulations on beginning your journey towards recovery!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, AppRoutes.home, (_) => false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Back to Home',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}