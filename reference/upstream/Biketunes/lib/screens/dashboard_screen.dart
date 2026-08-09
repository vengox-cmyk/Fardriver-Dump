import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show FlutterBluePlus, BluetoothAdapterState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/models/controller_state.dart';
import 'package:biketunes/providers/bluetooth_provider.dart';
import 'package:biketunes/providers/controller_provider.dart';
import 'package:biketunes/providers/stats_provider.dart';
import 'package:biketunes/services/bluetooth_service.dart';
import 'package:biketunes/utils/unit_converter.dart';
import 'package:biketunes/widgets/battery_indicator.dart';
import 'package:biketunes/widgets/connection_status_bar.dart';
import 'package:biketunes/widgets/data_tile.dart';
import 'package:biketunes/widgets/ride_mode_card.dart';
import 'package:biketunes/widgets/speedometer_gauge.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;
  double _sessionTopSpeed = 0;

  static const int _connectTabIndex = 4;

  final List<_NavItem> _navItems = [
    const _NavItem(icon: Icons.speed, label: 'DASH'),
    const _NavItem(icon: Icons.tune, label: 'TUNE'),
    const _NavItem(icon: Icons.bar_chart, label: 'STATS'),
    const _NavItem(icon: Icons.settings, label: 'SETUP'),
    const _NavItem(icon: Icons.bluetooth, label: 'CONNECT'),
  ];

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(controllerProvider);
    final connectionState =
        ref.watch(connectionStateProvider).valueOrNull ?? DongleConnectionState.idle;
    final isConnected = ref.watch(isConnectedProvider);
    final deviceName = ref.watch(connectedDeviceNameProvider);

    // Track session top speed
    if (controllerState.speedKph > _sessionTopSpeed) {
      _sessionTopSpeed = controllerState.speedKph;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'BIKETUNES',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const Spacer(),
                  ConnectionStatusBar(
                    state: connectionState,
                    deviceName: deviceName,
                  ),
                ],
              ),
            ),

            // Fault banner
            if (controllerState.hasAnyFault)
              _FaultBanner(state: controllerState),

            // Main content (screens)
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _DashTab(
                    controllerState: controllerState,
                    isConnected: isConnected,
                    sessionTopSpeed: _sessionTopSpeed,
                    onModeSelected: (mode) =>
                        ref.read(controllerProvider.notifier).setRideMode(mode),
                  ),
                  // Screens pushed via named routes from bottom nav taps
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  // Connect tab — persistent connection/scan UI
                  _ConnectTab(
                    connectionState: connectionState,
                    deviceName: deviceName,
                    onConnected: () => setState(() => _selectedIndex = 0),
                  ),
                ],
              ),
            ),

            // Bottom nav
            _BottomNav(
              items: _navItems,
              selectedIndex: _selectedIndex,
              onTap: (i) {
                if (i == 0) {
                  setState(() => _selectedIndex = 0);
                } else if (i == 1) {
                  Navigator.of(context).pushNamed('/tuning');
                } else if (i == 2) {
                  Navigator.of(context).pushNamed('/stats');
                } else if (i == 3) {
                  Navigator.of(context).pushNamed('/settings');
                } else if (i == _connectTabIndex) {
                  setState(() => _selectedIndex = _connectTabIndex);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectTab extends ConsumerStatefulWidget {
  final DongleConnectionState connectionState;
  final String? deviceName;
  final VoidCallback onConnected;

  const _ConnectTab({
    required this.connectionState,
    required this.deviceName,
    required this.onConnected,
  });

  @override
  ConsumerState<_ConnectTab> createState() => _ConnectTabState();
}

class _ConnectTabState extends ConsumerState<_ConnectTab> {
  bool _isScanning = false;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    if (widget.connectionState != DongleConnectionState.connected) {
      _startScan();
    }
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    final adapterState = await FlutterBluePlus.adapterState
        .firstWhere((s) => s != BluetoothAdapterState.unknown)
        .timeout(const Duration(seconds: 5),
            onTimeout: () => BluetoothAdapterState.unavailable);
    if (adapterState != BluetoothAdapterState.on) {
      if (mounted) setState(() => _isScanning = false);
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
        widget.onConnected();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection failed. Make sure the dongle is powered on.'),
            backgroundColor: Color(0xFFFF1744),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    final service = ref.read(bluetoothServiceProvider);
    await service.disconnect();
    if (mounted) _startScan();
  }

  @override
  Widget build(BuildContext context) {
    final scanResults = ref.watch(scanResultsProvider).valueOrNull ?? [];
    final isConnected =
        widget.connectionState == DongleConnectionState.connected;

    if (isConnected) {
      return _ConnectedView(
        deviceName: widget.deviceName ?? 'Tuner',
        onDisconnect: _disconnect,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'NEARBY TUNERS',
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
                label: Text(_isScanning ? 'Scanning...' : 'Scan'),
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
          Expanded(
            child: scanResults.isEmpty
                ? Center(
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
                          _isScanning
                              ? 'Searching for tuners...'
                              : 'No tuners found',
                          style: const TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isScanning
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
                  )
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
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2030).withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A3548)),
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
    );
  }
}

class _ConnectedView extends StatelessWidget {
  final String deviceName;
  final VoidCallback onDisconnect;

  const _ConnectedView({
    required this.deviceName,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF00E5FF).withOpacity(0.4),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.bluetooth_connected,
              color: Color(0xFF00E5FF),
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'CONNECTED',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            deviceName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDisconnect,
              icon: const Icon(Icons.bluetooth_disabled, size: 18),
              label: const Text('DISCONNECT'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF1744),
                side: const BorderSide(color: Color(0xFFFF1744), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashTab extends StatelessWidget {
  final ControllerState controllerState;
  final bool isConnected;
  final double sessionTopSpeed;
  final ValueChanged<RideMode> onModeSelected;

  // Rough constant for display purposes (will be refined from controller data)
  static const double _avgConsumptionWhPerKm = 25.0;
  static const double _battCapacityWh = 1000.0;

  const _DashTab({
    required this.controllerState,
    required this.isConnected,
    required this.sessionTopSpeed,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final speedMph = UnitConverter.kphToMph(controllerState.speedKph);
    final topSpeedMph = UnitConverter.kphToMph(sessionTopSpeed);
    final maxSpeedMph = controllerState.maxSpeedRaw > 0
        ? UnitConverter.kphToMph(100.0)
        : UnitConverter.kphToMph(80.0);

    final estimatedRange = UnitConverter.estimatedRangeKm(
      batteryPercent: controllerState.batteryPercent,
      battCapacityWh: _battCapacityWh,
      avgConsumptionWhPerKm: _avgConsumptionWhPerKm,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Speedometer
          SizedBox(
            width: double.infinity,
            height: 240,
            child: SpeedometerGauge(
              speed: speedMph,
              maxSpeed: maxSpeedMph,
              topSpeed: topSpeedMph,
              unit: 'mph',
            ),
          ),

          const SizedBox(height: 8),

          // Battery section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF111518),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1A2030)),
            ),
            child: BatteryIndicator(
              percentage: controllerState.batteryPercent,
              voltageV: controllerState.voltageV,
              estimatedRangeKm: estimatedRange > 0 ? estimatedRange : null,
              useMph: true,
            ),
          ),

          const SizedBox(height: 14),

          // Data tiles 2×2 grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              DataTile(
                label: 'MOTOR TEMP',
                value: UnitConverter.fmt0(controllerState.motorTempC),
                unit: '°C',
                icon: Icons.thermostat,
                accentColor: controllerState.motorTempProtect
                    ? const Color(0xFFFF1744)
                    : const Color(0xFFFF9800),
                isWarning: controllerState.motorTempProtect,
              ),
              DataTile(
                label: 'CTRL TEMP',
                value: UnitConverter.fmt0(controllerState.controllerTempC),
                unit: '°C',
                icon: Icons.memory,
                accentColor: controllerState.controllerTempProtect
                    ? const Color(0xFFFF1744)
                    : const Color(0xFF00E5FF),
                isWarning: controllerState.controllerTempProtect,
              ),
              DataTile(
                label: 'CURRENT',
                value: UnitConverter.fmt1(controllerState.currentA),
                unit: 'A',
                icon: Icons.bolt,
                accentColor: const Color(0xFF39FF14),
              ),
              DataTile(
                label: 'POWER',
                value: UnitConverter.fmt1(controllerState.powerKw),
                unit: 'kW',
                icon: Icons.electric_bolt,
                accentColor: const Color(0xFF00E5FF),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Ride modes
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111518),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1A2030)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RIDE MODE',
                  style: TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: RideMode.values.map((mode) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: mode != RideMode.race ? 8 : 0,
                        ),
                        child: RideModeCard(
                          mode: mode,
                          isSelected: controllerState.rideMode == mode,
                          isConnected: isConnected,
                          onTap: () => onModeSelected(mode),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _FaultBanner extends StatelessWidget {
  final ControllerState state;
  const _FaultBanner({required this.state});

  String get _message {
    final faults = <String>[];
    if (state.motorHallError) faults.add('Motor Hall Error');
    if (state.throttleError) faults.add('Throttle Error');
    if (state.motorTempProtect) faults.add('Motor Overheat');
    if (state.controllerTempProtect) faults.add('Controller Overheat');
    return faults.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF1744).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFFFF1744), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message,
              style: const TextStyle(
                color: Color(0xFFFF1744),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _BottomNav extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(top: BorderSide(color: Color(0xFF1A2030))),
      ),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[i].icon,
                        size: 22,
                        color: i == selectedIndex
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFF2A3548),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: i == selectedIndex
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF2A3548),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
