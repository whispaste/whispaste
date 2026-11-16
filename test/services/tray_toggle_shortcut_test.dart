// The dictation trigger shown in the tray and the button menu follows the
// active trigger and the key the user pressed, not the stored position.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/tray_service.dart';

void main() {
  final de = lookupL10n(const Locale('de'));

  test('a combination shows the pressed key, not the stored position', () {
    final settings = AppSettings.defaults.copyWith(
      hotkeyKey: ';',
      hotkeyKeyDisplay: 'Ö',
      hotkeyModifiers: 'meta',
    );
    expect(settings.hotkey.hotkeyDoubleTapKey, isEmpty);
    final shown = trayToggleShortcut(settings, de);
    expect(shown, contains('Ö'));
    expect(shown, isNot(contains(';')));
  });

  test('a single-key trigger shows that key, not the idle combination', () {
    final combo = AppSettings.defaults.copyWith(
      hotkeyKey: ';',
      hotkeyModifiers: 'meta',
    );
    final settings = combo.copyWithSections(
      hotkey: combo.hotkey.copyWith(hotkeyDoubleTapKey: 'rightMeta'),
    );
    expect(
      trayToggleShortcut(settings, de),
      modifierOnlyLabel(de, 'rightMeta'),
    );
  });
}
