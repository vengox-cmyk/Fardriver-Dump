import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/screens/parameter_compare_screen.dart';
import 'package:arcdash/screens/parameter_dump_screen.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {Locale locale = const Locale('de')}) => ProviderScope(
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: home,
      ),
    );

ParameterDump _dump({int seed = 11}) => ParameterDump.fromHeb(
      HebFile.parse(List<int>.generate(696, (i) => (i * 37 + seed) & 0xFF)),
      fileName: 'synthetic.heb',
    );

void main() {
  testWidgets('dump screen lists parameters and filters by name',
      (tester) async {
    await tester.pumpWidget(_app(ParameterDumpScreen(dump: _dump())));
    expect(find.text('heb:synthetic.heb'), findsOneWidget);
    expect(find.text('VolCoeff'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'MaxSpeed');
    await tester.pump();
    expect(find.text('MaxSpeed'), findsWidgets);
    expect(find.text('VolCoeff'), findsNothing);
  });

  testWidgets('compare screen starts empty with both source pickers',
      (tester) async {
    await tester.pumpWidget(
        _app(const ParameterCompareScreen(), locale: const Locale('en')));
    expect(find.text('Source A (old)'), findsOneWidget);
    expect(find.text('Source B (new)'), findsOneWidget);
    expect(find.text('Choose HEB or CSV file'), findsNWidgets(2));
  });

  testWidgets('dump screen hides unidentified rows until toggled',
      (tester) async {
    await tester.pumpWidget(_app(ParameterDumpScreen(dump: _dump())));
    expect(find.byKey(const ValueKey('disclaimer-short-line')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'unk14b');
    await tester.pump();
    expect(find.text('unk14b (unidentified)'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('param-show-unidentified')));
    await tester.pump();
    expect(find.text('unk14b (unidentified)'), findsOneWidget);
  });

  testWidgets('dump screen shows official names and finds hpp names',
      (tester) async {
    await tester.pumpWidget(_app(ParameterDumpScreen(dump: _dump())));
    await tester.enterText(find.byType(TextField), 'HighVolProtect');
    await tester.pump();
    expect(find.text('OverVolProtect'), findsOneWidget);
  });

  testWidgets('compare screen marks unidentified changes', (tester) async {
    await tester.pumpWidget(_app(
        ParameterCompareScreen(initialA: _dump(), initialB: _dump(seed: 12)),
        locale: const Locale('en')));
    expect(find.byKey(const ValueKey('disclaimer-short-line')), findsOneWidget);
    expect(find.textContaining('unidentified'), findsWidgets);
    await tester.scrollUntilVisible(
        find.textContaining('UNIDENTIFIED', findRichText: true), 300,
        scrollable: find.byType(Scrollable).last);
    expect(
        find.textContaining('UNIDENTIFIED', findRichText: true), findsWidgets);
  });
}
