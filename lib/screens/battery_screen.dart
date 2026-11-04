import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/battery_plan.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/write_screens.dart';
import 'package:arcdash/services/write/write_allowlist.dart';

class BatteryScreen extends ConsumerStatefulWidget {
  const BatteryScreen({super.key});

  @override
  ConsumerState<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends ConsumerState<BatteryScreen> {
  Chemistry _chem = Chemistry.nmc;
  int _cells = 24;
  int _ah = 45;

  String _current(String key) {
    final f = WriteAllowlist.byKey(key);
    if (f == null) return '—';
    final block =
        ref.read(controllerProvider.notifier).latestBlocks[f.def.block];
    return block == null ? 'not read yet' : f.format(f.readRaw(block));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(controllerProvider); // refresh current values
    final plan = BatteryPlan(_chem, _cells, _ah);
    final raw = plan.suggestedRaw();
    final refusal = plan.refusal(raw);
    return Scaffold(
      appBar: AppBar(title: const Text('Battery')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<Chemistry>(
              showSelectedIcon: false,
              segments: [
                for (final c in Chemistry.values)
                  ButtonSegment(value: c, label: Text(c.label)),
              ],
              selected: {_chem},
              onSelectionChanged: (s) => setState(() => _chem = s.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Cells in series'),
              const Spacer(),
              IconButton(
                  onPressed: () => setState(() => _cells =
                      (_cells - 1).clamp(BatteryPlan.minCells, BatteryPlan.maxCells)),
                  icon: const Icon(Icons.remove)),
              Text('${_cells}S'),
              IconButton(
                  onPressed: () => setState(() => _cells =
                      (_cells + 1).clamp(BatteryPlan.minCells, BatteryPlan.maxCells)),
                  icon: const Icon(Icons.add)),
            ]),
            Row(children: [
              const Text('Capacity'),
              const Spacer(),
              IconButton(
                  onPressed: () =>
                      setState(() => _ah = (_ah - 1).clamp(20, 250)),
                  icon: const Icon(Icons.remove)),
              Text('$_ah Ah'),
              IconButton(
                  onPressed: () =>
                      setState(() => _ah = (_ah + 1).clamp(20, 250)),
                  icon: const Icon(Icons.add)),
            ]),
            const Divider(),
            const Text('Suggested (you review before anything is written):'),
            for (final line in plan.math)
              Padding(
                  padding: const EdgeInsets.only(top: 4), child: Text(line)),
            const Divider(),
            const Text('On the controller now:'),
            for (final k in const [
              'LowVolProtect',
              'HighVolProtect',
              'HighVolRestore',
              'BattRatedCap'
            ])
              _CurrentRow(
                  field: WriteAllowlist.byKey(k), label: k, value: _current(k)),
            if (refusal != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(refusal,
                    style: const TextStyle(color: Color(0xFFFF6B6B))),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('battery-review'),
              onPressed: refusal != null
                  ? null
                  : () => startControllerWrite(context, ref,
                      values: raw,
                      title: 'Battery ${_chem.label} ${_cells}S $_ah Ah',
                      notes: plan.math),
              child: const Text('Review and write'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "on the controller now" line; read-only fields are greyed with a
/// note (v1.4: over voltage protect/restore).
class _CurrentRow extends StatelessWidget {
  const _CurrentRow(
      {required this.field, required this.label, required this.value});

  final WritableField? field;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final f = field;
    final readOnly = f?.readOnly ?? false;
    return Padding(
      key: ValueKey('battery-current-$label'),
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '${f?.label ?? label}: $value'
        '${readOnly ? '\n   ${WritableField.readOnlyNote}' : ''}',
        style: readOnly ? const TextStyle(color: Colors.white38) : null,
      ),
    );
  }
}
