import 'package:flutter/material.dart';
import 'package:biketunes/services/bluetooth_service.dart';

class ConnectionStatusBar extends StatelessWidget {
  final DongleConnectionState state;
  final String? deviceName;

  const ConnectionStatusBar({
    super.key,
    required this.state,
    this.deviceName,
  });

  Color get _dotColor {
    switch (state) {
      case DongleConnectionState.connected:
        return const Color(0xFF39FF14);
      case DongleConnectionState.scanning:
      case DongleConnectionState.connecting:
        return const Color(0xFFFF9800);
      case DongleConnectionState.error:
        return const Color(0xFFFF1744);
      default:
        return const Color(0xFF4A5568);
    }
  }

  String get _label {
    switch (state) {
      case DongleConnectionState.connected:
        return deviceName != null ? 'CONNECTED — $deviceName' : 'CONNECTED';
      case DongleConnectionState.scanning:
        return 'SCANNING...';
      case DongleConnectionState.connecting:
        return 'CONNECTING...';
      case DongleConnectionState.error:
        return 'CONNECTION ERROR';
      case DongleConnectionState.disconnected:
        return 'DISCONNECTED';
      default:
        return 'IDLE';
    }
  }

  bool get _isPulsing =>
      state == DongleConnectionState.scanning ||
      state == DongleConnectionState.connecting;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _isPulsing
            ? _PulsingDot(color: _dotColor)
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dotColor,
                  boxShadow: state == DongleConnectionState.connected
                      ? [
                          BoxShadow(
                            color: _dotColor.withOpacity(0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
        const SizedBox(width: 8),
        Text(
          _label,
          style: TextStyle(
            color: _dotColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(_anim.value),
        ),
      ),
    );
  }
}
