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
    final streakAsync = ref.watch(streakProvider);
    final gripImprovement = ref.watch(gripImprovementProvider);
    final chartData = ref.watch(mockFlexionChartProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (session.status == SessionStatus.guest)
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
        onRefresh: () async => ref.invalidate(streakProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Guest mode CTA
            if (session.status == SessionStatus.guest) ...[
              _GuestBanner(),
              const SizedBox(height: 16),
            ],

            // ----------------------------------------------------------------
            // Top row: Streak + Grip cards
            // ----------------------------------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: streakAsync.when(
                    data: (streak) => _StatCard(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: Colors.orange,
                      label: 'Day Streak',
                      value: '$streak',
                      subtitle: streak == 1 ? 'Great start!' : 'Keep it going!',
                    ),
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
            // ----------------------------------------------------------------
            _FlexionChart(data: chartData),

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
                      'Warm up your wrist for 2 minutes before starting '
                      'exercises. Slow, controlled flexion protects tendons '
                      'and improves long-term range of motion.',
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
// Stat card widget
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
// Flexion growth line chart
// ---------------------------------------------------------------------------

class _FlexionChart extends StatelessWidget {
  final List<FlexionDataPoint> data;

  const _FlexionChart({required this.data});

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
// Guest mode banner
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
