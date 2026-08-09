import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/services/diagnostic_log_exporter.dart';
import 'package:arcdash/services/profile_exporter.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(isConnectedProvider);
    final storage = ref.read(storageServiceProvider);
    final strings = AppStrings.of(context);
    final calibration = ref.watch(rangePredictionStateProvider);
    final maxVoltage = calibration?.maxVoltageV;
    final minVoltage = calibration?.minVoltageV;

    return Scaffold(
      appBar: AppBar(title: Text(strings.text(AppText.settings).toUpperCase())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _SectionTitle(strings.text(AppText.display)),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.connection)),
            ListTile(
              leading: Icon(Icons.bluetooth,
                  color: connected
                      ? const Color(0xFF54E39E)
                      : const Color(0xFFFFB45C)),
              title: Text(connected
                  ? strings.text(AppText.controllerConnected)
                  : strings.text(AppText.notConnected)),
              subtitle: Text(connected
                  ? strings.text(AppText.telemetryActive)
                  : strings.text(AppText.selectController)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/'),
            ),
            if (connected)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: Text(strings.text(AppText.disconnectAction)),
                onTap: () => ref.read(bluetoothServiceProvider).disconnect(),
              ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Diagnose-Log teilen'),
              onTap: () {
                final diagnostics = ref.read(diagnosticsLogProvider);
                DiagnosticLogExporter.shareOrCopy(context, diagnostics);
              },
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.dataManagement)),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: Text(strings.text(AppText.resetDashboard)),
              subtitle: Text(strings.text(AppText.resetDashboardHint)),
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.resetDashboardQuestion),
                message: strings.text(AppText.resetDashboardMessage),
                action: storage.resetDashboardLayout,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(strings.text(AppText.deleteRides)),
              subtitle: Text(strings.text(AppText.deleteRidesHint)),
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.deleteRidesQuestion),
                message: strings.text(AppText.irreversible),
                action: storage.clearRideSessions,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: Text(strings.text(AppText.deleteProfiles)),
              subtitle: Text(strings.text(AppText.deleteProfilesHint)),
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.deleteProfilesQuestion),
                message: strings.text(AppText.deleteProfilesMessage),
                action: storage.clearProfiles,
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.voltageCalibration)),
            ListTile(
              leading: const Icon(Icons.battery_charging_full_outlined),
              title: Text(strings.text(AppText.maxVoltage)),
              subtitle: Text(maxVoltage != null
                  ? '${maxVoltage.toStringAsFixed(1)} V'
                  : strings.text(AppText.noCalibrationData)),
            ),
            ListTile(
              leading: const Icon(Icons.battery_alert_outlined),
              title: Text(strings.text(AppText.minVoltage)),
              subtitle: Text(minVoltage != null
                  ? '${minVoltage.toStringAsFixed(1)} V'
                  : strings.text(AppText.noCalibrationData)),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(strings.text(AppText.resetCalibration)),
              subtitle: Text(strings.text(AppText.resetCalibrationHint)),
              enabled: maxVoltage != null || minVoltage != null,
              onTap: () => _confirm(
                context,
                title: strings.text(AppText.resetCalibrationQuestion),
                message: strings.text(AppText.resetCalibrationMessage),
                action: () async {
                  ref
                      .read(rangePredictionStateProvider.notifier)
                      .resetVoltageCalibration();
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Gelerntes Profil exportieren'),
              subtitle: const Text(
                  'Kopiert das gelernte Profil (Spannung & Verbrauch) als JSON'),
              onTap: () {
                final repo = ref.read(rangePredictionRepositoryProvider);
                final profile = calibration ?? repo.loadState(controllerId: '');
                ProfileExporter.exportProfile(context, profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Profil importieren'),
              subtitle: const Text(
                  'Fügt ein vordefiniertes oder geteiltes Profil ein'),
              onTap: () async {
                final imported =
                    await ProfileExporter.importProfileDialog(context);
                if (imported != null) {
                  final repo = ref.read(rangePredictionRepositoryProvider);
                  repo.saveState(imported);
                  ref.invalidate(rangePredictionStateProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Profil erfolgreich importiert & gespeichert!'),
                        backgroundColor: Color(0xFF123328),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.safety)),
            ListTile(
              leading: const Icon(Icons.visibility_outlined,
                  color: Color(0xFF54E39E)),
              title: Text(strings.text(AppText.readOnlyActive)),
              subtitle: Text(strings.text(AppText.readOnlyDescription)),
            ),
            const SizedBox(height: 20),
            _SectionTitle(strings.text(AppText.about)),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.hasData
                    ? 'v${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                    : '1.0.0';
                return ListTile(
                  leading: const Icon(Icons.electric_bike_outlined),
                  title: Text('ArcDash $version Read-only'),
                  subtitle: Text(strings.text(AppText.appDescription)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.of(context).text(AppText.cancel))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(context).text(AppText.reset))),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.of(context).text(AppText.dataReset))));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5)),
      );
}
