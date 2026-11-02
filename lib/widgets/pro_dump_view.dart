import 'package:flutter/material.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/pro_view.dart';

/// FarDriver pro-mode layout of a saved dump: grey section bars with centred
/// titles, then two columns of "Label:value". Read-only; built lazily row by
/// row so a full dump stays cheap on a small phone.
class ProDumpView extends StatelessWidget {
  const ProDumpView({super.key, required this.view});

  final ProView view;

  static const _bar = Color(0xFF1C222B);
  static const _title = Color(0xFFC8874E); // FarDriver's brown, lifted for dark
  static const _label = Color(0xFFE6EDF3);
  static const _accent = Color(0xFF00E5FF);
  static const _muted = Color(0xFF8B949E);

  @override
  Widget build(BuildContext context) {
    // Flat item list: 0 = hint, 1 = ModelType bar, 2 = ModelType block, then
    // per section one bar and its two-column rows.
    final items = <_Item>[
      const _Item.hint(),
      const _Item.bar(ProView.modelTypeTitle),
      const _Item.header(),
      for (final s in view.sections) ...[
        _Item.bar(s.title),
        for (var r = 0; r < s.rowCount; r++) _Item.row(s, r),
      ],
    ];
    return ListView.builder(
      key: const ValueKey('pro-view-list'),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        switch (item.kind) {
          case _Kind.hint:
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Text(AppStrings.of(context).text(AppText.paramProHint),
                  style: const TextStyle(fontSize: 11, color: Colors.amber)),
            );
          case _Kind.bar:
            return _SectionBar(item.title!);
          case _Kind.header:
            return _ModelTypeBlock(view.header);
          case _Kind.row:
            final s = item.section!;
            final left = s.cells[item.row * 2];
            final right = item.row * 2 + 1 < s.cells.length
                ? s.cells[item.row * 2 + 1]
                : null;
            final grey = s.title == '- DateTime';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ProCellText(left, grey: grey)),
                  const SizedBox(width: 8),
                  Expanded(child: _ProCellText(right, grey: grey)),
                ],
              ),
            );
        }
      },
    );
  }
}

enum _Kind { hint, bar, header, row }

class _Item {
  const _Item.hint()
      : kind = _Kind.hint,
        title = null,
        section = null,
        row = 0;
  const _Item.bar(this.title)
      : kind = _Kind.bar,
        section = null,
        row = 0;
  const _Item.header()
      : kind = _Kind.header,
        title = null,
        section = null,
        row = 0;
  const _Item.row(this.section, this.row)
      : kind = _Kind.row,
        title = null;

  final _Kind kind;
  final String? title;
  final ProViewSection? section;
  final int row;
}

class _SectionBar extends StatelessWidget {
  const _SectionBar(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('pro-section-$title'),
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: ProDumpView._bar,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(title,
          style: const TextStyle(
              color: ProDumpView._title,
              fontSize: 17,
              fontWeight: FontWeight.w500)),
    );
  }
}

void _explain(BuildContext context, ProViewCell cell) {
  if (cell.note.isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('${cell.label}: ${cell.note}')));
}

class _ProCellText extends StatelessWidget {
  const _ProCellText(this.cell,
      {this.grey = false, this.color, this.size = 13.5, this.bold = false});

  final ProViewCell? cell;
  final bool grey;
  final Color? color;
  final double size;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = cell;
    if (c == null) return const SizedBox.shrink();
    final text = Text.rich(
      TextSpan(children: [
        TextSpan(text: c.text),
        if (c.uncertain)
          const TextSpan(
              text: ' *', style: TextStyle(color: Colors.amber, fontSize: 11)),
      ]),
      key: ValueKey('pro-cell-${c.label}'),
      style: TextStyle(
        color: color ?? (grey ? ProDumpView._muted : ProDumpView._label),
        fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    if (c.note.isEmpty) return text;
    return GestureDetector(
        onLongPress: () => _explain(context, c), child: text);
  }
}

/// FarDriver's ModelType block: logo box, model/voltage/current lines, the
/// bold ProductCode, then CostumCode and MorseCode side by side.
class _ModelTypeBlock extends StatelessWidget {
  const _ModelTypeBlock(this.header);

  final ProViewHeader header;

  @override
  Widget build(BuildContext context) {
    final model = header.modelTyp;
    return Padding(
      key: const ValueKey('pro-model-type'),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: const Text('FarDrive',
                  style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            const SizedBox(width: 6),
            const Text('Motor FOC\nController',
                style: TextStyle(color: ProDumpView._label, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          GestureDetector(
            onLongPress: () => _explain(context, model),
            child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${model.label}   '),
                  TextSpan(
                      text: model.value,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (model.uncertain)
                    const TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.amber, fontSize: 11)),
                ]),
                key: const ValueKey('pro-cell-ModelTyp'),
                style:
                    const TextStyle(color: ProDumpView._label, fontSize: 13.5)),
          ),
          _ProCellText(_spaced(header.voltagePower)),
          _ProCellText(_spaced(header.lineCurrPhaseCurr)),
          const SizedBox(height: 4),
          _ProCellText(header.productCode, size: 18, bold: true),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: _ProCellText(header.costumCode,
                    color: ProDumpView._accent, size: 15)),
            Expanded(
                child: _ProCellText(header.morseCode,
                    color: ProDumpView._accent, size: 15)),
          ]),
        ],
      ),
    );
  }

  /// FarDriver writes "Voltage/Power  96V15000W" with a gap, no colon.
  static ProViewCell _spaced(ProViewCell c) => ProViewCell(c.label, c.value,
      uncertain: c.uncertain, colon: false, note: c.note);
}
