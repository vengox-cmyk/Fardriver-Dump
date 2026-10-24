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

ParameterDump _dump() => ParameterDump.fromHeb(
      HebFile.parse(List<int>.generate(696, (i) => (i * 37 + 11) & 0xFF)),
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
}
