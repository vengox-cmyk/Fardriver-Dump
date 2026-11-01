import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlus, BluetoothAdapterState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/remembered_device.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/widgets/connection_status_bar.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/android_permission_service.dart';
import 'package:arcdash/services/diagnostic_log_exporter.dart';

/// Scan + connect. v1.2.3: controllers connected before are listed first
/// under "Previously connected" (recognised by advertised name + service
/// UUIDs + manufacturer IDs, since the address changes) and FarSure
/// connects automatically when exactly one of them is broadcasting.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen(
      {super.key,
      this.repository = const RememberedDeviceRepository(),
      this.autoConnectDelay = const Duration(seconds: 3)});

  final RememberedDeviceRepository repository;

  /// How long to listen before deciding that exactly one remembered
  /// controller is around (checked again when the scan ends).
  final Duration autoConnectDelay;

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  bool _isScanning = false;
  String? _connectingId;
  List<RememberedDevice> _remembered = const [];
  bool _autoTried = false;
  bool _autoCancelled = false;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRemembered());
    _startScan();
    _autoTimer = Timer(widget.autoConnectDelay, _maybeAutoConnect);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRemembered() async {
    final list = await widget.repository.load();
    if (mounted) setState(() => _remembered = list);
  }

  static SeenDevice _seen(DiscoveredDongle d) =>
      (address: d.address, fingerprint: d.fingerprint);

  /// Connects once, on its own, when exactly one remembered controller is
  /// broadcasting and nothing else is going on.
  void _maybeAutoConnect() {
    if (!mounted || _autoTried || _autoCancelled || _connectingId != null) {
      return;
    }
    if (ref.read(isConnectedProvider) || _remembered.isEmpty) return;
    final scan = ref.read(scanResultsProvider).valueOrNull ?? const [];
    final candidate =
        RememberedDeviceMatcher(_remembered).autoConnectCandidate(scan, _seen);
    if (candidate == null) return;
    _autoTried = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: const ValueKey('auto-connect-snack'),
      content: Text('Connecting to ${candidate.name} (previously connected)'),
      behavior: SnackBarBehavior.floating,
    ));
    unawaited(_connect(candidate));
  }

  Future<void> _forget(RememberedDevice device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('forget-device-dialog'),
        title: const Text('Forget this controller?'),
        content: Text(
            '${device.fingerprint.name.isEmpty ? device.lastAddress : device.fingerprint.name}\n\n'
            'FarSure will no longer connect to it automatically. You can connect again any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: Text(AppStrings.of(c).text(AppText.cancel))),
          FilledButton(
              key: const ValueKey('forget-device-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Forget')),
        ],
      ),
    );
    if (ok != true) return;
    final list = await widget.repository.forget(device);
    if (mounted) setState(() => _remembered = list);
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    // Explicitly request both Bluetooth and Fine Location permissions on Android
    try {
      const permService =
          AndroidPermissionService(PermissionHandlerRequester());
      await permService.requestForSdk(33);
      await permService.requestForSdk(30);
    } catch (_) {}

    // Wait until the BT adapter is on (handles macOS/iOS/Android initialization delay)
    final BluetoothAdapterState adapterState;
    try {
      adapterState = await FlutterBluePlus.adapterState
          .firstWhere((s) => s != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 5),
              onTimeout: () => BluetoothAdapterState.unavailable);
    } on UnsupportedError {
      if (mounted) setState(() => _isScanning = false);
      return;
    }
    if (adapterState != BluetoothAdapterState.on) {
      if (mounted) {
        setState(() => _isScanning = false);
        _showError(AppStrings.of(context).text(AppText.bluetoothOff));
      }
      return;
    }
    final service = ref.read(bluetoothServiceProvider);
    await service.startScan(timeout: const Duration(seconds: 10));
    if (mounted) setState(() => _isScanning = false);
    _maybeAutoConnect();
  }

  Future<void> _connect(DiscoveredDongle dongle) async {
    setState(() => _connectingId = dongle.device.remoteId.str);
    final service = ref.read(bluetoothServiceProvider);
    final success = await service.connect(dongle);
    if (success) {
      try {
        await widget.repository
            .remember(address: dongle.address, fingerprint: dongle.fingerprint);
      } on Object catch (e) {
        debugPrint('Remembering controller failed: $e');
      }
    }
    if (mounted) {
      setState(() => _connectingId = null);
      if (success) {
        // Opened from the cockpit/settings: return to the existing shell
        // instead of stacking a second one (which made back behave oddly).
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          navigator.pushReplacementNamed('/dashboard');
        }
      } else {
        _showError(AppStrings.of(context).text(AppText.connectionFailed));
      }
    }
  }

  Widget _buildList(List<DiscoveredDongle> scanResults) {
    final matcher = RememberedDeviceMatcher(_remembered);
    final split = matcher.split(scanResults, _seen);
    final seenRemembered = {
      for (final d in split.previous) matcher.rememberedFor(_seen(d)),
    };
    final absent =
        _remembered.where((r) => !seenRemembered.contains(r)).toList();
    if (scanResults.isEmpty && _remembered.isEmpty) {
      return _EmptyState(isScanning: _isScanning);
    }
    Widget header(String text, Key key) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
          child: Text(text,
              key: key,
              style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
        );
    Widget card(DiscoveredDongle d, {RememberedDevice? remembered}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _DongleCard(
            key: ValueKey('dongle-${d.address}'),
            dongle: d,
            isConnecting: _connectingId == d.device.remoteId.str,
            onTap: () {
              _autoCancelled = true; // the user chose
              _connect(d);
            },
            onForget: remembered == null ? null : () => _forget(remembered),
          ),
        );
    return ListView(
      key: const ValueKey('dongle-list'),
      children: [
        if (_remembered.isNotEmpty) ...[
          header('PREVIOUSLY CONNECTED', const ValueKey('section-previous')),
          for (final d in split.previous)
            card(d, remembered: matcher.rememberedFor(_seen(d))),
          for (final r in absent)
            ListTile(
              key: ValueKey('remembered-absent-${r.lastAddress}'),
              dense: true,
              leading: const Icon(Icons.bluetooth_disabled,
                  color: Color(0xFF4A5568)),
              title: Text(
                  r.fingerprint.name.isEmpty
                      ? r.lastAddress
                      : r.fingerprint.name,
                  style: const TextStyle(color: Colors.white70)),
              subtitle: Text('Not in range · last ${r.lastAddress}',
                  style: const TextStyle(color: Color(0xFF4A5568))),
              trailing: IconButton(
                key: ValueKey('forget-${r.lastAddress}'),
                tooltip: 'Forget',
                icon:
                    const Icon(Icons.delete_outline, color: Color(0xFF4A5568)),
                onPressed: () => _forget(r),
              ),
            ),
          if (split.others.isNotEmpty)
            header('OTHER DEVICES', const ValueKey('section-others')),
        ],
        for (final d in split.others) card(d),
        if (scanResults.isEmpty) _EmptyState(isScanning: _isScanning),
      ],
    );
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
    final connectionState = ref.watch(connectionStateProvider).valueOrNull ??
        DongleConnectionState.idle;
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
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
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
                        'FARSURE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                      Text(
                        AppStrings.of(context).text(AppText.controllerConnect),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
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
                  Text(
                    AppStrings.of(context).text(AppText.nearbyDongles),
                    style: const TextStyle(
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
                    label: Text(AppStrings.of(context).text(
                        _isScanning ? AppText.searching : AppText.search)),
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
                child: _buildList(scanResults),
              ),
              // Info footer
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2030).withValues(alpha: 0.5),
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
                        AppStrings.of(context)
                            .text(AppText.scanShowsAllDevices),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Diagnostic Log Share Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final diagnostics = ref.read(diagnosticsLogProvider);
                    DiagnosticLogExporter.shareOrCopy(context, diagnostics,
                        store: ref.read(savedFilesStoreProvider));
                  },
                  icon: const Icon(Icons.share, size: 18),
                  label: Text(
                      AppStrings.of(context).text(AppText.shareDiagnosticLog)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
  final VoidCallback? onForget;

  const _DongleCard({
    super.key,
    required this.dongle,
    required this.isConnecting,
    required this.onTap,
    this.onForget,
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
                color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
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
                      color: Colors.white.withValues(alpha: 0.35),
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
                if (onForget != null)
                  IconButton(
                    key: ValueKey('forget-${dongle.address}'),
                    tooltip: 'Forget',
                    onPressed: onForget,
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFF4A5568), size: 20),
                  )
                else
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
          const Icon(
            Icons.bluetooth_searching,
            size: 56,
            color: Color(0xFF2A3548),
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.of(context).text(
                isScanning ? AppText.searchingDongles : AppText.noDongles),
            style: const TextStyle(
              color: Color(0xFF4A5568),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isScanning
                ? AppStrings.of(context).text(AppText.scanningHint)
                : AppStrings.of(context).text(AppText.searchAgain),
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
