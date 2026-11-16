import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/modifier_only_flow.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

final _en = lookupL10n(const Locale('en'));

void main() {
  test('macOS suggests right Command, not Fn, whose tap opens the emoji '
      'picker', () {
    expect(modifierOnlySuggestion(isMacOS: true), 'rightMeta');
  });

  test('other platforms suggest right Control, not AltGr', () {
    expect(modifierOnlySuggestion(isMacOS: false), 'rightControl');
  });

  // PAR-054: the right Command / Windows / Super key is named after the
  // platform's own key, not as a list of all three.
  group('right Command, Windows or Super key is named per platform', () {
    final cases = <TargetPlatform, String>{
      TargetPlatform.macOS: _en.settingsModifierRightMetaMac,
      TargetPlatform.windows: _en.settingsModifierRightMetaWindows,
      TargetPlatform.linux: _en.settingsModifierRightMetaLinux,
    };
    for (final entry in cases.entries) {
      test('${entry.key.name} shows "${entry.value}"', () {
        debugDefaultTargetPlatformOverride = entry.key;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        expect(modifierOnlyLabel(_en, 'rightMeta'), entry.value);
      });
    }

    test('every single key has its own name', () {
      final names = {
        for (final key in ModifierHotkey.values)
          modifierOnlyLabel(_en, key.name),
      };
      expect(names, hasLength(ModifierHotkey.values.length));
    });

    test('the three labels are distinct', () {
      expect(cases.values.toSet(), hasLength(3));
    });
  });
}
