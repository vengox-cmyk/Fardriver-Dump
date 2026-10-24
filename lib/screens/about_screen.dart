import 'package:flutter/material.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/widgets/brand_version_label.dart';
import 'package:arcdash/widgets/disclaimer_gate.dart';

/// Settings → About: logo, version, full disclaimer and upstream credit.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const logoAsset = 'assets/images/vengox_logo_full_v3.png';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About FarSure')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Image.asset(logoAsset,
                    width: 180, height: 180, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: BrandVersionLabel(
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text('FarDriver controller reader',
                  style: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 24),
            const DisclaimerText(),
            const SizedBox(height: 24),
            const Text(Disclaimer.credit,
                key: ValueKey('about-credit'),
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
}
