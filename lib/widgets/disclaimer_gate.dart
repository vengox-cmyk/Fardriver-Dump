import 'package:flutter/material.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/widgets/brand_version_label.dart';

/// Rich text of the full disclaimer with the bold lead-in.
class DisclaimerText extends StatelessWidget {
  const DisclaimerText({super.key, this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return Text.rich(
      TextSpan(style: base, children: const [
        TextSpan(
            text: '${Disclaimer.lead} ',
            style: TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: Disclaimer.body),
      ]),
      key: const ValueKey('disclaimer-text'),
    );
  }
}

/// Small italic one-liner used on the dump and compare screens.
class DisclaimerShortLine extends StatelessWidget {
  const DisclaimerShortLine({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Text(
          Disclaimer.shortLine,
          key: ValueKey('disclaimer-short-line'),
          style: TextStyle(
              fontSize: 11, fontStyle: FontStyle.italic, color: Colors.white54),
        ),
      );
}

/// The two GPS-calibration safety lines (results screen, live view).
class CalibrationSafetyLines extends StatelessWidget {
  const CalibrationSafetyLines({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('calibration-safety'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(Disclaimer.calibrationLine,
              style: TextStyle(fontWeight: FontWeight.w700)),
          if (!compact) ...[
            const SizedBox(height: 4),
            const Text(Disclaimer.ridingWarning),
          ],
        ],
      );
}

/// Full disclaimer plus the calibration lines; must be accepted once before
/// the first calibration ride.
Future<bool> showCalibrationDisclaimer(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('calibration-disclaimer-dialog'),
      title: const Text('GPS speed calibration'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DisclaimerText(),
            SizedBox(height: 12),
            CalibrationSafetyLines(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('calibration-disclaimer-accept'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('I understand'),
        ),
      ],
    ),
  );
  return accepted == true;
}

/// Shows the disclaimer once per major version before [child] can be used.
class DisclaimerGate extends StatefulWidget {
  const DisclaimerGate({super.key, required this.child});

  final Widget child;

  static Future<void> show(BuildContext context,
          {required bool requireAccept}) =>
      showDialog<void>(
        context: context,
        barrierDismissible: !requireAccept,
        builder: (context) => PopScope(
          canPop: !requireAccept,
          child: AlertDialog(
            key: const ValueKey('disclaimer-dialog'),
            title: const Text('FarSure'),
            content: const SingleChildScrollView(child: DisclaimerText()),
            actions: [
              FilledButton(
                key: const ValueKey('disclaimer-accept'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('I understand'),
              ),
            ],
          ),
        ),
      );

  @override
  State<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends State<DisclaimerGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final version = await BrandVersionLabel.version();
    if (!await Disclaimer.needsAcceptance(version) || !mounted) return;
    await DisclaimerGate.show(context, requireAccept: true);
    await Disclaimer.accept(version);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
