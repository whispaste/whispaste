/// Unit tests for [NoteAutosave], the editors' adapter onto the one text
/// write path (#676). Timing details live in `text_writer_test.dart`; here
/// only the hand-over to the writer is checked, on a simulated clock.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/text_writer/text_journal.dart';
import 'package:whispaste/core/data/text_writer/text_writer.dart';
import 'package:whispaste/features/notes/data/note_autosave.dart';

void main() {
  late List<(String, String)> saves;
  late NoteAutosave autosave;

  void build() {
    saves = [];
    autosave = NoteAutosave(
      onSave: (id, content) async => saves.add((id, content)),
      writer: TextWriter(journal: MemoryTextJournal()),
    );
  }

  test('rapid keystrokes save the last content once after the pause', () {
    fakeAsync((async) {
      build();
      autosave.schedule('note-1', 'h');
      async.elapse(const Duration(milliseconds: 100));
      autosave.schedule('note-1', 'hel');
      async.elapse(const Duration(milliseconds: 1999));
      expect(saves, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(saves, [('note-1', 'hel')]);
    });
  });

  test('flush saves every scheduled note at once, then nothing more', () {
    fakeAsync((async) {
      build();
      autosave.schedule('note-1', 'a');
      autosave.schedule('note-2', 'b');
      bool? ok;
      autosave.flush().then((v) => ok = v);
      async.flushMicrotasks();
      expect(ok, isTrue);
      expect(saves, [('note-1', 'a'), ('note-2', 'b')]);
      async.elapse(const Duration(seconds: 5));
      expect(saves, hasLength(2));
    });
  });

  test('flush reports a failed save instead of throwing', () {
    fakeAsync((async) {
      final autosave = NoteAutosave(
        onSave: (_, _) async => throw StateError('locked'),
        writer: TextWriter(
          journal: MemoryTextJournal(),
          backupWriter: (_, _) async => null,
        ),
      );
      autosave.schedule('note-1', 'x');
      bool? ok;
      autosave.flush().then((v) => ok = v);
      async.flushMicrotasks();
      expect(ok, isFalse);
      expect(autosave.writer.hasPending(autosave.keyOf('note-1')), isTrue);
      autosave.writer.resetForTest();
    });
  });

  test('discard drops the pending edit of a deleted note', () {
    fakeAsync((async) {
      build();
      autosave.schedule('note-1', 'gone');
      autosave.discard('note-1');
      async.elapse(const Duration(seconds: 5));
      expect(saves, isEmpty);
    });
  });
}
