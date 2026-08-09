import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:biketunes/screens/connection_screen.dart';
import 'package:biketunes/screens/dashboard_screen.dart';
import 'package:biketunes/screens/debug_screen.dart';
import 'package:biketunes/screens/settings_screen.dart';
import 'package:biketunes/screens/stats_screen.dart';
import 'package:biketunes/screens/tuning_screen.dart';

class BikeTunesApp extends StatelessWidget {
  const BikeTunesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Force dark status bar icons on light backgrounds (none here, but good practice)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D1117),
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    return MaterialApp(
      title: 'BikeTunes',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      initialRoute: '/dashboard',
      routes: {
        '/': (_) => const ConnectionScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/tuning': (_) => const TuningScreen(),
        '/stats': (_) => const StatsScreen(),
        '/settings': (_) => const SettingsScreen(),
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
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.rajdhani(
          fontSize: 72,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -2,
        ),
        displayMedium: GoogleFonts.rajdhani(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        headlineLarge: GoogleFonts.rajdhani(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 1,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          color: Colors.white70,
        ),
        labelSmall: GoogleFonts.inter(
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
        titleTextStyle: GoogleFonts.inter(
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
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
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A3548)),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: Colors.white70,
          height: 1.6,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accentCyan
              : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accentCyan.withOpacity(0.4)
              : const Color(0xFF2A3548),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
