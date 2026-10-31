import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/utils/speed_units.dart';

/// km/h or mph for everything shown on screen. Persisted in AppSettings;
/// stored data and CSV exports always stay metric.
final speedUnitProvider =
    NotifierProvider<SpeedUnitController, SpeedUnit>(SpeedUnitController.new);

class SpeedUnitController extends Notifier<SpeedUnit> {
  @override
  SpeedUnit build() =>
      ref.read(storageServiceProvider).appSettings.loadSettings().speedUnit;

  void setUnit(SpeedUnit unit) {
    final repository = ref.read(storageServiceProvider).appSettings;
    repository
        .saveSettings(repository.loadSettings().copyWith(speedUnit: unit));
    state = unit;
  }
}

/// km/h ↔ mph switch for Settings → Display. Applies immediately.
class SpeedUnitSelector extends ConsumerWidget {
  const SpeedUnitSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final current = ref.watch(speedUnitProvider);
    return ListTile(
      key: const ValueKey('speed-unit-selector'),
      leading: const Icon(Icons.speed),
      title: Text(strings.text(AppText.speedUnit)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegmentedButton<SpeedUnit>(
          showSelectedIcon: false,
          segments: [
            for (final unit in SpeedUnit.values)
              ButtonSegment(
                  value: unit,
                  label: Text('${unit.speedLabel} · ${unit.distanceLabel}',
                      key: ValueKey('speed-unit-${unit.key}'))),
          ],
          selected: {current},
          onSelectionChanged: (selection) =>
              ref.read(speedUnitProvider.notifier).setUnit(selection.first),
        ),
      ),
    );
  }
}
