import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/app.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/services/public_files.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage
  final storage = StorageService();
  await storage.init();

  // Mirror Saved files to public Documents/FarSure (one-time migration
  // runs in the background).
  PublicFiles.install(
      SavedFilesStore(documentsDir: getApplicationDocumentsDirectory));

  runApp(
    ProviderScope(
      overrides: [
        // Inject initialized storage service
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const ArcDashApp(),
    ),
  );
}
