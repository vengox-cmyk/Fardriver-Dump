import 'dart:async';

import 'package:arcdash/models/remembered_device.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/remembered_auto_connect.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothDevice, DeviceIdentifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

AdvertFingerprint fp(String name, {List<int> mfr = const [0x0590]}) =>
    AdvertFingerprint.of(
        name: name, serviceUuids: [_uuid.toUpperCase()], manufacturerIds: mfr);

DiscoveredDongle dongle(String address, AdvertFingerprint f) =>
    DiscoveredDongle(
      device: BluetoothDevice(remoteId: DeviceIdentifier(address)),
      name: f.name,
      rssi: -60,
      fingerprint: f,
    );

SeenDevice seen(DiscoveredDongle d) =>
    (address: d.address, fingerprint: d.fingerprint);

class _FakeService extends DongleService {
  _FakeService(this.results);
  final List<DiscoveredDongle> results;
  final _scan = StreamController<List<DiscoveredDongle>>.broadcast();
  final connected = <String>[];

  @override
  DongleConnectionState get state => DongleConnectionState.idle;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => _scan.stream;
  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    _scan.add(results);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<bool> connect(DiscoveredDongle dongle) async {
    connected.add(dongle.address);
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AdvertFingerprint', () {
    test('normalises and survives JSON', () {
      final f = AdvertFingerprint.of(
          name: ' FarDriver ',
          serviceUuids: ['B', 'a', 'A'],
          manufacturerIds: [2, 1, 2]);
      expect(f.name, 'FarDriver');
      expect(f.serviceUuids, ['a', 'b']);
      expect(f.manufacturerIds, [1, 2]);
      expect(AdvertFingerprint.fromJson(f.toJson()).matches(f), isTrue);
    });

    test('no name never matches', () {
      expect(AdvertFingerprint.empty.matches(AdvertFingerprint.empty), isFalse);
    });

    test('different UUIDs or company IDs do not match', () {
      expect(fp('FD').matches(fp('FD', mfr: [1])), isFalse);
      expect(
          fp('FD').matches(
              AdvertFingerprint.of(name: 'FD', manufacturerIds: [0x0590])),
          isFalse);
    });
  });

  group('matcher', () {
    final controller = RememberedDevice(
      fingerprint: fp('FarDriver_BLE'),
      lastAddress: 'C0:02:4D:BA:00:16',
      lastConnectedAt: DateTime(2026, 10, 30),
    );

    test('recognises the controller after its address changed', () {
      final m = RememberedDeviceMatcher([controller]);
      final moved = dongle('E0:07:D3:FD:00:5A', fp('FarDriver_BLE'));
      final other = dongle('11:22:33:44:55:66', fp('Mi Band'));
      final split = m.split([other, moved], seen);
      expect(split.previous, [moved]);
      expect(split.others, [other]);
      expect(m.autoConnectCandidate([other, moved], seen), moved);
    });

    test('same address is enough even with another name', () {
      final m = RememberedDeviceMatcher([controller]);
      final d = dongle('C0:02:4D:BA:00:16', AdvertFingerprint.empty);
      expect(m.autoConnectCandidate([d], seen), d);
    });

    test('no auto-connect when two previously connected are broadcasting', () {
      final m = RememberedDeviceMatcher([controller]);
      final a = dongle('E0:07:D3:FD:00:5A', fp('FarDriver_BLE'));
      final b = dongle('E0:07:D3:FD:00:5B', fp('FarDriver_BLE'));
      expect(m.split([a, b], seen).previous, hasLength(2));
      expect(m.autoConnectCandidate([a, b], seen), isNull);
      expect(m.autoConnectCandidate(<DiscoveredDongle>[], seen), isNull);
    });
  });

  group('repository', () {
    const repo = RememberedDeviceRepository();

    test('remember upserts across address changes; forget removes', () async {
      await repo.remember(
          address: 'C0:02:4D:BA:00:16', fingerprint: fp('FarDriver_BLE'));
      var list = await repo.remember(
          address: 'E0:07:D3:FD:00:5A', fingerprint: fp('FarDriver_BLE'));
      expect(list, hasLength(1));
      expect(list.single.lastAddress, 'E0:07:D3:FD:00:5A');
      expect(list.single.addresses, ['C0:02:4D:BA:00:16', 'E0:07:D3:FD:00:5A']);
      list = await repo.remember(
          address: 'AA:BB:CC:DD:EE:FF', fingerprint: fp('Other'));
      expect(list, hasLength(2));
      expect((await repo.load()).first.fingerprint.name, 'Other');
      list = await repo.forget(list.last);
      expect(list.map((r) => r.fingerprint.name), ['Other']);
      expect(await repo.load(), hasLength(1));
    });

    test('corrupt storage reads as empty', () async {
      SharedPreferences.setMockInitialValues(
          {RememberedDeviceRepository.prefKey: '{not json'});
      expect(await repo.load(), isEmpty);
    });
  });

  group('startup auto-connect', () {
    const repo = RememberedDeviceRepository();

    test('does nothing when nothing is remembered', () async {
      final service =
          _FakeService([dongle('E0:07:D3:FD:00:5A', fp('FarDriver_BLE'))]);
      expect(await RememberedAutoConnect(service: service).run(), isNull);
      expect(service.connected, isEmpty);
    });

    test('connects to the single remembered controller in range', () async {
      await repo.remember(
          address: 'C0:02:4D:BA:00:16', fingerprint: fp('FarDriver_BLE'));
      final service = _FakeService([
        dongle('11:22:33:44:55:66', fp('Mi Band')),
        dongle('E0:07:D3:FD:00:5A', fp('FarDriver_BLE')),
      ]);
      final got = await RememberedAutoConnect(service: service).run();
      expect(got?.address, 'E0:07:D3:FD:00:5A');
      expect(service.connected, ['E0:07:D3:FD:00:5A']);
    });

    test('stays manual when two remembered controllers are around', () async {
      await repo.remember(
          address: 'C0:02:4D:BA:00:16', fingerprint: fp('FarDriver_BLE'));
      final service = _FakeService([
        dongle('E0:07:D3:FD:00:5A', fp('FarDriver_BLE')),
        dongle('E0:07:D3:FD:00:5B', fp('FarDriver_BLE')),
      ]);
      expect(await RememberedAutoConnect(service: service).run(), isNull);
      expect(service.connected, isEmpty);
    });
  });
}
