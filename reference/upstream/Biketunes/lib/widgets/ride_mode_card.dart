import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:biketunes/models/controller_state.dart';

class RideModeCard extends StatelessWidget {
  final RideMode mode;
  final bool isSelected;
  final bool isConnected;
  final VoidCallback onTap;

  const RideModeCard({
    super.key,
    required this.mode,
    required this.isSelected,
    required this.isConnected,
    required this.onTap,
  });

  Color get _accentColor {
    switch (mode) {
      case RideMode.eco:
        return const Color(0xFF39FF14);
      case RideMode.trail:
        return const Color(0xFF00E5FF);
      case RideMode.sport:
        return const Color(0xFFFF9800);
      case RideMode.race:
        return const Color(0xFFFF1744);
    }
  }

  IconData get _icon {
    switch (mode) {
      case RideMode.eco:
        return Icons.eco_outlined;
      case RideMode.trail:
        return Icons.terrain_outlined;
      case RideMode.sport:
        return Icons.flash_on_outlined;
      case RideMode.race:
        return Icons.whatshot_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnected
          ? () {
              HapticFeedback.mediumImpact();
              onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [
                    _accentColor.withOpacity(0.25),
                    _accentColor.withOpacity(0.08),
                  ]
                : [
                    const Color(0xFF1A2030).withOpacity(0.6),
                    const Color(0xFF111518).withOpacity(0.7),
                  ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? _accentColor.withOpacity(0.7)
                : const Color(0xFF2A3548),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : [],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _icon,
              color: isSelected ? _accentColor : const Color(0xFF4A5568),
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              mode.displayName,
              style: TextStyle(
                color: isSelected ? _accentColor : const Color(0xFF4A5568),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
