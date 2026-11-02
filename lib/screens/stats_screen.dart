import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/providers/rides_provider.dart';
import 'package:arcdash/screens/ride_detail_screen.dart';
import 'package:arcdash/screens/saved_calibration_screen.dart';
import 'package:arcdash/screens/saved_files_screen.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/providers/units_provider.dart';
import 'package:arcdash/utils/speed_units.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsState = ref.watch(statsProvider);
    final unit = ref.watch(speedUnitProvider);
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
          if (session != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: strings.text(AppText.exportRide),
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
        child: CustomScrollView(
          key: const ValueKey('rides-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RideControl(
                        session: session,
                        waitingForController: statsState.waitingForController),
                    const SizedBox(height: 20),
                    if (session != null) ...[
                      _SectionHeader(
                          title: strings.text(AppText.currentSession)),
                      const SizedBox(height: 12),
                      _SessionSummaryCards(
                        distanceKm: session.distanceKm,
                        durationSeconds: session.duration.inSeconds,
                        avgSpeedKph: session.avgSpeedKph,
                        maxSpeedKph: session.maxSpeedKph,
                        totalWhUsed: session.totalWhUsed,
                        unit: unit,
                      ),
                      const SizedBox(height: 20),
                      if (session.speedHistory.isNotEmpty) ...[
                        _SectionHeader(
                            title: strings.text(AppText.speedHistory)),
                        const SizedBox(height: 12),
                        _SpeedChart(
                          samples: session.speedHistory
                              .map((s) => unit.fromKph(s.speedKph))
                              .toList(),
                          unit: unit.speedLabel,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            _SavedRidesSliver(
                unit: unit, pastSessions: statsState.pastSessions),
          ],
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
  final SpeedUnit unit;

  const _SessionSummaryCards({
    required this.distanceKm,
    required this.durationSeconds,
    required this.avgSpeedKph,
    required this.maxSpeedKph,
    required this.totalWhUsed,
    this.unit = SpeedUnit.kmh,
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
          value: unit.fromKm(distanceKm).toStringAsFixed(2),
          unit: unit.distanceLabel,
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
          value: unit.fromKph(avgSpeedKph).toStringAsFixed(1),
          unit: unit.speedLabel,
          color: const Color(0xFFFF9800),
        ),
        _StatCard(
          label: strings.text(AppText.topSpeed),
          value: unit.fromKph(maxSpeedKph).toStringAsFixed(1),
          unit: unit.speedLabel,
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
              ? unit
                  .whPerDistanceFromWhPerKm(totalWhUsed / distanceKm)
                  .toStringAsFixed(1)
              : '--',
          unit: unit.energyPerDistanceLabel,
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
              color: color.withValues(alpha: 0.7),
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
                    color: Colors.white.withValues(alpha: 0.4),
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
                    const Color(0xFF00E5FF).withValues(alpha: 0.25),
                    const Color(0xFF00E5FF).withValues(alpha: 0.0),
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
  final SpeedUnit unit;
  const _PastSessionCard({required this.json, this.unit = SpeedUnit.kmh});

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
                    '${unit.distance(distKm, digits: 2)}  •  '
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
              tooltip: AppStrings.of(context).text(AppText.exportThisRide),
              onPressed: () => _exportJson(context, json, dateStr),
            ),
            const SizedBox(width: 4),
            Text(
              '${unit.fromKph(maxSpd).toStringAsFixed(0)}\n${AppStrings.of(context).text(AppText.kmhTop).replaceFirst('km/h', unit.speedLabel)}',
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
        content: Text(AppStrings.of(context)
            .text(AppText.rideCopied)
            .replaceAll('{date}', dateStr)),
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
    final whPerKm = distKm > 0.05
        ? unit.whPerDistanceFromWhPerKm(wh / distKm).toStringAsFixed(1)
        : '—';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1A2030)),
        ),
        title: Text(
          AppStrings.of(context)
              .text(AppText.rideDetails)
              .replaceAll('{date}', dateStr),
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
                label: AppStrings.of(context).text(AppText.detailDistance),
                value: unit.distance(distKm, digits: 2)),
            _DetailRow(
                label: AppStrings.of(context).text(AppText.detailRideTime),
                value: _fmt(durSec)),
            _DetailRow(
                label: AppStrings.of(context).text(AppText.detailTopSpeed),
                value: unit.speed(maxSpd, digits: 1)),
            _DetailRow(
                label: AppStrings.of(context).text(AppText.detailAverage),
                value: unit.speed(avgSpd, digits: 1)),
            _DetailRow(
                label: AppStrings.of(context).text(AppText.detailEnergy),
                value: '${wh.toStringAsFixed(1)} Wh'),
            _DetailRow(
                label: AppStrings.of(context).text(AppText.detailEfficiency),
                value: '$whPerKm ${unit.energyPerDistanceLabel}'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text(AppStrings.of(context).text(AppText.exportCopy)),
            onPressed: () {
              Navigator.of(context).pop();
              _exportJson(context, sessionJson, dateStr);
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.of(context).text(AppText.close)),
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

/// Start ride / Stop ride with the running time. Rides are manual: one
/// starts only here and ends only on Stop (it survives leaving the tab, the
/// screen going off and Bluetooth drops). Big targets, used before and after
/// riding, never during.
class _RideControl extends ConsumerWidget {
  const _RideControl(
      {required this.session, required this.waitingForController});

  final RideSession? session;
  final bool waitingForController;

  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final strings = AppStrings.of(context);
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text(AppText.rideStopConfirmTitle)),
        content: Text(strings.text(AppText.rideStopConfirmBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text(AppText.rideStopConfirmKeep)),
          ),
          ElevatedButton(
            key: const ValueKey('ride-stop-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text(AppText.rideStop)),
          ),
        ],
      ),
    );
    if (stop == true) await ref.read(statsProvider.notifier).stopRide();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final s = session;
    if (s == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: ElevatedButton.icon(
              key: const ValueKey('ride-start'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => ref.read(statsProvider.notifier).startRide(),
              icon: const Icon(Icons.play_arrow_rounded, size: 32),
              label: Text(strings.text(AppText.rideStart),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          Text(strings.text(AppText.rideIdleHint),
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
        ],
      );
    }
    return Container(
      key: const ValueKey('ride-recording'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB71C1C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.fiber_manual_record,
                color: Color(0xFFFF5252), size: 16),
            const SizedBox(width: 6),
            Text(strings.text(AppText.rideRecording),
                style: const TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2)),
            const Spacer(),
            _ElapsedText(start: s.startTime),
          ]),
          if (waitingForController) ...[
            const SizedBox(height: 8),
            Text(strings.text(AppText.rideWaitingForController),
                key: const ValueKey('ride-waiting-controller'),
                style: const TextStyle(color: Colors.amber, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              key: const ValueKey('ride-stop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _confirmStop(context, ref),
              icon: const Icon(Icons.stop_rounded, size: 30),
              label: Text(strings.text(AppText.rideStop),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Running time since [start], ticking once a second on its own (keeps
/// going while no samples arrive, e.g. during a Bluetooth drop).
class _ElapsedText extends StatefulWidget {
  const _ElapsedText({required this.start});

  final DateTime start;

  @override
  State<_ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<_ElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String format(Duration d) {
    final s = d.isNegative ? 0 : d.inSeconds;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
  }

  @override
  Widget build(BuildContext context) => Text(
        format(DateTime.now().difference(widget.start)),
        key: const ValueKey('ride-elapsed'),
        style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()]),
      );
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

/// Saved rides and captures (lazy: built row by row, [_page] at a time),
/// then rides from older versions that only have the prefs summary.
class _SavedRidesSliver extends ConsumerStatefulWidget {
  const _SavedRidesSliver({required this.unit, required this.pastSessions});

  final SpeedUnit unit;
  final List<Map<String, dynamic>> pastSessions;

  @override
  ConsumerState<_SavedRidesSliver> createState() => _SavedRidesSliverState();
}

class _SavedRidesSliverState extends ConsumerState<_SavedRidesSliver> {
  static const _page = 20;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final listing = ref.watch(ridesListingProvider).valueOrNull;
    final entries = listing?.entries ?? const <SavedFileEntry>[];
    final recordIds = listing?.recordIds ?? const <String>{};
    final legacy = [
      for (final json in widget.pastSessions.reversed)
        if (!recordIds.contains('${json['id']}')) json
    ];
    final visible = entries.length < _shown ? entries.length : _shown;
    final more = entries.length > visible;
    // rows: header, entries (or empty note), [show more], [legacy block]
    final rowCount = 1 +
        (entries.isEmpty ? 1 : visible) +
        (more ? 1 : 0) +
        (legacy.isEmpty ? 0 : 1 + legacy.length);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      sliver: SliverList.builder(
        itemCount: rowCount,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SectionHeader(title: strings.text(AppText.ridesSaved)),
            );
          }
          i -= 1;
          if (entries.isEmpty) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(strings.text(AppText.ridesNoneSaved),
                    key: const ValueKey('rides-none-saved'),
                    style: const TextStyle(
                        color: Color(0xFF4A5568), fontSize: 13)),
              );
            }
            i -= 1;
          } else {
            if (i < visible) return _SavedEntryTile(entries[i], widget.unit);
            i -= visible;
          }
          if (more) {
            if (i == 0) {
              return TextButton(
                key: const ValueKey('rides-show-more'),
                onPressed: () => setState(() => _shown += _page),
                child: Text(strings.text(AppText.ridesShowMore)),
              );
            }
            i -= 1;
          }
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              child: _SectionHeader(
                  title: strings.text(AppText.ridesOlderSummaryOnly)),
            );
          }
          return _PastSessionCard(json: legacy[i - 1], unit: widget.unit);
        },
      ),
    );
  }
}

class _SavedEntryTile extends ConsumerWidget {
  const _SavedEntryTile(this.entry, this.unit);

  final SavedFileEntry entry;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final date = DateFormat('dd.MM.yyyy  HH:mm').format(entry.time);
    final info = entry.info;
    final (IconData icon, String title, String subtitle) = switch (entry.kind) {
      SavedFileKind.rideRecord => (
          Icons.two_wheeler,
          date,
          [
            if (double.tryParse(info['distanceKm'] ?? '') case final km?)
              unit.distance(km, digits: 2),
            if (int.tryParse(info['durationSeconds'] ?? '') case final s?)
              '${s ~/ 60}m ${s % 60}s',
            if (double.tryParse(info['maxSpeedKph'] ?? '') case final v?)
              '${strings.text(AppText.calloutTopSpeed)} ${unit.speed(v)}',
          ].join('  •  ')
        ),
      SavedFileKind.calibration => (
          Icons.speed,
          strings.text(AppText.savedCalibrations),
          date
        ),
      SavedFileKind.dashCheck => (
          Icons.speed_outlined,
          strings.text(AppText.savedDashChecks),
          date
        ),
      _ => (Icons.route_outlined, strings.text(AppText.savedRides), date),
    };
    final ride = entry.kind == SavedFileKind.rideRecord;
    final activeId =
        ref.watch(statsProvider.select((st) => st.currentSession?.id));
    final String? badge = !ride || info['finished'] != 'false'
        ? null
        : info['id'] == activeId
            ? strings.text(AppText.rideRecording).toLowerCase()
            : strings.text(AppText.rideUnfinished);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF1A2030)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('ride-entry-${entry.name}'),
          dense: true,
          leading: Icon(icon,
              color: ride ? const Color(0xFF00E5FF) : const Color(0xFF8B949E)),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: Text.rich(
              TextSpan(children: [
                if (badge != null)
                  TextSpan(
                      text: '$badge  ',
                      style: const TextStyle(
                          color: Colors.amber, fontWeight: FontWeight.w700)),
                TextSpan(text: subtitle),
              ]),
              key: badge == null ? null : ValueKey('ride-badge-${entry.name}'),
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF4A5568)),
          onTap: () => _open(context),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final Widget page = switch (entry.kind) {
      SavedFileKind.rideRecord =>
        RideDetailScreen(file: entry.file, unit: unit),
      SavedFileKind.calibration => SavedCalibrationScreen(file: entry.file),
      _ => SavedTextFileScreen(
          title: entry.name, text: await entry.file.readAsString()),
    };
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }
}
