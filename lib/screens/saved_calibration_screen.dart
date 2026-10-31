import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/screens/speed_calibration_results.dart';
import 'package:arcdash/services/calibration_archive.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/parameter_dump_io.dart';

/// A calibration ride reopened from Saved files: the same results screen,
/// computed from the saved samples with the settings saved alongside them.
/// Nothing needs the controller. DKD readings typed here are written back
/// into the same file.
class SavedCalibrationScreen extends StatefulWidget {
  const SavedCalibrationScreen({super.key, required this.file});

  final File file;

  @override
  State<SavedCalibrationScreen> createState() => _SavedCalibrationScreenState();
}

class _SavedCalibrationScreenState extends State<SavedCalibrationScreen> {
  SavedCalibration? _saved;
  CalibrationSessionState? _session;
  Object? _error;
  Timer? _debounce;
  Future<void> _writing = Future.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = CalibrationCsv.parse(await widget.file.readAsString());
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _session = saved.toSessionState();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(_write());
    }
    super.dispose();
  }

  void _updateDkd(List<DkdSnapshot> snapshots) {
    final session = _session;
    if (session == null) return;
    setState(() => _session = session.copyWith(dkdSnapshots: snapshots));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _write);
  }

  Future<void> _write() {
    final saved = _saved, session = _session;
    if (saved == null || session == null) return Future.value();
    final dkd = session.dkdSnapshots;
    _writing = _writing.then((_) async {
      try {
        await CalibrationArchive.rewrite(widget.file, saved,
            dkdSnapshots: dkd, appVersion: await ParameterDumpIo.appVersion());
      } catch (e) {
        debugPrint('Updating saved calibration failed: $e');
      }
    });
    return _writing;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = _session;
    final saved = _saved;
    return Scaffold(
      appBar: AppBar(
          title:
              Text(strings.text(AppText.savedCalibrationTitle).toUpperCase())),
      body: SafeArea(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child:
                    Text('${strings.text(AppText.savedOpenFailed)}: $_error'),
              )
            : session == null || saved == null
                ? const Center(child: CircularProgressIndicator())
                : SpeedCalibrationResults(
                    session: session,
                    settingsOverride: saved.settings,
                    savedFile: widget.file,
                    interrupted: saved.status == CalibrationCsv.statusRecording,
                    onDkdChanged: (i, kph) {
                      final list = [...session.dkdSnapshots];
                      if (i < 0 || i >= list.length) return;
                      list[i] = list[i].withReading(kph);
                      _updateDkd(list);
                    },
                    onDkdRemove: (i) {
                      final list = [...session.dkdSnapshots];
                      if (i < 0 || i >= list.length) return;
                      list.removeAt(i);
                      _updateDkd(list);
                    },
                  ),
      ),
    );
  }
}
