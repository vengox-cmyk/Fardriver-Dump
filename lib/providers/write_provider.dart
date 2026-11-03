import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/services/write/write_service.dart';

/// Experimental-writes toggle (Settings › Controller writes). Persisted in
/// AppSettings, off by default.
final experimentalWritesProvider =
    NotifierProvider<ExperimentalWritesController, bool>(
        ExperimentalWritesController.new);

class ExperimentalWritesController extends Notifier<bool> {
  @override
  bool build() => ref
      .read(storageServiceProvider)
      .appSettings
      .loadSettings()
      .experimentalWrites;

  void set(bool on) {
    final repo = ref.read(storageServiceProvider).appSettings;
    repo.saveSettings(repo.loadSettings().copyWith(experimentalWrites: on));
    state = on;
  }
}

/// [ControllerWriteLink] over the live BLE connection.
class _NotifierLink implements ControllerWriteLink {
  _NotifierLink(this.ref);
  final Ref ref;

  ControllerNotifier get _n => ref.read(controllerProvider.notifier);

  @override
  bool get connected => _n.linkConnected;
  @override
  Duration get connectedFor => _n.connectedFor;
  @override
  Duration get sinceLastFrame => _n.sinceLastFrame;
  @override
  int get rpm => ref.read(controllerProvider).motorRpm;
  @override
  double get speedKph => ref.read(controllerProvider).speedKph;
  @override
  String get controllerName {
    final name = ref.read(connectedDeviceNameProvider)?.trim();
    return (name == null || name.isEmpty) ? 'FarDriver' : name;
  }

  @override
  Map<int, List<int>> get latestBlocks => _n.latestBlocks;
  @override
  Stream<int> get blockArrivals => _n.blockArrivals;
  @override
  Future<void> send(List<int> frame) => _n.sendFrame(frame);
}

final controllerWriteServiceProvider = Provider<ControllerWriteService>((ref) {
  return ControllerWriteService(
    link: _NotifierLink(ref),
    store: ref.watch(savedFilesStoreProvider),
    experimentalEnabled: () => ref.read(experimentalWritesProvider),
    appVersion: 'FarSure',
  );
});

/// Settings tile for the experimental toggle.
class ExperimentalWritesTile extends ConsumerWidget {
  const ExperimentalWritesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(experimentalWritesProvider);
    return SwitchListTile(
      key: const ValueKey('experimental-writes'),
      secondary: const Icon(Icons.science_outlined),
      title: const Text('Experimental controller writes'),
      subtitle: const Text(
          'Also allow settings whose write is not yet confirmed on a real '
          'controller (battery over-voltage protect / restore). Every write '
          'still needs your review, makes a backup and is verified.'),
      value: on,
      onChanged: (v) => ref.read(experimentalWritesProvider.notifier).set(v),
    );
  }
}
