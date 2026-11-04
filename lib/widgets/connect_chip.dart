import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/providers/bluetooth_provider.dart';

/// v1.4: the app never connects on its own at start. This chip shows the
/// link state; tapping it opens the controller list, and after connecting
/// the connection screen pops back to the screen it was opened from.
class ConnectChip extends ConsumerWidget {
  const ConnectChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(isConnectedProvider);
    final name = ref.watch(connectedDeviceNameProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ActionChip(
        key: const ValueKey('connect-chip'),
        avatar: Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 18,
            color: connected ? const Color(0xFF54E39E) : const Color(0xFFFFB45C)),
        label: Text(connected ? (name ?? 'Connected') : 'Connect'),
        onPressed: () => Navigator.of(context).pushNamed('/'),
      ),
    );
  }
}
