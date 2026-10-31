import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';

/// A fresh/partial storage map has no `*_modifiers` key. The fromMap default
/// must be the platform-correct modifier (⌘+Shift on macOS), not a hard-coded
/// Ctrl+Shift — otherwise a macOS install that has other settings stored but
/// no hotkey keys silently binds Ctrl+Shift+KEY.
void main() {
  final expectedDefault = Platform.isMacOS ? 'meta+shift' : 'ctrl+shift';

  group('hotkey modifier default when the storage key is missing', () {
    test('main hotkey', () {
      expect(HotkeySettings.fromMap(const {}).hotkeyModifiers, expectedDefault);
    });

    test('quick-note hotkey', () {
      expect(
        QuickNoteHotkeySettings.fromMap(const {}).quickNoteHotkeyModifiers,
        expectedDefault,
      );
    });

    test('snippet-picker hotkey', () {
      expect(
        SnippetPickerHotkeySettings.fromMap(
          const {},
        ).snippetPickerHotkeyModifiers,
        expectedDefault,
      );
    });

    test('smart-mode hotkey', () {
      expect(
        SmartModeHotkeySettings.fromMap(const {}).smartModeHotkeyModifiers,
        expectedDefault,
      );
    });

    test('selection-edit hotkey', () {
      expect(
        SelectionEditHotkeySettings.fromMap(
          const {},
        ).selectionEditHotkeyModifiers,
        expectedDefault,
      );
    });

    test('fromMap default matches the platform-aware factory', () {
      expect(
        SelectionEditHotkeySettings.fromMap(
          const {},
        ).selectionEditHotkeyModifiers,
        buildDefaultSelectionEditHotkeySettings().selectionEditHotkeyModifiers,
      );
      expect(
        QuickNoteHotkeySettings.fromMap(const {}).quickNoteHotkeyModifiers,
        buildDefaultQuickNoteHotkeySettings().quickNoteHotkeyModifiers,
      );
      expect(
        SnippetPickerHotkeySettings.fromMap(
          const {},
        ).snippetPickerHotkeyModifiers,
        buildDefaultSnippetPickerHotkeySettings().snippetPickerHotkeyModifiers,
      );
    });

    test(
      'a fresh storage map yields the platform default for every hotkey',
      () {
        final settings = AppSettings.fromStorageMap(const {
          'stt_model': 'whisper-small',
        });
        expect(settings.hotkey.hotkeyModifiers, expectedDefault);
        expect(
          settings.quickNoteHotkey.quickNoteHotkeyModifiers,
          expectedDefault,
        );
        expect(
          settings.snippetPickerHotkey.snippetPickerHotkeyModifiers,
          expectedDefault,
        );
        expect(
          settings.smartModeHotkey.smartModeHotkeyModifiers,
          expectedDefault,
        );
        expect(
          settings.selectionEditHotkey.selectionEditHotkeyModifiers,
          expectedDefault,
        );
      },
    );
  });

  group('stored modifier values are never overridden', () {
    test('an explicitly stored ctrl+shift survives on every platform', () {
      final settings = AppSettings.fromStorageMap(const {
        'hotkey_modifiers': 'ctrl+shift',
        'quick_note_hotkey_modifiers': 'ctrl+shift',
        'snippet_picker_hotkey_modifiers': 'ctrl+shift',
        'smart_mode_hotkey_modifiers': 'ctrl+shift',
        'selection_edit_hotkey_modifiers': 'ctrl+shift',
      });
      expect(settings.hotkey.hotkeyModifiers, 'ctrl+shift');
      expect(settings.quickNoteHotkey.quickNoteHotkeyModifiers, 'ctrl+shift');
      expect(
        settings.snippetPickerHotkey.snippetPickerHotkeyModifiers,
        'ctrl+shift',
      );
      expect(settings.smartModeHotkey.smartModeHotkeyModifiers, 'ctrl+shift');
      expect(
        settings.selectionEditHotkey.selectionEditHotkeyModifiers,
        'ctrl+shift',
      );
    });

    test('an explicitly stored meta+shift survives on every platform', () {
      expect(
        SelectionEditHotkeySettings.fromMap(const {
          'selection_edit_hotkey_modifiers': 'meta+shift',
        }).selectionEditHotkeyModifiers,
        'meta+shift',
      );
    });
  });
}
