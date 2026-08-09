import 'package:arcdash/models/versioned_profile.dart';

class ProfileManager {
  final String Function() _idFactory;
  final List<VersionedProfile> _profiles;

  ProfileManager({
    List<VersionedProfile> initial = const [],
    String Function()? idFactory,
  })  : _profiles = List<VersionedProfile>.from(initial),
        _idFactory = idFactory ?? _defaultId;

  List<VersionedProfile> get profiles => List.unmodifiable(_profiles);

  VersionedProfile create({
    required String name,
    required String description,
    required Map<String, Object?> parameters,
  }) {
    _ensureNameAvailable(name);
    final profile = VersionedProfile(
      id: _idFactory(),
      name: name,
      description: description,
      parameters: parameters,
      source: ProfileSource.user,
      createdAt: DateTime.now(),
    );
    _profiles.add(profile);
    return profile;
  }

  VersionedProfile rename(String id, String name) {
    final index = _indexOf(id);
    final current = _profiles[index];
    if (current.immutable) throw StateError('immutable profile');
    _ensureNameAvailable(name, exceptId: id);
    final updated = VersionedProfile(
      id: current.id,
      name: name,
      description: current.description,
      controllerFamily: current.controllerFamily,
      parameters: current.parameters,
      source: current.source,
      createdAt: current.createdAt,
    );
    _profiles[index] = updated;
    return updated;
  }

  VersionedProfile duplicate(String id, {required String name}) {
    final current = _profiles[_indexOf(id)];
    _ensureNameAvailable(name);
    final copy = VersionedProfile(
      id: _idFactory(),
      name: name,
      description: current.description,
      controllerFamily: current.controllerFamily,
      parameters: Map<String, Object?>.from(current.parameters),
      source: ProfileSource.user,
      createdAt: DateTime.now(),
    );
    _profiles.add(copy);
    return copy;
  }

  void delete(String id) {
    final index = _indexOf(id);
    if (_profiles[index].immutable) throw StateError('immutable profile');
    _profiles.removeAt(index);
  }

  int _indexOf(String id) {
    final index = _profiles.indexWhere((profile) => profile.id == id);
    if (index < 0) throw ArgumentError.value(id, 'id');
    return index;
  }

  void _ensureNameAvailable(String name, {String? exceptId}) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (_profiles.any((profile) =>
        profile.id != exceptId &&
        profile.name.toLowerCase() == name.trim().toLowerCase())) {
      throw StateError('profile name already exists');
    }
  }

  static String _defaultId() =>
      'profile-${DateTime.now().microsecondsSinceEpoch}';
}
