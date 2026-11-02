import 'dart:io';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/screens/parameter_dump_screen.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/pro_view.dart';
import 'package:arcdash/utils/speed_units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ParameterDump _dumpE() => ParameterCsvCodec.decode(
    File('test/fixtures/pro_view/dumpE.csv').readAsStringSync(),
    fileName: 'dumpE.csv');

Widget _app(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: home,
      ),
    );

void main() {
  group('ProView model', () {
    final view = ProView.build(_dumpE());

    test('sections follow FarDriver pro_p1..p8 order', () {
      expect(view.sections.map((s) => s.title).toList(), [
        '- DateTime',
        '- Parameters',
        '- Ratios in Speed',
        '- Ratios in Gear',
        '- Energy Regenerate',
        '- Functions',
        '- Display',
        '- Protect',
        '- PID Paras',
        '- Product',
        '- FixedParas',
        'Not on FarDriver screens',
      ]);
    });

    test('ModelType block reads like FarDriver', () {
      expect(view.header.voltagePower.value, '96V15000W');
      expect(view.header.lineCurrPhaseCurr.value, '250A/600A');
      expect(view.header.costumCode.value, 'ND');
      expect(view.header.morseCode.value, '000000');
      expect(view.header.productCode.value, isNot('—'));
      expect(view.header.modelTyp.value, startsWith('ND961000_34_'));
      expect(view.header.modelTyp.uncertain, isTrue);
    });

    test('first Parameters rows in screen order with FarDriver labels', () {
      final p = view.sections[1].cells;
      expect(p.take(6).map((c) => c!.label).toList(), [
        'AngleDetect',
        'TempSensor',
        'PhaseOffset',
        'PolePairs',
        'Motor Direction',
        'RatedSpeed',
      ]);
      expect(view.find('TempSensor')!.value, '6-NTC10K');
      expect(view.find('Throttle Low')!.text, 'Throttle Low:1.1V');
      expect(view.find('Throttle High')!.text, 'Throttle High:3.65V');
      expect(view.find('ThrottleResponse')!.value, '0-Line');
      expect(view.find('AngleDetect')!.uncertain, isTrue);
    });

    test('ratio rows have no colon; regen rows carry the marker', () {
      final speed = view.find('500RPM', section: '- Ratios in Speed')!;
      expect(speed.text, '500RPM 100%');
      expect(speed.uncertain, isFalse);
      final regen = view.find('500RPM', section: '- Energy Regenerate')!;
      expect(regen.text, '500RPM 0%');
      expect(regen.uncertain, isTrue);
    });

    test('empty slots where FarDriver leaves one', () {
      final regen = view.sections[4].cells;
      expect(regen[2]!.label, 'Batt RatedCapacity');
      expect(regen[3], isNull);
      final functions = view.sections[5].cells;
      expect(functions[functions.indexWhere((c) => c?.label == 'Gear') + 1],
          isNull);
    });

    test('pins use FarDriver UI index-name', () {
      expect(ProView.pin(4), '8-PIN17');
      expect(ProView.pin(15), '13-Invalid');
      expect(ProView.pin(0), '0-NC');
      expect(ProView.pin(9), '13-Invalid');
      expect(view.find('Boost Pin')!.value, '8-PIN17');
    });

    test('enum and unit quirks', () {
      expect(view.find('LM')!.value, endsWith('en-US'));
      expect(view.find('Gear')!.value, '1-Default D');
      expect(view.find('Follow')!.value, '1-Disabled');
      expect(view.find('CAN Baud')!.value, '0-250K');
      expect(view.find('FollowSpeed')!.value, endsWith('rpm'));
      expect(view.find('LowVolRestore')!.value, '65V');
      expect(view.find('Batt RatedCapacity')!.value, '45AH');
    });

    test('every catalog field appears exactly once (screens or extra)', () {
      final extra = view.sections.last;
      expect(extra.extra, isTrue);
      expect(extra.cells.map((c) => c!.label), contains('DistanceLSB'));
      expect(extra.cells.map((c) => c!.label), isNot(contains('MaxLineCurr')));
    });

    test('mph adds a conversion beside the native value (display only)', () {
      final km = ProView.build(_dumpE());
      final mph = ProView.build(_dumpE(), unit: SpeedUnit.mph);
      final kmOdo = km.find('DistanceLSB', section: ProView.extraTitle)!;
      final mphOdo = mph.find('DistanceLSB', section: ProView.extraTitle)!;
      expect(kmOdo.value, endsWith(' km'));
      expect(mphOdo.value, startsWith(kmOdo.value));
      expect(mphOdo.value, contains(' · '));
      expect(mphOdo.value, endsWith(' mi'));
      // Pro pages themselves are untouched.
      expect(mph.find('RatedSpeed')!.value, km.find('RatedSpeed')!.value);
    });

    test('missing blocks show a dash instead of failing', () {
      final full = _dumpE();
      final partial = ParameterDump(
          source: full.source,
          sourceLabel: 'partial',
          requiredBlocks: full.requiredBlocks,
          blocks: Map.of(full.blocks)
            ..remove(0xA0)
            ..remove(0x12));
      final v = ProView.build(partial);
      expect(v.header.productCode.value, '—');
      expect(v.header.voltagePower.value, '—');
      expect(v.find('PolePairs')!.value, isNotEmpty);
    });

    test('works on the synthetic dump too', () {
      final dump = ParameterDump.fromHeb(
          HebFile.parse(List<int>.generate(696, (i) => (i * 37 + 11) & 0xFF)),
          fileName: 'synthetic.heb');
      final v = ProView.build(dump);
      expect(v.allCells.length, greaterThan(250));
    });
  });

  testWidgets('Pro view toggle on the saved-dump viewer', (tester) async {
    await tester.pumpWidget(_app(ParameterDumpScreen(dump: _dumpE())));
    expect(
        find.byKey(const ValueKey('param-show-unidentified')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('param-pro-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pro-view-list')), findsOneWidget);
    expect(find.text('ModelType'), findsOneWidget);
    expect(find.text('FarDrive'), findsOneWidget);
    expect(find.text('- DateTime'), findsOneWidget);
    expect(find.text('Date:2026-11-02'), findsOneWidget);
    expect(find.text('List view'), findsOneWidget);
    // Lazily built: the last section is not built until scrolled to.
    expect(find.text('- FixedParas'), findsNothing);
    await tester.scrollUntilVisible(find.text('- FixedParas'), 600,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('- FixedParas'), findsOneWidget);
    // Back to the default viewer.
    await tester.tap(find.byKey(const ValueKey('param-pro-toggle')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('param-show-unidentified')), findsOneWidget);
  });
}
