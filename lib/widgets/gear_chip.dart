import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/drive_state.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';

/// Small read-only gear/boost chip: "N", "R", "D · LOW/MID/HIGH" or
/// "D · BST" (amber). Glanceable, no taps. Hidden while disconnected; "—"
/// when connected but no fresh 0xE2 frame.
class GearChip extends ConsumerWidget {
  const GearChip({super.key, this.dense = false});

  /// Slightly smaller variant for list headers.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(isConnectedProvider);
    if (!connected) return const SizedBox.shrink();
    final status = ref
        .watch(controllerProvider.select((s) => s.gearStatus(DateTime.now())));
    return GearChipView(status: status, dense: dense);
  }
}

/// Stateless rendering of [GearChip] (also used in tests).
class GearChipView extends StatelessWidget {
  const GearChipView({super.key, required this.status, this.dense = false});

  final GearStatus? status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final boost = s?.showsBoost ?? false;
    final reverse = s?.direction == DriveDirection.reverse;
    final Color fg = s == null
        ? Colors.white38
        : boost
            ? const Color(0xFF1A1200)
            : reverse
                ? const Color(0xFFFFB45C)
                : Colors.white;
    final Color bg = boost
        ? const Color(0xFFFFB020)
        : reverse
            ? const Color(0xFF3A2410)
            : const Color(0xFF1B2230);
    return Semantics(
      label: 'Gear ${s?.label ?? 'unknown'}',
      child: Container(
        key: const ValueKey('gear-chip'),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          s?.label ?? '—',
          key: const ValueKey('gear-chip-label'),
          maxLines: 1,
          style: TextStyle(
              color: fg,
              fontSize: dense ? 11 : 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8),
        ),
      ),
    );
  }
}
