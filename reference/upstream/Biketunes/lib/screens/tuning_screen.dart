import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/models/tuning_profile.dart';
import 'package:biketunes/providers/controller_provider.dart';
import 'package:biketunes/providers/tuning_provider.dart';
import 'package:biketunes/utils/unit_converter.dart';

class TuningScreen extends ConsumerWidget {
  const TuningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuningState = ref.watch(tuningProvider);
    final controllerState = ref.watch(controllerProvider);
    final profile = tuningState.pendingProfile;
    final notifier = ref.read(tuningProvider.notifier);
    final isMoving = controllerState.speedKph > 2.0;

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          'TUNING',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1A2030)),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Safety warning banner
              _WarningBanner(isMoving: isMoving),
              const SizedBox(height: 20),

              // Presets
              _SectionHeader(title: 'PRESETS'),
              const SizedBox(height: 10),
              _PresetRow(
                onPreset: (p) => notifier.loadPreset(p),
                selectedName: profile.name,
              ),
              const SizedBox(height: 24),

              // Controls
              _SectionHeader(title: 'CONTROLS'),
              const SizedBox(height: 14),

              // Max Speed
              _TuningSlider(
                label: 'Max Speed',
                icon: Icons.speed,
                value: UnitConverter.kphToMph(profile.maxSpeedKph),
                min: UnitConverter.kphToMph(10),
                max: UnitConverter.kphToMph(100),
                unit: 'mph',
                displayValue: UnitConverter.kphToMph(profile.maxSpeedKph).toStringAsFixed(0),
                onChanged: (mph) => notifier.updateMaxSpeed(UnitConverter.mphToKph(mph)),
                accentColor: const Color(0xFF00E5FF),
              ),
              const SizedBox(height: 14),

              // Peak Torque — maps to phase current (20–400 A → 0–100%)
              _TuningSlider(
                label: 'Peak Torque',
                icon: Icons.rotate_right,
                value: (profile.maxPhaseCurrA / 400.0 * 100).clamp(0, 100),
                min: 5,
                max: 100,
                unit: '%',
                displayValue: (profile.maxPhaseCurrA / 400.0 * 100).clamp(0, 100).toStringAsFixed(0),
                onChanged: (pct) => notifier.updateMaxPhaseCurr((pct / 100.0 * 400.0).clamp(20, 400)),
                accentColor: const Color(0xFF39FF14),
                warningThreshold: 80,
              ),
              const SizedBox(height: 14),

              // Peak Power — maps to line current (10–200 A × 72 V = 0.7–14.4 kW)
              _TuningSlider(
                label: 'Peak Power',
                icon: Icons.electric_bolt,
                value: (profile.maxLineCurrA * 72.0 / 1000.0).clamp(0.7, 14.4),
                min: 0.7,
                max: 14.4,
                unit: 'kW',
                displayValue: (profile.maxLineCurrA * 72.0 / 1000.0).toStringAsFixed(1),
                onChanged: (kw) => notifier.updateMaxLineCurr((kw * 1000.0 / 72.0).clamp(10, 200)),
                accentColor: const Color(0xFFFF9800),
                warningThreshold: 11.0,
              ),
              const SizedBox(height: 24),

              // Throttle response
              _SectionHeader(title: 'THROTTLE RESPONSE'),
              const SizedBox(height: 10),
              _ThrottleResponseSelector(
                value: profile.throttleResponse,
                onChanged: notifier.updateThrottleResponse,
              ),
              const SizedBox(height: 28),

              // Error message
              if (tuningState.lastError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFF1744).withOpacity(0.3)),
                  ),
                  child: Text(
                    tuningState.lastError!,
                    style: const TextStyle(
                      color: Color(0xFFFF1744),
                      fontSize: 13,
                    ),
                  ),
                ),

              // Success message
              if (tuningState.appliedSuccessfully)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39FF14).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF39FF14).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF39FF14), size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Profile applied successfully',
                        style: TextStyle(
                          color: Color(0xFF39FF14),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: tuningState.isApplying || isMoving
                      ? null
                      : () => _showApplyDialog(context, ref, profile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF080B0E),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor:
                        const Color(0xFF2A3548),
                  ),
                  child: tuningState.isApplying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF080B0E),
                          ),
                        )
                      : Text(
                          isMoving
                              ? 'STOP BIKE TO APPLY'
                              : 'APPLY TO CONTROLLER',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showApplyDialog(
      BuildContext context, WidgetRef ref, TuningProfile profile) async {
    final isFullSend = profile.name == 'Full Send';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111518),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isFullSend
                ? const Color(0xFFFF1744).withOpacity(0.5)
                : const Color(0xFF2A3548),
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: isFullSend
                  ? const Color(0xFFFF1744)
                  : const Color(0xFFFF9800),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              isFullSend ? 'EXTREME WARNING' : 'APPLY CHANGES?',
              style: TextStyle(
                color: isFullSend
                    ? const Color(0xFFFF1744)
                    : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFullSend) ...[
              const Text(
                '⚠ This preset pushes the motor and controller to extreme limits. It can:',
                style: TextStyle(color: Color(0xFFFF1744), fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Overheat and permanently damage the motor\n'
                '• Void your warranty\n'
                '• Create dangerously high speeds\n'
                '• Be illegal on public roads',
                style: TextStyle(color: Color(0xFFFF9800), fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Writing to: ${profile.name}\n'
              'Max Speed: ${UnitConverter.kphToMph(profile.maxSpeedKph).toStringAsFixed(0)} mph\n'
              'Peak Torque: ${(profile.maxPhaseCurrA / 400.0 * 100).toStringAsFixed(0)}%\n'
              'Peak Power: ${(profile.maxLineCurrA * 72.0 / 1000.0).toStringAsFixed(1)} kW',
              style: const TextStyle(
                color: Color(0xFF8899AA),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Changes are written directly to the controller. A stock backup will be preserved.',
              style: TextStyle(
                color: Color(0xFF4A5568),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF4A5568), letterSpacing: 1),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isFullSend
                  ? const Color(0xFFFF1744)
                  : const Color(0xFF00E5FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isFullSend ? 'I UNDERSTAND, APPLY' : 'APPLY',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Color(0xFF080B0E),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.heavyImpact();
      ref.read(tuningProvider.notifier).applyProfile();
    }
  }
}

class _WarningBanner extends StatelessWidget {
  final bool isMoving;
  const _WarningBanner({required this.isMoving});

  @override
  Widget build(BuildContext context) {
    if (isMoving) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFF1744).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning, color: Color(0xFFFF1744), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'VEHICLE MOVING — Tuning locked until stationary',
                style: TextStyle(
                  color: Color(0xFFFF1744),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: Color(0xFFFF9800), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aggressive tuning can overheat the motor, void warranty, or be illegal on public roads. Ride responsibly.',
              style: TextStyle(
                color: Color(0xFFFF9800),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF4A5568),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final ValueChanged<TuningProfile> onPreset;
  final String selectedName;

  const _PresetRow({required this.onPreset, required this.selectedName});

  @override
  Widget build(BuildContext context) {
    final presets = [
      TuningProfile.stock(),
      TuningProfile.street(),
      TuningProfile.trail(),
      TuningProfile.fullSend(),
    ];

    return Row(
      children: presets.map((p) {
        final isSelected = p.name == selectedName;
        final isFullSend = p.name == 'Full Send';
        final color = isFullSend
            ? const Color(0xFFFF1744)
            : const Color(0xFF00E5FF);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                right: p == presets.last ? 0 : 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onPreset(p);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.15)
                      : const Color(0xFF111518),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? color : const Color(0xFF2A3548),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      p.name.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? color : const Color(0xFF4A5568),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TuningSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final String unit;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final Color accentColor;
  final double? warningThreshold;

  const _TuningSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.displayValue,
    required this.onChanged,
    required this.accentColor,
    this.warningThreshold,
  });

  bool get _isWarning => warningThreshold != null && value >= warningThreshold!;

  @override
  Widget build(BuildContext context) {
    final color = _isWarning ? const Color(0xFFFF9800) : accentColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isWarning
              ? const Color(0xFFFF9800).withOpacity(0.35)
              : const Color(0xFF1A2030),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$displayValue',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: color.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: color,
              inactiveTrackColor: const Color(0xFF1A2030),
              thumbColor: color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayColor: color.withOpacity(0.15),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ),
          if (_isWarning)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  const Icon(Icons.warning_amber, color: Color(0xFFFF9800), size: 12),
                  const SizedBox(width: 4),
                  const Text(
                    'High — monitor temps closely',
                    style: TextStyle(
                      color: Color(0xFFFF9800),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThrottleResponseSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _ThrottleResponseSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (0, 'RACE', const Color(0xFFFF1744)),
      (1, 'SPORT', const Color(0xFFFF9800)),
      (2, 'ECO', const Color(0xFF39FF14)),
    ];

    return Row(
      children: options.map((opt) {
        final (val, label, color) = opt;
        final isSelected = value == val;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: val < 2 ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(val);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.15)
                      : const Color(0xFF111518),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? color : const Color(0xFF2A3548),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? color : const Color(0xFF4A5568),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
