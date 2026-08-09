import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/services/dashboard_layout_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements AtomicJsonStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> replace(String contents) async => this.contents = contents;
}

void main() {
  test('atomically round-trips a validated dashboard layout', () async {
    final store = _MemoryStore();
    final repository = DashboardLayoutRepository(VersionedJsonRepository(
      store: store,
      type: DashboardLayoutRepository.documentType,
      schemaVersion: DashboardLayoutRepository.documentVersion,
    ));

    await repository.save(DashboardLayout.defaults());
    final result = await repository.load();

    expect(result.status, DashboardLayoutLoadStatus.loaded);
    expect(result.layout, DashboardLayout.defaults());
  });

  test('missing and corrupt documents fall back diagnostically', () async {
    final store = _MemoryStore();
    final repository = DashboardLayoutRepository(VersionedJsonRepository(
      store: store,
      type: DashboardLayoutRepository.documentType,
      schemaVersion: DashboardLayoutRepository.documentVersion,
    ));

    expect((await repository.load()).status, DashboardLayoutLoadStatus.missing);
    store.contents = '{broken';
    final corrupt = await repository.load();
    expect(corrupt.status, DashboardLayoutLoadStatus.corrupt);
    expect(corrupt.layout, DashboardLayout.defaults());
  });
}
