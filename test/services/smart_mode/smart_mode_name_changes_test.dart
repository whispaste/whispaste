import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_name_changes.dart';

void main() {
  group('name changes of a free instruction (2c)', () {
    test('a changed name is reported as one pair', () {
      final changes = smartModeNameChanges(
        before: 'Ich habe Müller gesehen.',
        after: 'Ich habe Meier gesehen.',
        singleCapitalisedWordsAreNames: true,
      );

      expect(changes, hasLength(1));
      expect(changes.single.from, 'Müller');
      expect(changes.single.to, 'Meier');
      expect(formatNameChangeSummary(changes), 'Müller → Meier');
    });

    test('unpaired removals and additions keep their own line', () {
      final removed = smartModeNameChanges(
        before: 'Ich habe Müller und Schulz gesehen.',
        after: 'Ich habe Müller gesehen.',
        singleCapitalisedWordsAreNames: true,
      );
      expect(formatNameChangeSummary(removed), '– Schulz');

      final added = smartModeNameChanges(
        before: 'Ich habe Müller gesehen.',
        after: 'Ich habe Müller und Schulz gesehen.',
        singleCapitalisedWordsAreNames: true,
      );
      expect(formatNameChangeSummary(added), '+ Schulz');
    });

    test('more than three pairs show the first three and "+N"', () {
      final changes = smartModeNameChanges(
        before: 'Wir sahen Anna, Berta, Clara, Dora und Emil.',
        after: 'Wir sahen Ida, Jana, Kira, Lina und Mona.',
        singleCapitalisedWordsAreNames: true,
      );

      expect(changes, hasLength(5));
      expect(
        formatNameChangeSummary(changes),
        'Anna → Ida, Berta → Jana, Clara → Kira, +2',
      );
    });

    test('no changed name gives no changes', () {
      final changes = smartModeNameChanges(
        before: 'Ich habe Müller gesehen.',
        after: 'Ich habe Müller gesehen, sagt er.',
        singleCapitalisedWordsAreNames: true,
      );

      expect(changes, isEmpty);
      expect(formatNameChangeSummary(changes), '');
    });
  });

  group('translation keywords (2c)', () {
    const samples = <String>[
      'übersetze das ins Englische',
      'Übersetze bitte',
      'translate this',
      'Make it short and translate into English',
      'traduce esto al inglés',
      'traduza isto para o inglês',
      'переведи на английский',
      'תרגם את זה לאנגלית',
    ];

    for (final sample in samples) {
      test('"$sample" is a translation', () {
        expect(isTranslationInstruction(sample), isTrue);
      });
    }

    test('an ordinary rewrite is not a translation', () {
      expect(isTranslationInstruction('mach es formeller'), isFalse);
      expect(isTranslationInstruction('ändere 3 zu 5'), isFalse);
    });
  });
}
