import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/providers/bluetooth_provider.dart';
import 'package:biketunes/providers/controller_provider.dart';
import 'package:biketunes/providers/tuning_provider.dart';
import 'package:biketunes/services/bluetooth_service.dart';
import 'package:biketunes/services/storage_service.dart';

final _useMphProvider = StateProvider<bool>((ref) {
  final storage = ref.read(storageServiceProvider);
  return storage.useMph;
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useMph = ref.watch(_useMphProvider);
    final isConnected = ref.watch(isConnectedProvider);
    final storage = ref.read(storageServiceProvider);
    final hasBackup = storage.hasStockBackup;
    final savedProfiles = ref.watch(tuningProvider).savedProfiles;

    return Scaffold(
      backgroundColor: const Color(0xFF080B0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1A2030)),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Display settings
            const _SectionHeader(title: 'DISPLAY'),
            const SizedBox(height: 10),
            _SettingsTile(
              title: 'Speed Units',
              subtitle: useMph ? 'mph' : 'km/h',
              trailing: Switch(
                value: useMph,
                onChanged: (v) {
                  ref.read(_useMphProvider.notifier).state = v;
                  storage.setUseMph(v);
                },
                activeColor: const Color(0xFF00E5FF),
                inactiveTrackColor: const Color(0xFF2A3548),
              ),
            ),

            const SizedBox(height: 24),

            // Safety
            const _SectionHeader(title: 'SAFETY'),
            const SizedBox(height: 10),
            _SettingsTile(
              title: 'Stock Backup',
              subtitle: hasBackup
                  ? 'Backup saved from first connect'
                  : 'Not yet backed up — connect first',
              icon: Icons.save_outlined,
              iconColor: hasBackup
                  ? const Color(0xFF39FF14)
                  : const Color(0xFF4A5568),
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              title: 'Restore Stock',
              subtitle: 'Write original parameters back to controller',
              icon: Icons.restore,
              iconColor: const Color(0xFFFF9800),
              enabled: isConnected && hasBackup,
              onTap: () => _showRestoreDialog(context, ref),
            ),

            const SizedBox(height: 24),

            // Profiles
            if (savedProfiles.isNotEmpty) ...[
              const _SectionHeader(title: 'SAVED PROFILES'),
              const SizedBox(height: 10),
              for (final profile in savedProfiles)
                _ProfileTile(
                  name: profile.name,
                  description: profile.description,
                  onDelete: () =>
                      ref.read(tuningProvider.notifier).deleteProfile(profile.name),
                  onLoad: () {
                    ref.read(tuningProvider.notifier).loadPreset(profile);
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/tuning');
                  },
                ),
              const SizedBox(height: 24),
            ],

            // Connection
            const _SectionHeader(title: 'CONNECTION'),
            const SizedBox(height: 10),
            _SettingsTile(
              title: 'Disconnect',
              subtitle: isConnected
                  ? 'Currently connected'
                  : 'Not connected',
              icon: Icons.bluetooth_disabled,
              iconColor: isConnected
                  ? const Color(0xFFFF1744)
                  : const Color(0xFF4A5568),
              enabled: isConnected,
              onTap: () async {
                await ref.read(bluetoothServiceProvider).disconnect();
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
            ),

            const SizedBox(height: 24),

            // Info
            const _SectionHeader(title: 'ABOUT'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111518),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1A2030)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BikeTunes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'FarDriver Controller Tuning App\nVersion 1.0.0',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Protocol based on jackhumbert/fardriver-controllers',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.25),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Safety notice
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF1744).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFFFF1744).withOpacity(0.2)),
              ),
              child: const Text(
                '⚠ SAFETY: This app modifies live controller parameters. Always test in a safe, open area. High current settings can permanently damage motor and controller. Modified bikes may be illegal on public roads.',
                style: TextStyle(
                  color: Color(0xFFFF9800),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showRestoreDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111518),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFFFF9800).withOpacity(0.4)),
        ),
        title: const Text(
          'RESTORE STOCK',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        content: const Text(
          'This will write the original factory parameters back to the controller. Any custom tuning will be overwritten.\n\nAre you sure?',
          style: TextStyle(color: Color(0xFF8899AA), fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(color: Color(0xFF4A5568))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(tuningProvider.notifier).restoreStock();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'RESTORE',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF080B0E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF4A5568),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final bool enabled;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111518),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A2030)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color:
                    enabled ? (iconColor ?? const Color(0xFF00E5FF)) : const Color(0xFF2A3548),
                size: 20,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? Colors.white : const Color(0xFF4A5568),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: enabled
                          ? Colors.white.withOpacity(0.4)
                          : const Color(0xFF2A3548),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null && enabled)
              const Icon(Icons.chevron_right, color: Color(0xFF4A5568), size: 20),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String name;
  final String description;
  final VoidCallback onDelete;
  final VoidCallback onLoad;

  const _ProfileTile({
    required this.name,
    required this.description,
    required this.onDelete,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2030)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF4A5568),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onLoad,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF00E5FF)),
            child: const Text('LOAD', style: TextStyle(fontSize: 11, letterSpacing: 1)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: const Color(0xFF4A5568),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
