import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/dictionary/replacement_duplicates.dart';
import 'package:whispaste/services/replacements/symbol_template_pack.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';

void main() {
  group('planSymbolPack', () {
    test('an empty list gets the whole pack', () {
      final plan = planSymbolPack(const []);
      expect(plan.toAdd, symbolTemplatePack);
      expect(plan.skipped, 0);
    });

    test('a template is skipped when one of its triggers already exists', () {
      final plan = planSymbolPack(const ['Klammer auf']);
      expect(plan.toAdd.any((t) => t.replacement == '('), isFalse);
      expect(plan.skipped, 1);
    });

    test('the comparison ignores case and punctuation', () {
      final plan = planSymbolPack(const ['  KLAMMER,  auf! ']);
      expect(plan.toAdd.any((t) => t.replacement == '('), isFalse);
    });

    test('the pack adds nothing after its own triggers are in the list', () {
      final existing = [for (final t in symbolTemplatePack) ...t.triggers];
      final plan = planSymbolPack(existing);
      expect(plan.toAdd, isEmpty);
      expect(plan.skipped, symbolTemplatePack.length);
    });

    test('no trigger is a single common word or a sentence mark', () {
      const marks = {'punkt', 'komma', 'point', 'comma', 'at', 'dot', 'plus'};
      for (final template in symbolTemplatePack) {
        for (final trigger in template.triggers) {
          final key = normalizeTriggerKey(trigger);
          expect(key.contains(' ') || key.length >= 6, isTrue, reason: trigger);
          expect(marks.contains(key), isFalse, reason: trigger);
        }
      }
    });
  });

  group('the pack in the matcher', () {
    CompiledTextReplacements compile() => CompiledTextReplacements([
      for (final t in symbolTemplatePack)
        TextReplacementRule(triggers: t.triggers, replacement: t.replacement),
    ]);

    test('spoken symbols become the symbol', () {
      final out = compile().apply('Das Ergebnis klammer auf 3 klammer zu');
      expect(out, contains('('));
      expect(out, contains(')'));
      expect(out.toLowerCase(), isNot(contains('klammer')));
    });

    test('English triggers work too', () {
      final out = compile().apply('mail me at sign home');
      expect(out, contains('@'));
    });

    test('ordinary speech without a trigger is untouched', () {
      const text = 'Das Auto ist klar und der Plan steht fest';
      expect(compile().apply(text), text);
    });
  });

  group('the pack in the database', () {
    late HistoryDatabase db;

    setUp(() {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'a second run adds nothing, the first run writes every template',
      () async {
        final first = planSymbolPack(
          (await db.readAllReplacements()).expand((r) => r.triggers),
        );
        final now = DateTime(2026, 10, 30);
        await db.writeReplacements([
          for (var i = 0; i < first.toAdd.length; i++)
            ReplacementWrite(
              id: 'pack-$i',
              triggers: first.toAdd[i].triggers,
              replacement: first.toAdd[i].replacement,
              createdAt: now,
            ),
        ]);

        final rows = await db.readAllReplacements();
        expect(rows.length, symbolTemplatePack.length);

        final second = planSymbolPack(rows.expand((r) => r.triggers));
        expect(second.toAdd, isEmpty);
        expect(second.skipped, symbolTemplatePack.length);
      },
    );
  });
}
