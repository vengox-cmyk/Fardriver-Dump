import 'package:flutter/material.dart';

class BatteryIndicator extends StatelessWidget {
  final double percentage; // 0–100
  final double voltageV;
  final double? estimatedRangeKm;
  final bool useMph;

  const BatteryIndicator({
    super.key,
    required this.percentage,
    required this.voltageV,
    this.estimatedRangeKm,
    this.useMph = false,
  });

  Color get _batteryColor {
    if (percentage > 50) return const Color(0xFF39FF14);
    if (percentage > 25) return const Color(0xFFFF9800);
    return const Color(0xFFFF1744);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${percentage.toStringAsFixed(0)}',
              style: TextStyle(
                color: _batteryColor,
                fontSize: 48,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '%',
              style: TextStyle(
                color: _batteryColor.withOpacity(0.7),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Battery bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                height: 8,
                width: double.infinity,
                color: const Color(0xFF1A2030),
              ),
              FractionallySizedBox(
                widthFactor: (percentage / 100).clamp(0.0, 1.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 8,
                  decoration: BoxDecoration(
                    color: _batteryColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: _batteryColor.withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${voltageV.toStringAsFixed(1)}V',
              style: const TextStyle(
                color: Color(0xFF8899AA),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (estimatedRangeKm != null) ...[
              const SizedBox(width: 12),
              Text(
                '~${useMph ? (estimatedRangeKm! * 0.621371).toStringAsFixed(0) : estimatedRangeKm!.toStringAsFixed(0)} ${useMph ? 'mi' : 'km'}',
                style: const TextStyle(
                  color: Color(0xFF8899AA),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
