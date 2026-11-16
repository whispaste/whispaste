import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_text_model.dart';
import 'package:whispaste/services/snippets/spoken_fields.dart';

class _FakeEngine implements SmartModeEngine {
  _FakeEngine(this.answer);

  /// Returns the answer, or never completes when null (a hung model).
  final String? answer;
  int runs = 0;
  int cancels = 0;

  @override
  Future<String> run({required String systemPrompt, required String userText}) {
    runs++;
    final a = answer;
    return a == null ? Completer<String>().future : Future.value(a);
  }

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  group('stage 1: field names as anchors', () {
    test('values follow their spoken names, in any order', () {
      expect(
        assignSpokenFieldsByName([
          'Name',
          'Termin',
        ], 'Termin Dienstag, Name Krüger.'),
        ['Krüger', 'Dienstag'],
      );
    });

    test('connector words and case are ignored', () {
      expect(
        assignSpokenFieldsByName([
          'Name',
          'Termin',
        ], 'name ist Frau Krüger, termin lautet morgen'),
        ['Frau Krüger', 'morgen'],
      );
      expect(
        assignSpokenFieldsByName([
          'Name',
          'Date',
        ], 'Name is Bob, date is Monday'),
        ['Bob', 'Monday'],
      );
    });

    test('a single field takes the whole sentence', () {
      expect(assignSpokenFieldsByName(['Grund'], 'Krank heute.'), [
        'Krank heute',
      ]);
    });

    test('an unspoken field stays empty, nothing is guessed', () {
      expect(
        assignSpokenFieldsByName([
          'Name',
          'Termin',
        ], 'Absage an Frau Krüger, Dienstag'),
        ['', ''],
      );
    });

    test('a longer name wins over a shorter one it contains', () {
      expect(
        assignSpokenFieldsByName([
          'Name',
          'Nachname',
        ], 'Nachname Krüger Name Anna'),
        ['Anna', 'Krüger'],
      );
    });
  });

  group('stage 2: checking the model answer', () {
    const names = ['Name', 'Termin'];
    const sentence = 'Absage an Frau Krüger, Termin Dienstag';

    test('keeps values that occur in the sentence', () {
      expect(
        parseModelFieldAssignment(
          'Sure:\n```json\n{"Name": "Frau Krüger", "Termin": "Dienstag"}\n```',
          names,
          sentence,
        ),
        ['Frau Krüger', 'Dienstag'],
      );
    });

    test('drops invented values and unknown fields', () {
      expect(
        parseModelFieldAssignment(
          '{"Name": "Herr Müller", "Termin": "Dienstag", "Ort": "Berlin"}',
          names,
          sentence,
        ),
        ['', 'Dienstag'],
      );
    });

    test('broken or missing JSON is rejected as a whole', () {
      expect(parseModelFieldAssignment('{"Name": ', names, sentence), isNull);
      expect(parseModelFieldAssignment('no idea', names, sentence), isNull);
    });
  });

  group('SpokenFieldsAssigner', () {
    ProviderContainer containerWith(
      _FakeEngine engine, {
      SmartModeTextModelStatus status = SmartModeTextModelStatus.ready,
    }) {
      final c = ProviderContainer(
        overrides: [
          smartModeEngineProvider.overrideWithValue(engine),
          smartModeTextModelStatusProvider.overrideWithValue(status),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    const names = ['Name', 'Termin'];

    test('a natural sentence goes through the model', () async {
      final engine = _FakeEngine(
        '{"Name": "Frau Krüger", "Termin": "Dienstag"}',
      );
      final r = await containerWith(engine)
          .read(spokenFieldsAssignerProvider)
          .assign(names, 'Absage an Frau Krüger, Dienstag');
      expect(r.values, ['Frau Krüger', 'Dienstag']);
      expect(r.modelReady, isTrue);
    });

    test('spoken names fill everything: the model is not asked', () async {
      final engine = _FakeEngine('{}');
      final r = await containerWith(engine)
          .read(spokenFieldsAssignerProvider)
          .assign(names, 'Name Krüger Termin Dienstag');
      expect(r.values, ['Krüger', 'Dienstag']);
      expect(engine.runs, 0);
    });

    test('without a ready model the names alone decide and the hint is '
        'due', () async {
      final engine = _FakeEngine('{"Name": "Krüger"}');
      final r = await containerWith(
        engine,
        status: SmartModeTextModelStatus.localModelMissing,
      ).read(spokenFieldsAssignerProvider).assign(names, 'Absage an Krüger');
      expect(r.values, ['', '']);
      expect(r.modelReady, isFalse);
      expect(engine.runs, 0);
    });

    test('a hung model falls back to the names and is stopped', () async {
      final engine = _FakeEngine(null);
      final assigner = containerWith(engine).read(spokenFieldsAssignerProvider)
        ..timeout = Duration.zero;
      final r = await assigner.assign(names, 'Termin Dienstag für Krüger');
      expect(r.values, ['', 'Dienstag für Krüger']);
      expect(engine.cancels, 1);
    });
  });
}
