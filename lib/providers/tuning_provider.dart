import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/providers/controller_provider.dart';

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
    state = state.copyWith(
      lastError:
          'Write engine locked until hardware limits and read-back are verified.',
    );
    return false;
  }

  /// Restores stock parameters from backup.
  Future<bool> restoreStock() async {
    state = state.copyWith(
      lastError: 'Restore locked until the safe write engine is complete.',
    );
    return false;
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
