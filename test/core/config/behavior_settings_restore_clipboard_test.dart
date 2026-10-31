/// Round-trip tests for `BehaviorSettings.restoreClipboardAfterPaste`, the
/// setting "Zwischenablage nach dem Einfügen": restore the copy the user had
/// (default) or keep the dictation on the clipboard.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';

void main() {
  group('BehaviorSettings.restoreClipboardAfterPaste', () {
    test('defaults to true (restore what was copied)', () {
      expect(AppSettings.defaults.behavior.restoreClipboardAfterPaste, isTrue);
    });

    test('storage key is present in toStorageMap', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('restore_clipboard_after_paste'), isTrue);
    });

    test('false survives a toStorageMap → fromStorageMap round-trip', () {
      final settings = AppSettings.defaults.copyWithSections(
        behavior: AppSettings.defaults.behavior.copyWith(
          restoreClipboardAfterPaste: false,
        ),
      );

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.behavior.restoreClipboardAfterPaste, isFalse);
    });

    test('a settings store from before the setting restores (migration '
        'default for existing users)', () {
      final map = Map<String, String>.from(AppSettings.defaults.toStorageMap())
        ..remove('restore_clipboard_after_paste');

      final restored = AppSettings.fromStorageMap(map);

      expect(restored.behavior.restoreClipboardAfterPaste, isTrue);
    });
  });

  group('BehaviorSettings.restoreClipboardWithoutReceipt (W-E1)', () {
    test('defaults to false (receipt only for new installs)', () {
      expect(
        AppSettings.defaults.behavior.restoreClipboardWithoutReceipt,
        isFalse,
      );
    });

    test('true survives a toStorageMap → fromStorageMap round-trip', () {
      final settings = AppSettings.defaults.copyWithSections(
        behavior: AppSettings.defaults.behavior.copyWith(
          restoreClipboardWithoutReceipt: true,
        ),
      );

      final restored = AppSettings.fromStorageMap(settings.toStorageMap());

      expect(restored.behavior.restoreClipboardWithoutReceipt, isTrue);
    });
  });
}
