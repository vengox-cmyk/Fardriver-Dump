import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:arcdash/services/saved_files.dart';

/// Permanent file store under `<app documents>/farsure/`. Overridden in
/// tests with a temp directory.
final savedFilesStoreProvider = Provider<SavedFilesStore>(
    (ref) => SavedFilesStore(documentsDir: getApplicationDocumentsDirectory));
