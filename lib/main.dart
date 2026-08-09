import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/app.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage
  final storage = StorageService();
  await storage.init();

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
