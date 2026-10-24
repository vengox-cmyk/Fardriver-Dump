import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';

/// The current controller values the calibration compares against, read
/// (never written) from the captured parameter blocks.
class CalibrationSettings {
  /// Wheel geometry + RateRatio (0xD0), null if never received.
  final BleSpeedSettings? ble;

  /// Speed Pulses (0x18 byte 5 bits 0-4) and SpdPulseNum (0x30 byte 10, u16).
  final int? speedPulses;
  final int? spdPulseNum;

  /// Human readable origin, e.g. "parameter snapshot 2026-10-24 18:02".
  final String source;

  const CalibrationSettings({
    required this.ble,
    required this.speedPulses,
    required this.spdPulseNum,
    required this.source,
  });

  static const none = CalibrationSettings(
      ble: null, speedPulses: null, spdPulseNum: null, source: 'not read yet');

  static int? _read(Map<int, List<int>> blocks, String name, int block) {
    final bytes = blocks[block];
    if (bytes == null || bytes.length < FardriverParamCatalog.blockLength) {
      return null;
    }
    return FardriverDecoder.rawInt(
        FardriverParamCatalog.byName(name, block: block), bytes);
  }

  /// Decodes the needed fields from raw config blocks (address -> 12 bytes).
  static CalibrationSettings fromBlocks(Map<int, List<int>> blocks,
      {required String source}) {
    final radius = _read(blocks, 'WheelRadius', 0xD0);
    final width = _read(blocks, 'WheelWidth', 0xD0);
    final ratio = _read(blocks, 'WheelRatio', 0xD0);
    final rate = _read(blocks, 'RateRatio', 0xD0);
    return CalibrationSettings(
      ble: radius != null && width != null && ratio != null && (rate ?? 0) > 0
          ? BleSpeedSettings(
              wheelRadius: radius,
              wheelWidth: width,
              wheelRatio: ratio,
              rateRatio: rate!)
          : null,
      speedPulses: _read(blocks, 'SpeedPulse', 0x18),
      spdPulseNum: _read(blocks, 'SpdPulseNum', 0x30),
      source: source,
    );
  }

  /// Prefers a parameter snapshot; falls back to the live 0xD0 geometry
  /// already decoded into [ControllerState] (Speed Pulses / SpdPulseNum are
  /// only available from a snapshot).
  static CalibrationSettings resolve({
    PersistedParameterSnapshot? snapshot,
    required ControllerState live,
    required bool liveGeometryReceived,
  }) {
    final fromSnapshot = snapshot == null
        ? null
        : fromBlocks(snapshot.rawBlocks,
            source: 'parameter snapshot ${_stamp(snapshot.capturedAt)}');
    final liveBle = liveGeometryReceived && live.rateRatio > 0
        ? BleSpeedSettings(
            wheelRadius: live.wheelRadius,
            wheelWidth: live.wheelWidth,
            wheelRatio: live.wheelRatio,
            rateRatio: live.rateRatio)
        : null;
    if (fromSnapshot == null) {
      return CalibrationSettings(
        ble: liveBle,
        speedPulses: null,
        spdPulseNum: null,
        source: liveBle == null ? 'not read yet' : 'live telemetry (0xD0)',
      );
    }
    return CalibrationSettings(
      ble: fromSnapshot.ble ?? liveBle,
      speedPulses: fromSnapshot.speedPulses,
      spdPulseNum: fromSnapshot.spdPulseNum,
      source: fromSnapshot.source,
    );
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
