// Guards of the one text write path (#676): pause abort, failing save,
// concurrent change — all on a simulated clock.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/text_writer/paragraph_merge.dart';
import 'package:whispaste/core/data/text_writer/text_journal.dart';
import 'package:whispaste/core/data/text_writer/text_writer.dart';

/// A stored document the writer saves into.
class _Store {
  _Store(this.text);
  String? text;
  int saves = 0;
  Object? failWith;

  Future<void> save(String t) async {
    if (failWith != null) throw failWith!;
    saves++;
    text = t;
  }

  Future<String?> load() async => text;
}

const _key = TextDocKey('note', 'n1');

void main() {
  group('quiet pause', () {
    test('saves once after 2 s of quiet, not per keystroke', () {
      fakeAsync((clock) {
        final store = _Store('');
        final w = TextWriter(journal: MemoryTextJournal());
        for (final t in ['H', 'He', 'Hel', 'Hell', 'Hello']) {
          w.schedule(_key, t, save: store.save, load: store.load);
          clock.elapse(const Duration(milliseconds: 500));
        }
        expect(store.saves, 0);
        clock.elapse(const Duration(milliseconds: 1600));
        expect(store.saves, 1);
        expect(store.text, 'Hello');
      });
    });

    test('a long text waits longer, capped at 6 s', () {
      expect(quietPauseFor(100), const Duration(seconds: 2));
      expect(quietPauseFor(20000), const Duration(seconds: 2));
      expect(quietPauseFor(45000), const Duration(seconds: 4));
      expect(quietPauseFor(10000000), const Duration(seconds: 6));
    });

    test('flush saves at once (close, switch, blur, quit)', () {
      fakeAsync((clock) {
        final store = _Store('');
        final w = TextWriter(journal: MemoryTextJournal());
        w.schedule(_key, 'draft', save: store.save, load: store.load);
        w.flushAll();
        clock.flushMicrotasks();
        expect(store.text, 'draft');
        clock.elapse(const Duration(seconds: 5));
        expect(
          store.saves,
          1,
          reason: 'the cancelled pause must not save again',
        );
      });
    });
  });

  group('abort during the quiet pause', () {
    test('the journal brings the typed text back on the next start', () {
      fakeAsync((clock) {
        final journal = MemoryTextJournal();
        final store = _Store('Line one');
        final w = TextWriter(journal: journal)..opened(_key, 'Line one');
        w.schedule(_key, 'Line one\nLine', save: store.save, load: store.load);
        clock.elapse(const Duration(milliseconds: 400));
        w.schedule(
          _key,
          'Line one\nLine two',
          save: store.save,
          load: store.load,
        );
        clock.elapse(const Duration(milliseconds: 400));
        // Crash: the pause never ends, nothing was saved.
        w.resetForTest();
        clock.elapse(const Duration(seconds: 10));
        expect(store.text, 'Line one');

        final next = TextWriter(journal: journal);
        int? restored;
        next
            .recover({
              'note': TextDocAccess(
                load: (_) => store.load(),
                save: (_, t) => store.save(t),
              ),
            })
            .then((n) => restored = n);
        clock.flushMicrotasks();
        expect(restored, 1);
        expect(store.text, 'Line one\nLine two');
      });
    });

    test('a successful save empties the journal', () {
      fakeAsync((clock) {
        final journal = MemoryTextJournal();
        final store = _Store('');
        final w = TextWriter(journal: journal)..opened(_key, '');
        w.schedule(_key, 'abc', save: store.save, load: store.load);
        clock.elapse(const Duration(seconds: 3));
        late List<TextJournalEntry> left;
        journal.readAll().then((e) => left = e);
        clock.flushMicrotasks();
        expect(store.text, 'abc');
        expect(left, isEmpty);
      });
    });

    test('replay merges with a change stored after the crash', () {
      fakeAsync((clock) {
        final journal = MemoryTextJournal();
        final store = _Store('A\n\nB');
        final w = TextWriter(journal: journal)..opened(_key, 'A\n\nB');
        w.schedule(_key, 'A typed\n\nB', save: store.save, load: store.load);
        clock.elapse(const Duration(milliseconds: 400));
        w.resetForTest();
        store.text = 'A\n\nB\n\nQuick note';

        TextWriter(journal: journal).recover({
          'note': TextDocAccess(
            load: (_) => store.load(),
            save: (_, t) => store.save(t),
          ),
        });
        clock.flushMicrotasks();
        expect(store.text, 'A typed\n\nB\n\nQuick note');
      });
    });
  });

  group('failing save', () {
    test('keeps the text, writes a backup, reports, retries', () {
      fakeAsync((clock) {
        final store = _Store('')..failWith = StateError('disk full');
        final backups = <String, String>{};
        final w = TextWriter(
          journal: MemoryTextJournal(),
          backupWriter: (key, text) async {
            backups['$key'] = text;
            return 'backup/$key';
          },
        );
        final failures = <TextWriteFailure>[];
        w.failures.listen(failures.add);
        w.schedule(_key, 'precious', save: store.save, load: store.load);

        bool? ok;
        w.flush(_key).then((v) => ok = v);
        clock.flushMicrotasks();

        expect(ok, isFalse, reason: 'flush reports, it never throws');
        expect(w.hasPending(_key), isTrue);
        expect(failures.single.backupPath, 'backup/note:n1');
        expect(backups['note:n1'], 'precious');

        store.failWith = null;
        clock.elapse(retryDelay);
        expect(w.hasPending(_key), isFalse);
        expect(store.text, 'precious');
      });
    });

    test('the backup is a real file next to the data', () async {
      final dir = Directory.systemTemp.createTempSync('text_writer_backup');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = _Store('')..failWith = StateError('disk full');
      final w = TextWriter(
        journal: MemoryTextJournal(),
        backupDirectory: dir.path,
      );
      final failure = w.failures.first;
      w.schedule(_key, 'precious', save: store.save);
      await w.flush(_key);
      final path = (await failure).backupPath!;
      expect(p.isWithin(dir.path, path), isTrue);
      expect(File(path).readAsStringSync(), 'precious');
      w.resetForTest();
    });

    test('writeNow rethrows after the backup', () {
      fakeAsync((clock) {
        final store = _Store('')..failWith = StateError('locked');
        final w = TextWriter(journal: MemoryTextJournal());
        Object? error;
        w.writeNow(_key, 'x', save: store.save).catchError((Object e) {
          error = e;
          return '';
        });
        clock.flushMicrotasks();
        expect(error, isA<StateError>());
      });
    });
  });

  group('concurrent change', () {
    test('a change made elsewhere is merged, never overwritten', () {
      fakeAsync((clock) {
        final store = _Store('Intro\n\nBody');
        final w = TextWriter(journal: MemoryTextJournal())
          ..opened(_key, 'Intro\n\nBody');
        final merges = <TextMerge>[];
        w.merges.listen(merges.add);
        w.schedule(
          _key,
          'Intro edited\n\nBody',
          save: store.save,
          load: store.load,
        );
        // A second window appends while the pause runs.
        store.text = 'Intro\n\nBody\n\nAppended elsewhere';
        clock.elapse(const Duration(seconds: 3));
        expect(store.text, 'Intro edited\n\nBody\n\nAppended elsewhere');
        expect(merges.single.conflict, isFalse);

        // Typing on: the next save keeps the other side's paragraph.
        w.schedule(
          _key,
          'Intro edited\n\nBody more',
          save: store.save,
          load: store.load,
        );
        clock.elapse(const Duration(seconds: 3));
        expect(store.text, 'Intro edited\n\nBody more\n\nAppended elsewhere');
      });
    });

    test('saves of two windows never interleave', () {
      fakeAsync((clock) {
        final order = <String>[];
        // Each save stays open until the test releases it, so a second save
        // starting early would show up in [order] (#1491).
        final release = <String, Completer<void>>{};
        Future<void> slow(String tag) async {
          order.add('start $tag');
          await (release[tag] = Completer<void>()).future;
          order.add('end $tag');
        }

        final w = TextWriter(journal: MemoryTextJournal());
        w.writeNow(const TextDocKey('note', 'a'), 'a', save: (_) => slow('a'));
        w.writeNow(const TextDocKey('note', 'b'), 'b', save: (_) => slow('b'));
        clock.elapse(const Duration(milliseconds: 200));
        expect(order, ['start a']);
        release['a']!.complete();
        clock.elapse(const Duration(milliseconds: 200));
        expect(order, ['start a', 'end a', 'start b']);
        release['b']!.complete();
        clock.elapse(const Duration(milliseconds: 200));
        expect(order, ['start a', 'end a', 'start b', 'end b']);
      });
    });
  });

  group('paragraph merge', () {
    test('adjacent edits merge independently and overlaps keep both sides', () {
      final cases = [
        ('a\nb', 'a\nB', 'a\nb\nc', 'a\nB\nc', false),
        ('a\nb', 'prefix\na\nb', 'A\nb', 'prefix\nA\nb', false),
        ('a\nb', 'A\nb', 'a\nB', 'A\nB', false),
        ('a\nb', 'a', 'a\nb\nc', 'a\nc', false),
        ('a\nb', 'a\nx\nb', 'a\ny\nb', 'a\nx\ny\nb', true),
        ('a\nb\nc', 'a\nours', 'a\nb\ntheirs', 'a\nours\nb\ntheirs', true),
      ];
      for (final (base, ours, theirs, expected, conflict) in cases) {
        final result = mergeParagraphs(base, ours, theirs);
        expect(result.text, expected);
        expect(result.conflict, conflict);
        if (!conflict) {
          final reversed = mergeParagraphs(base, theirs, ours);
          expect(reversed.text, expected);
          expect(reversed.conflict, isFalse);
        }
      }
    });

    test('edits of different paragraphs both survive', () {
      final r = mergeParagraphs('a\nb\nc', 'A\nb\nc', 'a\nb\nC');
      expect(r.text, 'A\nb\nC');
      expect(r.conflict, isFalse);
    });

    test('an overlap keeps both versions and reports a conflict', () {
      final r = mergeParagraphs('a\nb', 'a\nmine', 'a\ntheirs');
      expect(r.text, 'a\nmine\ntheirs');
      expect(r.conflict, isTrue);
    });

    test('one-sided change wins without a conflict', () {
      expect(mergeParagraphs('x', 'x', 'y').text, 'y');
      expect(mergeParagraphs('x', 'y', 'x').text, 'y');
    });
  });

  group('file journal', () {
    test('round trip survives a torn last line', () async {
      final dir = Directory.systemTemp.createTempSync('text_journal');
      addTearDown(() => dir.deleteSync(recursive: true));
      final j = FileTextJournal(dir.path);
      await j.start(_key, 'base', TextDelta.between('base', 'base1'));
      await j.append(_key, TextDelta.between('base1', 'base12')!);
      final file = dir.listSync().whereType<File>().single;
      file.writeAsStringSync('{"s":9', mode: FileMode.append);

      final entries = await j.readAll();
      expect(entries.single.key, _key);
      expect(entries.single.replay(), 'base12');

      await j.clear(_key);
      expect(await j.readAll(), isEmpty);
      expect(p.basename(file.path), endsWith('.jsonl'));
    });
  });
}
