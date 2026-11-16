// Named own Smart Mode presets (#891): storage, lookup, display names and
// the add/edit/delete helpers of the Smart Mode page.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/config/smart_mode_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/smart_mode/smart_mode_page.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

void main() {
  const mail = SmartModeCustomPreset(
    id: 'a1',
    name: 'Mail',
    instruction: 'Write it as a polite e-mail.',
  );
  const bullets = SmartModeCustomPreset(
    id: 'b2',
    name: '',
    instruction: 'Turn it into bullet points.',
  );
  final l10n = lookupL10n(const Locale('en'));

  group('SmartModeSettings custom presets', () {
    test('survive a toMap/fromMap round trip', () {
      const settings = SmartModeSettings(
        standardPreset: 'custom:a1',
        customPresets: [mail, bullets],
      );
      final restored = SmartModeSettings.fromMap(settings.toMap());
      expect(restored, settings);
      expect(restored.activeCustomPreset, mail);
    });

    test('a damaged stored list reads as no presets', () {
      expect(SmartModeCustomPreset.listFromJson('{not json'), isEmpty);
      expect(SmartModeCustomPreset.listFromJson('{"id":"x"}'), isEmpty);
      expect(
        SmartModeCustomPreset.listFromJson('[{"name":"no id"},{"id":"x"}]'),
        isEmpty,
      );
    });

    test('customPresetFor resolves only known custom values', () {
      const settings = SmartModeSettings(customPresets: [mail]);
      expect(settings.customPresetFor('custom:a1'), mail);
      expect(settings.customPresetFor('custom:gone'), isNull);
      expect(settings.customPresetFor('cleanup'), isNull);
    });
  });

  group('save rule (#1685)', () {
    const max = kSmartModeCustomInstructionMaxChars;

    test('needs a name and an instruction', () {
      expect(
        smartModeCustomPresetCanSave(name: 'Mail', instruction: 'Do it.'),
        isTrue,
      );
      expect(
        smartModeCustomPresetCanSave(name: '  ', instruction: 'Do it.'),
        isFalse,
      );
      expect(
        smartModeCustomPresetCanSave(name: 'Mail', instruction: ' \n '),
        isFalse,
      );
    });

    test('allows exactly the limit and refuses one character more', () {
      expect(
        smartModeCustomPresetCanSave(name: 'M', instruction: 'a' * max),
        isTrue,
      );
      expect(
        smartModeCustomPresetCanSave(name: 'M', instruction: 'a' * (max + 1)),
        isFalse,
      );
    });

    test('counts trimmed graphemes, not UTF-16 units', () {
      // One flag emoji is four UTF-16 units but one character on screen.
      expect(smartModeCustomInstructionLength('  🇩🇪ab  '), 3);
      expect(
        smartModeCustomPresetCanSave(name: 'M', instruction: '🇩🇪' * max),
        isTrue,
      );
    });

    test('a stored over-long preset survives a round trip uncut', () {
      final long = SmartModeCustomPreset(
        id: 'x',
        name: 'Long',
        instruction: 'a' * (max * 2),
      );
      final restored = SmartModeSettings.fromMap(
        SmartModeSettings(customPresets: [long]).toMap(),
      );
      expect(restored.customPresets.single.instruction.length, max * 2);
    });
  });

  group('display names', () {
    const settings = SmartModeSettings(customPresets: [mail, bullets]);

    test('built-in presets use their localized names', () {
      expect(
        smartModePresetDisplayName('cleanup', l10n),
        l10n.smartModePresetCleanup,
      );
      expect(
        smartModePresetDisplayName('bogus', l10n),
        l10n.smartModePresetOff,
      );
    });

    test('own presets show their name or the untitled fallback', () {
      expect(
        smartModePresetDisplayName('custom:a1', l10n, settings: settings),
        'Mail',
      );
      expect(
        smartModePresetDisplayName('custom:b2', l10n, settings: settings),
        l10n.smartModeCustomPresetUntitled,
      );
      expect(
        smartModePresetDisplayName('custom:gone', l10n, settings: settings),
        l10n.smartModePresetOff,
      );
    });

    test('values list built-ins first, then own presets', () {
      expect(smartModePresetValues(settings), [
        ...kSmartModeBuiltInPresets,
        'custom:a1',
        'custom:b2',
      ]);
    });
  });

  group('page helpers', () {
    test('upsert replaces by id or appends', () {
      final edited = mail.copyWith(name: 'Mail 2');
      expect(upsertSmartModeCustomPreset([mail, bullets], edited), [
        edited,
        bullets,
      ]);
      expect(upsertSmartModeCustomPreset([mail], bullets), [mail, bullets]);
    });

    test('removing the active preset falls back to off', () {
      const settings = SmartModeSettings(
        standardPreset: 'custom:a1',
        customPresets: [mail, bullets],
      );
      final removed = removeSmartModeCustomPreset(settings, 'a1');
      expect(removed.customPresets, [bullets]);
      expect(removed.standardPreset, 'off');

      final other = removeSmartModeCustomPreset(settings, 'b2');
      expect(other.standardPreset, 'custom:a1');
    });
  });

  group('custom instruction prompt', () {
    test('replaces the cleanup wording and keeps the guard rails', () {
      final prompt = smartModeSystemPromptFor(
        SmartModePreset.cleanup,
        customInstruction: '  Say "hi"  ',
      );
      expect(prompt, smartModeCustomSystemPrompt('Say "hi"'));
      expect(prompt, contains(r'"Say \"hi\""'));
      expect(prompt, contains('Output ONLY'));
    });

    test('an empty instruction keeps the built-in cleanup prompt', () {
      expect(
        smartModeSystemPromptFor(
          SmartModePreset.cleanup,
          customInstruction: '   ',
        ),
        smartModeCleanupSystemPrompt,
      );
    });
  });
}
