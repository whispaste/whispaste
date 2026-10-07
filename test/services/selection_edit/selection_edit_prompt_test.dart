import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/selection_edit/selection_edit_prompt.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

void main() {
  group('selectionEditQuickActionFor', () {
    test('maps the spoken keywords of all four UI locales', () {
      const cases = {
        // en
        'shorter': SelectionEditQuickAction.shorten,
        'Shorten.': SelectionEditQuickAction.shorten,
        'improve': SelectionEditQuickAction.improve,
        'Translate!': SelectionEditQuickAction.translate,
        // de
        'Kürzer.': SelectionEditQuickAction.shorten,
        'kürzen': SelectionEditQuickAction.shorten,
        'Verbessern': SelectionEditQuickAction.improve,
        'Übersetzen.': SelectionEditQuickAction.translate,
        // ru
        'Короче.': SelectionEditQuickAction.shorten,
        'улучши': SelectionEditQuickAction.improve,
        'Переведи': SelectionEditQuickAction.translate,
        // he
        'קצר': SelectionEditQuickAction.shorten,
        'שפר.': SelectionEditQuickAction.improve,
        'תרגם': SelectionEditQuickAction.translate,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(selectionEditQuickActionFor(key), value, reason: key);
      }
    });

    test('a free-form instruction is not a quick action', () {
      expect(
        selectionEditQuickActionFor('make it shorter and friendlier'),
        isNull,
      );
      expect(selectionEditQuickActionFor('übersetze ins Spanische'), isNull);
      expect(selectionEditQuickActionFor(''), isNull);
    });
  });

  group('buildSelectionEditPrompt', () {
    test('free instruction carries both instruction and selection', () {
      final prompt = buildSelectionEditPrompt(
        instruction: 'make it friendlier',
        selection: 'Send me the report.',
      );
      expect(prompt.quickAction, isNull);
      expect(prompt.userText, contains('make it friendlier'));
      expect(prompt.userText, contains('Send me the report.'));
      // The instruction must not be mistaken for text to edit: the selection
      // is delimited explicitly.
      expect(prompt.userText, contains('<text>\nSend me the report.\n</text>'));
      expect(prompt.systemPrompt, contains('Output ONLY'));
      expect(prompt.systemPrompt, contains('same language'));
    });

    test('quick action shorten sends only the selection', () {
      final prompt = buildSelectionEditPrompt(
        instruction: 'Kürzer.',
        selection: 'Ein langer Absatz.',
      );
      expect(prompt.quickAction, SelectionEditQuickAction.shorten);
      expect(prompt.userText, 'Ein langer Absatz.');
      expect(prompt.systemPrompt, startsWith('Shorten this text'));
    });

    test('quick action improve keeps the language', () {
      final prompt = buildSelectionEditPrompt(
        instruction: 'improve',
        selection: 'teh text',
      );
      expect(prompt.quickAction, SelectionEditQuickAction.improve);
      expect(prompt.systemPrompt, startsWith('Improve this text'));
      expect(prompt.systemPrompt, contains('Do not translate'));
    });

    test('quick action translate uses the configured target language', () {
      final prompt = buildSelectionEditPrompt(
        instruction: 'übersetzen',
        selection: 'Hallo Welt',
        translateTarget: SmartModeTargetLanguage.french,
      );
      expect(prompt.quickAction, SelectionEditQuickAction.translate);
      expect(prompt.systemPrompt, contains('into French'));
      expect(prompt.userText, 'Hallo Welt');
    });
  });
}
