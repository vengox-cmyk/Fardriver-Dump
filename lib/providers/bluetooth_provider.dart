import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/diagnostic_log.dart';

// Global shared diagnostic log provider
final diagnosticsLogProvider = Provider<DiagnosticLog>((ref) {
  return DiagnosticLog(maxEvents: 1000);
});

// Singleton bluetooth service
final bluetoothServiceProvider = Provider<DongleService>((ref) {
  final diagnostics = ref.watch(diagnosticsLogProvider);
  final service = DongleService(diagnostics: diagnostics);
  ref.onDispose(service.dispose);
  return service;
});

// Connection state stream
final connectionStateProvider = StreamProvider<DongleConnectionState>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  return service.connectionStateStream;
});

// Scan results stream
final scanResultsProvider = StreamProvider<List<DiscoveredDongle>>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  return service.scanResultsStream;
});

// Whether currently connected
final isConnectedProvider = Provider<bool>((ref) {
  final state = ref.watch(connectionStateProvider).valueOrNull;
  return state == DongleConnectionState.connected;
});

// Connected device name
final connectedDeviceNameProvider = Provider<String?>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  ref.watch(connectionStateProvider); // rebuild on state change
  return service.connectedDeviceName;
});

// Stable identifier of the connected device (BLE remote id)
final connectedDeviceIdProvider = Provider<String?>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  ref.watch(connectionStateProvider); // rebuild on state change
  return service.connectedDeviceId;
});

// Action: start scan
final scanActionProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final service = ref.read(bluetoothServiceProvider);
    await service.startScan();
  };
});
