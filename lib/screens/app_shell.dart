import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/calibration_provider.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/screens/settings_screen.dart';
import 'package:arcdash/screens/stats_screen.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState;
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/remembered_auto_connect.dart';

/// The root of the app: Cockpit / Rides / Settings tabs.
///
/// The tabs are not routes, so Android's back (gesture, nav bar or a
/// hardware KEYCODE_BACK key such as on a Zebra TC72) would pop this root
/// route and close the app. [PopScope] catches it instead:
/// * Rides/Settings → back returns to the Cockpit tab.
/// * Cockpit → first back shows a hint, a second back within
///   [exitWindow] exits. While a controller is connected or a ride or
///   calibration is recording, a "Disconnect and exit?" dialog asks first.
/// Screens pushed on top (Saved files, dumps, calibration, …) are their own
/// routes and keep popping normally.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// How long the "Press back again to exit" hint stays armed.
  static const exitWindow = Duration(seconds: 2);

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  Timer? _exitArmedTimer;
  bool _confirmOpen = false;
  bool _exiting = false;

  static const _screens = [
    DashboardScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // v1.2.3: reconnect on its own when exactly one previously connected
    // controller is around. No-op when none is remembered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
          RememberedAutoConnect(service: ref.read(bluetoothServiceProvider))
              .run());
    });
  }

  @override
  void dispose() {
    _exitArmedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack();
        },
        child: LayoutBuilder(builder: _buildLayout),
      );

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    final strings = AppStrings.of(context);
    final destinations = [
      NavigationDestination(
          icon: const Icon(Icons.speed), label: strings.text(AppText.cockpit)),
      NavigationDestination(
          icon: const Icon(Icons.route_outlined),
          label: strings.text(AppText.rides)),
      NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          label: strings.text(AppText.settings)),
    ];
    final useRail = constraints.maxWidth >= 700;
    final content = IndexedStack(
      index: _selectedIndex,
      children: _screens,
    );
    if (useRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: destinations
                    .map((destination) => NavigationRailDestination(
                          icon: destination.icon,
                          selectedIcon: destination.selectedIcon,
                          label: Text(destination.label),
                        ))
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        destinations: destinations,
      ),
    );
  }

  void _select(int index) {
    _disarmExit();
    setState(() => _selectedIndex = index);
  }

  void _handleBack() {
    if (_exiting || _confirmOpen) return;
    if (_selectedIndex != 0) {
      _select(0);
      return;
    }
    if (_isBusy()) {
      unawaited(_confirmExit());
      return;
    }
    if (_exitArmedTimer?.isActive ?? false) {
      _disarmExit();
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      unawaited(_exitApp());
      return;
    }
    _exitArmedTimer = Timer(AppShell.exitWindow, () {});
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      key: const ValueKey('press-back-again-snackbar'),
      content: Text(AppStrings.of(context).text(AppText.pressBackAgainToExit)),
      duration: AppShell.exitWindow,
    ));
  }

  void _disarmExit() {
    _exitArmedTimer?.cancel();
    _exitArmedTimer = null;
  }

  /// Connected (or connecting) controller, a ride being recorded, or a
  /// running GPS calibration: leaving would cut the live session.
  bool _isBusy() {
    final connection = ref.read(connectionStateProvider).valueOrNull;
    if (connection == DongleConnectionState.connected ||
        connection == DongleConnectionState.connecting) {
      return true;
    }
    if (ref.read(statsProvider).currentSession != null) return true;
    return ref.exists(gpsCalibrationProvider) &&
        ref.read(gpsCalibrationProvider).isRecording;
  }

  Future<void> _confirmExit() async {
    _disarmExit();
    _confirmOpen = true;
    final strings = AppStrings.of(context);
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('exit-confirm-dialog'),
        title: Text(strings.text(AppText.exitConfirmTitle)),
        content: Text(strings.text(AppText.exitConfirmBody)),
        actions: [
          TextButton(
            key: const ValueKey('exit-confirm-stay'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text(AppText.exitConfirmStay)),
          ),
          FilledButton(
            key: const ValueKey('exit-confirm-exit'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text(AppText.exitConfirmExit)),
          ),
        ],
      ),
    );
    _confirmOpen = false;
    if (exit == true && mounted) await _disconnectAndExit();
  }

  /// Saves what is running, closes the BLE link, then leaves the app.
  Future<void> _disconnectAndExit() async {
    _exiting = true;
    try {
      if (ref.exists(gpsCalibrationProvider) &&
          ref.read(gpsCalibrationProvider).isRecording) {
        await ref.read(gpsCalibrationProvider.notifier).stop();
      }
      await ref.read(statsProvider.notifier).finishSession();
      await ref
          .read(bluetoothServiceProvider)
          .disconnect()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Leaving must not get stuck on a save or a BLE error.
    }
    await _exitApp();
  }

  Future<void> _exitApp() async {
    _exiting = true;
    await SystemNavigator.pop();
    // On Android the activity finishes; elsewhere nothing happens, so allow
    // back to work again.
    _exiting = false;
  }
}
