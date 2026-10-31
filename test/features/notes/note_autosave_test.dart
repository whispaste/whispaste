/// Unit tests for [NoteAutosave] — pure-Dart debounce, driven via `fakeAsync`
/// so no real time passes during the test run.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_autosave.dart';

void main() {
  group('schedule', () {
    test('saves after the debounce window elapses', () {
      fakeAsync((async) {
        final saves = <(String, String)>[];
        final autosave = NoteAutosave(
          onSave: (id, content) async {
            saves.add((id, content));
          },
        );

        autosave.schedule('note-1', 'hello');
        async.elapse(const Duration(milliseconds: 399));
        expect(saves, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        expect(saves, [('note-1', 'hello')]);
      });
    });

    test('rapid keystrokes only save the last content once', () {
      fakeAsync((async) {
        final saves = <(String, String)>[];
        final autosave = NoteAutosave(
          onSave: (id, content) async {
            saves.add((id, content));
          },
        );

        autosave.schedule('note-1', 'h');
        async.elapse(const Duration(milliseconds: 100));
        autosave.schedule('note-1', 'he');
        async.elapse(const Duration(milliseconds: 100));
        autosave.schedule('note-1', 'hel');
        async.elapse(const Duration(milliseconds: 400));

        expect(saves, [('note-1', 'hel')]);
      });
    });
  });

  group('flush', () {
    test('saves immediately and cancels the pending timer', () {
      fakeAsync((async) {
        final saves = <(String, String)>[];
        final autosave = NoteAutosave(
          onSave: (id, content) async {
            saves.add((id, content));
          },
        );

        autosave.schedule('note-1', 'draft');
        async.flushMicrotasks();
        autosave.flush();
        async.flushMicrotasks();

        expect(saves, [('note-1', 'draft')]);

        // The debounce timer was cancelled by flush — elapsing past its
        // window must not save again.
        async.elapse(const Duration(milliseconds: 500));
        expect(saves, [('note-1', 'draft')]);
      });
    });

    test('is a no-op when nothing is pending', () {
      fakeAsync((async) {
        final saves = <(String, String)>[];
        final autosave = NoteAutosave(
          onSave: (id, content) async {
            saves.add((id, content));
          },
        );

        autosave.flush();
        async.flushMicrotasks();

        expect(saves, isEmpty);
      });
    });
  });

  group('dispose', () {
    test('cancels a pending timer without saving', () {
      fakeAsync((async) {
        final saves = <(String, String)>[];
        final autosave = NoteAutosave(
          onSave: (id, content) async {
            saves.add((id, content));
          },
        );

        autosave.schedule('note-1', 'unsaved');
        autosave.dispose();
        async.elapse(const Duration(milliseconds: 500));

        expect(saves, isEmpty);
      });
    });
  });
}
