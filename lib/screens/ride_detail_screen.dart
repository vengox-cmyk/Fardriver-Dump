import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/screens/parameter_dump_screen.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/ride_analysis.dart';
import 'package:arcdash/services/ride_archive.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/utils/speed_units.dart';

/// One saved ride, offline: summary, the settings in force at the start,
/// what changed since the previous ride, telemetry callouts and rule-based
/// suggestions with a "Copy for AI" button. Read-only; nothing here writes
/// to the controller or uses the network.
class RideDetailScreen extends ConsumerStatefulWidget {
  const RideDetailScreen(
      {super.key, required this.file, this.unit = SpeedUnit.kmh});

  final File file;
  final SpeedUnit unit;

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class RideDetailData {
  final RideRecord ride;
  final RideRecord? previous;
  final ParameterDump? settings;
  final ConfigDiff? diff;
  final List<String> suggestions;
  final String aiText;

  const RideDetailData({
    required this.ride,
    this.previous,
    this.settings,
    this.diff,
    required this.suggestions,
    required this.aiText,
  });

  /// Loads everything the detail screen shows (also used by tests).
  static Future<RideDetailData> load(
      SavedFilesStore store, File file, SpeedUnit unit) async {
    final archive = RideArchive(store);
    final ride = await RideArchive.load(file);
    final previous = await archive.previousOf(ride);
    final settings = await archive.loadDump(ride.settingsDump);
    ConfigDiff? diff;
    if (previous != null && settings != null) {
      if (previous.settingsDump == ride.settingsDump) {
        diff = const ConfigDiff([], 0); // same saved configuration
      } else {
        final before = await archive.loadDump(previous.settingsDump);
        if (before != null) diff = RideAnalysis.configDiff(before, settings);
      }
    }
    final suggestions = RideAnalysis.suggestions(ride,
        previous: previous, diff: diff, settings: settings, unit: unit);
    return RideDetailData(
      ride: ride,
      previous: previous,
      settings: settings,
      diff: diff,
      suggestions: suggestions,
      aiText: RideAnalysis.aiPrompt(ride,
          previous: previous, diff: diff, suggestions: suggestions, unit: unit),
    );
  }
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  late final Future<RideDetailData> _data = RideDetailData.load(
      ref.read(savedFilesStoreProvider), widget.file, widget.unit);

  static const _bg = Color(0xFF080B0E);
  static const _card = Color(0xFF0D1117);
  static const _border = Color(0xFF1A2030);
  static const _muted = Color(0xFF8B949E);
  static const _accent = Color(0xFF00E5FF);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: Text(strings.text(AppText.rideDetailTitle)),
      ),
      body: SafeArea(
        child: FutureBuilder<RideDetailData>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: Text(
                      '${strings.text(AppText.savedOpenFailed)}: ${snap.error}',
                      style: const TextStyle(color: _muted)));
            }
            final data = snap.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content(context, strings, data);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppStrings strings, RideDetailData d) {
    final unit = widget.unit;
    final r = d.ride;
    final date = DateFormat('yyyy-MM-dd HH:mm').format(r.start);
    return ListView(
      key: const ValueKey('ride-detail-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(date,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          [
            _duration(r.duration),
            unit.distance(r.distanceKm, digits: 2),
            '${strings.text(AppText.calloutTopSpeed)} '
                '${unit.speed(r.maxSpeedKph, digits: 1)}',
            'Ø ${unit.speed(r.avgSpeedKph, digits: 1)}',
            '${r.whUsed.toStringAsFixed(0)} Wh',
            if (r.whPerKm != null)
              '${unit.whPerDistanceFromWhPerKm(r.whPerKm!).toStringAsFixed(1)} '
                  '${unit.energyPerDistanceLabel}',
          ].join('  •  '),
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
        if (r.gearSeconds.isNotEmpty || r.boostSeconds >= 1) ...[
          _header(strings.text(AppText.rideGearTime)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in r.gearSeconds.entries)
              _pill('${e.key.replaceFirst('-', ' · ')}  '
                  '${_duration(Duration(seconds: e.value.round()))}'),
            if (r.boostSeconds >= 1)
              _pill(
                  'BST  '
                  '${_duration(Duration(seconds: r.boostSeconds.round()))}',
                  color: const Color(0xFFFFB020)),
          ]),
        ],
        _header(strings.text(AppText.rideSettingsSnapshot)),
        _settingsCard(context, strings, d),
        _header(strings.text(AppText.rideChangesVsPrevious)),
        _changesCard(strings, d),
        _header(strings.text(AppText.rideTelemetry)),
        _calloutsCard(strings, d),
        _header(strings.text(AppText.rideSummary)),
        _box(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in d.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $s',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            const SizedBox(height: 4),
            Text(strings.text(AppText.rideDisclaimer),
                key: const ValueKey('ride-disclaimer'),
                style: const TextStyle(
                    color: _muted, fontSize: 11, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('ride-copy-ai'),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text(strings.text(AppText.rideCopyForAi)),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: d.aiText));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(strings.text(AppText.rideCopiedForAi))));
              },
            ),
          ],
        )),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _settingsCard(
      BuildContext context, AppStrings strings, RideDetailData d) {
    final name = d.ride.settingsDump;
    if (name == null) {
      return _box(Text(strings.text(AppText.rideNoSnapshot),
          style: const TextStyle(color: _muted, fontSize: 13)));
    }
    final settings = d.settings;
    return _box(Row(children: [
      Expanded(
        child: Text(
            settings == null
                ? '$name\n${strings.text(AppText.rideSnapshotMissing)}'
                : name,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
      if (settings != null)
        TextButton(
          key: const ValueKey('ride-view-settings'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  ParameterDumpScreen(dump: settings, unit: widget.unit))),
          child: Text(strings.text(AppText.rideViewSettings)),
        ),
    ]));
  }

  Widget _changesCard(AppStrings strings, RideDetailData d) {
    if (d.previous == null) {
      return _box(Text(strings.text(AppText.rideNoPrevious),
          style: const TextStyle(color: _muted, fontSize: 13)));
    }
    final diff = d.diff;
    if (diff == null) {
      return _box(Text(strings.text(AppText.rideNoSettingsToCompare),
          style: const TextStyle(color: _muted, fontSize: 13)));
    }
    return _box(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (diff.changes.isEmpty)
          Text(strings.text(AppText.rideNoChanges),
              style: const TextStyle(color: _muted, fontSize: 13)),
        for (final c in diff.changes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${c.name}: ',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              TextSpan(
                  text: '${c.before(widget.unit)} → ',
                  style: const TextStyle(color: _muted, fontSize: 13)),
              TextSpan(
                  text: c.after(widget.unit),
                  style: const TextStyle(
                      color: _accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ])),
          ),
        if (diff.unidentifiedChanged > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                strings
                    .text(AppText.rideUnidentifiedChanged)
                    .replaceAll('{n}', '${diff.unidentifiedChanged}'),
                style: const TextStyle(color: _muted, fontSize: 11)),
          ),
      ],
    ));
  }

  Widget _calloutsCard(AppStrings strings, RideDetailData d) {
    final callouts = RideAnalysis.callouts(d.ride, d.previous);
    if (callouts.isEmpty) {
      return _box(const Text('—', style: TextStyle(color: _muted)));
    }
    return _box(Column(children: [
      for (final c in callouts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(strings.text(_calloutText(c.kind)),
                    style: const TextStyle(color: _muted, fontSize: 13))),
            Text(c.value(c.current, widget.unit),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            SizedBox(
              width: 92,
              child: Text(
                _delta(c),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    color: c.notable ? const Color(0xFFFFB020) : _muted,
                    fontWeight: c.notable ? FontWeight.w700 : null),
              ),
            ),
          ]),
        ),
    ]));
  }

  String _delta(Callout c) {
    final d = c.delta;
    if (d == null) return '';
    final sign = d >= 0 ? '+' : '−';
    if (c.kind.relative) {
      return c.previous! > 0
          ? '$sign${(d.abs() / c.previous! * 100).toStringAsFixed(0)} %'
          : '';
    }
    if (c.kind == CalloutKind.topSpeed) {
      return '$sign${widget.unit.fromKph(d.abs()).toStringAsFixed(1)}';
    }
    return '$sign${d.abs().toStringAsFixed(c.kind == CalloutKind.voltageSag ? 1 : 0)}';
  }

  static AppText _calloutText(CalloutKind k) => switch (k) {
        CalloutKind.topSpeed => AppText.calloutTopSpeed,
        CalloutKind.peakLineCurrent => AppText.calloutLineCurrent,
        CalloutKind.peakPhaseCurrent => AppText.calloutPhaseCurrent,
        CalloutKind.voltageSag => AppText.calloutSag,
        CalloutKind.motorTemp => AppText.calloutMotorTemp,
        CalloutKind.controllerTemp => AppText.calloutControllerTemp,
        CalloutKind.avgPower => AppText.calloutAvgPower,
      };

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2)),
      );

  Widget _box(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: child,
      );

  Widget _pill(String text, {Color color = _accent}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12)),
      );

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
