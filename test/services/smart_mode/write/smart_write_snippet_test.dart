// Snippet as the base of a write run (#252, ADR 0015 D10, D11, D15).
//
// The fixture runs every case through the real SmartWriteService; the fake
// engine answers the selection call with the case's raw model answer and
// counts the generation calls. 0 wrong uses here is evidence for these
// cases, not a guarantee for every instruction.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_notice.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_preview.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_prompt.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_service.dart';
import 'package:whispaste/services/smart_mode/write/smart_write_snippet.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_notice_card.dart';

/// One engine call as the service made it.
typedef _Call = ({String systemPrompt, String userText, bool schema});

/// A local engine: the selection call gets [choice], a generation [draft].
class _LocalEngine implements SmartModeEngine {
  _LocalEngine({this.choice = ''});

  String choice;
  final String draft = 'GENERATED';
  Completer<void>? holdChoice;
  final calls = <_Call>[];
  int cancelCalls = 0;

  int get generations =>
      calls.where((c) => c.systemPrompt != snippetChoiceSystemPrompt).length;
  int get choices => calls.length - generations;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    calls.add((systemPrompt: systemPrompt, userText: userText, schema: false));
    if (systemPrompt != snippetChoiceSystemPrompt) return draft;
    if (holdChoice != null) await holdChoice!.future;
    return choice;
  }
}

/// A cloud engine (OpenAI): structured output for the selection call.
class _CloudEngine extends _LocalEngine implements SmartWriteEngine {
  _CloudEngine({super.choice});

  @override
  Duration get writeTimeout => const Duration(seconds: 30);

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) => throw StateError('write jobs must not use run');

  @override
  Future<String> write({
    required String systemPrompt,
    required String userText,
    required String jobId,
    Map<String, Object>? jsonSchema,
  }) async {
    calls.add((
      systemPrompt: systemPrompt,
      userText: userText,
      schema: jsonSchema != null,
    ));
    return systemPrompt == snippetChoiceSystemPrompt ? choice : draft;
  }

  @override
  void cancelWrite(String jobId) {}
}

Map<String, Object?> _fixture() =>
    jsonDecode(
          File(
            'test/services/smart_mode/write/fixtures/snippet_cases.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  final fixture = _fixture();
  final snippets = [
    for (final s in (fixture['snippets']! as List).cast<Map<String, Object?>>())
      SnippetRef(
        id: s['id']! as String,
        title: s['title']! as String,
        body: s['body']! as String,
      ),
  ];
  final byId = {for (final s in snippets) s.id: s};
  final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();

  group('snippet fixture (${cases.length} cases)', () {
    test('has at least 60 cases and every category', () {
      expect(cases.length, greaterThanOrEqualTo(60));
      expect(
        cases.map((c) => c['kind']).toSet(),
        containsAll(<String>[
          'exact',
          'tolerance',
          'mispronounced',
          'partial',
          'homonym',
          'ambiguous',
          'free',
          'wrong-title',
          'model',
        ]),
      );
    });

    for (final c in cases) {
      final name = '${c['kind']}: ${c['name']}';
      final instruction = c['instruction']! as String;
      final expectedCandidate = c['candidate'] as String?;
      final expectedUsed = c['used'] as String?;
      final verbatim = c['verbatim']! as bool;

      test(name, () async {
        final candidate = snippetCandidate(instruction, snippets);
        expect(candidate?.snippet.id, expectedCandidate, reason: 'candidate');

        final engine = _LocalEngine(choice: c['model']! as String);
        final out = await SmartWriteService(
          engine: engine,
        ).write(instruction: instruction, snippets: snippets);

        final used = expectedUsed == null ? null : byId[expectedUsed];
        expect(out.failure, isNull);
        expect(out.snippetTitle, used?.title, reason: 'snippet used');
        expect(engine.choices, candidate == null ? 0 : 1);
        if (used != null && verbatim) {
          expect(engine.generations, 0, reason: 'verbatim needs no generation');
          expect(out.text, used.body.trim());
        } else {
          expect(engine.generations, 1);
          expect(out.text, 'GENERATED');
        }
        if (used != null && !verbatim) {
          final generation = engine.calls.last;
          expect(generation.userText, contains('<snippet>'));
          expect(generation.userText, contains(used.body.trim()));
          expect(generation.systemPrompt, contains(smartWriteSnippetRule));
        }
        // A snippet text reaches the engine only when that snippet is used.
        for (final s in snippets) {
          if (s.id == used?.id || s.body.trim().isEmpty) continue;
          for (final call in engine.calls) {
            expect(call.userText, isNot(contains(s.body.trim())));
          }
        }
      });
    }
  });

  group('snippetCandidate', () {
    SnippetRef ref(String id, String title) =>
        SnippetRef(id: id, title: title, body: 'BODY-$id');

    test('titles that normalize the same never give a candidate', () {
      final list = [ref('a', 'Grüße, Max!'), ref('b', 'grusse max')];
      expect(snippetCandidate('Grüße Max', list), isNull);
    });

    test('tolerance is one edit per five characters', () {
      expect(snippetTitleTolerance('faq'), 0);
      expect(snippetTitleTolerance('angebot'), 1);
      expect(snippetTitleTolerance('angebot rabatt'), 2);
      expect(snippetTitleTolerance('rechnungserinnerung'), 3);
    });

    test('an exact hit beats a fuzzy one on the same words', () {
      final list = [ref('a', 'Absage'), ref('b', 'Absagen')];
      expect(snippetCandidate('Absage einfügen', list)?.snippet.id, 'a');
    });
  });

  group('selection call', () {
    const snippet = SnippetRef(
      id: 's-1',
      title: 'Angebot',
      body: 'SECRET-BODY ___',
    );

    test('the cloud call sends titles and ids only, with the schema', () async {
      final engine = _CloudEngine(
        choice: '{"snippet_id":"s-1","confidence":0.95}',
      );
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'Angebot für Firma Weber', snippets: [snippet]);
      expect(out.snippetTitle, 'Angebot');
      final choice = engine.calls.first;
      expect(choice.schema, isTrue);
      expect(choice.userText, contains('id: s-1 | title: Angebot'));
      expect(choice.userText, isNot(contains('SECRET-BODY')));
      expect(engine.calls.last.userText, contains('SECRET-BODY'));
    });

    test('a rejected snippet never reaches the cloud', () async {
      final engine = _CloudEngine(choice: '{"snippet_id":null,"confidence":0}');
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'Ich brauche ein Angebot', snippets: [snippet]);
      expect(out.snippetTitle, isNull);
      expect(out.snippetMissed, isTrue);
      for (final call in engine.calls) {
        expect(call.userText, isNot(contains('SECRET-BODY')));
      }
    });

    test('an unparsable local answer means no snippet', () async {
      final engine = _LocalEngine(choice: 'I think the Angebot one, yes.');
      final out = await SmartWriteService(
        engine: engine,
      ).write(instruction: 'Angebot', snippets: [snippet]);
      expect(out.snippetTitle, isNull);
      expect(out.text, 'GENERATED');
      expect(engine.generations, 1);
    });

    test('a revision ignores snippets', () async {
      final engine = _LocalEngine(
        choice: '{"snippet_id":"s-1","confidence":0.99}',
      );
      final out = await SmartWriteService(engine: engine).write(
        instruction: 'Angebot',
        previousDraft: 'Hello',
        snippets: [snippet],
      );
      expect(engine.choices, 0);
      expect(out.snippetTitle, isNull);
      expect(engine.calls.single.userText, isNot(contains('<snippet>')));
    });

    test('a plain writing request gets no "no snippet" line', () async {
      final out = await SmartWriteService(
        engine: _LocalEngine(),
      ).write(instruction: 'Thank Anna for the call', snippets: [snippet]);
      expect(out.snippetMissed, isFalse);
    });

    test('Esc during the selection call ends as cancelled', () async {
      final engine = _LocalEngine(
        choice: '{"snippet_id":"s-1","confidence":0.99}',
      )..holdChoice = Completer<void>();
      final service = SmartWriteService(engine: engine);
      final run = service.write(instruction: 'Angebot', snippets: [snippet]);
      await Future<void>.delayed(Duration.zero);
      await service.cancel();
      engine.holdChoice!.complete();
      final out = await run;
      expect(out.failure, SmartWriteFailure.cancelled);
      expect(engine.generations, 0);
      expect(engine.cancelCalls, 1);
    });
  });

  group('snippet line on the preview', () {
    final l10n = lookupL10n(const Locale('en'));
    DictationNotice card(SmartWriteDraft draft) =>
        smartWriteDraftNotice(l10n, draft, onInsert: () {}, onDiscard: () {});

    test('used, missed and a changed target over the overlay wire', () {
      String? line(SmartWriteDraft draft) {
        final wire = OverlayNotice.fromMap(
          overlayNoticeFor(card(draft), l10n).toMap(),
        )!;
        return wire.notes
            .where((n) => n.id == kSmartWriteSnippetLineId)
            .map((n) => n.text)
            .firstOrNull;
      }

      expect(
        line(
          const SmartWriteDraft(text: 'Hi', serial: 1, snippetTitle: 'Angebot'),
        ),
        l10n.smartWriteSnippetUsed('Angebot'),
      );
      expect(
        line(const SmartWriteDraft(text: 'Hi', serial: 1, snippetMissed: true)),
        l10n.smartWriteSnippetNone,
      );
      expect(
        line(
          const SmartWriteDraft(
            text: 'Hi',
            serial: 1,
            snippetTitle: 'Angebot',
            targetChanged: true,
          ),
        ),
        isNull,
      );
      expect(line(const SmartWriteDraft(text: 'Hi', serial: 1)), isNull);
    });

    testWidgets('the card shows the line under its testID', (tester) async {
      final handle = tester.ensureSemantics();
      Future<void> pump(String line) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: WpOverlayNoticeCard(
              notice: OverlayNotice(
                kind: OverlayNoticeKind.message,
                tone: OverlayNoticeTone.hint,
                title: 'Title',
                body: 'Body',
                notes: [
                  if (line.isNotEmpty)
                    OverlayNoticeNote(id: kSmartWriteSnippetLineId, text: line),
                ],
                actions: const [],
              ),
              colors: OverlayDesignSpec.colorsFor(),
              onAction: (_) {},
            ),
          ),
        ),
      );
      await pump('Based on snippet "Angebot"');
      expect(find.byKey(const ValueKey(kSmartWriteSnippetLineId)), findsOne);
      expect(
        find.semantics.byPredicate(
          (n) => n.identifier == kSmartWriteSnippetLineId,
        ),
        findsOne,
      );
      await pump('');
      expect(
        find.byKey(const ValueKey(kSmartWriteSnippetLineId)),
        findsNothing,
      );
      handle.dispose();
    });
  });
}
