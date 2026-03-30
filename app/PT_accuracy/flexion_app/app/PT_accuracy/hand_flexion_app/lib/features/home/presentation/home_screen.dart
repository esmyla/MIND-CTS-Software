/// lib/features/home/presentation/home_screen.dart
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/home_provider.dart';
import '../../auth/state/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final session = ref.watch(sessionProvider);
    final isGuest = session.status == SessionStatus.guest;

    final streakAsync = ref.watch(streakProvider);
    final sessionsAsync = ref.watch(sessionHistoryProvider);

    // Only read mock data if we actually need it (guest mode)
    final chartData = isGuest ? ref.watch(mockFlexionChartProvider) : const <FlexionDataPoint>[];
    final gripImprovement = ref.watch(gripImprovementProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (isGuest)
            TextButton.icon(
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Sign In'),
            )
          else
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign Out',
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(streakProvider);
          ref.invalidate(sessionHistoryProvider); // NEW: refresh calendar data too
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Guest mode CTA
            if (isGuest) ...[
              _GuestBanner(),
              const SizedBox(height: 16),
            ],

            // ----------------------------------------------------------------
            // Top row: Streak (or Calendar) + Grip cards
            // ----------------------------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: streakAsync.when(
                    data: (streak) {
                      // If streak is 0 or 1, show calendar for current month.
                      if (streak <= 1) {
                        return sessionsAsync.when(
                          data: (allDates) => _MonthlySessionCalendar(completedDays: allDates),
                          loading: () => const _StatCardSkeleton(),
                          error: (_, __) => const _StatCard(
                            icon: Icons.calendar_month_rounded,
                            iconColor: Colors.blueGrey,
                            label: 'Sessions',
                            value: '—',
                            subtitle: 'History unavailable',
                          ),
                        );
                      }

                      // Otherwise show regular streak card
                      return _StatCard(
                        icon: Icons.local_fire_department_rounded,
                        iconColor: Colors.orange,
                        label: 'Day Streak',
                        value: '$streak',
                        subtitle: streak == 1 ? 'Great start!' : 'Keep it going!',
                      );
                    },
                    loading: () => const _StatCardSkeleton(),
                    error: (_, __) => const _StatCard(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: Colors.orange,
                      label: 'Day Streak',
                      value: '—',
                      subtitle: 'Unavailable',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.fitness_center_rounded,
                    iconColor: cs.primary,
                    label: 'Grip Strength',
                    value: gripImprovement == 0 ? 'N/A' : '+${gripImprovement.toStringAsFixed(1)}%',
                    subtitle: 'Coming from FSR data',
                    subtitleIcon: Icons.info_outline_rounded,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ----------------------------------------------------------------
            // Flexion growth chart
            //   - Only show mock chart in guest mode.
            //   - Hide mock chart for signed-in users (show a subtle placeholder).
            // ----------------------------------------------------------------
            if (isGuest)
              _FlexionChart(data: chartData, isMock: true)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.show_chart_rounded, color: cs.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your wrist flexion chart will appear here once data is available.',
                          style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // ----------------------------------------------------------------
            // Quick tips card
            // ----------------------------------------------------------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.tips_and_updates_rounded,
                          color: cs.secondary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Today\'s Tip',
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Warm up your wrist for 2 minutes before starting exercises. '
                      'Slow, controlled flexion protects tendons and improves long-term range of motion.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card widget (unchanged)
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
  final IconData? subtitleIcon;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.subtitleIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: tt.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: tt.labelLarge?.copyWith(
                color: cs.onSurface.withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (subtitleIcon != null) ...[
                  Icon(
                    subtitleIcon,
                    size: 12,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                    ),
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

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(height: 100),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly Session Calendar (simple, dependency-free)
// ---------------------------------------------------------------------------

class _MonthlySessionCalendar extends StatelessWidget {
  final Set<DateTime> completedDays;
  final DateTime month;

  _MonthlySessionCalendar({
    required Set<DateTime> completedDays,
    DateTime? month,
  })  : completedDays = completedDays.map(_dateOnly).toSet(),
        month = DateTime(
          (month ?? DateTime.now()).year,
          (month ?? DateTime.now()).month,
        );

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final firstDay = DateTime(month.year, month.month, 1);
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;

    // Sunday-first calendar: leading blanks = weekday % 7 (Mon=1..Sun=7)
    final leadingBlanks = firstDay.weekday % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7.0).ceil();
    final cells = rows * 7;

    // Build a fast lookup set for completed days in this month
    final completedThisMonth = <int>{};
    for (var d in completedDays) {
      if (d.year == month.year && d.month == month.month) {
        completedThisMonth.add(d.day);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${_monthName(month.month)} ${month.year}',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (completedThisMonth.isNotEmpty)
                  Text(
                    '${completedThisMonth.length} day${completedThisMonth.length == 1 ? '' : 's'}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Weekday labels (Sun..Sat)
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DowLabel('S'),
                _DowLabel('M'),
                _DowLabel('T'),
                _DowLabel('W'),
                _DowLabel('T'),
                _DowLabel('F'),
                _DowLabel('S'),
              ],
            ),
            const SizedBox(height: 8),

            // Calendar grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: cells,
              itemBuilder: (_, index) {
                final dayNum = index - leadingBlanks + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final isDone = completedThisMonth.contains(dayNum);
                return _DayCell(
                  day: dayNum,
                  isDone: isDone,
                );
              },
            ),
            const SizedBox(height: 8),

            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _Dot(color: cs.primary),
                const SizedBox(width: 6),
                Text('Completed', style: tt.labelSmall),
                const SizedBox(width: 12),
                _Dot(color: cs.outlineVariant),
                const SizedBox(width: 6),
                Text('No session', style: tt.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return names[m - 1];
  }
}

class _DowLabel extends StatelessWidget {
  final String text;
  const _DowLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: cs.onSurface.withOpacity(0.6),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isDone;

  const _DayCell({required this.day, required this.isDone});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final bg = isDone ? cs.primary.withOpacity(0.12) : cs.surfaceContainerHighest.withOpacity(0.6);
    final border = isDone ? cs.primary : cs.outlineVariant;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '$day',
        style: tt.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDone ? cs.primary : cs.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flexion growth line chart (adds isMock flag to control "Mock data" tag)
// ---------------------------------------------------------------------------

class _FlexionChart extends StatelessWidget {
  final List<FlexionDataPoint> data;
  final bool isMock; // NEW

  const _FlexionChart({required this.data, this.isMock = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.show_chart_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Wrist Flexion Progress',
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (isMock)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Mock data',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              'Last ${data.length} sessions • Forward & Backward targets',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.55),
              ),
            ),

            const SizedBox(height: 16),

            // Chart
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 10,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: cs.outlineVariant.withOpacity(0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, m) => Text(
                          '${v.toInt()}°',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) {
                          final idx = v.toInt() - 1;
                          if (idx < 0 || idx >= data.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            'S${data[idx].session}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(0.5),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 60,
                  lineBarsData: [
                    // Forward line
                    LineChartBarData(
                      spots: data
                          .map((d) => FlSpot(
                                d.session.toDouble(),
                                d.forwardAngle,
                              ))
                          .toList(),
                      isCurved: true,
                      color: cs.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 4,
                          color: cs.primary,
                          strokeWidth: 2,
                          strokeColor: cs.surface,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: cs.primary.withOpacity(0.08),
                      ),
                    ),
                    // Backward line
                    LineChartBarData(
                      spots: data
                          .map((d) => FlSpot(
                                d.session.toDouble(),
                                d.backwardAngle,
                              ))
                          .toList(),
                      isCurved: true,
                      color: cs.secondary,
                      barWidth: 3,
                      dashArray: [6, 4],
                      dotData: FlDotData(
                        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 4,
                          color: cs.secondary,
                          strokeWidth: 2,
                          strokeColor: cs.surface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: cs.primary),
                const SizedBox(width: 4),
                Text('Forward', style: tt.labelSmall),
                const SizedBox(width: 16),
                _LegendDot(color: cs.secondary, dashed: true),
                const SizedBox(width: 4),
                Text('Backward', style: tt.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final bool dashed;

  const _LegendDot({required this.color, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 3,
      decoration: BoxDecoration(
        color: dashed ? Colors.transparent : color,
        border: dashed ? Border(bottom: BorderSide(color: color, width: 2)) : null,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guest mode banner (unchanged)
// ---------------------------------------------------------------------------

class _GuestBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_rounded, color: cs.onSecondaryContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sign in to sync your progress',
                  style: tt.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSecondaryContainer,
                  ),
                ),
                Text(
                  'Guest data is stored locally only.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSecondaryContainer.withOpacity(0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
