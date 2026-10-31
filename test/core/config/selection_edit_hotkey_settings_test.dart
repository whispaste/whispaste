import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/hotkey_flow.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';

void main() {
  group('SelectionEditHotkeySettings', () {
    test('is off by default — an update never claims a shortcut', () {
      expect(
        const SelectionEditHotkeySettings().selectionEditHotkeyEnabled,
        isFalse,
      );
      expect(
        AppSettings.defaults.selectionEditHotkey.selectionEditHotkeyEnabled,
        isFalse,
      );
    });

    test('round-trips through the flat storage map', () {
      const custom = SelectionEditHotkeySettings(
        selectionEditHotkeyEnabled: true,
        selectionEditHotkeyKey: 'K',
        selectionEditHotkeyKeyDisplay: 'K',
        selectionEditHotkeyModifiers: 'ctrl+alt',
      );
      final settings = const AppSettings().copyWithSections(
        selectionEditHotkey: custom,
      );
      final restored = AppSettings.fromStorageMap(settings.toStorageMap());
      expect(restored.selectionEditHotkey, custom);
    });

    test('survives the deprecated copyWith API', () {
      final settings = const AppSettings().copyWithSections(
        selectionEditHotkey: const SelectionEditHotkeySettings(
          selectionEditHotkeyEnabled: true,
        ),
      );
      // ignore: deprecated_member_use_from_same_package
      final copied = settings.copyWith(windowMaximized: true);
      expect(copied.selectionEditHotkey.selectionEditHotkeyEnabled, isTrue);
    });
  });

  group('activeHotkeyBindings', () {
    final l10n = lookupL10n(const Locale('en'));

    test('includes the enabled selection-edit hotkey as a collision '
        'candidate', () {
      const settings = AppSettings(
        hotkey: HotkeySettings(hotkeyEnabled: false),
        selectionEditHotkey: SelectionEditHotkeySettings(
          selectionEditHotkeyEnabled: true,
          selectionEditHotkeyKey: 'Y',
          selectionEditHotkeyModifiers: 'ctrl+shift',
        ),
      );
      final bindings = activeHotkeyBindings(settings, l10n);
      expect(bindings.map((b) => b.actionId), ['selectionEdit']);
      expect(
        bindings.single.actionLabel,
        l10n.settingsHotkeyActionSelectionEdit,
      );

      final hit = findHotkeyCollision(
        modifiers: 'ctrl+shift',
        key: 'Y',
        bindings: bindings,
      );
      expect(hit?.actionId, 'selectionEdit');
    });

    test('omits it while disabled', () {
      const settings = AppSettings(
        hotkey: HotkeySettings(hotkeyEnabled: false),
      );
      expect(activeHotkeyBindings(settings, l10n), isEmpty);
    });
  });
}
