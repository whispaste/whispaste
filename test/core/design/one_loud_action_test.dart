/// *The One-Loud-Action Rule*, armed for the list-panel family.
///
/// The rule (`lib/DESIGN.md`): **at most one `primary` variant in a screen's
/// main content area.** Everything else that can be pressed is `secondary` or
/// `ghost`. Two loud buttons on one screen is two answers to "what am I
/// supposed to do here", which is the same as none.
///
/// What this test does and does not look at:
///
/// * **Main content area, not the chrome.** Each page is pumped bare, without
///   `WpScreenshotShell` — the title bar, sidebar and status bar are not part
///   of the screen's answer to "what do I do here", and they carry no
///   `WpButton` of their own anyway.
/// * **The resting screen, not its dialogs.** A modal's submit button is
///   `primary` by construction (Snippets `:725`, Replacements `:534`) and is
///   the only thing on screen while the modal is up. No test here opens one.
/// * **Every state the content area can be in**, not just the populated one —
///   which is where the rule actually bites: four of the five states put a
///   CTA in the middle of an otherwise blank page, and the toolbar button
///   above it has to step back for exactly those. The loading skeleton is the
///   one state with no action at all and is therefore not covered.
///
/// The assertion is *exactly* one, not *at most* one. At-most-one passes
/// trivially on a screen with no loud action left, which is a different bug
/// with the same symptom (nothing to do here) — and every state below is
/// supposed to have one. A state that legitimately loses its loud action has
/// to come here and say so.
///
/// Ticket 13 brings the four list screens under the rule. Tickets 14 and 15
/// extend this file to the remaining pages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// A query no fixture in this file contains, in any field.
const _noMatch = 'zzqqxx-nothing-matches-this';

/// Asserts the screen currently on the tester paints exactly one loud action,
/// and that it is the one [expectedLabel] names.
void _expectOneLoudAction(
  WidgetTester tester, {
  required String state,
  required String expectedLabel,
}) {
  final loud = tester
      .widgetList<WpButton>(find.byType(WpButton))
      .where((b) => b.variant == WpButtonVariant.primary)
      .map((b) => b.label)
      .toList();

  expect(
    loud,
    [expectedLabel],
    reason:
        '*The One-Loud-Action Rule* — $state.\n'
        'Expected exactly one `primary` button, labelled "$expectedLabel"; '
        'found $loud.\n'
        'More than one: two buttons are shouting and the screen no longer '
        'reads as one task — demote the one the state is not pointing at '
        '(the toolbar button steps back while an empty state carries a CTA; '
        'see `emptyStateOwnsTheCta` in `lib/widgets/searchable_list_page.dart` '
        'and `createIsLoud` / `newRecordingIsLoud` on the two hand-built '
        'toolbars).\n'
        'None: the screen has nothing to do on it. That may be right, but it '
        'is a decision — make it here first.',
  );
}

/// Types [_noMatch] into the page's own search field.
///
/// The toolbar sits above the content area on all four screens and no list
/// page puts a second search field in front of it, so the first
/// [WpSearchField] in the tree is always the page's own.
Future<void> _searchForNothing(WidgetTester tester) async {
  final searchField = find.byType(WpSearchField).first;
  expect(
    searchField,
    findsOneWidget,
    reason: 'the page is supposed to have a search field in its toolbar',
  );
  await tester.enterText(
    find.descendant(of: searchField, matching: find.byType(TextField)),
    _noMatch,
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

List<Object> _historyOverrides({List<HistoryEntry>? entries}) => [
  historyEntriesProvider.overrideWith(
    (ref) => entries == null
        ? Stream<List<HistoryEntry>>.error(StateError('load failed'))
        : Stream.value(entries),
  ),
  archivedEntriesProvider.overrideWith(
    (ref) => Stream.value(const <HistoryEntry>[]),
  ),
  trashEntriesProvider.overrideWith(
    (ref) => Stream.value(const <HistoryEntry>[]),
  ),
];

List<HistoryEntry> _sampleActiveEntries() => generateSampleEntries()
    .where((e) => e.deletedAt == null && !e.archived)
    .toList();

/// The two tag providers are overridden alongside the note streams in every
/// notes test: left alone they fall through to real Drift `.watch()` queries
/// whose stream cleanup schedules a Timer on disposal, which flutter_test's
/// pending-timer check then trips.
List<Object> _notesOverrides({List<Note>? notes, List<Note> trash = const []}) =>
    [
      notesProvider.overrideWith(
        (ref) => notes == null
            ? Stream<List<Note>>.error(StateError('load failed'))
            : Stream.value(notes),
      ),
      trashNotesProvider.overrideWith((ref) => Stream.value(trash)),
      allNoteTagsProvider.overrideWith(
        (ref) => Stream.value(const <String, List<Tag>>{}),
      ),
      noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const <Tag>[])),
    ];

Note _note(String id, String content) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: false,
    isQuickNote: false,
    createdAt: t,
    updatedAt: t,
  );
}

/// Serves a fixed list — or fails — instead of reading the database, so the
/// empty and error states are reachable (the real notifier seeds sample rows
/// into an empty table and would never report an empty list).
class _FakeSnippets extends SnippetsNotifier {
  _FakeSnippets(this.items);

  final List<SnippetItem>? items;

  @override
  Future<List<SnippetItem>> build() async {
    final v = items;
    if (v == null) throw StateError('load failed');
    return v;
  }
}

class _FakeReplacements extends ReplacementsNotifier {
  _FakeReplacements(this.items);

  final List<Replacement>? items;

  @override
  Future<List<Replacement>> build() async {
    final v = items;
    if (v == null) throw StateError('load failed');
    return v;
  }
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  // -------------------------------------------------------------------------
  // Verlauf
  // -------------------------------------------------------------------------

  group('History', () {
    testWidgets('a populated list leaves "New recording" as the loud one', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _historyOverrides(entries: _sampleActiveEntries()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'History with entries',
        expectedLabel: l10n.historyNewRecording,
      );
    });

    testWidgets('an empty list keeps it loud — that empty state offers no CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _historyOverrides(entries: const []),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'History with nothing recorded yet',
        expectedLabel: l10n.historyNewRecording,
      );
    });

    testWidgets('a search that finds nothing hands the volume to "Clear '
        'search"', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _historyOverrides(entries: _sampleActiveEntries()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _searchForNothing(tester);

      _expectOneLoudAction(
        tester,
        state: 'History with a query that matched nothing',
        expectedLabel: l10n.actionClearSearch,
      );
    });

    testWidgets('a load error hands it to "Try again"', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: _historyOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'History after a failed load',
        expectedLabel: l10n.actionRetry,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Notizen
  // -------------------------------------------------------------------------

  group('Notes', () {
    testWidgets('a populated list leaves "New note" as the loud one', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: _notesOverrides(
            notes: [_note('n1', 'Grocery list'), _note('n2', 'Meeting notes')],
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'Notes with notes',
        expectedLabel: l10n.notesNewNote,
      );
    });

    testWidgets('the empty state owns the CTA — the toolbar button steps back', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: _notesOverrides(notes: const []),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Both carry the same label, so the count is what separates them: the
      // empty state's centred CTA is the one that stays `primary`.
      _expectOneLoudAction(
        tester,
        state: 'Notes with no notes yet',
        expectedLabel: l10n.notesNewNote,
      );
    });

    testWidgets('the trash keeps the toolbar button loud — its empty state '
        'offers nothing', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: _notesOverrides(notes: const [], trash: const []),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.notesTrash));
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'Notes trash, empty',
        expectedLabel: l10n.notesNewNote,
      );
    });

    testWidgets('a search that finds nothing hands the volume to "Clear '
        'search"', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: _notesOverrides(notes: [_note('n1', 'Grocery list')]),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _searchForNothing(tester);

      _expectOneLoudAction(
        tester,
        state: 'Notes with a query that matched nothing',
        expectedLabel: l10n.actionClearSearch,
      );
    });

    testWidgets('a load error hands it to "Try again"', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: _notesOverrides(),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'Notes after a failed load',
        expectedLabel: l10n.actionRetry,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Snippets & Ersetzungen — both are `WpSearchableListPage`, and the rule is
  // enforced in one place for both. Covered twice anyway: the shared widget is
  // where the demotion lives, but the pages are what the ticket signs off.
  // -------------------------------------------------------------------------

  group('Snippets', () {
    Future<void> pump(WidgetTester tester, List<SnippetItem>? items) async {
      await tester.pumpWidget(
        makeTestable(
          const SnippetsPage(),
          overrides: [snippetsProvider.overrideWith(() => _FakeSnippets(items))],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    const items = [
      SnippetItem(id: 's1', title: 'Signature', body: 'Kind regards'),
    ];

    testWidgets('a populated list leaves "Add" as the loud one', (tester) async {
      await pump(tester, items);

      _expectOneLoudAction(
        tester,
        state: 'Snippets with snippets',
        expectedLabel: l10n.snippetsAdd,
      );
    });

    testWidgets('the empty state owns the CTA', (tester) async {
      await pump(tester, const []);

      _expectOneLoudAction(
        tester,
        state: 'Snippets with none saved yet',
        expectedLabel: l10n.snippetsAdd,
      );
    });

    testWidgets('a search that finds nothing hands the volume to "Clear '
        'search"', (tester) async {
      await pump(tester, items);
      await _searchForNothing(tester);

      _expectOneLoudAction(
        tester,
        state: 'Snippets with a query that matched nothing',
        expectedLabel: l10n.actionClearSearch,
      );
    });

    testWidgets('a load error hands it to "Try again"', (tester) async {
      await pump(tester, null);

      _expectOneLoudAction(
        tester,
        state: 'Snippets after a failed load',
        expectedLabel: l10n.actionRetry,
      );
    });
  });

  group('Replacements', () {
    Future<void> pump(WidgetTester tester, List<Replacement>? items) async {
      await tester.pumpWidget(
        makeTestable(
          const ReplacementsPage(),
          overrides: [
            replacementsProvider.overrideWith(() => _FakeReplacements(items)),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    const items = [
      Replacement(id: 'r1', triggers: ['btw'], replacement: 'by the way'),
    ];

    testWidgets('a populated list leaves "Add" as the loud one', (tester) async {
      await pump(tester, items);

      _expectOneLoudAction(
        tester,
        state: 'Replacements with replacements',
        expectedLabel: l10n.replacementsAdd,
      );
    });

    testWidgets('the empty state owns the CTA', (tester) async {
      await pump(tester, const []);

      _expectOneLoudAction(
        tester,
        state: 'Replacements with none saved yet',
        expectedLabel: l10n.replacementsAdd,
      );
    });

    testWidgets('a search that finds nothing hands the volume to "Clear '
        'search"', (tester) async {
      await pump(tester, items);
      await _searchForNothing(tester);

      _expectOneLoudAction(
        tester,
        state: 'Replacements with a query that matched nothing',
        expectedLabel: l10n.actionClearSearch,
      );
    });

    testWidgets('a load error hands it to "Try again"', (tester) async {
      await pump(tester, null);

      _expectOneLoudAction(
        tester,
        state: 'Replacements after a failed load',
        expectedLabel: l10n.actionRetry,
      );
    });
  });
}
