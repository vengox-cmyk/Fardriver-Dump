import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/utils/speed_units.dart';

/// Read-only "Pro view" of a saved dump: FarDriver's own pro-mode pages
/// (pro_p1..p8) rebuilt from the raw blocks, in FarDriver's section and
/// field order, with FarDriver's labels (typos included, e.g. "CostumCode")
/// and value formatting ("96V15000W", "0-120°Hall", "8-PIN17", ...).
///
/// Pure Dart and offline: it only reads `dump.blocks`. Nothing here is ever
/// written to the controller.
class ProViewCell {
  const ProViewCell(
    this.label,
    this.value, {
    this.uncertain = false,
    this.colon = true,
    this.note = '',
  });

  /// FarDriver's label exactly as on its screen.
  final String label;

  /// Value formatted the way FarDriver shows it.
  final String value;

  /// Mapping or scale not proven against the official app (small marker).
  final bool uncertain;

  /// False for the ratio rows ("500RPM 100%"), which have no colon.
  final bool colon;

  /// Why it is uncertain / where it comes from (shown on long-press).
  final String note;

  /// "Label:value" / "500RPM 100%".
  String get text => colon ? '$label:$value' : '$label $value';
}

class ProViewSection {
  const ProViewSection(this.title, this.cells, {this.extra = false});

  /// Header text as FarDriver shows it ("- Parameters").
  final String title;

  /// Two-column grid, read left to right; `null` is an empty slot (FarDriver
  /// leaves e.g. the cell next to "Gear" blank).
  final List<ProViewCell?> cells;

  /// True for the trailing "Not on FarDriver screens" section.
  final bool extra;

  int get rowCount => (cells.length + 1) ~/ 2;
}

/// The ModelType block at the top of page 1.
class ProViewHeader {
  const ProViewHeader({
    required this.modelTyp,
    required this.voltagePower,
    required this.lineCurrPhaseCurr,
    required this.productCode,
    required this.costumCode,
    required this.morseCode,
  });

  final ProViewCell modelTyp;
  final ProViewCell voltagePower;
  final ProViewCell lineCurrPhaseCurr;
  final ProViewCell productCode;
  final ProViewCell costumCode;
  final ProViewCell morseCode;

  List<ProViewCell> get cells => [
        modelTyp,
        voltagePower,
        lineCurrPhaseCurr,
        productCode,
        costumCode,
        morseCode
      ];
}

class ProView {
  ProView._(this.header, this.sections);

  final ProViewHeader header;

  /// Sections after the ModelType block, ending with the extra
  /// "Not on FarDriver screens" section.
  final List<ProViewSection> sections;

  static const String modelTypeTitle = 'ModelType';
  static const String extraTitle = 'Not on FarDriver screens';

  /// Every cell with its section title (header cells under "ModelType").
  Iterable<(String, ProViewCell)> get allCells sync* {
    for (final c in header.cells) {
      yield (modelTypeTitle, c);
    }
    for (final s in sections) {
      for (final c in s.cells) {
        if (c != null) yield (s.title, c);
      }
    }
  }

  /// First cell with this FarDriver [label] (optionally in [section]).
  ProViewCell? find(String label, {String? section}) {
    for (final (title, cell) in allCells) {
      if (cell.label == label && (section == null || title == section)) {
        return cell;
      }
    }
    return null;
  }

  static ProView build(ParameterDump dump, {SpeedUnit unit = SpeedUnit.kmh}) =>
      _Builder(dump, unit).build();

  /// FarDriver's pin dropdown index for a raw pin code (PIN_lut in
  /// fardriver.hpp; matches the official screens, e.g. raw 4 -> 8-PIN17).
  static const List<int> pinUiIndex = [
    0, 10, 7, 3, 8, 6, 2, 4, 12, 13, 1, 9, 5, 11, 13, 13 //
  ];

  static const Map<int, String> _pinNames = {
    0: 'NC', 1: 'PIN24', 2: 'PIN15', 3: 'PIN5', 4: 'PIN17', 5: 'PIN14', //
    6: 'PIN3', 7: 'PIN8', 8: 'PB4', 10: 'PIN2', 11: 'PIN18', 12: 'PIN9',
    13: 'PD1',
  };

  /// "8-PIN17", "13-Invalid", "0-NC".
  static String pin(int raw) {
    final index = raw >= 0 && raw < 16 ? pinUiIndex[raw] : raw;
    return '$index-${_pinNames[raw] ?? 'Invalid'}';
  }
}

class _Builder {
  _Builder(this.dump, this.unit);

  final ParameterDump dump;
  final SpeedUnit unit;
  final Set<String> _used = {};

  static const _dash = '—';

  FardriverParamDef _def(String name, [int? block]) {
    final def = FardriverParamCatalog.byName(name, block: block);
    _used.add(def.key);
    return def;
  }

  /// Raw integer of a catalog field, or null when its block is missing.
  int? raw(String name, [int? block]) {
    final def = _def(name, block);
    final bytes = dump.blocks[def.block];
    return bytes == null ? null : FardriverDecoder.rawInt(def, bytes);
  }

  /// Scaled number formatted like the dump CSV ("1.1", "121.5").
  String? num(String name, [int? block]) {
    final def = _def(name, block);
    final bytes = dump.blocks[def.block];
    if (bytes == null) return null;
    return FardriverDecoder.formatScaled(
        FardriverDecoder.rawInt(def, bytes), def.factor, def.offset);
  }

  ProViewCell cell(String label, String? value,
          {bool uncertain = false, bool colon = true, String note = ''}) =>
      ProViewCell(label, value ?? _dash,
          uncertain: uncertain || value == null, colon: colon, note: note);

  /// Numeric field + FarDriver unit suffix ("250A", "6299RPM", "45AH").
  ProViewCell n(String label, String name,
      {String suffix = '',
      int? block,
      bool uncertain = false,
      String note = ''}) {
    final v = num(name, block);
    return cell(label, v == null ? null : '$v$suffix',
        uncertain: uncertain, note: note);
  }

  /// "number-name" enum using FarDriver's names; unknown raw -> number only.
  ProViewCell e(String label, String name, Map<int, String> names,
      {bool uncertain = false, String note = ''}) {
    final r = raw(name);
    if (r == null) return cell(label, null);
    final text = names[r];
    return cell(label, text == null ? '$r' : '$r-$text',
        uncertain: uncertain || text == null,
        note: text == null ? 'Name for raw $r not known' : note);
  }

  ProViewCell pinCell(String label, String name) {
    final r = raw(name);
    return cell(label, r == null ? null : ProView.pin(r));
  }

  String _ascii(int block, int from, int to) {
    final bytes = dump.blocks[block];
    if (bytes == null) return '';
    return FardriverDecoder.ascii(bytes.sublist(from, to));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  ProViewHeader header() {
    final custom = _ascii(0x1E, 4, 6);
    _def('CustomCode');
    final volt = num('ProdMaxVol');
    final phase2 = raw('MaxPhaseCurr2');
    final dia = raw('MotorDia');
    final tens = raw('unkBEb');
    int? sensorType;
    if (dia != null && tens != null) {
      sensorType = tens == 0 ? dia + 10 : (tens < 10 ? dia + tens * 10 : 0);
    }
    final model = (volt == null || phase2 == null || sensorType == null)
        ? null
        : '$custom${volt.split('.').first}${phase2 ~/ 4}_${sensorType}_…';
    final ratedV = num('RatedVoltage');
    final ratedP = num('RatedPower');
    final line = num('MaxLineCurr');
    final phase = num('MaxPhaseCurr');
    _def('ModelName', 0xA0);
    _def('ModelName', 0xA6);
    final product = dump.blocks[0xA0] == null || dump.blocks[0xA6] == null
        ? null
        : '${_ascii(0xA0, 2, 12)}${_ascii(0xA6, 0, 10)}';
    final morse = raw('MorseCode');
    return ProViewHeader(
      modelTyp: cell('ModelTyp', model,
          uncertain: true,
          note: 'Built from CustomCode + ProdMaxVol + MaxPhaseCurr2/4 + '
              'sensor type (MotorDia + unkBEb×10). The trailing letters '
              '(e.g. AKH) are not in the dump.'),
      voltagePower: cell('Voltage/Power',
          ratedV == null || ratedP == null ? null : '${ratedV}V${ratedP}W'),
      lineCurrPhaseCurr: cell('LineCurr/PhaseCurr',
          line == null || phase == null ? null : '${line}A/${phase}A'),
      productCode: cell('ProductCode', product),
      costumCode: cell('CostumCode', dump.blocks[0x1E] == null ? null : custom),
      morseCode: cell('MorseCode', morse?.toString().padLeft(6, '0')),
    );
  }

  ProViewSection dateTime() {
    final y = raw('ModelYear'), m = raw('ModelMonth'), d = raw('ModelDay');
    final h = raw('TimeHour'), mi = raw('TimeMin'), s = raw('TimeSecond');
    return ProViewSection('- DateTime', [
      cell(
          'Date',
          y == null || m == null || d == null
              ? null
              : '${2000 + y}-${_two(m)}-${_two(d)}'),
      cell(
          'Time',
          h == null || mi == null || s == null
              ? null
              : '${_two(h)}:${_two(mi)}:${_two(s)}'),
    ]);
  }

  ProViewSection parameters() {
    final phaseOffset = raw('PhaseOffset');
    final weak = raw('WeakA');
    final exchange = raw('PhaseExchange');
    return ProViewSection('- Parameters', [
      cell('AngleDetect', null,
          note: 'Not located in the dump (FarDriver showed 0-120°Hall).'),
      e('TempSensor', 'TempSensor', _labels('TempSensor')),
      cell('PhaseOffset', phaseOffset == null ? null : '${phaseOffset ~/ 10}',
          note: 'FarDriver drops the decimal (raw/10, truncated).'),
      n('PolePairs', 'PolePairs'),
      n('Motor Direction', 'Direction'),
      n('RatedSpeed', 'RatedSpeed', suffix: 'RPM'),
      n('RatedVoltage', 'RatedVoltage', suffix: 'V'),
      n('RatedPower', 'RatedPower', suffix: 'W'),
      n('MaxSpeed', 'MaxSpeed', suffix: 'RPM'),
      n('BackSpeed', 'BackSpeed', suffix: 'RPM'),
      n('MaxLineCurr', 'MaxLineCurr', suffix: 'A'),
      n('MaxPhaseCurr', 'MaxPhaseCurr', suffix: 'A'),
      e('ThrottleResponse', 'ThrottleResponse', _labels('ThrottleResponse')),
      n('Throttle Acc Step', 'Max_Acc'),
      n('BoostLineCurr', 'CustomMaxLineCurr', suffix: 'A'),
      n('BoostPhaseCurr', 'CustomMaxPhaseCurr', suffix: 'A'),
      cell('PhaseExchange',
          exchange == null ? null : (exchange == 1 ? 'Exchange' : 'Normal'),
          uncertain: exchange == 0,
          note: exchange == 0 ? 'Text for 0 not seen on FarDriver.' : ''),
      n('ECOAccCoeff', 'AccCoeff'),
      cell('Weak Character',
          weak == null ? null : (weak == 0 ? '0-Fast' : '$weak'),
          uncertain: true,
          note: 'WeakA (0x18 byte 4 bits 4-5); only value 0 seen.'),
      n('WeakResponse', 'WeakTime',
          uncertain: true, note: 'WeakTime (0x7C byte 0 bits 1-3).'),
      n('Throttle Dec Step', 'Max_Dec'),
      n('Release Throttle', 'QuickDown',
          uncertain: true,
          note: 'QuickDown (0x7C byte 0 bits 5-7); only value 0 seen.'),
      n('Throttle Low', 'ThrottleLow', suffix: 'V'),
      n('Throttle High', 'ThrottleHigh', suffix: 'V'),
    ]);
  }

  ProViewSection ratiosInSpeed() => ProViewSection('- Ratios in Speed', [
        for (var r = 500; r <= 9000; r += 500) _ratio('${r}RPM', 'Ratio$r'),
        n('LD', 'LD'),
        n('LQ', 'LQ'),
        n('FAIF', 'FAIF'),
        n('LimitSpeed', 'LmtSpeed', suffix: 'RPM'),
      ]);

  ProViewCell _ratio(String label, String name,
      {bool uncertain = false, String note = ''}) {
    final v = num(name);
    return cell(label, v == null ? null : '$v%',
        colon: false, uncertain: uncertain, note: note);
  }

  ProViewSection ratiosInGear() => ProViewSection('- Ratios in Gear', [
        n('LowSpeedLineRatio', 'LowSpeedLineCurr', suffix: '%'),
        n('MidSpeedLineRatio', 'MidSpeedLineCurr', suffix: '%'),
        n('LowSpeedPhaseRatio', 'LowSpeedPhaseCurr', suffix: '%'),
        n('MidSpeedPhaseRatio', 'MidSppedPhaseCurr', suffix: '%'),
        n('LowSpeed', 'LowSpeed', suffix: 'RPM'),
        n('MiddleSpeed', 'MidSpeed', suffix: 'RPM'),
      ]);

  ProViewSection energyRegenerate() => ProViewSection('- Energy Regenerate', [
        n('StopBackCurr', 'StopBackCurr', suffix: 'A'),
        n('MaxBackCurr', 'MaxBackCurr', suffix: 'A'),
        n('Batt RatedCapacity', 'BattRatedCap', suffix: 'AH'),
        null,
        n('FreeThrottle', 'FreeThrottle'),
        cell('Brake Voltage', null,
            note: 'Live reading on FarDriver, not stored in the dump.'),
        for (var i = 1; i <= 18; i++)
          _ratio('${i * 500}RPM', 'nratio_$i',
              uncertain: true,
              note: 'nratio_$i assumed = regen at ${i * 500} rpm '
                  '(by analogy with Ratios in Speed).'),
      ]);

  ProViewSection functions() {
    final longBack = raw('LongBack');
    final pc13 = raw('PC13Config');
    return ProViewSection('- Functions', [
      pinCell('Boost Pin', 'BoostPin'),
      pinCell('Cruise Pin', 'CruisePin'),
      pinCell('SideStand Pin', 'SideStandPin'),
      pinCell('Pause Pin', 'PausePin'),
      pinCell('Forward Pin', 'ForwardPin'),
      pinCell('Backward Pin', 'ReversePin'),
      pinCell('Highspeed Pin', 'HighSpeedPin'),
      pinCell('LowSpeed Pin', 'LowSpeedPin'),
      pinCell('Charge Pin', 'ChargePin'),
      pinCell('Anti-theft Pin', 'AntiTheftPin'),
      pinCell('Seat Pin', 'SeatPin'),
      pinCell('SpeedLimit Pin', 'SpeedLimitPin'),
      pinCell('Switch Voltage Pin', 'SwitchVolPin'),
      pinCell('Repair Pin', 'RepairPin'),
      n('BoostTime', 'BstTime', suffix: 's'),
      n('BoostRelease', 'BstRelease', suffix: 's'),
      e('HighLowSpeed', 'SPModeConfig', _labels('SPModeConfig')),
      cell('Puse RE',
          longBack == null ? null : (longBack == 0 ? '0-Invalid' : '$longBack'),
          uncertain: true, note: 'LongBack (0xCA byte 3 bit 6).'),
      n('EmptyRun', 'EmptySpeed',
          uncertain: true, note: 'EmptySpeed (0x9A byte 4 bits 6-7).'),
      n('SlowDown', 'SlowDown'),
      e('Gear', 'GearConfig', {
        for (final MapEntry(:key, :value) in _labels('GearConfig').entries)
          key: value.replaceFirstMapped(
              RegExp(r'^Default(N|D)$'), (m) => 'Default ${m[1]}'),
      }),
      null,
      e('Brake', 'BrakeConfig', _labels('BrakeConfig')),
      cell(
          'PC13',
          pc13 == null
              ? null
              : (pc13 == 0 ? '0-NomalResponse' : '$pc13-RaceResponse'),
          uncertain: pc13 == 1,
          note:
              pc13 == 1 ? 'Name from fardriver.hpp, not seen on screen.' : ''),
      e('Park', 'ParkConfig', {2: 'Disabled'}),
      e('Follow', 'FollowConfig', {
        0: 'Enabled',
        1: 'Disabled',
        2: 'EABSWhenBreakValid',
        3: 'EABSWhenReleaseThrottle'
      }),
    ]);
  }

  ProViewSection display() {
    final c1 = raw('SpeedMeterConfig1');
    final c2 = raw('SpeedMeterConfig2');
    final c3 = raw('SpeedMeterConfig3');
    String? speedo;
    var speedoSure = false;
    if (c1 != null && c2 != null && c3 != null) {
      speedoSure = c1 == 1 && c2 == 0 && c3 == 0;
      speedo = speedoSure ? '0-Pulse' : 'bits $c1/$c2/$c3';
    }
    final can = raw('CANConfig');
    _def('RateRatio'); // shown as GearRatio (same word, /1000)
    return ProViewSection('- Display', [
      n('Speed Pulses', 'SpeedPulse'),
      n('SpdPulseNum', 'SpdPulseNum'),
      cell('SpeedoMeter', speedo,
          uncertain: !speedoSure,
          note: 'SpeedMeterConfig1/2/3 bits; only 1/0/0 = 0-Pulse is known.'),
      n('AnalogSpeedCoeff', 'SpeedAnalog', suffix: 'RPM'),
      cell('CAN', can == null ? null : (can == 0 ? 'None' : '$can'),
          uncertain: can != null && can != 0),
      n('CAN Detect', 'NoCanCnt', suffix: 'ms'),
      e('CAN Baud', 'CANBaud', {0: '250K', 1: '500K', 2: '1M'}),
      n('TorqueCoeff', 'TorqueCoeff'),
      e('Step', 'Idle', {0: '0.5ms', 1: '0.9ms', 2: '1.5ms', 3: '1.9ms'}),
      e('Stop', 'Stop', {0: '24ms', 1: '55ms', 2: '124ms', 3: '216ms'}),
      n('SpecialFrame', 'SpecialFrame'),
      n('PULSE', 'Pulse'),
      n('SQH', 'SQH'),
      n('DATA0', 'Data0'),
      n('DATA1', 'Data1'),
      for (var i = 0; i < 8; i++) n('SEC$i', 'OneCommSec_$i'),
      n('PPosition', 'PausePosition'),
      n('BCPosition', 'SideStandPosition'),
      n('HbarPosition', 'HBarPosition'),
      n('FDPosition', 'AntiTheftPosition'),
      n('CurrentCoeff', 'OnelineCurrCoeff'),
      n('ByteOption', 'ByteOption'),
      n('WheelWidth', 'WheelWidth'),
      n('WheelRatio', 'WheelRatio'),
      n('WheelR', 'WheelRadius'),
      n('GearRatio', 'GearRatio', uncertain: true, note: 'RateRatio / 1000.'),
    ]);
  }

  ProViewSection protect() {
    final lowVol = raw('LowVolProtect');
    final lost = raw('ThrottleLost');
    final backP = raw('BackPTime');
    return ProViewSection('- Protect', [
      n('OverVolProtect', 'HighVolProtect', suffix: 'V'),
      n('OverVolRestore', 'HighVolRestore', suffix: 'V'),
      n('LowVolProtect', 'LowVolProtect', suffix: 'V'),
      cell(
          'LowVolRestore',
          lowVol == null
              ? null
              : '${FardriverDecoder.formatScaled(lowVol + 20, 0.1, 0)}V',
          note: 'Not stored: LowVolProtect + 2 V.'),
      n('MotorTempProtect', 'MotorTempProtect', suffix: '°C'),
      n('MotorTempRestore', 'MotorTempRestore', suffix: '°C'),
      n('ControllerTempProtect', 'MosTempProtect', suffix: '°C'),
      n('ControllerTempRestore', 'MosTempRestore', suffix: '°C'),
      n('0 BattCoeff', 'ZeroBattCoeff'),
      n('Full BattCoeff', 'FullBattCoeff'),
      cell('ThrottleLost',
          lost == null ? null : (lost == 0 ? '0-Inval' : '$lost'),
          uncertain: lost == 1),
      n('ThrottleInsert', 'ThrottleInsert'),
      cell('BackP_Time',
          backP == null ? null : (backP == 18 ? '18-240s' : '$backP'),
          uncertain: backP != 18,
          note: backP == 18 ? '' : 'Only index 18 = 240s is known.'),
      n('ReleaseToSeat', 'ReleaseToSeat', suffix: 's'),
      n('BlockTime', 'BlockTime', suffix: 's'),
      n('ParkTime', 'ParkTime', suffix: 's'),
      n('LmtSpdStartCap', 'MidSpeedCap',
          uncertain: true, note: 'MidSpeedCap per header alias.'),
      n('LmtSpdMinCap', 'SpeedLowCap',
          uncertain: true, note: 'SpeedLowCap per header alias.'),
      n('LmtSpdMaxCoeff', 'MinSpeedCapCoeff'),
      n('TurtleSpeedCurrCoeff', 'Stage1Curr'),
      e('BattSignal', 'BattSignal', {
        for (final MapEntry(:key, :value) in _labels('BattSignal').entries)
          key: _spaced(value),
      }),
      e('LowVol Way', 'LowVolWay', _labels('LowVolWay')),
      n('IntRes', 'IntRes'),
      n('TempCoeff', 'TempCoeff'),
    ]);
  }

  ProViewSection pid() {
    final lm = raw('LM');
    final curve = raw('CurveTime');
    final moe = raw('MOE');
    return ProViewSection('- PID Paras', [
      n('AN', 'AN'),
      cell('LM', lm == null ? null : '${lm}en-US',
          note: 'FarDriver appends its UI locale.'),
      n('StartKI', 'StartKI'),
      n('StartKC', 'StartKP'),
      n('MidKI', 'MidKI'),
      n('MidKC', 'MidKP'),
      n('MaxKI', 'MaxKI'),
      n('MaxKC', 'MaxKP',
          uncertain: true,
          note: 'FarDriver showed 169 where this byte read 120; unresolved.'),
      n('SpeedKI', 'SpeedKI'),
      n('SpeedKP', 'SppedKP'),
      cell('MOE', moe == null ? null : (moe == 0 ? '0-Enable' : '$moe-Disable'),
          uncertain: moe == 1),
      cell('CurveTime', curve == null ? null : '${(curve + 1) * 2}ms',
          uncertain: true,
          note: 'Scale assumed (raw+1)×2 ms (raw 49 showed 100ms).'),
    ]);
  }

  ProViewSection product() {
    final zero = raw('ZeroSwitch');
    final curr = raw('CurrAntiTheft');
    final deep = raw('SpecialWeak');
    String inv(int? v) => v == null ? _dash : (v == 0 ? '0-Invalid' : '$v');
    return ProViewSection('- Product', [
      n('ReCurrRatio', 'ReCurrRatio'),
      n('FwReRatio', 'FwReRatio'),
      n('VolSelectRatio', 'VolSelectRatio'),
      n('WeakCurrCoeff', 'Stage2Soc',
          uncertain: true, note: 'Candidate only: Stage2Soc (0xB8 byte 11).'),
      n('Re Acc', 'ReIsinAcc', suffix: 's', uncertain: true),
      n('AlarmDelay', 'AlarmDelay'),
      n('RelayDelay', 'RelayDelay',
          suffix: 'ms',
          uncertain: true,
          note: 'u16 at 0x1E bytes 6-7 (same word as the enable flags).'),
      n('RelayOut', 'RelayOut'),
      n('BCEnable', 'BCState'),
      n('SeatEnable', 'SeatEnable'),
      n('PEnable', 'PEnable'),
      n('AutoBackPEnable', 'AutoBackPEnable'),
      n('CruiseEnable', 'CruiseEnable'),
      n('EABSEnable', 'EABSEnable'),
      n('PushEnable', 'PushEnable'),
      n('ForseAntiTheft', 'ForceAntiTheft'),
      n('OverSpeedAlarm', 'OverSpeedAlarm'),
      n('BrakeStillPark', 'BrakeStillPark'),
      n('RememberGear', 'RememberGear'),
      n('BackEnable', 'BackEnable'),
      n('RelayDelay1S', 'RelayDelay1S'),
      cell('0SpeedSwitch', zero == null ? null : inv(zero),
          uncertain: zero != null && zero != 0),
      n('StartIs', 'StartIs'),
      n('FollowSpeed', 'ExitFollowSpeed', suffix: 'rpm'),
      cell('Curr-Anti-theft', curr == null ? null : inv(curr),
          uncertain: curr != null && curr != 0),
      e('Anti-theft Pulse', 'AntiTheftPulse', _labels('AntiTheftPulse')),
      n('Temp 70', 'Temp70'),
      n('Fast RE', 'FastRE'),
      n('InverseTime', 'ReverseTime'),
      n('SlowDownRpm', 'SlowDownRpm'),
      n('SlowDownCoeff', 'ParkCoeff'),
      e('RXD', 'RXD', _labels('RXD')),
      n('LearnThrottle', 'LearnThrottle'),
      n('LearnVolLow', 'LearnVolLow'),
      n('LearnVolHigh', 'LearnVolHigh'),
      null,
      cell('DeepWeak', deep == null ? null : (deep == 0 ? '0-Normal' : '$deep'),
          uncertain: deep != null && deep != 0),
      n('Protocol485', 'Protocol485'),
    ]);
  }

  ProViewSection fixedParas() => ProViewSection('- FixedParas', [
        n('LineCurrCoeff', 'LineCoeff'),
        n('BattVoltage', 'VolCoeff',
            uncertain: true, note: 'VolCoeff; order vs VoltageCoeff assumed.'),
        n('PhaseCoeffA', 'PhaseACoeff'),
        n('PhaseCoeffB', 'PhaseCCoeff',
            uncertain: true, note: 'PhaseCCoeff; order assumed.'),
        cell('PhseAZero', null,
            note: 'Live ADC offset, not stored in the dump.'),
        cell('PhaseCZero', null,
            note: 'Live ADC offset, not stored in the dump.'),
        n('TempCoeff', 'TempCoeff'),
        n('VoltageCoeff', 'Voltage2Coeff',
            uncertain: true, note: 'Voltage2Coeff; order assumed.'),
        n('Save Times', 'SaveNum'),
      ]);

  /// Catalog fields no pro page shows, identified ones first. Speeds and
  /// distances keep FarDriver's metric value, with mph/miles beside it when
  /// the rider has mph on (display only).
  ProViewSection extra() {
    final cells = <ProViewCell>[];
    final unidentified = <ProViewCell>[];
    final seen = <String>{};
    for (final def in FardriverParamCatalog.all) {
      if (_used.contains(def.key) || !seen.add(def.key)) continue;
      final bytes = dump.blocks[def.block];
      final String value;
      if (bytes == null) {
        value = _dash;
      } else {
        final d = FardriverDecoder.decode(def, bytes);
        value =
            d.label.isNotEmpty ? '${d.value}-${d.label}' : _withConversion(d);
      }
      final c = ProViewCell(def.displayName, value,
          note: '0x${def.block.toRadixString(16).padLeft(2, '0').toUpperCase()}'
              ' byte ${def.byteOffset} bits ${def.bitsLabel}');
      (def.unidentified ? unidentified : cells).add(c);
    }
    return ProViewSection(ProView.extraTitle, [...cells, ...unidentified],
        extra: true);
  }

  String _withConversion(DecodedParameter d) {
    final u = d.def.unit;
    final native = '${d.value}${u.isEmpty ? '' : ' $u'}';
    if (unit == SpeedUnit.kmh) return native;
    final formatted = DecodedParameter.formatValue(u, d.value, unit);
    if (formatted == native) return native;
    // formatValue gives "converted (native)"; FarDriver's value goes first.
    final converted =
        formatted.substring(0, formatted.length - native.length - 3);
    return '$native · $converted';
  }

  static Map<int, String> _labels(String name) =>
      FardriverParamCatalog.byName(name).labels;

  /// "LithiumBattery" -> "Lithium Battery".
  static String _spaced(String s) =>
      s.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ');

  ProView build() {
    final h = header();
    final sections = [
      dateTime(),
      parameters(),
      ratiosInSpeed(),
      ratiosInGear(),
      energyRegenerate(),
      functions(),
      display(),
      protect(),
      pid(),
      product(),
      fixedParas(),
    ];
    sections.add(extra());
    return ProView._(h, sections);
  }
}
