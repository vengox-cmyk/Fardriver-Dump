import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/providers/controller_provider.dart';

/// Current UI locale. Defaults to English; a language explicitly picked in
/// Settings is persisted in [AppSettings] and restored on launch.
final localeProvider =
    NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    final settings =
        ref.read(storageServiceProvider).appSettings.loadSettings();
    return Locale(settings.languageCode);
  }

  void setLanguage(String languageCode) {
    if (!AppSettings.supportedLanguageCodes.contains(languageCode)) return;
    final repository = ref.read(storageServiceProvider).appSettings;
    repository.saveSettings(repository
        .loadSettings()
        .copyWith(languageCode: languageCode, languageChosen: true));
    state = Locale(languageCode);
  }
}

/// English / Deutsch switch for the Settings screen. Applies immediately.
class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    final current = ref.watch(localeProvider).languageCode;
    return ListTile(
      key: const ValueKey('language-selector'),
      leading: const Icon(Icons.language),
      title: Text(strings.text(AppText.language)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: 'en',
                label: Text(strings.text(AppText.languageEnglish))),
            ButtonSegment(
                value: 'de', label: Text(strings.text(AppText.languageGerman))),
          ],
          selected: {current},
          onSelectionChanged: (selection) =>
              ref.read(localeProvider.notifier).setLanguage(selection.first),
        ),
      ),
    );
  }
}
