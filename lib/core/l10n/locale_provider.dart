import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings_provider.dart';
import 'generated/app_localizations.dart';
import 'initial_locale.dart';
import 'persisted_locale.dart';

/// The app language.
///
/// In this order: a language picked on a start screen before the database
/// opened ([startupLocaleChoiceProvider]), the stored setting, the plain-file
/// mirror of the last stored setting, the system language. The mirror matters
/// while the settings cannot load, for example while the data key waits for
/// consent (#1461): without it that screen fell back to English although the
/// user had chosen another language.
final localeProvider = Provider<Locale>((ref) {
  final choice = ref.watch(startupLocaleChoiceProvider);
  if (choice != null) return Locale(choice);
  final stored = ref.watch(settingsProvider).value?.locale;
  if (stored != null) return Locale(stored);
  final mirrored = ref.watch(startupLocaleMirrorProvider);
  if (mirrored != null && isSupportedAppLocale(mirrored)) {
    return Locale(mirrored);
  }
  return Locale(
    initialLocaleCode(
      ref.watch(systemLocalesProvider).map((l) => l.toLanguageTag()),
    ),
  );
});

/// Whether [code] is one of the app's UI languages.
bool isSupportedAppLocale(String code) =>
    L10n.supportedLocales.any((l) => l.languageCode == code);

/// The locale mirror as read once at start ([readStartupLocaleMirror]).
/// Tests override it instead of writing a file.
final startupLocaleMirrorProvider = Provider<String?>(
  (ref) => readStartupLocaleMirror(),
);

/// A language picked while the settings could not load yet (the data key
/// start screen, #1461). It wins over the stored setting until
/// [StartupLocaleChoice.commit] has written it into the settings, so the
/// database's older value never switches the language back after unlocking.
final startupLocaleChoiceProvider =
    NotifierProvider<StartupLocaleChoice, String?>(StartupLocaleChoice.new);

class StartupLocaleChoice extends Notifier<String?> {
  bool _committing = false;

  @override
  String? build() => null;

  /// The user picked [code]: it shows at once and is mirrored, so the next
  /// start shows it too, even if the user quits before unlocking.
  void choose(String code) {
    writeLocaleMirror(code);
    state = code;
  }

  /// The database is about to open. The language the start screen showed is
  /// kept, so a pick from an earlier run (left only in the mirror) applies as
  /// well. Without a mirror nothing is kept and the stored setting decides.
  void keepShown() {
    if (state != null) return;
    final mirrored = ref.read(startupLocaleMirrorProvider);
    if (mirrored != null && isSupportedAppLocale(mirrored)) state = mirrored;
  }

  /// Writes the pending choice into [settings] once they have loaded, then
  /// hands the language back to the setting. Runs once per choice; a failed
  /// save still clears it, so the settings page stays in charge afterwards.
  Future<void> commit(AppSettings settings) async {
    final choice = state;
    if (choice == null || _committing) return;
    _committing = true;
    try {
      if (settings.locale != choice) {
        await ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(locale: choice));
      }
    } finally {
      _committing = false;
      if (ref.mounted) state = null;
    }
  }
}
