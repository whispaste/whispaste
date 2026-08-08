/// Tests for [WpSplitView] — the master/detail layout history and notes now
/// share (Ticket 08).
///
/// The point of the shared widget is that both areas *transition the same
/// way*: before the extraction the history detail cross-faded between entries
/// while the notes editor cut hard. These tests pin the cross-fade in the
/// generic widget and then assert it actually reaches both callers, plus the
/// "Reduce Motion" clause that pulls its duration to zero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_split_view.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/features/notes/widgets/notes_split_view.dart';
import 'package:whispaste/widgets/wp_split_view.dart';

import '../fixtures/test_helpers.dart';

/// Wide enough that the split view stays side-by-side (the compact fallback
/// and the too-narrow fallback both render a full-screen detail instead).
const _wide = Size(1280, 800);

HistoryEntry _entry(String id) => HistoryEntry(
  id: id,
  content: 'Inhalt von $id',
  title: 'Eintrag $id',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
);

Note _note(String id) => Note(
  id: id,
  content: 'Notiz $id\nZweite Zeile von $id',
  createdAt: DateTime(2026, 4, 14, 10, 30),
  updatedAt: DateTime(2026, 4, 14, 10, 30),
  pinned: false,
  deletedAt: null,
);

/// Rebuilds [builder] with whatever the last call to `setSelection` passed —
/// the split views take their selection from above, so a switch has to come
/// from a parent rebuild rather than from inside.
class _Host<T> extends StatefulWidget {
  const _Host({super.key, required this.initial, required this.builder});

  final T initial;
  final Widget Function(T selected) builder;

  @override
  State<_Host<T>> createState() => _HostState<T>();
}

class _HostState<T> extends State<_Host<T>> {
  late T _selected = widget.initial;

  void select(T value) => setState(() => _selected = value);

  @override
  Widget build(BuildContext context) => widget.builder(_selected);
}

void main() {
  group('WpSplitView', () {
    testWidgets('cross-fades between two selections', (tester) async {
      final key = GlobalKey<_HostState<String>>();
      await tester.pumpWidget(
        makeTestable(
          _Host<String>(
            key: key,
            initial: 'a',
            builder: (selected) => WpSplitView<String>(
              isDark: true,
              selectedItem: selected,
              idOf: (id) => id,
              listBuilder: (_, _) => const SizedBox.expand(),
              detailBuilder: (_, id) => Text('detail-$id'),
            ),
          ),
          size: _wide,
        ),
      );
      expect(find.text('detail-a'), findsOneWidget);

      key.currentState!.select('b');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // Mid-transition both details are mounted, each under a FadeTransition.
      expect(find.text('detail-a'), findsOneWidget);
      expect(find.text('detail-b'), findsOneWidget);
      expect(find.byType(FadeTransition), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.text('detail-a'), findsNothing);
      expect(find.text('detail-b'), findsOneWidget);
    });

    testWidgets('"Reduce Motion" collapses the cross-fade to nothing', (
      tester,
    ) async {
      final key = GlobalKey<_HostState<String>>();
      await tester.pumpWidget(
        makeTestable(
          MediaQuery(
            data: const MediaQueryData(size: _wide, disableAnimations: true),
            child: _Host<String>(
              key: key,
              initial: 'a',
              builder: (selected) => WpSplitView<String>(
                isDark: true,
                selectedItem: selected,
                idOf: (id) => id,
                listBuilder: (_, _) => const SizedBox.expand(),
                detailBuilder: (_, id) => Text('detail-$id'),
              ),
            ),
          ),
          size: _wide,
        ),
      );

      key.currentState!.select('b');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // No overlap at all — the outgoing detail is gone on the very next frame.
      expect(find.text('detail-a'), findsNothing);
      expect(find.text('detail-b'), findsOneWidget);
    });

    testWidgets('an in-place update of the same item does not re-fade', (
      tester,
    ) async {
      final key = GlobalKey<_HostState<String>>();
      await tester.pumpWidget(
        makeTestable(
          _Host<String>(
            key: key,
            initial: 'a',
            builder: (selected) => WpSplitView<String>(
              isDark: true,
              selectedItem: selected,
              // Identity is the first character, so 'a' and 'a2' are the same
              // item with changed content — a stream emit, not a switch.
              idOf: (id) => id.substring(0, 1),
              listBuilder: (_, _) => const SizedBox.expand(),
              detailBuilder: (_, id) => Text('detail-$id'),
            ),
          ),
          size: _wide,
        ),
      );

      key.currentState!.select('a2');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('detail-a'), findsNothing);
      expect(find.text('detail-a2'), findsOneWidget);
    });
  });

  group('cross-fade reaches both areas', () {
    testWidgets('history fades between entries', (tester) async {
      final key = GlobalKey<_HostState<HistoryEntry>>();
      await tester.pumpWidget(
        makeTestable(
          _Host<HistoryEntry>(
            key: key,
            initial: _entry('a'),
            builder: (selected) => HistorySplitView(
              groups: [
                DateGroup(
                  labelKey: 'today',
                  entries: [_entry('a'), _entry('b')],
                ),
              ],
              isDark: true,
              viewMode: HistoryViewMode.list,
              selectedEntry: selected,
              onEntryTap: (_) {},
              onCopy: (_) {},
              onPin: (_) {},
              onDelete: (_) {},
              onArchive: (_) {},
              onRestore: (_) {},
              onCloseDetail: () {},
              multiSelectMode: false,
              selectedIds: const {},
              isTrashView: false,
              isArchiveView: false,
            ),
          ),
          size: _wide,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HistoryDetailPanel), findsOneWidget);

      key.currentState!.select(_entry('b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(HistoryDetailPanel), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(find.byType(HistoryDetailPanel), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Drain the pending Drift / Riverpod cleanup timers before teardown,
      // otherwise the framework's `!timersPending` invariant fires from the
      // in-memory DB's `StreamQueryStore.markAsClosed`.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('notes fade between notes — with the page-owned controller '
        'and focus node shared by both panels', (tester) async {
      final controller = TextEditingController(text: 'Notiz a');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      final key = GlobalKey<_HostState<Note>>();
      await tester.pumpWidget(
        makeTestable(
          _Host<Note>(
            key: key,
            initial: _note('a'),
            builder: (selected) => NotesSplitView(
              notes: [_note('a'), _note('b')],
              tagsByNoteId: const {},
              isDark: true,
              isTrashView: false,
              selectedNote: selected,
              focusedNoteId: null,
              selectedNoteTags: const [],
              editorController: controller,
              editorFocusNode: focusNode,
              onNoteTap: (_) {},
              onCloseEditor: () {},
              onFavoriteToggle: (_) {},
              onMoveToTrash: (_) {},
              onRestore: (_) {},
              onDeleteForever: (_) {},
              onAddTag: (_) {},
              onRemoveTag: (_) {},
              onExport: () {},
              onVoiceTranscript: (_) {},
            ),
          ),
          size: _wide,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPanel), findsOneWidget);

      // Focused editor + text in the controller: the state that makes the
      // double-mount during the fade risky.
      focusNode.requestFocus();
      await tester.pump();

      key.currentState!.select(_note('b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(NoteEditorPanel), findsNWidgets(2));
      expect(find.byType(FadeTransition), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorPanel), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
