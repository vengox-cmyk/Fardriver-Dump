import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biketunes/models/tuning_profile.dart';
import 'package:biketunes/models/ride_stats.dart';
import 'package:csv/csv.dart';

const _prefKeyUseMph = 'use_mph';
const _prefKeyStockBackup = 'stock_backup_json';
const _prefKeyProfiles = 'tuning_profiles';
const _prefKeyRideSessions = 'ride_sessions';
const _prefKeyFirstConnect = 'first_connect_done';

class StorageService {
  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Unit preference ---
  bool get useMph => _prefs.getBool(_prefKeyUseMph) ?? false;
  Future<void> setUseMph(bool v) => _prefs.setBool(_prefKeyUseMph, v);

  // --- Stock backup ---
  bool get hasStockBackup => _prefs.containsKey(_prefKeyStockBackup);

  Future<void> saveStockBackup(Map<int, int> rawAddressValues) async {
    final encoded = jsonEncode(rawAddressValues.map(
      (k, v) => MapEntry(k.toString(), v),
    ));
    await _prefs.setString(_prefKeyStockBackup, encoded);
    await _prefs.setBool(_prefKeyFirstConnect, true);
  }

  Map<int, int>? loadStockBackup() {
    final s = _prefs.getString(_prefKeyStockBackup);
    if (s == null) return null;
    final map = jsonDecode(s) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(int.parse(k), v as int));
  }

  bool get firstConnectDone => _prefs.getBool(_prefKeyFirstConnect) ?? false;

  // --- Tuning profiles ---
  Future<void> saveProfile(TuningProfile profile) async {
    final profiles = loadProfiles();
    final idx = profiles.indexWhere((p) => p.name == profile.name);
    if (idx >= 0) {
      profiles[idx] = profile;
    } else {
      profiles.add(profile);
    }
    await _prefs.setString(
      _prefKeyProfiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  List<TuningProfile> loadProfiles() {
    final s = _prefs.getString(_prefKeyProfiles);
    if (s == null) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .map((e) => TuningProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteProfile(String name) async {
    final profiles = loadProfiles()..removeWhere((p) => p.name == name);
    await _prefs.setString(
      _prefKeyProfiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  // --- Ride sessions ---
  Future<void> saveRideSession(RideSession session) async {
    final sessions = _loadSessionJsonList();
    sessions.add(session.toJson());
    // Keep only last 50 sessions
    final trimmed =
        sessions.length > 50 ? sessions.sublist(sessions.length - 50) : sessions;
    await _prefs.setString(_prefKeyRideSessions, jsonEncode(trimmed));
  }

  List<Map<String, dynamic>> _loadSessionJsonList() {
    final s = _prefs.getString(_prefKeyRideSessions);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> loadRideSessions() => _loadSessionJsonList();

  // --- CSV export ---
  Future<String> exportSessionToCsv(RideSession session) async {
    final rows = session.toCsvRows();
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/biketunes_ride_${session.startTime.millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
