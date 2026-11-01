import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What a BLE controller dongle advertises that stays the same when its
/// address changes (v1.2.3). The FarDriver dongle showed up as
/// C0:02:4D:BA:00:16 on one day and E0:07:D3:FD:00:5A on another, so the
/// address alone cannot recognise it.
///
/// Stable parts: the advertised name, the advertised service UUIDs and the
/// manufacturer company IDs (the manufacturer payload itself is NOT used: it
/// can carry counters or the address).
class AdvertFingerprint {
  const AdvertFingerprint({
    this.name = '',
    this.serviceUuids = const [],
    this.manufacturerIds = const [],
  });

  static const empty = AdvertFingerprint();

  /// Builds a normalised fingerprint (trimmed name, sorted lowercase UUIDs,
  /// sorted unique company IDs).
  factory AdvertFingerprint.of({
    required String name,
    Iterable<String> serviceUuids = const [],
    Iterable<int> manufacturerIds = const [],
  }) =>
      AdvertFingerprint(
        name: name.trim(),
        serviceUuids: ({for (final u in serviceUuids) u.trim().toLowerCase()}
              ..remove(''))
            .toList()
          ..sort(),
        manufacturerIds: {...manufacturerIds}.toList()..sort(),
      );

  final String name;
  final List<String> serviceUuids;
  final List<int> manufacturerIds;

  /// A fingerprint with no name cannot identify anything.
  bool get isUsable => name.isNotEmpty;

  /// Same name, same service UUIDs, same company IDs.
  bool matches(AdvertFingerprint other) =>
      isUsable &&
      name == other.name &&
      _listEq(serviceUuids, other.serviceUuids) &&
      _listEq(manufacturerIds, other.manufacturerIds);

  Map<String, Object?> toJson() => {
        'name': name,
        'uuids': serviceUuids,
        'mfr': manufacturerIds,
      };

  factory AdvertFingerprint.fromJson(Map<String, Object?> json) =>
      AdvertFingerprint.of(
        name: json['name'] as String? ?? '',
        serviceUuids: (json['uuids'] as List? ?? const []).whereType<String>(),
        manufacturerIds: (json['mfr'] as List? ?? const []).whereType<int>(),
      );

  @override
  String toString() =>
      '$name ${serviceUuids.join(',')} ${manufacturerIds.join(',')}';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A controller FarSure connected to successfully before.
class RememberedDevice {
  const RememberedDevice({
    required this.fingerprint,
    required this.lastAddress,
    required this.lastConnectedAt,
    this.addresses = const [],
  });

  final AdvertFingerprint fingerprint;
  final String lastAddress;
  final DateTime lastConnectedAt;

  /// Every address it was seen under (newest last, capped).
  final List<String> addresses;

  /// Recognised by an address it used before, or by its advertisement.
  bool matches({required String address, required AdvertFingerprint seen}) =>
      address.toUpperCase() == lastAddress.toUpperCase() ||
      addresses.any((a) => a.toUpperCase() == address.toUpperCase()) ||
      fingerprint.matches(seen);

  Map<String, Object?> toJson() => {
        'fp': fingerprint.toJson(),
        'address': lastAddress,
        'addresses': addresses,
        'at': lastConnectedAt.toUtc().toIso8601String(),
      };

  factory RememberedDevice.fromJson(Map<String, Object?> json) =>
      RememberedDevice(
        fingerprint: AdvertFingerprint.fromJson(
            (json['fp'] as Map?)?.cast<String, Object?>() ?? const {}),
        lastAddress: json['address'] as String? ?? '',
        addresses: (json['addresses'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        lastConnectedAt:
            DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// One scan result reduced to what matching needs.
typedef SeenDevice = ({String address, AdvertFingerprint fingerprint});

/// Splits scan results into "previously connected" and "others".
class RememberedDeviceMatcher {
  const RememberedDeviceMatcher(this.remembered);

  final List<RememberedDevice> remembered;

  RememberedDevice? rememberedFor(SeenDevice d) {
    for (final r in remembered) {
      if (r.matches(address: d.address, seen: d.fingerprint)) return r;
    }
    return null;
  }

  ({List<T> previous, List<T> others}) split<T>(
      List<T> scan, SeenDevice Function(T) seen) {
    final previous = <T>[], others = <T>[];
    for (final d in scan) {
      (rememberedFor(seen(d)) != null ? previous : others).add(d);
    }
    return (previous: previous, others: others);
  }

  /// The one device to connect to automatically, or null when none or
  /// several previously connected controllers are broadcasting.
  T? autoConnectCandidate<T>(List<T> scan, SeenDevice Function(T) seen) {
    final previous = split(scan, seen).previous;
    return previous.length == 1 ? previous.single : null;
  }
}

/// Remembered controllers in SharedPreferences (JSON list).
class RememberedDeviceRepository {
  const RememberedDeviceRepository();

  static const prefKey = 'remembered_controllers_v1';
  static const _maxAddresses = 8;

  Future<List<RememberedDevice>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefKey);
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => RememberedDevice.fromJson(m.cast<String, Object?>()))
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> _save(List<RememberedDevice> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        prefKey, jsonEncode([for (final d in list) d.toJson()]));
  }

  /// Adds or updates the device after a successful connect.
  Future<List<RememberedDevice>> remember({
    required String address,
    required AdvertFingerprint fingerprint,
    DateTime? at,
  }) async {
    final list = [...await load()];
    final i =
        list.indexWhere((r) => r.matches(address: address, seen: fingerprint));
    final old = i >= 0 ? list.removeAt(i) : null;
    final addresses = [
      ...?old?.addresses.where((a) => a.toUpperCase() != address.toUpperCase()),
      address,
    ];
    list.insert(
        0,
        RememberedDevice(
          // Keep the old fingerprint if this scan carried no name.
          fingerprint: fingerprint.isUsable
              ? fingerprint
              : (old?.fingerprint ?? fingerprint),
          lastAddress: address,
          addresses: addresses.length > _maxAddresses
              ? addresses.sublist(addresses.length - _maxAddresses)
              : addresses,
          lastConnectedAt: at ?? DateTime.now(),
        ));
    await _save(list);
    return list;
  }

  /// Forgets the device (by any address it used).
  Future<List<RememberedDevice>> forget(RememberedDevice device) async {
    final list = [...await load()]..removeWhere((r) =>
        r.lastAddress == device.lastAddress ||
        (r.fingerprint.matches(device.fingerprint) &&
            r.addresses.contains(device.lastAddress)));
    await _save(list);
    return list;
  }
}
