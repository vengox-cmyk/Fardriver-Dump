import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/services/saved_files.dart';

/// What the Rides tab lists: ride records plus the captures made while
/// riding (calibration rides, dash checks, ride CSVs not already attached
/// to a ride record), newest first. Built from file heads only; a ride's
/// details are parsed when it is opened.
class RidesListing {
  final List<SavedFileEntry> entries;

  /// Ids of rides that have a saved record (hides their legacy copy).
  final Set<String> recordIds;

  const RidesListing(this.entries, this.recordIds);

  static const empty = RidesListing([], {});

  static const kinds = [
    SavedFileKind.rideRecord,
    SavedFileKind.calibration,
    SavedFileKind.dashCheck,
    SavedFileKind.rideCsv,
  ];

  static RidesListing from(List<SavedFileEntry> all) {
    final records =
        all.where((e) => e.kind == SavedFileKind.rideRecord).toList();
    final linkedCsv = {
      for (final r in records)
        if (r.info['csvFile'] != null) r.info['csvFile']!
    };
    final entries = all
        .where((e) =>
            kinds.contains(e.kind) &&
            !(e.kind == SavedFileKind.rideCsv && linkedCsv.contains(e.name)))
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return RidesListing(entries, {
      for (final r in records)
        if (r.info['id'] != null) r.info['id']!
    });
  }
}

final ridesListingProvider =
    FutureProvider.autoDispose<RidesListing>((ref) async {
  ref.watch(rideArchiveRevisionProvider);
  final store = ref.watch(savedFilesStoreProvider);
  try {
    return RidesListing.from([
      for (final k in RidesListing.kinds) ...await store.list(kind: k),
    ]);
  } on Object catch (e) {
    debugPrint('Rides list unavailable: $e');
    return RidesListing.empty;
  }
});
