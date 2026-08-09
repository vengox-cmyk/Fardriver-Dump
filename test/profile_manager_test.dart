import 'package:arcdash/models/versioned_profile.dart';
import 'package:arcdash/services/profile_manager.dart';
import 'package:flutter_test/flutter_test.dart';

const parameters = {
  'maxSpeedKph': 45.0,
  'maxLineCurrA': 60.0,
  'maxPhaseCurrA': 120.0,
  'regenStrength': 0.3,
  'throttleResponse': 1,
};

void main() {
  test('creates, renames, duplicates, and deletes independent profiles', () {
    var id = 0;
    final manager = ProfileManager(idFactory: () => 'id-${id++}');
    final created = manager.create(
      name: 'Street',
      description: 'test',
      parameters: parameters,
    );
    final renamed = manager.rename(created.id, 'Road');
    final copy = manager.duplicate(renamed.id, name: 'Trail');
    expect(copy.id, isNot(renamed.id));
    manager.delete(renamed.id);
    expect(manager.profiles.map((profile) => profile.name), ['Trail']);
  });

  test('protects immutable profiles and duplicate names', () {
    final integrated = VersionedProfile(
      id: 'stock',
      name: 'Stock',
      description: '',
      parameters: parameters,
      source: ProfileSource.integrated,
      createdAt: DateTime.utc(2026, 1, 1),
      immutable: true,
    );
    final manager = ProfileManager(initial: [integrated]);
    expect(() => manager.rename('stock', 'Other'), throwsStateError);
    expect(() => manager.delete('stock'), throwsStateError);
    expect(
      () => manager.create(
          name: 'stock', description: '', parameters: parameters),
      throwsStateError,
    );
  });
}
