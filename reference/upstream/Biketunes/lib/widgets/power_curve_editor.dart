import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:biketunes/models/tuning_profile.dart';

class PowerCurveEditor extends StatelessWidget {
  final List<PowerPoint> points;
  final ValueChanged<List<PowerPoint>> onChanged;

  const PowerCurveEditor({
    super.key,
    required this.points,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart, color: Color(0xFF00E5FF), size: 16),
            const SizedBox(width: 8),
            const Text(
              'POWER CURVE',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: const Color(0xFF1A2030),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (_) => FlLine(
                  color: const Color(0xFF1A2030),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      const labels = ['LOW', 'MID', 'HIGH'];
                      final idx = val.round();
                      if (idx < 0 || idx > 2) return const SizedBox();
                      return Text(
                        labels[idx],
                        style: const TextStyle(
                          color: Color(0xFF4A5568),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      );
                    },
                    reservedSize: 22,
                    interval: 1,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) => Text(
                      '${(val * 100).round()}%',
                      style: const TextStyle(
                        color: Color(0xFF4A5568),
                        fontSize: 10,
                      ),
                    ),
                    reservedSize: 36,
                    interval: 0.5,
                  ),
                ),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 2,
              minY: 0,
              maxY: 1,
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (int i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].torqueFraction),
                  ],
                  isCurved: true,
                  color: const Color(0xFF00E5FF),
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 6,
                      color: const Color(0xFF00E5FF),
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF00E5FF).withOpacity(0.2),
                        const Color(0xFF00E5FF).withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(enabled: false),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Sliders for each point's torque fraction
        for (int i = 0; i < points.length; i++) ...[
          _PointSlider(
            label: i == 0 ? 'Low RPM' : i == 1 ? 'Mid RPM' : 'High RPM',
            value: points[i].torqueFraction,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              final updated = List<PowerPoint>.from(points);
              updated[i] = PowerPoint(
                rpmFraction: points[i].rpmFraction,
                torqueFraction: v,
              );
              onChanged(updated);
            },
          ),
          if (i < points.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PointSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _PointSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8899AA),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: const Color(0xFF00E5FF),
              inactiveTrackColor: const Color(0xFF1A2030),
              thumbColor: const Color(0xFF00E5FF),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayColor: const Color(0xFF00E5FF).withOpacity(0.2),
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
