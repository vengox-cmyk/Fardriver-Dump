import 'dart:async';
import 'dart:io';

import 'package:arcdash/models/battery_plan.dart';
import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/models/tire_rack.dart';
import 'package:arcdash/services/public_files.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/tire_rack_store.dart';
import 'package:arcdash/services/write/fardriver_write_protocol.dart';
import 'package:arcdash/services/write/write_allowlist.dart';
import 'package:arcdash/services/write/write_log.dart';
import 'package:arcdash/services/write/write_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake controller: applies word writes to its blocks and streams the
/// touched blocks back after "save".
class FakeLink implements ControllerWriteLink {
  FakeLink() {
    for (final b in FardriverParamCatalog.mandatoryBlocks) {
      blocks[b] = List<int>.filled(12, 0);
    }
    _setField('RateRatio', 4000);
    _setField('SpdPulseNum', 100);
    _setField('SpeedPulse', 4);
    _setField('WheelWidth', 120);
    _setField('WheelRatio', 70);
    _setField('WheelRadius', 12);
    _setField('LowVolProtect', 630);
    _setField('BattRatedCap', 45);
    _setField('HighVolProtect', 1215);
    _setField('HighVolRestore', 1195);
  }

  final blocks = <int, List<int>>{};
  final sent = <List<int>>[];
  final _arrivals = StreamController<int>.broadcast();
  bool connected_ = true;
  int rpm_ = 0;
  double speed_ = 0;

  /// Word address whose write the fake "ignores" (read back unchanged).
  int? dropWord;
  final _dirty = <int>{};

  void _setField(String key, int raw) {
    final f = WriteAllowlist.byKey(key)!;
    final b = blocks[f.def.block]!;
    final o = f.wordByteOffset;
    final w = f.applyTo(b[o] | (b[o + 1] << 8), raw);
    b[o] = w & 0xFF;
    b[o + 1] = w >> 8;
  }

  int raw(String key) => WriteAllowlist.byKey(key)!
      .readRaw(blocks[WriteAllowlist.byKey(key)!.def.block]!);

  @override
  bool get connected => connected_;
  @override
  Duration get connectedFor => const Duration(seconds: 30);
  @override
  Duration get sinceLastFrame => const Duration(milliseconds: 100);
  @override
  int get rpm => rpm_;
  @override
  double get speedKph => speed_;
  @override
  String get controllerName => 'FarDriver-Test';
  @override
  Map<int, List<int>> get latestBlocks => blocks;
  @override
  Stream<int> get blockArrivals => _arrivals.stream;

  @override
  Future<void> send(List<int> frame) async {
    expect(FardriverWriteProtocol.verifyCrc(frame), isTrue);
    sent.add(List.of(frame));
    final addr = frame[2];
    if (addr == FardriverWriteProtocol.sysCmdAddress) {
      expect(frame.sublist(4, 6), FardriverWriteProtocol.saveCommand);
      for (final b in _dirty) {
        scheduleMicrotask(() => _arrivals.add(b));
      }
      _dirty.clear();
      return;
    }
    if (addr == FardriverWriteProtocol.saveStampAddress) return;
    if (addr == dropWord) {
      _dirty.add(_blockOf(addr));
      return;
    }
    final block = _blockOf(addr);
    final o = (addr - block) * 2;
    blocks[block]![o] = frame[4];
    blocks[block]![o + 1] = frame[5];
    _dirty.add(block);
  }

  int _blockOf(int word) {
    for (final b in blocks.keys) {
      if (word >= b && word < b + 6) return b;
    }
    throw StateError('no block for $word');
  }
}

void main() {
  late Directory docs;
  late SavedFilesStore store;
  late FakeLink link;
  var experimental = false;

  ControllerWriteService service() => ControllerWriteService(
        link: link,
        store: store,
        experimentalEnabled: () => experimental,
        frameGap: Duration.zero,
        readbackTimeout: const Duration(seconds: 2),
      );

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('farsure_write');
    store = SavedFilesStore(documentsDir: () async => docs);
    link = FakeLink();
    experimental = false;
  });
  tearDown(() => docs.delete(recursive: true));

  group('framing and CRC', () {
    test('matches the official vector (factory reset, never sent)', () {
      final f = FardriverWriteProtocol.frameForTest(0xA0, [0x88, 0x08]);
      expect(f, [0xAA, 0xC6, 0xA0, 0xA0, 0x88, 0x08, 0xC5, 0x09]);
    });
    test('save frame and word write', () {
      final s = FardriverWriteProtocol.saveFrame();
      expect(s.sublist(0, 6), [0xAA, 0xC6, 0xA0, 0xA0, 0x88, 0x04]);
      expect(FardriverWriteProtocol.verifyCrc(s), isTrue);
      final w = FardriverWriteProtocol.writeWord(0xD4, 4106);
      expect(w.sublist(0, 6), [0xAA, 0xC6, 0xD4, 0xD4, 4106 & 0xFF, 4106 >> 8]);
      expect(FardriverWriteProtocol.verifyCrc(w), isTrue);
      final stamp =
          FardriverWriteProtocol.saveStampFrame(DateTime(2026, 11, 2, 9, 8, 7));
      expect(
          stamp.sublist(0, 10), [0xAA, 0xCA, 0x22, 0x22, 26, 11, 2, 9, 8, 7]);
    });
    test('system command address cannot be written as a setting', () {
      expect(() => FardriverWriteProtocol.writeWord(0xA0, 0x0888),
          throwsArgumentError);
    });
  });

  group('allowlist', () {
    test('only safe fields; forbidden names refused', () {
      for (final f in WriteAllowlist.fields) {
        expect(WriteAllowlist.isForbiddenName(f.key), isFalse, reason: f.key);
      }
      for (final n in [
        'MaxLineCurr',
        'MaxPhaseCurr',
        'HallOrder',
        'PhaseOffset',
        'SpeedKp',
        'CurrKi',
        'WeakA',
        'AutoLearn',
        'Modulation',
        'FactoryReset'
      ]) {
        expect(WriteAllowlist.isForbiddenName(n), isTrue, reason: n);
      }
      expect(() => service().plan({'MaxLineCurr': 100}, title: 't'),
          throwsA(isA<WriteRefused>()));
    });
    test('experimental fields need the toggle', () {
      expect(() => service().plan({'HighVolProtect': 1010}, title: 't'),
          throwsA(isA<WriteRefused>()));
      experimental = true;
      expect(service().plan({'HighVolProtect': 1010}, title: 't').changes,
          hasLength(1));
    });
    test('range check and unchanged values dropped', () {
      expect(() => service().plan({'RateRatio': 10}, title: 't'),
          throwsA(isA<WriteRefused>()));
      final set =
          service().plan({'RateRatio': 4000, 'SpdPulseNum': 102}, title: 't');
      expect(set.changes.single.field.key, 'SpdPulseNum');
    });
    test('GearRatio label', () {
      expect(WriteAllowlist.gearRatioLabel(4106),
          'GearRatio 4.106 (RateRatio 4106)');
    });
  });

  group('gating', () {
    test('refuses while moving, disconnected', () async {
      final s = service();
      final set = s.plan({'RateRatio': 4106}, title: 't');
      link.rpm_ = 10;
      expect(s.refusalReason(), contains('turning'));
      await expectLater(s.apply(set), throwsA(isA<WriteRefused>()));
      link.rpm_ = 0;
      link.speed_ = 1;
      await expectLater(s.apply(set), throwsA(isA<WriteRefused>()));
      link.speed_ = 0;
      link.connected_ = false;
      await expectLater(s.apply(set), throwsA(isA<WriteRefused>()));
      expect(link.sent, isEmpty);
    });
  });

  group('write, verify, undo', () {
    test('writes, saves, verifies, logs and backs up', () async {
      final s = service();
      final r = await s.apply(s.plan({
        'WheelWidth': 130,
        'WheelRatio': 70,
        'WheelRadius': 12,
        'RateRatio': 4106
      }, title: 'tire'));
      expect(r.success, isTrue);
      expect(link.raw('WheelWidth'), 130);
      expect(link.raw('RateRatio'), 4106);
      expect(link.raw('WheelRadius'), 12, reason: 'other bits kept');
      expect(
          link.sent.last.sublist(0, 6), [0xAA, 0xC6, 0xA0, 0xA0, 0x88, 0x04]);
      expect(await r.backup.exists(), isTrue);
      final logs = await WriteLogStore(store).list();
      expect(logs.single.$2.rows.map((e) => e.field),
          containsAll(['WheelWidth', 'RateRatio']));
      expect(logs.single.$2.controllerName, 'FarDriver-Test');
    });

    test('mismatch offers restore of old values', () async {
      final s = service();
      link.dropWord = WriteAllowlist.byKey('SpdPulseNum')!.wordAddress;
      final r = await s
          .apply(s.plan({'SpdPulseNum': 110, 'RateRatio': 4200}, title: 'x'));
      expect(r.success, isFalse);
      expect(
          r.fields
              .firstWhere((f) => f.change.field.key == 'SpdPulseNum')
              .verify,
          VerifyResult.mismatch);
      final restore = s.planRestore(r);
      expect(restore.kind, ChangeSetKind.restore);
      expect(restore.changes.single.field.key, 'RateRatio');
      expect(restore.changes.single.newRaw, 4000);
    });

    test('undo restores only the fields the write touched', () async {
      final s = service();
      final r = await s.apply(s.plan({'RateRatio': 4106}, title: 'gear'));
      expect(r.success, isTrue);
      // Something else changed later (not by this write).
      link._setField('LowVolProtect', 650);
      final logs = await WriteLogStore(store).list();
      final undo = await s.planUndo(logs.single.$2);
      expect(undo.kind, ChangeSetKind.undo);
      expect(undo.changes.single.field.key, 'RateRatio');
      expect(undo.changes.single.newRaw, 4000);
      final u = await s.apply(undo);
      expect(u.success, isTrue);
      expect(link.raw('RateRatio'), 4000);
      expect(link.raw('LowVolProtect'), 650);
    });

    test('write log round trip', () {
      final session = WriteLogSession(
        writeId: 'id1',
        time: DateTime.utc(2026, 11, 2, 12),
        controllerName: 'FarDriver',
        kind: ChangeSetKind.write,
        title: 'Tire, "quoted", comma',
        backupFile: 'b.csv',
        rows: const [
          WriteLogRow(
              field: 'RateRatio',
              label: 'GearRatio (RateRatio)',
              oldRaw: 4000,
              newRaw: 4106,
              oldText: 'GearRatio 4.000 (RateRatio 4000)',
              newText: 'GearRatio 4.106 (RateRatio 4106)',
              verify: VerifyResult.ok,
              readBackRaw: 4106),
        ],
      );
      final back = WriteLogSession.decode(session.encode());
      expect(back.title, session.title);
      expect(back.rows.single.newRaw, 4106);
      expect(back.rows.single.verify, VerifyResult.ok);
      expect(back.success, isTrue);
    });
  });

  group('tire rack and battery', () {
    test('tire impact and JSON round trip', () {
      const t = TireSize(name: 'x', widthMm: 120, ratioPct: 70, rimInch: 12);
      expect(t.diameterMm, closeTo((12 * 1270 + 120 * 70) / 50, 1e-9));
      final kph = TireRack.kphAt(t, 4000, 4.0);
      expect(kph,
          closeTo(0.00376991136 * (12 * 1270 + 120 * 70) / 4000 * 4000, 0.05));
      final text = TireRack.encode([t]);
      expect(TireRack.looksLikeRack(text), isTrue);
      expect(TireRack.decode(text).single.code, '120/70-12');
    });
    test('tire rack store import merges by name', () async {
      final rack = TireRackStore(store);
      await rack.saveCustom(
          [const TireSize(name: 'A', widthMm: 100, ratioPct: 70, rimInch: 12)]);
      final n = await rack.importText(TireRack.encode([
        const TireSize(name: 'A', widthMm: 110, ratioPct: 70, rimInch: 12),
        const TireSize(name: 'B', widthMm: 90, ratioPct: 90, rimInch: 10),
      ]));
      expect(n, 2);
      final all = await rack.loadCustom();
      expect(all, hasLength(2));
      expect(all.firstWhere((e) => e.name == 'A').widthMm, 110);
    });
    test('battery 24S NMC suggestions and refusals', () {
      const p = BatteryPlan(Chemistry.nmc, 24, 45);
      final raw = p.suggestedRaw(includeOverVoltage: true);
      expect(raw['LowVolProtect'], 720);
      expect(raw['BattRatedCap'], 45);
      expect(p.refusal(raw), isNull);
      expect(p.refusal({...raw, 'LowVolProtect': 500}), isNotNull);
      expect(p.refusal({...raw, 'HighVolProtect': 1215}), isNotNull,
          reason: '121.5 V is 5.06 V/cell on 24S NMC');
      expect(p.math, isNotEmpty);
    });
  });

  group('public files', () {
    test('folders and import of a tire rack', () async {
      expect(PublicFiles.folderFor(SavedFileKind.writeLog), 'write_log');
      expect(PublicFiles.folderFor(SavedFileKind.backup), 'backups');
      final msg = await PublicFiles.importBytes(
          store,
          'tires.json',
          TireRack.encode([
            const TireSize(name: 'C', widthMm: 90, ratioPct: 90, rimInch: 10)
          ]).codeUnits);
      expect(msg, contains('Imported 1'));
      expect(await PublicFiles.importBytes(store, 'x.bin', [1, 2, 3]),
          startsWith('Not imported'));
    });
  });
}
