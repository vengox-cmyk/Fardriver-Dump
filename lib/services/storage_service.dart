import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:arcdash/models/tuning_profile.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/services/dashboard_layout_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:csv/csv.dart';

const _prefKeyStockBackup = 'stock_backup_json';
const _prefKeyProfiles = 'tuning_profiles';
const _prefKeyRideSessions = 'ride_sessions';
const _prefKeyFirstConnect = 'first_connect_done';

class StorageService {
  late SharedPreferences _prefs;
  bool _initialized = false;
  DashboardLayout _dashboardLayout = DashboardLayout.defaults();
  DashboardLayoutRepository? _dashboardRepository;
  DashboardLayoutLoadStatus dashboardLayoutStatus =
      DashboardLayoutLoadStatus.missing;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final directory = await getApplicationSupportDirectory();
    _dashboardRepository = DashboardLayoutRepository(VersionedJsonRepository(
      store:
          AtomicJsonFileStore(File('${directory.path}/dashboard-layout.json')),
      type: DashboardLayoutRepository.documentType,
      schemaVersion: DashboardLayoutRepository.documentVersion,
    ));
    final loaded = await _dashboardRepository!.load();
    _dashboardLayout = loaded.layout;
    dashboardLayoutStatus = loaded.status;
    if (loaded.status == DashboardLayoutLoadStatus.missing) {
      await _migrateLegacyDashboardLayout();
    }
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  /// Key-value storage for the range prediction / voltage calibration state.
  /// Gracefully degrades to a no-op store when not initialized (e.g. in tests).
  KeyValueStorage get rangePredictionStorage =>
      SharedPreferencesKeyValueStorage(_initialized ? _prefs : null);

  DashboardLayout loadDashboardLayout() {
    return _dashboardLayout;
  }

  Future<void> saveDashboardLayout(DashboardLayout layout) async {
    layout.portrait.validate();
    layout.landscape.validate();
    _dashboardLayout = layout;
    if (!_initialized) return;
    await _dashboardRepository!.save(layout);
    dashboardLayoutStatus = DashboardLayoutLoadStatus.loaded;
  }

  Future<void> resetDashboardLayout() async {
    _dashboardLayout = DashboardLayout.defaults();
    if (_initialized) {
      await _dashboardRepository!.save(_dashboardLayout);
      await _prefs.remove('dashboard_layout');
      dashboardLayoutStatus = DashboardLayoutLoadStatus.loaded;
    }
  }

  Future<void> _migrateLegacyDashboardLayout() async {
    final encoded = _prefs.getString('dashboard_layout');
    if (encoded == null) return;
    try {
      final legacy = DashboardLayout.fromJson(jsonDecode(encoded));
      await _dashboardRepository!.save(legacy);
      _dashboardLayout = legacy;
      dashboardLayoutStatus = DashboardLayoutLoadStatus.loaded;
      await _prefs.remove('dashboard_layout');
    } on Object {
      dashboardLayoutStatus = DashboardLayoutLoadStatus.corrupt;
    }
  }

  Future<void> clearRideSessions() async {
    if (_initialized) await _prefs.remove(_prefKeyRideSessions);
  }

  Future<void> clearProfiles() async {
    if (_initialized) await _prefs.remove(_prefKeyProfiles);
  }

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
    if (!_initialized) return;
    final sessions = _loadSessionJsonList();
    sessions.add(session.toJson());
    // Keep only last 50 sessions
    final trimmed = sessions.length > 50
        ? sessions.sublist(sessions.length - 50)
        : sessions;
    await _prefs.setString(_prefKeyRideSessions, jsonEncode(trimmed));
  }

  List<Map<String, dynamic>> _loadSessionJsonList() {
    if (!_initialized) return [];
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
        '${dir.path}/arcdash_ride_${session.startTime.millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    return file.path;
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
