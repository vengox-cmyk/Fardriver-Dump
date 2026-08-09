import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/models/controller_state.dart';
import 'package:biketunes/models/tuning_profile.dart';
import 'package:biketunes/providers/bluetooth_provider.dart';
import 'package:biketunes/providers/controller_provider.dart';
import 'package:biketunes/services/protocol_service.dart';
import 'package:biketunes/services/storage_service.dart';

class TuningState {
  final TuningProfile pendingProfile;
  final bool isApplying;
  final String? lastError;
  final bool appliedSuccessfully;
  final List<TuningProfile> savedProfiles;

  const TuningState({
    required this.pendingProfile,
    this.isApplying = false,
    this.lastError,
    this.appliedSuccessfully = false,
    this.savedProfiles = const [],
  });

  TuningState copyWith({
    TuningProfile? pendingProfile,
    bool? isApplying,
    String? lastError,
    bool? appliedSuccessfully,
    List<TuningProfile>? savedProfiles,
  }) =>
      TuningState(
        pendingProfile: pendingProfile ?? this.pendingProfile,
        isApplying: isApplying ?? this.isApplying,
        lastError: lastError,
        appliedSuccessfully: appliedSuccessfully ?? this.appliedSuccessfully,
        savedProfiles: savedProfiles ?? this.savedProfiles,
      );
}

class TuningNotifier extends StateNotifier<TuningState> {
  final Ref _ref;

  TuningNotifier(this._ref)
      : super(TuningState(pendingProfile: TuningProfile.trail())) {
    _loadProfiles();
  }

  void _loadProfiles() {
    final storage = _ref.read(storageServiceProvider);
    final profiles = storage.loadProfiles();
    state = state.copyWith(savedProfiles: profiles);
  }

  void updateMaxSpeed(double kph) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxSpeedKph: kph),
      appliedSuccessfully: false,
    );
  }

  void updateMaxLineCurr(double amps) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxLineCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateMaxPhaseCurr(double amps) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(maxPhaseCurrA: amps),
      appliedSuccessfully: false,
    );
  }

  void updateRegen(double strength) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(regenStrength: strength),
      appliedSuccessfully: false,
    );
  }

  void updateThrottleResponse(int val) {
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(throttleResponse: val),
      appliedSuccessfully: false,
    );
  }

  void updatePowerCurvePoint(int index, PowerPoint point) {
    final curve = List<PowerPoint>.from(state.pendingProfile.powerCurve);
    if (index >= 0 && index < curve.length) {
      curve[index] = point;
    }
    state = state.copyWith(
      pendingProfile: state.pendingProfile.copyWith(powerCurve: curve),
      appliedSuccessfully: false,
    );
  }

  void loadPreset(TuningProfile preset) {
    state = state.copyWith(
      pendingProfile: preset,
      appliedSuccessfully: false,
      lastError: null,
    );
  }

  /// Applies all pending profile parameters to the controller.
  Future<bool> applyProfile() async {
    final controllerState = _ref.read(controllerProvider);

    // Safety: must be stationary
    if (controllerState.speedKph > 2.0) {
      state = state.copyWith(
        lastError: 'Cannot apply tuning while moving. Stop the bike first.',
      );
      return false;
    }

    state = state.copyWith(isApplying: true, lastError: null);

    final bluetooth = _ref.read(bluetoothServiceProvider);
    final profile = state.pendingProfile;

    try {
      // Convert speed kph → raw RPM using wheel geometry
      final rawSpeed = ProtocolService.kphToMaxSpeedRaw(
        kph: profile.maxSpeedKph,
        wheelRadius: controllerState.wheelRadius,
        wheelWidth: controllerState.wheelWidth,
        wheelRatio: controllerState.wheelRatio,
        rateRatio: controllerState.rateRatio,
      );

      // Write max speed
      final ok1 = await bluetooth.write(
          ProtocolService.setMaxSpeedPacket(rawSpeed));
      await Future.delayed(const Duration(milliseconds: 50));

      // Write max line current
      final ok2 = await bluetooth.write(
          ProtocolService.setMaxLineCurrPacket(profile.maxLineCurrA));
      await Future.delayed(const Duration(milliseconds: 50));

      // Write throttle response
      final ok3 = await bluetooth.write(
          ProtocolService.setThrottleResponsePacket(profile.throttleResponse));
      await Future.delayed(const Duration(milliseconds: 50));

      final success = ok1 && ok2 && ok3;
      state = state.copyWith(
        isApplying: false,
        appliedSuccessfully: success,
        lastError: success ? null : 'Write failed — check connection',
      );
      return success;
    } catch (e) {
      state = state.copyWith(
        isApplying: false,
        lastError: 'Error applying profile: $e',
      );
      return false;
    }
  }

  /// Restores stock parameters from backup.
  Future<bool> restoreStock() async {
    final storage = _ref.read(storageServiceProvider);
    final backup = storage.loadStockBackup();
    if (backup == null) {
      state = state.copyWith(lastError: 'No stock backup found.');
      return false;
    }

    state = state.copyWith(isApplying: true, lastError: null);
    final bluetooth = _ref.read(bluetoothServiceProvider);

    try {
      for (final entry in backup.entries) {
        await bluetooth.write(
            ProtocolService.buildWritePacket(entry.key, entry.value));
        await Future.delayed(const Duration(milliseconds: 50));
      }
      state = state.copyWith(
        isApplying: false,
        appliedSuccessfully: true,
        pendingProfile: TuningProfile.stock(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(isApplying: false, lastError: 'Restore failed: $e');
      return false;
    }
  }

  Future<void> saveCurrentProfile(String name) async {
    final storage = _ref.read(storageServiceProvider);
    final profile = state.pendingProfile.copyWith(
      name: name,
      createdAt: DateTime.now(),
    );
    await storage.saveProfile(profile);
    _loadProfiles();
  }

  Future<void> deleteProfile(String name) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.deleteProfile(name);
    _loadProfiles();
  }
}

final tuningProvider =
    StateNotifierProvider<TuningNotifier, TuningState>((ref) {
  return TuningNotifier(ref);
});
