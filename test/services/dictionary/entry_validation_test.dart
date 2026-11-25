import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/dictionary/entry_validation.dart';

void main() {
  DictionaryEntryProblem? check(
    String t, {
    List<String> existing = const [],
    List<String> triggers = const [],
  }) => checkDictionaryEntry(t, existing: existing, triggers: triggers);

  test('a plain entry passes, an empty one is no problem', () {
    expect(check('Kubernetes'), isNull);
    expect(check('  '), isNull);
  });

  test('60 characters pass, 61 are too long', () {
    expect(check('a' * 60), isNull);
    expect(check('a' * 61), DictionaryEntryProblem.tooLong);
  });

  test('only punctuation or symbols is refused, a digit is enough', () {
    expect(check('...'), DictionaryEntryProblem.onlyPunctuation);
    expect(check('-- !?'), DictionaryEntryProblem.onlyPunctuation);
    expect(check('B2B'), isNull);
    expect(check('ГК РФ'), isNull);
  });

  test('a duplicate is found whatever the letter case', () {
    expect(
      check('github', existing: ['GitHub']),
      DictionaryEntryProblem.duplicate,
    );
  });

  test('a term equal to a replacement trigger is a conflict', () {
    expect(
      check('Mfg', triggers: ['mfg']),
      DictionaryEntryProblem.triggerConflict,
    );
    expect(check('Mfg'), isNull);
  });

  group('checkReplacementDraft (#623)', () {
    test('a plain draft and a symbol trigger pass', () {
      expect(
        checkReplacementDraft(['mfg', ''], 'Mit freundlichen Grüßen'),
        isNull,
      );
      expect(checkReplacementDraft(['->'], '→'), isNull);
    });

    test('61 characters are too long', () {
      final r = checkReplacementDraft(['a' * 61], 'x');
      expect(r?.problem, ReplacementDraftProblem.tooLong);
      expect(checkReplacementDraft(['a' * 60], 'x'), isNull);
    });

    test('a repeated trigger is found whatever the letter case', () {
      final r = checkReplacementDraft(['MfG', ' mfg '], 'x');
      expect(r?.problem, ReplacementDraftProblem.duplicateTrigger);
      expect(r?.trigger, 'mfg');
    });

    test(
      'a trigger equal to its replacement is refused, a case fix is not',
      () {
        expect(
          checkReplacementDraft(['iPhone'], ' iPhone ')?.problem,
          ReplacementDraftProblem.sameAsReplacement,
        );
        expect(checkReplacementDraft(['iphone'], 'iPhone'), isNull);
      },
    );

    test('a term entry (trigger = replacement) is allowed with Similar '
        '(#1969)', () {
      expect(
        checkReplacementDraft(['Kubernetes'], 'Kubernetes', similar: true),
        isNull,
      );
    });
  });
}
