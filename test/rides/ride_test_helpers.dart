import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/services/parameter_dump.dart';

/// Builds a live dump with the given values (unset fields are zero).
ParameterDump testDump({
  double maxLineA = 200,
  double maxPhaseA = 400,
  int motorProtectC = 120,
  int mosProtectC = 90,
  int timeHour = 10,
  int unk2Cb = 0,
  DateTime? at,
}) {
  final blocks = <int, List<int>>{
    0x18: List.filled(12, 0),
    0x1E: List.filled(12, 0),
    0x2A: List.filled(12, 0),
    0x82: List.filled(12, 0),
  };
  void u16(int block, int offset, int raw) {
    blocks[block]![offset] = raw & 0xFF;
    blocks[block]![offset + 1] = (raw >> 8) & 0xFF;
  }

  u16(0x18, 2, (maxLineA * 4).round());
  u16(0x2A, 6, (maxPhaseA * 4).round());
  blocks[0x2A]![5] = unk2Cb;
  blocks[0x82]![4] = motorProtectC;
  blocks[0x82]![6] = mosProtectC;
  blocks[0x1E]![11] = timeHour;
  return ParameterDump(
    source: ParameterDumpSource.live,
    sourceLabel: 'live',
    blocks: blocks,
    requiredBlocks: const [],
    controllerId: 'ND961000',
    capturedAt: at,
  );
}

RideRecord testRide({
  required DateTime start,
  Duration length = const Duration(minutes: 10),
  double maxSpeedKph = 50,
  double? maxLineA = 150,
  double? maxPhaseA = 300,
  double? maxV = 84,
  double? maxSagV = 4,
  double? maxMotorC = 60,
  double? maxControllerC = 45,
  double? avgPowerW = 1000,
  double boostSeconds = 0,
  String? settingsDump,
}) =>
    RideRecord(
      id: start.millisecondsSinceEpoch.toString(),
      start: start,
      end: start.add(length),
      distanceKm: 5,
      maxSpeedKph: maxSpeedKph,
      avgSpeedKph: 30,
      whUsed: 120,
      maxLineA: maxLineA,
      maxPhaseA: maxPhaseA,
      minV: maxV == null ? null : maxV - 8,
      maxV: maxV,
      maxSagV: maxSagV,
      maxMotorC: maxMotorC,
      maxControllerC: maxControllerC,
      avgPowerW: avgPowerW,
      peakPowerW: 9000,
      boostSeconds: boostSeconds,
      settingsDump: settingsDump,
    );

FardriverParamDef def(String name) => FardriverParamCatalog.byName(name);
