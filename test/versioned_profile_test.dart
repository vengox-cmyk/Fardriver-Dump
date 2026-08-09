import 'package:arcdash/models/versioned_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _parameters() => const {
      'maxSpeedKph': 45.0,
      'maxLineCurrA': 60.0,
      'maxPhaseCurrA': 120.0,
      'regenStrength': 0.3,
      'throttleResponse': 1,
    };

VersionedProfile _profile() => VersionedProfile(
      id: 'profile-1',
      name: 'Street',
      description: 'Test',
      parameters: _parameters(),
      source: ProfileSource.user,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('versioned profile round-trips and keeps technical identity separate',
      () {
    final profile = _profile();
    final restored = VersionedProfile.fromJson(profile.toJson());
    expect(restored.id, 'profile-1');
    expect(restored.parameters, profile.parameters);
  });

  test('rejects unknown parameters and newer schemas', () {
    expect(
      () => VersionedProfile(
        id: 'x',
        name: 'X',
        description: '',
        parameters: {..._parameters(), 'unknown': 1},
        source: ProfileSource.user,
        createdAt: DateTime.now(),
      ),
      throwsFormatException,
    );
    expect(
      () => VersionedProfile.fromJson(
          {..._profile().toJson(), 'schemaVersion': 2}),
      throwsFormatException,
    );
  });

  test('migrates complete legacy profiles and rejects incomplete ones', () {
    final migrated = VersionedProfile.migrateLegacy({
      'name': 'Old',
      'description': 'legacy',
      ..._parameters(),
    });
    expect(migrated.source, ProfileSource.migrated);
    expect(
      () => VersionedProfile.migrateLegacy({'name': 'incomplete'}),
      throwsFormatException,
    );
  });
}
