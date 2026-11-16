/// Editing helpers for the auto-paste block list (app list editor).
///
/// The stored value stays one comma-separated string (same setting, no
/// migration of meaning). These helpers read and write that string, and derive
/// the "recently dictated into" app list from the history target apps.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/auto_paste_blocklist.dart';

void main() {
  group('app list entries', () {
    test('old comma-separated values read unchanged, in stored order', () {
      expect(
        autoPasteBlocklistEntries('com.1password.1password,com.apple.Terminal'),
        ['com.1password.1password', 'com.apple.Terminal'],
      );
    });

    test('blank pieces and duplicates by key are dropped', () {
      expect(
        autoPasteBlocklistEntries(' 1Password.EXE , , 1password ,Terminal'),
        ['1Password.EXE', 'Terminal'],
      );
    });

    test('an empty value has no entries', () {
      expect(autoPasteBlocklistEntries(''), isEmpty);
      expect(autoPasteBlocklistEntries(' , '), isEmpty);
    });
  });

  group('adding and removing', () {
    test('adding appends the identifier in comma form', () {
      expect(autoPasteBlocklistWith('chrome', 'notepad'), 'chrome, notepad');
    });

    test('adding into an empty list stores just the identifier', () {
      expect(
        autoPasteBlocklistWith('', ' com.apple.Terminal '),
        'com.apple.Terminal',
      );
    });

    test('adding a key that is already listed changes nothing', () {
      expect(autoPasteBlocklistWith('chrome', 'Chrome.exe'), 'chrome');
    });

    test('adding a blank identifier changes nothing', () {
      expect(autoPasteBlocklistWith('chrome', '   '), 'chrome');
    });

    test('removing matches by key, not by spelling', () {
      expect(
        autoPasteBlocklistWithout('chrome, notepad', 'NOTEPAD.exe'),
        'chrome',
      );
    });

    test('removing the last entry leaves an empty value', () {
      expect(autoPasteBlocklistWithout('chrome', 'chrome'), '');
    });

    test('contains uses the same key rule as the block list', () {
      expect(autoPasteBlocklistContains('chrome', 'Chrome.exe'), isTrue);
      expect(autoPasteBlocklistContains('chrome', 'notepad'), isFalse);
      expect(autoPasteBlocklistContains('chrome', null), isFalse);
    });
  });

  group('recent target apps', () {
    test('lists each app once, newest first, skipping blanks', () {
      final apps = recentTargetApps([
        (targetApp: 'com.apple.Terminal', timestamp: DateTime(2026, 10, 1)),
        (targetApp: null, timestamp: DateTime(2026, 10, 3)),
        (targetApp: '  ', timestamp: DateTime(2026, 10, 3)),
        (targetApp: 'Chrome.exe', timestamp: DateTime(2026, 10, 2)),
        (targetApp: 'chrome', timestamp: DateTime(2026, 9, 1)),
      ]);

      expect(apps.map((app) => app.identifier), [
        'Chrome.exe',
        'com.apple.Terminal',
      ]);
      expect(apps.first.lastUsed, DateTime(2026, 10, 2));
    });

    test('no history gives no apps', () {
      expect(recentTargetApps(const []), isEmpty);
    });
  });
}
