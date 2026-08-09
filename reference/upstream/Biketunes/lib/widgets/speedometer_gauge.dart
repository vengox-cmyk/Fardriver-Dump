import 'dart:math' as math;
import 'package:flutter/material.dart';

class SpeedometerGauge extends StatefulWidget {
  final double speed;
  final double maxSpeed;
  final double topSpeed;
  final String unit;

  const SpeedometerGauge({
    super.key,
    required this.speed,
    required this.maxSpeed,
    this.topSpeed = 0.0,
    required this.unit,
  });

  @override
  State<SpeedometerGauge> createState() => _SpeedometerGaugeState();
}

class _SpeedometerGaugeState extends State<SpeedometerGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _previousSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(SpeedometerGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _animation = Tween<double>(
        begin: _previousSpeed,
        end: widget.speed,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
      _previousSpeed = widget.speed;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return CustomPaint(
          painter: _SpeedometerPainter(
            speed: _animation.value,
            maxSpeed: widget.maxSpeed,
            topSpeed: widget.topSpeed,
            unit: widget.unit,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final double topSpeed;
  final String unit;

  static const double _startAngle = 130 * (math.pi / 180);
  static const double _sweepAngle = 280 * (math.pi / 180);

  _SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    required this.topSpeed,
    required this.unit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;

    _drawTrack(canvas, center, radius);
    _drawTopSpeedMarker(canvas, center, radius);
    _drawArc(canvas, center, radius);
    _drawTicks(canvas, center, radius);
    _drawSpeedText(canvas, center, size);
  }

  void _drawTrack(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = const Color(0xFF1A2030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      paint,
    );
  }

  void _drawArc(Canvas canvas, Offset center, double radius) {
    final fraction = (speed / maxSpeed).clamp(0.0, 1.0);

    // Color gradient: green → cyan → amber → red
    final Color arcColor;
    if (fraction < 0.5) {
      arcColor = Color.lerp(
        const Color(0xFF39FF14),
        const Color(0xFF00E5FF),
        fraction / 0.5,
      )!;
    } else if (fraction < 0.8) {
      arcColor = Color.lerp(
        const Color(0xFF00E5FF),
        const Color(0xFFFF9800),
        (fraction - 0.5) / 0.3,
      )!;
    } else {
      arcColor = Color.lerp(
        const Color(0xFFFF9800),
        const Color(0xFFFF1744),
        (fraction - 0.8) / 0.2,
      )!;
    }

    final paint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    // Glow
    final glowPaint = Paint()
      ..color = arcColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle * fraction,
      false,
      glowPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle * fraction,
      false,
      paint,
    );
  }

  void _drawTopSpeedMarker(Canvas canvas, Offset center, double radius) {
    if (topSpeed <= 0 || topSpeed > maxSpeed) return;
    final fraction = (topSpeed / maxSpeed).clamp(0.0, 1.0);
    final angle = _startAngle + _sweepAngle * fraction;
    final markerPaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 24);
    final outer = center + Offset(math.cos(angle), math.sin(angle)) * (radius + 2);
    canvas.drawLine(inner, outer, markerPaint);
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    final int majorTicks = (maxSpeed / 20).round().clamp(5, 10);
    final tickPaint = Paint()
      ..color = const Color(0xFF2A3548)
      ..strokeWidth = 2;
    final majorTickPaint = Paint()
      ..color = const Color(0xFF4A5568)
      ..strokeWidth = 2;

    for (int i = 0; i <= majorTicks * 5; i++) {
      final fraction = i / (majorTicks * 5);
      final angle = _startAngle + _sweepAngle * fraction;
      final isMajor = i % 5 == 0;
      final len = isMajor ? 12.0 : 6.0;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 24 - len);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 24);
      canvas.drawLine(inner, outer, isMajor ? majorTickPaint : tickPaint);
    }
  }

  void _drawSpeedText(Canvas canvas, Offset center, Size size) {
    final speedStr = speed.toStringAsFixed(0);

    final speedPainter = TextPainter(
      text: TextSpan(
        text: speedStr,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 72,
          fontWeight: FontWeight.w700,
          height: 1.0,
          letterSpacing: -2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    speedPainter.layout();
    speedPainter.paint(
      canvas,
      center + Offset(-speedPainter.width / 2, -speedPainter.height / 2 - 8),
    );

    final unitPainter = TextPainter(
      text: TextSpan(
        text: unit,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    unitPainter.layout();
    unitPainter.paint(
      canvas,
      center + Offset(-unitPainter.width / 2, speedPainter.height / 2 - 4),
    );
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) =>
      old.speed != speed ||
      old.maxSpeed != maxSpeed ||
      old.topSpeed != topSpeed;
}
