/// Unit-Tests für [activeHotkeyBindings] — die eine Liste, gegen die jeder
/// Belegungs-Versuch geprüft wird (Ticket 27).
///
/// Der Kollisions-Algorithmus selbst hat seine Tests in
/// `test/services/hotkey_conflicts_test.dart`. Hier geht es um die Frage
/// davor: *welche* Hotkeys stehen überhaupt in der Liste — seit Ticket 27
/// drei statt zwei, und der dritte darf weder fehlen noch doppelt erscheinen.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/hotkey_flow.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  const allOn = AppSettings(
    hotkey: HotkeySettings(
      hotkeyEnabled: true,
      hotkeyKey: 'D',
      hotkeyModifiers: 'ctrl+shift',
    ),
    quickNoteHotkey: QuickNoteHotkeySettings(
      quickNoteHotkeyEnabled: true,
      quickNoteHotkeyKey: 'N',
      quickNoteHotkeyModifiers: 'ctrl+shift',
    ),
    snippetPickerHotkey: SnippetPickerHotkeySettings(
      snippetPickerHotkeyEnabled: true,
      snippetPickerHotkeyKey: 'E',
      snippetPickerHotkeyModifiers: 'ctrl+shift',
    ),
  );

  group('activeHotkeyBindings', () {
    test('führt alle drei eingeschalteten Hotkeys mit ihren Action-IDs', () {
      expect(activeHotkeyBindings(allOn, l10n).map((b) => b.actionId), [
        'global',
        'quickNote',
        'snippetPicker',
      ]);
    });

    test('übernimmt Taste und Modifier des Snippet-Picker-Hotkeys', () {
      final picker = activeHotkeyBindings(
        allOn,
        l10n,
      ).firstWhere((b) => b.actionId == 'snippetPicker');
      expect(picker.key, 'E');
      expect(picker.modifiers, 'ctrl+shift');
      expect(picker.actionLabel, l10n.settingsHotkeyActionSnippetPicker);
    });

    test('lässt einen abgeschalteten Hotkey weg — er belegt nichts', () {
      final bindings = activeHotkeyBindings(
        allOn.copyWithSections(
          snippetPickerHotkey: allOn.snippetPickerHotkey.copyWith(
            snippetPickerHotkeyEnabled: false,
          ),
        ),
        l10n,
      );
      expect(bindings.map((b) => b.actionId), ['global', 'quickNote']);
    });

    test('ist bei durchweg abgeschalteten Hotkeys leer', () {
      // Der Aufnahme-Hotkey ist per Default an, deshalb hier ausdrücklich aus.
      const allOff = AppSettings(hotkey: HotkeySettings(hotkeyEnabled: false));
      expect(activeHotkeyBindings(allOff, l10n), isEmpty);
    });

    test('meldet den Snippet-Picker als Belegung an die anderen beiden', () {
      // Was der Schnellnotiz-Dialog tut, wenn dort Ctrl+Shift+E getippt wird.
      final hit = findHotkeyCollision(
        modifiers: 'ctrl+shift',
        key: 'E',
        bindings: activeHotkeyBindings(allOn, l10n),
        excludeActionId: 'quickNote',
      );
      expect(hit?.actionId, 'snippetPicker');
      expect(hit?.actionLabel, l10n.settingsHotkeyActionSnippetPicker);
    });

    test(
      'lässt den Snippet-Picker-Hotkey nicht mit sich selbst kollidieren',
      () {
        expect(
          findHotkeyCollision(
            modifiers: 'ctrl+shift',
            key: 'E',
            bindings: activeHotkeyBindings(allOn, l10n),
            excludeActionId: 'snippetPicker',
          ),
          isNull,
        );
      },
    );

    test('prüft den Snippet-Picker trotz Ausschluss gegen die übrigen', () {
      final hit = findHotkeyCollision(
        modifiers: 'ctrl+shift',
        key: 'N',
        bindings: activeHotkeyBindings(allOn, l10n),
        excludeActionId: 'snippetPicker',
      );
      expect(hit?.actionId, 'quickNote');
    });
  });
}
