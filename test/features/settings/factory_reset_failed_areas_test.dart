import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/cloud_advanced_section.dart';
import 'package:whispaste/services/factory_reset/factory_reset_coordinator.dart';

/// A failed reset names the areas that still hold data, in every language
/// (BIZ-30, DEV-80). The retry label is the same in every language.
const _languages = ['de', 'en', 'es', 'pt', 'he', 'ru'];

void main() {
  for (final code in _languages) {
    test('$code names each failed area once, with the fixed term', () {
      final l10n = lookupL10n(Locale(code));

      final areas = factoryResetFailedAreas([
        ResetPhase.deletingDatabase,
        ResetPhase.deletingDatabase,
        ResetPhase.deletingAudio,
      ], l10n);

      expect(
        areas,
        '${l10n.factoryResetAreaDb}, ${l10n.factoryResetAreaAudio}',
      );
      expect(l10n.settingsFactoryResetFailedMessage(areas), contains(areas));
      expect(l10n.factoryResetRetryAction, isNotEmpty);
    });
  }

  test('a failure in the subprocess stop names the background process', () {
    final l10n = lookupL10n(const Locale('en'));

    expect(
      factoryResetFailedAreas([ResetPhase.stoppingSubprocess], l10n),
      l10n.factoryResetAreaProcess,
    );
  });

  test('no failed phase yields no area names', () {
    final l10n = lookupL10n(const Locale('en'));

    expect(factoryResetFailedAreas(const [], l10n), isEmpty);
  });

  for (final code in _languages) {
    test('$code adds the keyring hint only when the API keys stayed '
        '(XP-6-11)', () {
      final l10n = lookupL10n(Locale(code));

      final keyring = factoryResetFailureMessage([
        ResetPhase.resettingSecureStore,
      ], l10n);
      final other = factoryResetFailureMessage([
        ResetPhase.deletingAudio,
      ], l10n);

      expect(keyring, contains(l10n.factoryResetKeyringHint));
      expect(keyring, contains(l10n.factoryResetAreaSecure));
      expect(other, isNot(contains(l10n.factoryResetKeyringHint)));
      expect(
        other,
        l10n.settingsFactoryResetFailedMessage(l10n.factoryResetAreaAudio),
      );
    });
  }
}
