import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/dictation_text_steps.dart';
import 'package:whispaste/services/dictionary/term_similarity.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

String fix(String text, List<String> terms) => applyTermSimilarity(text, terms);

void main() {
  group('issue #147 cases', () {
    test('T5: Kubernetis stays uncorrected (0.90 < 0.92, 10 characters)', () {
      expect(
        normalizedLevenshteinSimilarity('Kubernetis', 'Kubernetes'),
        closeTo(0.9, 1e-9),
      );
      expect(
        fix('Wir nutzen Kubernetis.', ['Kubernetes']),
        'Wir nutzen Kubernetis.',
      );
    });

    test(
      'T8: strict replacement Whisper -> WhisPaste does not hit Whisker',
      () {
        final strict = CompiledTextReplacements([
          const TextReplacementRule(
            triggers: ['Whisper'],
            replacement: 'WhisPaste',
            matchMode: TextReplacementMatchMode.fuzzy,
            fuzzyThreshold: fuzzyThresholdStrict,
          ),
        ]);
        expect(strict.apply('Das ist ein Whisker.'), 'Das ist ein Whisker.');
        expect(
          normalizedLevenshteinSimilarity('Whisker', 'Whisper'),
          closeTo(0.857, 1e-3),
        );
      },
    );

    test('T9: standard 0.85 is a false positive that strict prevents', () {
      CompiledTextReplacements rule(double t) => CompiledTextReplacements([
        TextReplacementRule(
          triggers: const ['Whisper'],
          replacement: 'WhisPaste',
          matchMode: TextReplacementMatchMode.fuzzy,
          fuzzyThreshold: t,
        ),
      ]);
      expect(
        rule(fuzzyThresholdStandard).apply('Das ist ein Whisker.'),
        'Das ist ein WhisPaste.',
      );
      expect(
        rule(fuzzyThresholdStrict).apply('Das ist ein Whisker.'),
        'Das ist ein Whisker.',
      );
      expect(termSimilarityMatches('Whisker', 'Whisper'), isFalse);
    });
  });

  group('boundary of the strict threshold', () {
    test('one typo is refused at 12 characters and accepted at 13', () {
      expect(termSimilarityMatches('aaaaaaaaaaab', 'aaaaaaaaaaaa'), isFalse);
      expect(termSimilarityMatches('aaaaaaaaaaaab', 'aaaaaaaaaaaaa'), isTrue);
    });

    test('long terms are corrected after a typo, in running text', () {
      expect(
        fix('Die Authentifizierong ist an.', ['Authentifizierung']),
        'Die Authentifizierung ist an.',
      );
      expect(
        fix('Die Datenschutzerklärong, bitte.', ['Datenschutzerklärung']),
        'Die Datenschutzerklärung, bitte.',
      );
    });
  });

  group('guards (corpus: 20 counter samples, 0 false replacements)', () {
    // Real different words, names, inflections, stopwords: never replaced.
    const counterSamples = <(String, String)>[
      ('Whisker', 'Whisper'),
      ('Docker', 'Locker'),
      ('GitLab', 'GitHub'),
      ('Java', 'JavaScript'),
      ('Notion', 'Motion'),
      ('Slack', 'Stack'),
      ('Internationalisierung', 'Internationalisation'),
      ('Krankenhausverwaltungen', 'Krankenhausverwaltung'),
      ('Datenschutzerklärungen', 'Datenschutzerklärung'),
      ('Projektmanagements', 'Projektmanagement'),
      ('Benutzerverwaltung', 'Benutzerverwalter'),
      ('Mikroorganismen', 'Mikroorganismus'),
      ('und', 'Hund'),
      ('oder', 'Coder'),
      ('aber', 'Uber'),
      ('nicht', 'Nichte'),
      ('the', 'Thea'),
      ('and', 'Andy'),
      ('for', 'Ford'),
      ('with', 'Wirth'),
    ];

    test('none of the 20 samples is replaced', () {
      var falseReplacements = 0;
      for (final (heard, term) in counterSamples) {
        final out = fix('Ich sage $heard heute.', [term]);
        if (out != 'Ich sage $heard heute.') falseReplacements++;
      }
      expect(falseReplacements, 0);
    });

    test('an inflected form of a term is not a recognition error', () {
      expect(
        fix('Das Projektmanagements', ['Projektmanagement']),
        'Das Projektmanagements',
      );
    });

    test('a stopword is neither a term nor corrected', () {
      expect(fix('I will go', ['Will']), 'I will go');
      expect(fix('with the', ['Wirth']), 'with the');
    });

    test('words under the minimum length are never matched', () {
      expect(fix('abc', ['abd']), 'abc');
    });

    test('only a camel-case term has its spelling fixed', () {
      expect(fix('ich nutze github', ['GitHub']), 'ich nutze GitHub');
      expect(fix('ein apple fällt', ['Apple']), 'ein apple fällt');
    });

    test('multi-word terms match the same number of words', () {
      expect(
        fix('im Bundesverfassungsgerichtsurteil Karlsruher Gerichthof', [
          'Karlsruher Gerichtshof',
        ]),
        'im Bundesverfassungsgerichtsurteil Karlsruher Gerichtshof',
      );
    });
  });

  group('DictationTextSteps', () {
    Future<String> noReplacements(String t, {bool cascade = true}) async => t;

    DictationTextSteps stepsFor(AppSettings s) =>
        DictationTextSteps.fromSettings(s);

    final parakeet = AppSettings.defaults.copyWithSections(
      stt: AppSettings.defaults.stt.copyWith(
        provider: SttProviderType.onDevice.value,
        engine: OnDeviceEngine.parakeet.value,
      ),
    );

    test('active for an engine without hint, off with a hint channel', () {
      expect(stepsFor(parakeet).termSimilarity, isTrue);
      expect(
        stepsFor(
          parakeet.copyWithSections(
            stt: parakeet.stt.copyWith(provider: SttProviderType.openAI.value),
          ),
        ).termSimilarity,
        isFalse,
      );
    });

    test('can be switched off', () {
      final off = parakeet.copyWithSections(
        behavior: parakeet.behavior.copyWith(termSimilarityEnabled: false),
      );
      expect(stepsFor(off).termSimilarity, isFalse);
    });

    test('runs after the replacements and corrects to the term', () async {
      final text = await stepsFor(parakeet).apply(
        'Der Elasticsearc läuft',
        languageCode: 'de',
        applyReplacements: noReplacements,
        terms: const ['Elasticsearch'],
      );
      expect(text, 'Der Elasticsearch läuft');
    });
  });
}
