import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';

/// Loads the latest saved live snapshot, falling back to the in-memory one.
Future<ParameterDump?> loadLiveParameterDump(WidgetRef ref) async {
  final storage = ref.read(storageServiceProvider);
  final saved = await ParameterDumpIo.loadLive(storage.parameterSnapshots);
  if (saved != null) return saved;
  final latest = ref.read(parameterCaptureProvider).latest;
  return latest == null ? null : ParameterCaptureService.toDump(latest);
}

/// Compare two dumps (live snapshot, .heb or ArcDash CSV). Read-only.
class ParameterCompareScreen extends ConsumerStatefulWidget {
  const ParameterCompareScreen({super.key});

  @override
  ConsumerState<ParameterCompareScreen> createState() =>
      _ParameterCompareScreenState();
}

class _ParameterCompareScreenState
    extends ConsumerState<ParameterCompareScreen> {
  ParameterDump? _a;
  ParameterDump? _b;
  bool _showAll = false;

  Future<void> _load(bool isA, bool live) async {
    final strings = AppStrings.of(context);
    try {
      final dump = live
          ? await loadLiveParameterDump(ref)
          : await ParameterDumpIo.pickAndParse();
      if (!mounted) return;
      if (dump == null) {
        if (live) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(strings.text(AppText.paramNoSnapshot))));
        }
        return;
      }
      setState(() => isA ? _a = dump : _b = dump);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${strings.text(AppText.paramLoadFailed)}: $e')));
    }
  }

  Future<void> _share() async {
    final a = _a, b = _b;
    if (a == null || b == null) return;
    final strings = AppStrings.of(context);
    final csv = ParameterDiff.toCsv(a, b,
        showAll: _showAll, appVersion: await ParameterDumpIo.appVersion());
    if (!mounted) return;
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    await ParameterDumpIo.shareOrCopy(
      context,
      text: csv,
      fileName: 'arcdash_param_diff_$stamp.csv',
      subject: 'ArcDash FarDriver parameter comparison',
      copiedMessage: strings.text(AppText.paramCopied),
    );
  }

  Widget _slot(String title, ParameterDump? dump, bool isA) {
    final strings = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(dump == null
                ? '—'
                : '${dump.sourceLabel}'
                    '${dump.capturedAt == null ? '' : ' · ${dump.capturedAt!.toLocal()}'}'),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                icon: const Icon(Icons.memory),
                label: Text(strings.text(AppText.paramSourceLive)),
                onPressed: () => _load(isA, true),
              ),
              TextButton.icon(
                icon: const Icon(Icons.folder_open),
                label: Text(strings.text(AppText.paramSourceFile)),
                onPressed: () => _load(isA, false),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final a = _a, b = _b;
    final entries = a != null && b != null
        ? ParameterDiff.compare(a, b, showAll: _showAll)
        : const <ParameterDiffEntry>[];
    final changed =
        entries.where((e) => e.change == ParameterChange.changed).length;
    final oneSide = entries
        .where((e) =>
            e.change == ParameterChange.onlyA ||
            e.change == ParameterChange.onlyB)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text(AppText.paramCompare)),
        actions: [
          IconButton(
            tooltip: strings.text(AppText.paramShareDiff),
            icon: const Icon(Icons.share),
            onPressed: a != null && b != null ? _share : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _slot(strings.text(AppText.paramSourceA), a, true),
            _slot(strings.text(AppText.paramSourceB), b, false),
            if (a != null && b != null) ...[
              SwitchListTile(
                dense: true,
                title: Text('${strings.text(AppText.paramDifferences)}: '
                    '$changed${oneSide > 0 ? ' (+$oneSide ${strings.text(AppText.paramOnlyOneSide)})' : ''}'),
                subtitle: Text(strings.text(AppText.paramShowAll)),
                value: _showAll,
                onChanged: (v) => setState(() => _showAll = v),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(strings.text(AppText.paramNoDifferences)))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final e = entries[index];
                          final unit =
                              e.def.unit.isEmpty ? '' : ' ${e.def.unit}';
                          String show(DecodedParameter? p) => p == null
                              ? '—'
                              : p.label.isEmpty
                                  ? '${p.value}$unit'
                                  : '${p.label} (${p.value})';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              switch (e.change) {
                                ParameterChange.changed => Icons.compare_arrows,
                                ParameterChange.same => Icons.check,
                                _ => Icons.remove_circle_outline,
                              },
                              color: e.change == ParameterChange.changed
                                  ? Colors.amber
                                  : Colors.white54,
                            ),
                            title: Text(e.def.name),
                            subtitle: Text(
                                '${hexByte(e.def.block)} · w${hexByte(e.def.wordAddress)} · ${e.changeLabel}'),
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 190),
                              child: Text(
                                '${strings.text(AppText.paramOld)}: ${show(e.a)}\n'
                                '${strings.text(AppText.paramNew)}: ${show(e.b)}',
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
