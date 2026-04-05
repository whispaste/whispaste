import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Locale state — persists the user's language choice.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  void setLocale(Locale locale) => state = locale;

  /// Set locale from a language display name.
  void setFromDisplayName(String name) {
    state = switch (name) {
      'Deutsch' => const Locale('de'),
      _ => const Locale('en'),
    };
  }

  /// Get the display name for the current locale.
  String get displayName => switch (state.languageCode) {
    'de' => 'Deutsch',
    _ => 'English',
  };
}

/// Primary locale provider.
final localeProvider =
    NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
