import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_choice_commands.dart';

const _choices = [
  SttChoice(value: 'whisper:base', label: 'Whisper · Base', onDevice: true),
  SttChoice(value: 'download:small', label: 'Laden (466 MB)…', onDevice: true),
  SttChoice(value: 'parakeet', label: 'Parakeet', onDevice: true),
];

void main() {
  group('buildSpeechModelCommands', () {
    test('offers downloaded models and engines, checks the one in use', () {
      final commands = buildSpeechModelCommands(
        choices: _choices,
        current: 'parakeet',
        locked: false,
      );
      expect(
        [for (final c in commands) c.id],
        ['stt:whisper:base', 'stt:parakeet'],
      );
      expect([for (final c in commands) c.checked], [false, true]);
      expect(commands.every((c) => c.enabled), isTrue);
    });

    test('a locked group shows the dock reason and greys out every entry', () {
      final commands = buildSpeechModelCommands(
        choices: _choices,
        current: 'whisper:base',
        locked: true,
      );
      expect(commands.first.id, kTraySpeechModelLockedId);
      expect(commands.first.labelKey, 'dockMenuSttLockedReason');
      expect(commands.first.enabled, isFalse);
      expect(commands[1].isSeparator, isTrue);
      final choices = commands.where(
        (c) => c.id.startsWith(kTraySpeechModelPrefix),
      );
      expect(choices, isNotEmpty);
      expect(choices.every((c) => !c.enabled), isTrue);
    });
  });

  group('buildSmartModeCommands', () {
    test('lists the four presets and checks the standard one', () {
      final commands = buildSmartModeCommands(current: 'cleanup');
      expect(
        [for (final c in commands) c.id],
        ['smart:off', 'smart:cleanup', 'smart:concise', 'smart:translate'],
      );
      expect(
        [for (final c in commands) c.checked],
        [false, true, false, false],
      );
      expect(commands.first.labelKey, 'smartModePresetOff');
    });
  });

  group('buildOutputCommands', () {
    String label(AfterTranscriptionAction a) => a.name;

    test('offers every action where the build can paste', () {
      final commands = buildOutputCommands(
        current: AfterTranscriptionAction.clipboard,
        labelFor: label,
        autoPasteSupported: true,
      );
      expect(commands, hasLength(AfterTranscriptionAction.values.length));
      final checked = [
        for (final c in commands)
          if (c.checked ?? false) c.id,
      ];
      expect(checked, ['output:clipboard']);
    });

    test('leaves out the paste actions where the build cannot paste', () {
      final commands = buildOutputCommands(
        current: AfterTranscriptionAction.nothing,
        labelFor: label,
        autoPasteSupported: false,
      );
      expect(
        [for (final c in commands) c.id],
        ['output:clipboard', 'output:nothing'],
      );
    });
  });

  test('the tooltip joins speech model, Smart Mode and output', () {
    expect(
      trayTooltipText(
        speechModel: 'Parakeet',
        smartMode: 'Smart Mode: Off',
        output: 'Copy only',
      ),
      'Parakeet · Smart Mode: Off · Copy only',
    );
  });

  test('flattening the groups reaches the submenu children', () {
    final commands = buildSmartModeCommands(current: 'off');
    expect(flattenAppCommands(commands), hasLength(4));
  });
}
