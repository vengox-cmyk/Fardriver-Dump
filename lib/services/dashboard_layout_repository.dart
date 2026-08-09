import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/services/versioned_json_repository.dart';

enum DashboardLayoutLoadStatus { loaded, missing, corrupt }

class DashboardLayoutLoadResult {
  final DashboardLayout layout;
  final DashboardLayoutLoadStatus status;

  const DashboardLayoutLoadResult({required this.layout, required this.status});
}

class DashboardLayoutRepository {
  static const documentType = 'dashboard-layout';
  static const documentVersion = 1;

  final VersionedJsonRepository _repository;

  const DashboardLayoutRepository(this._repository);

  Future<DashboardLayoutLoadResult> load() async {
    try {
      final payload = await _repository.load();
      if (payload == null) {
        return DashboardLayoutLoadResult(
          layout: DashboardLayout.defaults(),
          status: DashboardLayoutLoadStatus.missing,
        );
      }
      return DashboardLayoutLoadResult(
        layout: DashboardLayout.fromJson(payload),
        status: DashboardLayoutLoadStatus.loaded,
      );
    } on Object {
      return DashboardLayoutLoadResult(
        layout: DashboardLayout.defaults(),
        status: DashboardLayoutLoadStatus.corrupt,
      );
    }
  }

  Future<void> save(DashboardLayout layout) async {
    layout.portrait.validate();
    layout.landscape.validate();
    await _repository.save(layout.toJson());
  }
}
