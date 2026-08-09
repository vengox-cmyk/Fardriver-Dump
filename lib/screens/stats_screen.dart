import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/ride_stats.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsState = ref.watch(statsProvider);
    final session = statsState.currentSession;
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: Text(
          strings.text(AppText.stats),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            tooltip: 'Session zurücksetzen',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Session zurücksetzen'),
                  content: const Text(
                      'Möchtest du die aktuelle Fahrt-Session jetzt beenden und auf 0 zurücksetzen? Die bisherigen Daten werden in der Historie archiviert.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Abbrechen'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Zurücksetzen'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(statsProvider.notifier).resetCurrentSession();
              }
            },
          ),
          if (session != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: 'Fahrt exportieren / teilen',
              onPressed: () async {
                final path = await ref
                    .read(statsProvider.notifier)
                    .exportCurrentSession();
                if (path != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${strings.text(AppText.exported)} $path'),
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
                _SectionHeader(title: strings.text(AppText.currentSession)),
                const SizedBox(height: 12),
                _SessionSummaryCards(
                  distanceKm: session.distanceKm,
                  durationSeconds: session.duration.inSeconds,
                  avgSpeedKph: session.avgSpeedKph,
                  maxSpeedKph: session.maxSpeedKph,
                  totalWhUsed: session.totalWhUsed,
                ),
                const SizedBox(height: 20),
                if (session.speedHistory.isNotEmpty) ...[
                  _SectionHeader(title: strings.text(AppText.speedHistory)),
                  const SizedBox(height: 12),
                  _SpeedChart(
                    samples:
                        session.speedHistory.map((s) => s.speedKph).toList(),
                    unit: 'km/h',
                  ),
                  const SizedBox(height: 24),
                ],
              ] else ...[
                const _EmptySession(),
                const SizedBox(height: 24),
              ],
              if (statsState.pastSessions.isNotEmpty) ...[
                _SectionHeader(title: strings.text(AppText.pastSessions)),
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
  final double distanceKm;
  final int durationSeconds;
  final double avgSpeedKph;
  final double maxSpeedKph;
  final double totalWhUsed;

  const _SessionSummaryCards({
    required this.distanceKm,
    required this.durationSeconds,
    required this.avgSpeedKph,
    required this.maxSpeedKph,
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
    final strings = AppStrings.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          label: strings.text(AppText.distance),
          value: distanceKm.toStringAsFixed(2),
          unit: 'km',
          color: const Color(0xFF00E5FF),
        ),
        _StatCard(
          label: strings.text(AppText.rideTime),
          value: _formatDuration(durationSeconds),
          unit: '',
          color: const Color(0xFF39FF14),
        ),
        _StatCard(
          label: strings.text(AppText.averageSpeed),
          value: avgSpeedKph.toStringAsFixed(1),
          unit: 'km/h',
          color: const Color(0xFFFF9800),
        ),
        _StatCard(
          label: strings.text(AppText.topSpeed),
          value: maxSpeedKph.toStringAsFixed(1),
          unit: 'km/h',
          color: const Color(0xFF00E5FF),
        ),
        _StatCard(
          label: strings.text(AppText.energyUsed),
          value: totalWhUsed.toStringAsFixed(0),
          unit: 'Wh',
          color: const Color(0xFF39FF14),
        ),
        _StatCard(
          label: strings.text(AppText.efficiency),
          value: distanceKm > 0
              ? (totalWhUsed / distanceKm).toStringAsFixed(1)
              : '--',
          unit: 'Wh/km',
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
  const _SpeedChart({required this.samples, this.unit = 'km/h'});

  @override
  Widget build(BuildContext context) {
    final maxY = samples.fold(0.0, (a, b) => a > b ? a : b);
    final spots = [
      for (int i = 0; i < samples.length; i++) FlSpot(i.toDouble(), samples[i]),
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
    final maxSpd = (json['maxSpeedKph'] as num?)?.toDouble() ?? 0.0;
    final avgSpd = (json['avgSpeedKph'] as num?)?.toDouble() ?? 0.0;
    final durSec = (json['durationSeconds'] as num?)?.toInt() ?? 0;
    final wh = (json['totalWhUsed'] as num?)?.toDouble() ?? 0.0;

    final dateStr = startTime != null
        ? DateFormat('dd.MM.yyyy, HH:mm').format(startTime)
        : '—';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showSessionDetailsDialog(
          context, dateStr, distKm, avgSpd, maxSpd, durSec, wh, json),
      child: Container(
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
                    '${distKm.toStringAsFixed(2)} km  •  '
                    '${_fmt(durSec)}  •  '
                    '${wh.toStringAsFixed(0)} Wh',
                    style: const TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined,
                  size: 18, color: Color(0xFF54E39E)),
              tooltip: 'Diese Fahrt exportieren / teilen',
              onPressed: () => _exportJson(context, json, dateStr),
            ),
            const SizedBox(width: 4),
            Text(
              '${maxSpd.toStringAsFixed(0)}\nkm/h top',
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
      ),
    );
  }

  void _exportJson(
      BuildContext context, Map<String, dynamic> sessionJson, String dateStr) {
    final formatted = const JsonEncoder.withIndent('  ').convert(sessionJson);
    Clipboard.setData(ClipboardData(text: formatted));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Fahrt ($dateStr) als JSON in die Zwischenablage kopiert!'),
        backgroundColor: const Color(0xFF123328),
      ),
    );
  }

  void _showSessionDetailsDialog(
    BuildContext context,
    String dateStr,
    double distKm,
    double avgSpd,
    double maxSpd,
    int durSec,
    double wh,
    Map<String, dynamic> sessionJson,
  ) {
    final whPerKm = distKm > 0.05 ? (wh / distKm).toStringAsFixed(1) : '—';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1A2030)),
        ),
        title: Text(
          'Fahrtdetails ($dateStr)',
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
                label: 'Distanz', value: '${distKm.toStringAsFixed(2)} km'),
            _DetailRow(label: 'Fahrzeit', value: _fmt(durSec)),
            _DetailRow(
                label: 'Max. Geschwindigkeit',
                value: '${maxSpd.toStringAsFixed(1)} km/h'),
            _DetailRow(
                label: 'Durchschnitt',
                value: '${avgSpd.toStringAsFixed(1)} km/h'),
            _DetailRow(
                label: 'Verbrauchte Energie',
                value: '${wh.toStringAsFixed(1)} Wh'),
            _DetailRow(label: 'Effizienz / Verbrauch', value: '$whPerKm Wh/km'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Exportieren / Kopieren'),
            onPressed: () {
              Navigator.of(context).pop();
              _exportJson(context, sessionJson, dateStr);
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
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
          Text(
            AppStrings.of(context).text(AppText.noActiveSession),
            style: const TextStyle(color: Color(0xFF4A5568), fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.of(context).text(AppText.connectToTrack),
            style:
                TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
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
