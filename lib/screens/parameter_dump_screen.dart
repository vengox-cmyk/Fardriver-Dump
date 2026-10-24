import 'package:flutter/material.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';

/// Read-only list of every decoded parameter in a dump, with CSV export.
class ParameterDumpScreen extends StatefulWidget {
  final ParameterDump dump;

  const ParameterDumpScreen({super.key, required this.dump});

  @override
  State<ParameterDumpScreen> createState() => _ParameterDumpScreenState();
}

class _ParameterDumpScreenState extends State<ParameterDumpScreen> {
  late final List<DecodedParameter> _all = widget.dump.decode();
  String _query = '';

  Future<void> _share() async {
    final strings = AppStrings.of(context);
    final dump = widget.dump;
    final String csv;
    try {
      csv = ParameterCsvCodec.encode(dump,
          appVersion: await ParameterDumpIo.appVersion());
    } on IncompleteSnapshotException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${strings.text(AppText.paramIncomplete)}: '
              '${e.missingBlocks.map(hexByte).join(' ')}')));
      return;
    }
    if (!mounted) return;
    final stamp = (dump.capturedAt ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    await ParameterDumpIo.shareOrCopy(
      context,
      text: csv,
      fileName: ParameterDumpIo.safeFileName(
          'arcdash_params_${dump.source.name}_$stamp.csv'),
      subject: 'ArcDash FarDriver parameters',
      copiedMessage: strings.text(AppText.paramCopied),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final dump = widget.dump;
    final q = _query.toLowerCase();
    final rows = q.isEmpty
        ? _all
        : _all
            .where((p) =>
                p.def.name.toLowerCase().contains(q) ||
                hexByte(p.def.block).toLowerCase().contains(q) ||
                hexByte(p.def.wordAddress).toLowerCase().contains(q))
            .toList();
    final missing = dump.missingBlocks;
    return Scaffold(
      appBar: AppBar(
        title: Text(dump.sourceLabel, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: strings.text(AppText.paramShareCsv),
            icon: const Icon(Icons.share),
            onPressed: _share,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dump.controllerId.isNotEmpty)
                    Text('ID: ${dump.controllerId}'),
                  if (dump.capturedAt != null)
                    Text(dump.capturedAt!.toLocal().toString()),
                  Text('${_all.length} / ${dump.blocks.length} blocks'
                      '${missing.isEmpty ? '' : ' · missing ${missing.map(hexByte).join(' ')}'}'),
                  const SizedBox(height: 4),
                  Text(strings.text(AppText.paramUnverifiedHint),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.amber)),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: strings.text(AppText.paramSearch),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final p = rows[index];
                  return ListTile(
                    dense: true,
                    title: Text(p.def.name,
                        style: TextStyle(
                            color: p.def.unknown ? Colors.white54 : null)),
                    subtitle: Text(
                        '${hexByte(p.def.block)} · w${hexByte(p.def.wordAddress)}'
                        ' · byte ${p.def.byteOffset} bits ${p.def.bitsLabel}'
                        ' · raw ${p.raw} · ${p.def.status}'),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(p.display,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
