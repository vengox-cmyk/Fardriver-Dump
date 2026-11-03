import 'package:flutter/material.dart';

import 'package:arcdash/screens/dash_speed_check_screen.dart';
import 'package:arcdash/screens/speed_calibration_screen.dart';
import 'package:arcdash/screens/tire_rack_screen.dart';
import 'package:arcdash/widgets/connect_chip.dart';

/// v1.4: pick which speed to calibrate. Two paths, each explained in one
/// plain sentence. Nothing here needs a connection to open.
class SpeedCalibrationChooser extends StatelessWidget {
  const SpeedCalibrationChooser({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('SPEED CALIBRATION'),
            actions: const [ConnectChip()]),
        body: SafeArea(
          child: ListView(
            key: const ValueKey('speed-chooser'),
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Which speed do you want to get right?'),
              const SizedBox(height: 12),
              _Choice(
                key: const ValueKey('choose-gps'),
                icon: Icons.gps_fixed,
                title: 'GPS speed (FarSure / app speed)',
                body: 'Ride steady on a flat road while the phone GPS is '
                    'compared with the motor RPM. Gives a corrected '
                    'RateRatio. Pick your tire in the tire rack first if '
                    'you changed it.',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const SpeedCalibrationScreen())),
                extra: TextButton.icon(
                  key: const ValueKey('open-tire-rack'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const TireRackScreen())),
                  icon: const Icon(Icons.tire_repair),
                  label: const Text('Tire rack'),
                ),
              ),
              const SizedBox(height: 12),
              _Choice(
                key: const ValueKey('choose-dkd'),
                icon: Icons.speed_outlined,
                title: 'DKD dash speed (one-wire dash)',
                body: 'For the speed shown on the DKD dash. Done standing '
                    'still with the drive wheel lifted: you read the dash, '
                    'FarSure reads the RPM.',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const DashSpeedCheckScreen())),
              ),
            ],
          ),
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice(
      {super.key,
      required this.icon,
      required this.title,
      required this.body,
      required this.onTap,
      this.extra});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(body),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
          if (extra != null)
            Align(alignment: Alignment.centerLeft, child: extra!),
        ]),
      );
}
