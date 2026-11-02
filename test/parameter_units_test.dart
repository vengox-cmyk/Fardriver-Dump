import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/screens/parameter_dump_screen.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/utils/speed_units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DecodedParameter.formatValue', () {
    test('km/h mode keeps the stored metric value', () {
      expect(
          DecodedParameter.formatValue('km', '25.6', SpeedUnit.kmh), '25.6 km');
      expect(
          DecodedParameter.formatValue('km/h', '40', SpeedUnit.kmh), '40 km/h');
    });

    test('mph mode converts km, km/h and Wh/km only', () {
      expect(DecodedParameter.formatValue('km', '25.6', SpeedUnit.mph),
          '15.9 mi (25.6 km)');
      expect(DecodedParameter.formatValue('km/h', '40', SpeedUnit.mph),
          '24.9 mph (40 km/h)');
      expect(DecodedParameter.formatValue('Wh/km', '30', SpeedUnit.mph),
          '48.3 Wh/mi (30 Wh/km)');
      expect(DecodedParameter.formatValue('rpm', '5000', SpeedUnit.mph),
          '5000 rpm');
      expect(DecodedParameter.formatValue('A', '250', SpeedUnit.mph), '250 A');
      expect(
          DecodedParameter.formatValue('km', 'abc', SpeedUnit.mph), 'abc km');
    });

    test('catalog has exactly the three converted units', () {
      final units = FardriverParamCatalog.all.map((d) => d.unit).toList();
      expect(units.where((u) => u == 'km').length, 1);
      expect(units.where((u) => u == 'km/h').length, 1);
      expect(units.where((u) => u == 'Wh/km').length, 1);
    });
  });

  testWidgets('dump viewer shows odometer in miles in mph mode',
      (tester) async {
    final dump = ParameterDump.fromHeb(
      HebFile.parse(List<int>.generate(696, (i) => (i * 37 + 11) & 0xFF)),
      fileName: 'synthetic.heb',
    );
    final odo = dump.decode().firstWhere((p) => p.def.unit == 'km');
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: ParameterDumpScreen(dump: dump, unit: SpeedUnit.mph),
      ),
    ));
    await tester.enterText(find.byType(TextField), odo.def.name);
    await tester.pump();
    expect(find.text(odo.displayIn(SpeedUnit.mph)), findsOneWidget);
    expect(odo.displayIn(SpeedUnit.mph), contains(' mi ('));
  });
}
