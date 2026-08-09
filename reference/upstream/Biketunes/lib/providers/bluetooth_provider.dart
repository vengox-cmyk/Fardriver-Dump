import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/services/bluetooth_service.dart';

// Singleton bluetooth service
final bluetoothServiceProvider = Provider<DongleService>((ref) {
  final service = DongleService();
  ref.onDispose(service.dispose);
  return service;
});

// Connection state stream
final connectionStateProvider =
    StreamProvider<DongleConnectionState>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  return service.connectionStateStream;
});

// Scan results stream
final scanResultsProvider =
    StreamProvider<List<DiscoveredDongle>>((ref) {
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

// Action: start scan
final scanActionProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final service = ref.read(bluetoothServiceProvider);
    await service.startScan();
  };
});
