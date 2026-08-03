/// Widget tests for the note-editor "Export" button wiring (Ticket 07).
///
/// The button resolves through `NotesPage.exportFn`, an injection seam that
/// defaults to the production top-level `notes_exporter.exportNote`. The
/// tests substitute a fake that captures the call so we can assert the open
/// note and its tags reach the exporter, without touching the filesystem or
/// platform channels. Vorbild `history_export_wiring_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

List<Object> get _noTagOverrides => [
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Note _sampleNote({required String id, required String content}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

// ─── Fake exporter that captures invocations ──────────────────────────────

class _ExportCall {
  _ExportCall(this.note, this.tags);
  final Note note;
  final List<Tag> tags;
}

class _FakeExporter {
  final List<_ExportCall> calls = [];

  Future<void> call(BuildContext context, Note note, List<Tag> tags) async {
    calls.add(_ExportCall(note, tags));
  }
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'toolbar Export button invokes exportFn with the open note and its tags',
    (tester) async {
      final tag = Tag(id: 't1', name: 'work', createdAt: DateTime(2025, 6, 1));
      final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];
      final fake = _FakeExporter();

      await tester.pumpWidget(
        makeTestable(
          NotesPage(exportFn: fake.call),
          // Extra-wide viewport so the split view has room for the editor.
          size: const Size(1800, 900),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            allNoteTagsProvider.overrideWith(
              (ref) => Stream.value({
                'n1': [tag],
              }),
            ),
            noteTagsProvider.overrideWith(
              (ref, noteId) => Stream.value(noteId == 'n1' ? [tag] : const []),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grocery list'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.download));
      await tester.pumpAndSettle();

      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.note.id, 'n1');
      expect(fake.calls.single.tags.map((t) => t.name), ['work']);
    },
  );

  testWidgets('Export button is not shown when no note is open', (
    tester,
  ) async {
    final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];
    final fake = _FakeExporter();

    await tester.pumpWidget(
      makeTestable(
        NotesPage(exportFn: fake.call),
        overrides: [
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          ..._noTagOverrides,
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.download), findsNothing);
  });
}
