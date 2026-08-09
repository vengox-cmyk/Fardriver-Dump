import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:biketunes/providers/stats_provider.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsState = ref.watch(statsProvider);
    final session = statsState.currentSession;

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          'STATS',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          if (session != null)
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              onPressed: () async {
                final path = await ref
                    .read(statsProvider.notifier)
                    .exportCurrentSession();
                if (path != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Exported to $path'),
                      backgroundColor: const Color(0xFF1A2030),
                    ),
                  );
                }
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1A2030)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session != null) ...[
                const _SectionHeader(title: 'CURRENT SESSION'),
                const SizedBox(height: 12),
                _SessionSummaryCards(
                  distanceMi: session.distanceKm * 0.621371,
                  durationSeconds: session.duration.inSeconds,
                  avgSpeedMph: session.avgSpeedKph * 0.621371,
                  maxSpeedMph: session.maxSpeedKph * 0.621371,
                  totalWhUsed: session.totalWhUsed,
                  distanceKm: session.distanceKm,
                ),
                const SizedBox(height: 20),
                if (session.speedHistory.isNotEmpty) ...[
                  const _SectionHeader(title: 'SPEED HISTORY'),
                  const SizedBox(height: 12),
                  _SpeedChart(
                    samples: session.speedHistory
                        .map((s) => s.speedKph * 0.621371)
                        .toList(),
                    unit: 'mph',
                  ),
                  const SizedBox(height: 24),
                ],
              ] else ...[
                const _EmptySession(),
                const SizedBox(height: 24),
              ],
              if (statsState.pastSessions.isNotEmpty) ...[
                const _SectionHeader(title: 'PAST SESSIONS'),
                const SizedBox(height: 12),
                for (final json in statsState.pastSessions.reversed)
                  _PastSessionCard(json: json),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSummaryCards extends StatelessWidget {
  final double distanceMi;
  final double distanceKm;
  final int durationSeconds;
  final double avgSpeedMph;
  final double maxSpeedMph;
  final double totalWhUsed;

  const _SessionSummaryCards({
    required this.distanceMi,
    required this.distanceKm,
    required this.durationSeconds,
    required this.avgSpeedMph,
    required this.maxSpeedMph,
    required this.totalWhUsed,
  });

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          label: 'DISTANCE',
          value: distanceMi.toStringAsFixed(2),
          unit: 'mi',
          color: const Color(0xFF00E5FF),
        ),
        _StatCard(
          label: 'RIDE TIME',
          value: _formatDuration(durationSeconds),
          unit: '',
          color: const Color(0xFF39FF14),
        ),
        _StatCard(
          label: 'AVG SPEED',
          value: avgSpeedMph.toStringAsFixed(1),
          unit: 'mph',
          color: const Color(0xFFFF9800),
        ),
        _StatCard(
          label: 'TOP SPEED',
          value: maxSpeedMph.toStringAsFixed(1),
          unit: 'mph',
          color: const Color(0xFF00E5FF),
        ),
        _StatCard(
          label: 'ENERGY USED',
          value: totalWhUsed.toStringAsFixed(0),
          unit: 'Wh',
          color: const Color(0xFF39FF14),
        ),
        _StatCard(
          label: 'EFFICIENCY',
          value: distanceMi > 0
              ? (totalWhUsed / distanceMi).toStringAsFixed(1)
              : '--',
          unit: 'Wh/mi',
          color: const Color(0xFFFF9800),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2030)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedChart extends StatelessWidget {
  final List<double> samples;
  final String unit;
  const _SpeedChart({required this.samples, this.unit = 'mph'});

  @override
  Widget build(BuildContext context) {
    final maxY = samples.fold(0.0, (a, b) => a > b ? a : b);
    final spots = [
      for (int i = 0; i < samples.length; i++)
        FlSpot(i.toDouble(), samples[i]),
    ];

    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2030)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF1A2030), strokeWidth: 1),
            getDrawingVerticalLine: (_) =>
                const FlLine(color: Color(0xFF1A2030), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (val, _) => Text(
                  val.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 10,
                  ),
                ),
                interval: maxY > 0 ? maxY / 2 : 1,
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (samples.length - 1).toDouble().clamp(1, double.infinity),
          minY: 0,
          maxY: (maxY * 1.1).clamp(10, double.infinity),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF00E5FF),
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF00E5FF).withOpacity(0.25),
                    const Color(0xFF00E5FF).withOpacity(0.0),
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

class _PastSessionCard extends StatelessWidget {
  final Map<String, dynamic> json;
  const _PastSessionCard({required this.json});

  @override
  Widget build(BuildContext context) {
    final startTime = DateTime.tryParse(json['startTime'] as String? ?? '');
    final distKm = (json['distanceKm'] as num?)?.toDouble() ?? 0.0;
    final distMi = distKm * 0.621371;
    final maxSpd = ((json['maxSpeedKph'] as num?)?.toDouble() ?? 0.0) * 0.621371;
    final durSec = (json['durationSeconds'] as num?)?.toInt() ?? 0;
    final wh = (json['totalWhUsed'] as num?)?.toDouble() ?? 0.0;

    final dateStr = startTime != null
        ? DateFormat('MMM d, HH:mm').format(startTime)
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2030)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${distMi.toStringAsFixed(2)} mi  •  '
                  '${_fmt(durSec)}  •  '
                  '${wh.toStringAsFixed(0)} Wh',
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${maxSpd.toStringAsFixed(0)}\nmph top',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    return '${m}m';
  }
}

class _EmptySession extends StatelessWidget {
  const _EmptySession();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.timeline, size: 48, color: Color(0xFF2A3548)),
          const SizedBox(height: 16),
          const Text(
            'No active session',
            style: TextStyle(color: Color(0xFF4A5568), fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to the controller to start tracking',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF4A5568),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }
}
