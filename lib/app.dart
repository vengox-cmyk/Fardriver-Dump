import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/screens/connection_screen.dart';
import 'package:arcdash/screens/app_shell.dart';
import 'package:arcdash/screens/debug_screen.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/l10n/app_strings.dart';

class ArcDashApp extends ConsumerWidget {
  final Locale? locale;

  const ArcDashApp({super.key, this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep telemetry and session recording active globally
    ref.watch(statsProvider);
    ref.watch(controllerProvider);
    // Force dark status bar icons on light backgrounds (none here, but good practice)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return MaterialApp(
      title: 'ArcDash',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      locale: locale ?? const Locale('de'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      initialRoute: '/dashboard',
      routes: {
        '/': (_) => const ConnectionScreen(),
        '/dashboard': (_) => const AppShell(),
        '/debug': (_) => const DebugScreen(),
      },
    );
  }

  ThemeData _buildTheme() {
    const bgColor = Color(0xFF080B0E);
    const surfaceColor = Color(0xFF111518);
    const accentCyan = Color(0xFF00E5FF);

    final base = ThemeData.dark();

    return base.copyWith(
      scaffoldBackgroundColor: bgColor,
      colorScheme: const ColorScheme.dark(
        primary: accentCyan,
        secondary: Color(0xFF39FF14),
        surface: surfaceColor,
        error: Color(0xFFFF1744),
        onPrimary: Color(0xFF080B0E),
        onSurface: Colors.white,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 72,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -2,
        ),
        displayMedium: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        headlineLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 1,
        ),
        headlineMedium: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          color: Colors.white70,
        ),
        labelSmall: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: const Color(0xFF4A5568),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF1A2030)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentCyan,
          foregroundColor: const Color(0xFF080B0E),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentCyan,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1A2030),
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: surfaceColor,
        iconColor: accentCyan,
        textColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceColor,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A3548)),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 13,
          color: Colors.white70,
          height: 1.6,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentCyan : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accentCyan.withOpacity(0.4)
              : const Color(0xFF2A3548),
        ),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
