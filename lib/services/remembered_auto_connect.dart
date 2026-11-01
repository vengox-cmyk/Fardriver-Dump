import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:arcdash/models/remembered_device.dart';
import 'package:arcdash/services/bluetooth_service.dart';

/// Startup auto-connect (v1.2.3): when FarSure has connected to a
/// controller before, scan briefly in the background and connect when
/// exactly ONE remembered controller is broadcasting. Asks for no
/// permissions and does nothing when none are remembered, Bluetooth is off
/// or anything fails; the Connect screen always remains the manual path.
class RememberedAutoConnect {
  RememberedAutoConnect({
    required this.service,
    this.repository = const RememberedDeviceRepository(),
    this.scanFor = const Duration(seconds: 6),
  });

  final DongleService service;
  final RememberedDeviceRepository repository;
  final Duration scanFor;

  /// Returns the device it connected to, or null.
  Future<DiscoveredDongle?> run() async {
    try {
      final remembered = await repository.load();
      if (remembered.isEmpty) return null;
      if (service.state != DongleConnectionState.idle &&
          service.state != DongleConnectionState.disconnected) {
        return null;
      }
      if (!await service.isBluetoothOn()) return null;
      var latest = const <DiscoveredDongle>[];
      final sub = service.scanResultsStream.listen((r) => latest = r);
      try {
        await service.startScan(timeout: scanFor);
      } finally {
        await sub.cancel();
      }
      final candidate = RememberedDeviceMatcher(remembered)
          .autoConnectCandidate<DiscoveredDongle>(
              latest, (d) => (address: d.address, fingerprint: d.fingerprint));
      if (candidate == null) return null;
      if (service.state == DongleConnectionState.connected) return null;
      if (!await service.connect(candidate)) return null;
      await repository.remember(
          address: candidate.address, fingerprint: candidate.fingerprint);
      return candidate;
    } on Object catch (e) {
      debugPrint('Startup auto-connect skipped: $e');
      return null;
    }
  }
}
