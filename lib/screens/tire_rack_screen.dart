import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/tire_rack.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/providers/units_provider.dart';
import 'package:arcdash/screens/write_screens.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/public_files.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/tire_rack_store.dart';
import 'package:arcdash/services/write/write_allowlist.dart';
import 'package:arcdash/utils/speed_units.dart';

/// Rpm used for the "speed impact" line.
const tireImpactRpm = 4000.0;

/// "at 4000 rpm: 47.1 → 48.0 mph" for moving from [from] to [to].
String tireImpactLine(
    TireSize from, TireSize to, int rateRatio, SpeedUnit unit) {
  final g = rateRatio / 1000.0;
  final a = unit.fromKph(TireRack.kphAt(from, tireImpactRpm, g));
  final b = unit.fromKph(TireRack.kphAt(to, tireImpactRpm, g));
  return 'at ${tireImpactRpm.round()} rpm: ${a.toStringAsFixed(1)} → '
      '${b.toStringAsFixed(1)} ${unit.speedLabel}';
}

class TireRackScreen extends ConsumerStatefulWidget {
  const TireRackScreen({super.key});

  @override
  ConsumerState<TireRackScreen> createState() => _TireRackScreenState();
}

class _TireRackScreenState extends ConsumerState<TireRackScreen> {
  List<TireSize> _custom = [];
  late final TireRackStore _rack =
      TireRackStore(ref.read(savedFilesStoreProvider));

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final c = await _rack.loadCustom();
    if (mounted) setState(() => _custom = c);
  }

  Future<void> _save(List<TireSize> list) async {
    await _rack.saveCustom(list);
    await _reload();
  }

  Future<void> _edit([TireSize? existing]) async {
    final result = await showDialog<TireSize>(
        context: context, builder: (_) => _TireDialog(existing: existing));
    if (result == null) return;
    final list = [
      for (final t in _custom)
        if (t.name != existing?.name && t.name != result.name) t,
      result,
    ];
    await _save(list);
  }

  Future<void> _export() async {
    final store = ref.read(savedFilesStoreProvider);
    final dir = await store.directoryFor(SavedFileKind.tires);
    final file = File('${dir.path}/${TireRackStore.fileName}');
    if (!await file.exists()) await _rack.saveCustom(_custom);
    if (!mounted) return;
    await ParameterDumpIo.shareSavedFile(context, file,
        subject: 'FarSure tire rack', copiedMessage: 'Tire rack copied');
  }

  Future<void> _import() async {
    final msg =
        await PublicFiles.importWithPicker(ref.read(savedFilesStoreProvider));
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _reload();
  }

  void _apply(TireSize tire, TireSize current, int rateRatio) {
    final unit = ref.read(speedUnitProvider);
    startControllerWrite(context, ref,
        title: 'Tire size ${tire.name} (${tire.code})',
        values: {
          'WheelWidth': tire.widthMm,
          'WheelRatio': tire.ratioPct,
          'WheelRadius': tire.rimInch,
        },
        notes: [
          'Speed shown by the controller and app '
              '${tireImpactLine(current, tire, rateRatio, unit)}.',
          'Outer diameter ${current.diameterMm.toStringAsFixed(0)} → '
              '${tire.diameterMm.toStringAsFixed(0)} mm.',
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(controllerProvider);
    final unit = ref.watch(speedUnitProvider);
    final current = TireSize(
        name: 'Current',
        widthMm: s.wheelWidth,
        ratioPct: s.wheelRatio,
        rimInch: s.wheelRadius);
    Widget tile(TireSize t, {bool custom = false}) => ListTile(
          key: ValueKey('tire-${t.name}'),
          title: Text(t.name),
          subtitle: Text('${t.code} · '
              '${tireImpactLine(current, t, s.rateRatio, unit)}'),
          trailing: custom
              ? PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') await _edit(t);
                    if (v == 'delete') {
                      await _save([
                        for (final x in _custom)
                          if (x.name != t.name) x
                      ]);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                )
              : null,
          onTap: () => _apply(t, current, s.rateRatio),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Tire rack'), actions: [
        IconButton(
            tooltip: 'Import',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _import),
        IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onPressed: _export),
      ]),
      floatingActionButton: FloatingActionButton(
          tooltip: 'Add tire',
          onPressed: () => _edit(),
          child: const Icon(Icons.add)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            ListTile(
              title: const Text('On the controller now'),
              subtitle: Text('${current.code} · '
                  '${WriteAllowlist.gearRatioLabel(s.rateRatio)}'),
            ),
            const Divider(),
            if (_custom.isNotEmpty) ...[
              const ListTile(dense: true, title: Text('Your tires')),
              for (final t in _custom) tile(t, custom: true),
              const Divider(),
            ],
            const ListTile(dense: true, title: Text('Presets')),
            for (final t in TireRack.presets) tile(t),
          ],
        ),
      ),
    );
  }
}

class _TireDialog extends StatefulWidget {
  const _TireDialog({this.existing});
  final TireSize? existing;

  @override
  State<_TireDialog> createState() => _TireDialogState();
}

class _TireDialogState extends State<_TireDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _w =
      TextEditingController(text: widget.existing?.widthMm.toString() ?? '');
  late final _r =
      TextEditingController(text: widget.existing?.ratioPct.toString() ?? '');
  late final _rim =
      TextEditingController(text: widget.existing?.rimInch.toString() ?? '');
  String? _error;

  void _ok() {
    final w = int.tryParse(_w.text.trim());
    final r = int.tryParse(_r.text.trim());
    final rim = int.tryParse(_rim.text.trim());
    final name = _name.text.trim();
    if (name.isEmpty || w == null || r == null || rim == null ||
        !TireSize.valid(w, r, rim)) {
      setState(() => _error =
          'Width 40–255 mm, ratio 20–120 %, rim 4–24 inch, and a name.');
      return;
    }
    Navigator.of(context)
        .pop(TireSize(name: name, widthMm: w, ratioPct: r, rimInch: rim));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {bool number = true}) =>
        TextField(
            controller: c,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: label));
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add tire' : 'Edit tire'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        field(_name, 'Name', number: false),
        field(_w, 'Width (mm)'),
        field(_r, 'Aspect ratio (%)'),
        field(_rim, 'Rim (inch, whole)'),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: const Text('Save')),
      ],
    );
  }
}
