import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/screens/parameter_dump_screen.dart';
import 'package:arcdash/screens/saved_calibration_screen.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/saved_files.dart';

/// Settings → Data management → Saved files.
///
/// Everything FarSure keeps on the phone (calibration rides, parameter
/// dumps, diagnostic logs, ride CSVs), grouped by type, newest first.
/// Works offline: nothing here needs the controller.
class SavedFilesScreen extends ConsumerStatefulWidget {
  const SavedFilesScreen({super.key});

  @override
  ConsumerState<SavedFilesScreen> createState() => _SavedFilesScreenState();
}

class _SavedFilesScreenState extends ConsumerState<SavedFilesScreen> {
  late Future<_Listing> _listing = _load();

  Future<_Listing> _load() async {
    final store = ref.read(savedFilesStoreProvider);
    final entries = await store.list();
    String? location;
    try {
      location = (await store.root()).path;
    } on Object {
      location = null;
    }
    return _Listing(entries, location);
  }

  void _reload() {
    final next = _load();
    setState(() {
      _listing = next;
    });
  }

  String _kindTitle(AppStrings strings, SavedFileKind kind) =>
      strings.text(switch (kind) {
        SavedFileKind.calibration => AppText.savedCalibrations,
        SavedFileKind.dump => AppText.savedDumps,
        SavedFileKind.diagnosticLog => AppText.savedLogs,
        SavedFileKind.rideCsv => AppText.savedRides,
      });

  IconData _icon(SavedFileKind kind) => switch (kind) {
        SavedFileKind.calibration => Icons.speed,
        SavedFileKind.dump => Icons.table_chart_outlined,
        SavedFileKind.diagnosticLog => Icons.receipt_long_outlined,
        SavedFileKind.rideCsv => Icons.route_outlined,
      };

  Future<bool> _confirm(String title, String body) async {
    final strings = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              key: const ValueKey('saved-delete-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.text(AppText.cancel))),
          FilledButton(
              key: const ValueKey('saved-delete-confirm'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B6B)),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.text(AppText.savedDelete))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete(SavedFileEntry entry) async {
    final strings = AppStrings.of(context);
    if (!await _confirm(strings.text(AppText.savedDeleteQuestion),
        '${entry.name}\n\n${strings.text(AppText.savedDeleteBody)}')) {
      return;
    }
    await ref.read(savedFilesStoreProvider).delete(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text(AppText.savedDeleted))));
    _reload();
  }

  Future<void> _deleteAll() async {
    final strings = AppStrings.of(context);
    if (!await _confirm(strings.text(AppText.savedDeleteAllQuestion),
        strings.text(AppText.savedDeleteAllBody))) {
      return;
    }
    await ref.read(savedFilesStoreProvider).deleteAll();
    if (mounted) _reload();
  }

  Future<void> _share(SavedFileEntry entry) => ParameterDumpIo.shareSavedFile(
        context,
        entry.file,
        subject: 'FarSure ${entry.name}',
        copiedMessage: AppStrings.of(context).text(AppText.paramCopied),
      );

  Future<void> _open(SavedFileEntry entry) async {
    final strings = AppStrings.of(context);
    try {
      final Widget page;
      switch (entry.kind) {
        case SavedFileKind.calibration:
          page = SavedCalibrationScreen(file: entry.file);
        case SavedFileKind.dump:
          final dump = ParameterDumpIo.parseFile(
              await entry.file.readAsBytes(), entry.name);
          page = ParameterDumpScreen(dump: dump, savedFile: entry.file);
        case SavedFileKind.diagnosticLog:
        case SavedFileKind.rideCsv:
          page = _TextFileScreen(
              title: entry.name, text: await entry.file.readAsString());
      }
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
      if (mounted) _reload(); // DKD edits update the list entry
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${strings.text(AppText.savedOpenFailed)}: $e')));
    }
  }

  String _subtitle(AppStrings strings, SavedFileEntry e) {
    final parts = <String>[_formatTime(e.time)];
    final info = e.info;
    switch (e.kind) {
      case SavedFileKind.calibration:
        final confidence = info['confidence'];
        parts.add(confidence == null || confidence.isEmpty
            ? strings.text(AppText.savedNoFit)
            : '${strings.text(AppText.savedConfidence)} $confidence');
        final gear = info['suggested_GearRatio'];
        if (gear != null && gear.isNotEmpty) {
          parts.add('${strings.text(AppText.savedSuggestedGearRatio)} $gear');
        }
        final samples = info['samples'];
        if (samples != null && samples.isNotEmpty) parts.add('$samples s');
        if (info['status'] == 'recording') {
          parts.add(strings.text(AppText.savedInterrupted));
        }
      case SavedFileKind.dump:
        final id = info['controller_id'];
        parts.add('${strings.text(AppText.savedController)} '
            '${id == null || id.isEmpty ? '—' : id}');
        final source = info['source'];
        if (source != null && source.isNotEmpty) {
          parts.add('${strings.text(AppText.savedSource)} $source');
        }
      case SavedFileKind.diagnosticLog:
      case SavedFileKind.rideCsv:
        break;
    }
    parts.add(_formatSize(e.sizeBytes));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<_Listing>(
      future: _listing,
      builder: (context, snapshot) {
        final listing = snapshot.data;
        final entries = listing?.entries ?? const <SavedFileEntry>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(strings.text(AppText.savedFiles).toUpperCase()),
            actions: [
              IconButton(
                key: const ValueKey('saved-delete-all'),
                tooltip: strings.text(AppText.savedDeleteAll),
                onPressed: entries.isEmpty ? null : _deleteAll,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: snapshot.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      key: const ValueKey('saved-files-list'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(strings.text(AppText.savedFilesHint),
                              style: const TextStyle(color: Colors.white70)),
                        ),
                        if (snapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                                '${strings.text(AppText.savedOpenFailed)}: ${snapshot.error}',
                                style:
                                    const TextStyle(color: Color(0xFFFFB45C))),
                          ),
                        if (entries.isEmpty && !snapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(strings.text(AppText.savedFilesEmpty),
                                  key: const ValueKey('saved-files-empty')),
                            ),
                          ),
                        for (final kind in SavedFileKind.values)
                          ..._section(strings, kind,
                              entries.where((e) => e.kind == kind).toList()),
                        if (listing?.location != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                            child: Text(
                              '${strings.text(AppText.savedFilesLocation)} '
                              '${listing!.location}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white54),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  List<Widget> _section(
      AppStrings strings, SavedFileKind kind, List<SavedFileEntry> entries) {
    if (entries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text(
          '${_kindTitle(strings, kind).toUpperCase()}  (${entries.length})',
          key: ValueKey('saved-section-${kind.name}'),
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.white70),
        ),
      ),
      for (final e in entries)
        Card(
          child: ListTile(
            key: ValueKey('saved-file-${e.name}'),
            leading: Icon(_icon(e.kind)),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_subtitle(strings, e)),
            onTap: () => _open(e),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey('saved-share-${e.name}'),
                  tooltip: strings.text(AppText.savedShare),
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _share(e),
                ),
                IconButton(
                  key: ValueKey('saved-delete-${e.name}'),
                  tooltip: strings.text(AppText.savedDelete),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(e),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _Listing {
  const _Listing(this.entries, this.location);
  final List<SavedFileEntry> entries;
  final String? location;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Local date and time, e.g. `2026-10-31 15:45`.
String _formatTime(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} '
      '${_two(l.hour)}:${_two(l.minute)}';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Plain viewer for diagnostic logs and ride CSVs.
class _TextFileScreen extends StatelessWidget {
  const _TextFileScreen({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(text,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
        ),
      );
}
