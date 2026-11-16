import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/snippet_picker/snippet_trigger_resolver.dart';

const _signature = (id: 'sig', title: 'Signatur');
const _invoice = (id: 'inv', title: 'Rechnung');
const _mailBoss = (id: 'boss', title: 'Mail Chef');
const _mailBossFem = (id: 'bossf', title: 'Mail Chefin');

SnippetTriggerRoute route(
  String transcript, {
  String trigger = 'Textbaustein',
  List<SnippetTitleCandidate> snippets = const [_signature, _invoice],
}) => resolveSnippetTrigger(
  trigger: trigger,
  transcript: transcript,
  snippets: snippets,
);

void expectDirect(SnippetTriggerRoute r, String id) {
  expect(r, isA<SnippetTriggerDirect>());
  expect((r as SnippetTriggerDirect).snippetId, id);
}

void expectPicker(SnippetTriggerRoute r, String? query) {
  expect(r, isA<SnippetTriggerPicker>());
  expect((r as SnippetTriggerPicker).query, query);
}

void main() {
  group('resolveSnippetTrigger — direct insert', () {
    test('exact title after the trigger word inserts directly', () {
      expectDirect(route('Textbaustein Signatur'), 'sig');
    });

    test('recognition variant with a typo still matches uniquely', () {
      expectDirect(route('Textbaustein Signatru'), 'sig');
    });

    test('case, diacritics and a trailing period are ignored', () {
      expectDirect(
        route('textbaustein RECHNUNG.', snippets: const [_invoice]),
        'inv',
      );
      expectDirect(
        route('Textbaustein Rechnüng', snippets: const [_invoice]),
        'inv',
      );
    });

    test('umlaut in the title matches its ae spelling', () {
      expectDirect(
        route(
          'Textbaustein Mueller',
          snippets: const [(id: 'm', title: 'Müller')],
        ),
        'm',
      );
    });

    test('a single snippet has no runner-up and counts as unambiguous', () {
      expectDirect(
        route('Textbaustein Signatur', snippets: const [_signature]),
        'sig',
      );
    });

    test('an interactive snippet title is routed by its id', () {
      expectDirect(
        route(
          'Textbaustein Adressblock',
          snippets: const [(id: 'addr', title: 'Adressblock')],
        ),
        'addr',
      );
    });
  });

  group('resolveSnippetTrigger — picker', () {
    test('two similar titles are ambiguous: picker filtered by the name', () {
      expectPicker(
        route(
          'Textbaustein Mail Chef',
          snippets: const [_mailBoss, _mailBossFem],
        ),
        'mail chef',
      );
    });

    test('a partial name matching several titles opens the picker', () {
      expectPicker(
        route(
          'Textbaustein Rechnung',
          snippets: const [
            (id: 'mai', title: 'Rechnung Mai'),
            (id: 'jun', title: 'Rechnung Juni'),
          ],
        ),
        'rechnung',
      );
    });

    test('the trigger word alone opens the picker unfiltered', () {
      expectPicker(route('Textbaustein'), null);
    });

    test('the trigger word alone with a trailing period opens the picker '
        'unfiltered', () {
      expectPicker(route('Textbaustein.'), null);
    });

    test('the empty snippet list with only the trigger word opens the picker '
        '(it shows the empty hint)', () {
      expectPicker(route('Textbaustein', snippets: const []), null);
    });
  });

  // Decision 2026-10-31 (north-star review #23): a dictation that starts with
  // the trigger word but names no snippet is an ordinary dictation. It is
  // pasted and saved; the picker never swallows it.
  group('resolveSnippetTrigger — no snippet named: normal dictation', () {
    test('no title matches', () {
      expect(route('Textbaustein Gutschein'), isA<SnippetTriggerNone>());
    });

    test('a longer sentence after the trigger word', () {
      expect(
        route('Textbaustein meine Signatur ist noch nicht fertig'),
        isA<SnippetTriggerNone>(),
      );
    });

    test('a name below the threshold matching a single title', () {
      expect(
        route(
          'Textbaustein Tel',
          snippets: const [(id: 't', title: 'Telefon')],
        ),
        isA<SnippetTriggerNone>(),
      );
    });

    test('a partial name that begins only one title', () {
      expect(
        route(
          'Textbaustein Rechnung',
          snippets: const [(id: 'mai', title: 'Rechnung Mai'), _signature],
        ),
        isA<SnippetTriggerNone>(),
      );
    });

    test('an empty snippet list', () {
      expect(
        route('Textbaustein Signatur', snippets: const []),
        isA<SnippetTriggerNone>(),
      );
    });
  });

  group('resolveSnippetTrigger — no trigger', () {
    test('the trigger word in the middle of a sentence does nothing', () {
      expect(
        route('ich brauche einen Textbaustein Signatur'),
        isA<SnippetTriggerNone>(),
      );
    });

    test('unrelated text does nothing', () {
      expect(route('Guten Morgen zusammen'), isA<SnippetTriggerNone>());
    });

    test('an empty trigger (feature off) never matches', () {
      expect(
        route('Textbaustein Signatur', trigger: ''),
        isA<SnippetTriggerNone>(),
      );
    });

    test('a whitespace-only transcript never matches', () {
      expect(route('   '), isA<SnippetTriggerNone>());
    });

    test('a whitespace-only trigger (feature off) never matches', () {
      expect(
        route('Textbaustein Signatur', trigger: '   '),
        isA<SnippetTriggerNone>(),
      );
    });

    test('a transcript that is a prefix of the trigger does nothing', () {
      expect(route('Text'), isA<SnippetTriggerNone>());
    });
  });

  group('snippetTriggerPrefixMatches', () {
    test('true when the transcript starts with the trigger words', () {
      expect(
        snippetTriggerPrefixMatches('Textbaustein', 'textbaustein signatur'),
        isTrue,
      );
    });

    test('false when the trigger word is not at the start', () {
      expect(
        snippetTriggerPrefixMatches('Textbaustein', 'mein textbaustein'),
        isFalse,
      );
    });
  });
}
