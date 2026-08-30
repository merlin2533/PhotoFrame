import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../state/settings_providers.dart';

/// Lets the user pick the app's UI language: follow the system locale, or
/// pin it to one of [AppLocalizations.supportedLocales] explicitly. See
/// `app.dart` for how [AppSettings.languageCode] is turned into the actual
/// [Locale] passed to `MaterialApp.router`.
class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.languageScreenTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonError(e.toString()))),
        data: (settings) {
          return RadioGroup<String?>(
            groupValue: settings.languageCode,
            onChanged: (v) => notifier.updateSettings(
              (s) => v == null ? s.copyWith(clearLanguageCode: true) : s.copyWith(languageCode: v),
            ),
            child: ListView(
              children: [
                RadioListTile<String?>(
                  title: Text(l10n.languageSystemOption),
                  value: null,
                ),
                const RadioListTile<String?>(
                  title: Text('Deutsch'),
                  value: 'de',
                ),
                const RadioListTile<String?>(
                  title: Text('English'),
                  value: 'en',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
