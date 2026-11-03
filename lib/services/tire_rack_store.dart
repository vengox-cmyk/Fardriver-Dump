import 'dart:io';

import 'package:arcdash/models/tire_rack.dart';
import 'package:arcdash/services/saved_files.dart';

/// Custom tire sizes, kept as `tire_rack.json` in Saved files › Tires
/// (permanent, mirrored to Documents/FarSure/tires).
class TireRackStore {
  TireRackStore(this.store);
  final SavedFilesStore store;
  static const fileName = 'tire_rack.json';

  Future<File> _file() async =>
      File('${(await store.directoryFor(SavedFileKind.tires)).path}/$fileName');

  Future<List<TireSize>> loadCustom() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      return TireRack.decode(await f.readAsString());
    } on Object {
      return [];
    }
  }

  Future<void> saveCustom(List<TireSize> custom) =>
      store.write(SavedFileKind.tires, fileName, TireRack.encode(custom));

  /// Adds sizes from an exported rack; same-name entries are replaced.
  /// Returns how many sizes were imported.
  Future<int> importText(String text) async {
    final incoming = TireRack.decode(text);
    final current = await loadCustom();
    final names = {for (final t in incoming) t.name};
    await saveCustom([
      ...current.where((t) => !names.contains(t.name)),
      ...incoming,
    ]);
    return incoming.length;
  }
}
