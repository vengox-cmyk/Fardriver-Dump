import 'package:flutter/material.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/screens/settings_screen.dart';
import 'package:arcdash/screens/stats_screen.dart';
import 'package:arcdash/l10n/app_strings.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _screens = [
    DashboardScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final strings = AppStrings.of(context);
          final destinations = [
            NavigationDestination(
                icon: const Icon(Icons.speed),
                label: strings.text(AppText.cockpit)),
            NavigationDestination(
                icon: const Icon(Icons.route_outlined),
                label: strings.text(AppText.rides)),
            NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                label: strings.text(AppText.settings)),
          ];
          final useRail = constraints.maxWidth >= 700;
          final content = IndexedStack(
            index: _selectedIndex,
            children: _screens,
          );
          if (useRail) {
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _select,
                      labelType: NavigationRailLabelType.all,
                      destinations: destinations
                          .map((destination) => NavigationRailDestination(
                                icon: destination.icon,
                                selectedIcon: destination.selectedIcon,
                                label: Text(destination.label),
                              ))
                          .toList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                ),
              ),
            );
          }
          return Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              destinations: destinations,
            ),
          );
        },
      );

  void _select(int index) => setState(() => _selectedIndex = index);
}
