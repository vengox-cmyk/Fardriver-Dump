import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show FlutterBluePlus, BluetoothAdapterState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/providers/bluetooth_provider.dart';
import 'package:biketunes/services/bluetooth_service.dart';
import 'package:biketunes/widgets/connection_status_bar.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  bool _isScanning = false;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    // Wait until the BT adapter is on (handles macOS/iOS initialization delay)
    final adapterState = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.unavailable);
    if (adapterState != BluetoothAdapterState.on) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError('Bluetooth is off. Please enable Bluetooth and try again.');
      }
      return;
    }
    final service = ref.read(bluetoothServiceProvider);
    await service.startScan(timeout: const Duration(seconds: 10));
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connect(DiscoveredDongle dongle) async {
    setState(() => _connectingId = dongle.device.remoteId.str);
    final service = ref.read(bluetoothServiceProvider);
    final success = await service.connect(dongle);
    if (mounted) {
      setState(() => _connectingId = null);
      if (success) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else {
        _showError('Connection failed. Make sure the dongle is powered on.');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFFF1744),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState =
        ref.watch(connectionStateProvider).valueOrNull ?? DongleConnectionState.idle;
    final scanResults = ref.watch(scanResultsProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Logo / header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.electric_bolt,
                      color: Color(0xFF00E5FF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BIKETUNES',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                      Text(
                        'Tuner Connect',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              // Status
              ConnectionStatusBar(
                state: connectionState,
                deviceName: null,
              ),
              const SizedBox(height: 32),
              // Scan controls
              Row(
                children: [
                  const Text(
                    'NEARBY DONGLES',
                    style: TextStyle(
                      color: Color(0xFF4A5568),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00E5FF),
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label:
                        Text(_isScanning ? 'Scanning...' : 'Scan'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Device list
              Expanded(
                child: scanResults.isEmpty
                    ? _EmptyState(isScanning: _isScanning)
                    : ListView.separated(
                        itemCount: scanResults.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final dongle = scanResults[i];
                          final isConnecting =
                              _connectingId == dongle.device.remoteId.str;
                          return _DongleCard(
                            dongle: dongle,
                            isConnecting: isConnecting,
                            onTap: () => _connect(dongle),
                          );
                        },
                      ),
              ),
              // Info footer
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2030).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2A3548),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFF4A5568),
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Device names: YuanQ, FOC, FarDriver. Make sure the dongle is plugged into the controller and the bike is powered on.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DongleCard extends StatelessWidget {
  final DiscoveredDongle dongle;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DongleCard({
    required this.dongle,
    required this.isConnecting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111518),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A3548)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.bluetooth,
                color: Color(0xFF00E5FF),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dongle.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    dongle.device.remoteId.str,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Text(
                  '${dongle.rssi} dBm',
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 12),
                isConnecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00E5FF),
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF4A5568),
                        size: 20,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isScanning;
  const _EmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bluetooth_searching,
            size: 56,
            color: const Color(0xFF2A3548),
          ),
          const SizedBox(height: 16),
          Text(
            isScanning ? 'Searching for dongles...' : 'No dongles found',
            style: const TextStyle(
              color: Color(0xFF4A5568),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isScanning
                ? 'Make sure your bike is on and\nthe dongle is connected'
                : 'Tap Scan to search again',
            style: const TextStyle(
              color: Color(0xFF2A3548),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
