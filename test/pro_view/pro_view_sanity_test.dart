import 'dart:io';

import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/pro_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders dumpE (2026-11-02) through the Pro view and compares every pro
/// page value with FarDriver's own screens (screens_transcribed.csv, from the
/// 2026-10-22 screenshots). Mismatches are printed, never failed: some
/// settings legitimately changed between the two captures.
void main() {
  test('Pro view of dumpE vs FarDriver screens (report only)', () {
    final dump = ParameterCsvCodec.decode(
        File('test/fixtures/pro_view/dumpE.csv').readAsStringSync(),
        fileName: 'dumpE.csv');
    final view = ProView.build(dump);
    final rows = FlatCsv.decode(
        File('test/fixtures/pro_view/screens_transcribed.csv')
            .readAsStringSync());
    var compared = 0, matched = 0;
    final mismatches = <String>[];
    final regenSeen = <String, int>{};
    for (final row in rows.skip(1)) {
      if (row.length < 4 || !row[0].startsWith('pro_p')) continue;
      final section = row[1];
      var label = row[2];
      final expected = row[3];
      if (label.startsWith('Regen ')) label = label.substring(6);
      final title = section == 'ModelType' ? 'ModelType' : '- $section';
      final ProViewCell? cell;
      if (section == 'Energy Regenerate' && label.endsWith('RPM')) {
        final n = regenSeen[label] = (regenSeen[label] ?? 0) + 1;
        cell = view.sections
            .firstWhere((s) => s.title == title)
            .cells
            .whereType<ProViewCell>()
            .where((c) => c.label == label)
            .elementAtOrNull(n - 1);
      } else {
        cell = view.find(label, section: title);
      }
      compared++;
      if (cell == null) {
        mismatches.add('$section / $label: missing (screen $expected)');
      } else if (cell.value == expected) {
        matched++;
      } else {
        mismatches.add('$section / $label: pro "${cell.value}" vs screen '
            '"$expected"${cell.uncertain ? ' [uncertain]' : ''}');
      }
    }
    // ignore: avoid_print
    print(
        'Pro view sanity: $matched/$compared match\n${mismatches.join('\n')}');
    expect(compared, greaterThan(200));
    expect(matched, greaterThan(compared * 0.85));
  });
}
