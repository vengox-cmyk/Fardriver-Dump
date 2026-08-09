import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/app.dart';
import 'package:biketunes/providers/controller_provider.dart';
import 'package:biketunes/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait on mobile only — desktop platforms don't support orientation locking
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Initialize storage
  final storage = StorageService();
  await storage.init();

  runApp(
    ProviderScope(
      overrides: [
        // Inject initialized storage service
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const BikeTunesApp(),
    ),
  );
}
