import 'package:arcdash/screens/about_screen.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/widgets/brand_version_label.dart';
import 'package:arcdash/widgets/disclaimer_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockVersion(String version) {
  PackageInfo.setMockInitialValues(
    appName: 'FarSure',
    packageName: 'com.arcdash',
    version: version,
    buildNumber: '1',
    buildSignature: '',
  );
  BrandVersionLabel.resetCache();
}

Widget _gated() => const MaterialApp(
    home: DisclaimerGate(child: Scaffold(body: Text('home'))));

void main() {
  tearDown(BrandVersionLabel.resetCache);

  test('text is the issue #2 wording', () {
    expect(
        Disclaimer.fullText, startsWith('Use at your own risk. FarSure reads'));
    expect(Disclaimer.fullText, endsWith('arising from its use.'));
    expect(Disclaimer.fullText, contains('provided "as is"'));
  });

  test('acceptance is keyed on the major version', () {
    expect(Disclaimer.majorOf('1.1.205'), 1);
    expect(Disclaimer.majorOf('2.0.0'), 2);
    expect(Disclaimer.majorOf(null), Disclaimer.fallbackMajor);
    expect(Disclaimer.isAccepted(null, '1.1.0'), isFalse);
    expect(Disclaimer.isAccepted(1, '1.9.300'), isTrue);
    expect(Disclaimer.isAccepted(1, '2.0.0'), isFalse);
  });

  testWidgets('first launch shows the notice until "I understand"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    _mockVersion('1.1.10');
    await tester.pumpWidget(_gated());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-dialog')), findsOneWidget);
    expect(find.text('I understand'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('disclaimer-accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-dialog')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(Disclaimer.prefKey), 1);
  });

  testWidgets('accepted notice stays hidden within the same major',
      (tester) async {
    SharedPreferences.setMockInitialValues({Disclaimer.prefKey: 1});
    _mockVersion('1.4.0');
    await tester.pumpWidget(_gated());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-dialog')), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('notice is shown again after a major update', (tester) async {
    SharedPreferences.setMockInitialValues({Disclaimer.prefKey: 1});
    _mockVersion('2.0.0');
    await tester.pumpWidget(_gated());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-dialog')), findsOneWidget);
  });

  testWidgets('About shows the full text and the upstream credit',
      (tester) async {
    _mockVersion('1.1.10');
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-text')), findsOneWidget);
    expect(find.text('FarSure by Vengox · v1.1.10'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('about-credit')), 200);
    expect(find.text('Based on ArcDash / Biketunes by caydenchapple'),
        findsOneWidget);
  });
}
