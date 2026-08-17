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
/// Ticket 13 brings the four list screens under the rule. Tickets 15 and 14
/// extend this file to the remaining pages — the narrative family and then
/// the form family, each as a block at the bottom rather than as a change to
/// the four groups above or to the shared helper.
///
/// **Ticket 15 (the narrative family) is the extension at the bottom of this
/// file.** It reads differently from the four groups above, because the three
/// screens do:
///
///  * **About** has *zero* loud actions, by a decision documented at its call
///    sites — so it asserts zero explicitly with the reason, rather than
///    relaxing the shared helper to at-most-one and weakening it for the list
///    screens.
///  * **Onboarding** is checked at source level here (no step body may build a
///    `WpHeroButton`) and page by page in
///    `test/features/onboarding/onboarding_overlay_test.dart`, which owns the
///    fixtures the seven-page walk needs. The source half is the one that pins
///    the two CTAs Ticket 15 demoted.
///  * **Recording** — the 3-px bar above the content panel is the main
///    window's whole recording surface, and it carries no action at all.
///
/// **Ticket 14 (the form family) is the block after it** — Settings, Feedback
/// and Analytics. Two of the three turn out to be zero-form screens in their
/// populated state for the same reason About is, and the group's own header
/// comment says why; Feedback is the one true form here, and its thank-you
/// state is the one place this ticket changed a variant rather than recording
/// one.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';
import 'package:whispaste/features/feedback/feedback_page.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/about/about_page.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'package:whispaste/features/settings/settings_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/feedback_submission_service.dart';
import 'package:whispaste/widgets/recording_indicator_bar.dart';
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
List<Object> _notesOverrides({
  List<Note>? notes,
  List<Note> trash = const [],
}) => [
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

    testWidgets(
      'an empty list keeps it loud — that empty state offers no CTA',
      (tester) async {
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
      },
    );

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

    testWidgets(
      'the empty state owns the CTA — the toolbar button steps back',
      (tester) async {
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
      },
    );

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
          overrides: [
            snippetsProvider.overrideWith(() => _FakeSnippets(items)),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    const items = [
      SnippetItem(id: 's1', title: 'Signature', body: 'Kind regards'),
    ];

    testWidgets('a populated list leaves "Add" as the loud one', (
      tester,
    ) async {
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

    testWidgets('a populated list leaves "Add" as the loud one', (
      tester,
    ) async {
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

  // -------------------------------------------------------------------------
  // Ticket 15 — the narrative family (Onboarding · Über · Aufnahme)
  // -------------------------------------------------------------------------

  group('About', () {
    testWidgets('is deliberately quiet — no loud action at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const AboutPage(), locale: const Locale('en')),
      );
      await tester.pump();

      final loud = tester
          .widgetList<WpButton>(find.byType(WpButton))
          .where((b) => b.variant == WpButtonVariant.primary)
          .map((b) => b.label)
          .toList();

      expect(
        loud,
        isEmpty,
        reason:
            'The zero form of the rule, and a decision rather than an '
            'oversight — which is why it is spelled out here instead of '
            'quietly relaxing `_expectOneLoudAction` to at-most-one for '
            'everybody. About is a page you read: its quick actions are '
            'wayfinding and its support row is an ask, so both stay '
            '`secondary` and the hierarchy is carried by tone (neutral vs. '
            'accent) rather than by fill. Found $loud. Adding a `primary` here '
            'means deciding which single thing the page tells you to do — say '
            'so here first.',
      );
    });
  });

  group('Onboarding', () {
    // The seven-page walk lives in `onboarding_overlay_test.dart`, which owns
    // the fixtures it needs. What belongs here is the half a widget test
    // cannot reach non-vacuously: under the default fixtures most pages never
    // render their CTA at all, so a page-by-page count would wave through a
    // hero re-appearing in a state the walk does not visit.
    //
    // `WpHeroButton` is one step *above* the variant ladder — the flow's
    // signature CTA, and the flow spends it exactly once, on the shell's
    // Next/completion button. Before Ticket 15 two step bodies built one each
    // (the Auto-Paste grant CTA and the model download CTA), wearing the
    // identical `accentWarmGradient` a few pixels from the shell's own.
    const heroOwner = 'lib/features/onboarding/onboarding_overlay.dart';

    test('only the shell builds a hero — no step body does', () {
      final dir = Directory('lib/features/onboarding');
      expect(dir.existsSync(), isTrue, reason: 'the flow must exist');

      final lineComment = RegExp(r'//.*$', multiLine: true);
      final heroReference = RegExp(r'\bWpHeroButton\s*\(');

      final files = [
        for (final entity in dir.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart'))
            entity.path.replaceAll(r'\', '/'),
      ];
      expect(
        files.length,
        greaterThan(5),
        reason:
            'the sweep found only ${files.length} files under the flow — an '
            'empty offender list below would pass vacuously',
      );

      final offenders = <String>[];
      for (final relPath in files) {
        if (relPath == heroOwner) continue;
        final source = File(
          relPath,
        ).readAsStringSync().replaceAll(lineComment, '');
        if (heroReference.hasMatch(source)) offenders.add(relPath);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These onboarding files build a WpHeroButton of their own: '
            '${offenders.join(', ')}. The hero belongs to the shell\'s '
            'navigation row alone ($heroOwner) — a second one on the same '
            'page makes the page\'s own action outshout the one that ends the '
            'flow. Use `WpButton(variant: WpButtonVariant.primary)` for a '
            'page\'s own action.',
      );
    });

    test('the shell still builds the one hero it is allowed', () {
      // Anti-vacuum guard, mirroring `one_atmosphere_test.dart`: the sweep
      // above passes just as happily on a flow that has no hero at all.
      final source = File(heroOwner).readAsStringSync();
      expect(
        RegExp(r'\bWpHeroButton\s*\(').hasMatch(source),
        isTrue,
        reason:
            'The shell no longer builds a WpHeroButton, so the exemption above '
            'guards nothing. Either the flow lost its signature CTA or the '
            'hero moved — update this file rather than leaving it green.',
      );
    });
  });

  group('Recording', () {
    testWidgets('the main window\'s recording surface carries no action', (
      tester,
    ) async {
      // The 3-px bar above the content panel is the whole surface: the
      // in-window FAB is gone (`test/widgets/no_fab_regression_test.dart`)
      // and the floating overlay is a separate window. A signal, not a
      // control — so the rule is satisfied with nothing to demote, and this
      // records that as the finding it is rather than a gap in the sweep.
      await tester.pumpWidget(
        makeTestable(
          const WpRecordingIndicatorBar(phase: RecordingPhase.recording),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(WpButton), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Ticket 14 — the form family
  // ---------------------------------------------------------------------------
  //
  // Settings, Feedback and Analytics. The rule reads differently on a form
  // than on a list, and the difference is worth stating once here rather than
  // in each group below.
  //
  // A list screen always has one thing to do (add an item), so its states only
  // argue about *which* button carries the volume. A form has one thing to do
  // only while it is unfinished — and two of these three screens are not forms
  // at all. Settings is sixteen independent controls; Analytics is a page of
  // numbers. Neither has a single next step to point at, so both spend the
  // zero form of the rule in their populated state, the way About does, and
  // both get a loud action back the moment an empty state puts a CTA in the
  // middle of a blank page. That asymmetry is the finding, not a gap: it is
  // why these tests assert zero explicitly instead of leaving the states out.

  /// The labels of every loud button currently on screen.
  List<String> loudActionLabels(WidgetTester tester) => tester
      .widgetList<WpButton>(find.byType(WpButton))
      .where((b) => b.variant == WpButtonVariant.primary)
      .map((b) => b.label)
      .toList();

  group('Settings', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
    }

    testWidgets('the page of controls is deliberately quiet', (tester) async {
      await pump(tester);

      // Non-vacuity: an empty loud list also describes a page that failed to
      // build at all.
      expect(find.text(l10n.settingsInterface), findsOneWidget);

      expect(
        loudActionLabels(tester),
        isEmpty,
        reason:
            'The zero form of the rule, and a decision — spelled out here '
            'rather than by relaxing `_expectOneLoudAction` for everybody. '
            'Settings is sixteen sections of independent controls, and a loud '
            'button on it would have to answer "what am I supposed to do '
            'here" for a page whose whole point is that the reader already '
            'knows: they came for one switch. Every control is its own action '
            'and none of them outranks the others. Found '
            '${loudActionLabels(tester)}.',
      );
    });

    testWidgets('a search that finds nothing hands the volume to "Clear '
        'search"', (tester) async {
      final container = await pump(tester);
      // Through the provider, not the field: `SettingsSearchField` debounces,
      // and the debounce is not what this test is about (see
      // `settings_live_filter_test.dart`, which owns that path).
      container.read(settingsSearchQueryProvider.notifier).set(_noMatch);
      await tester.pumpAndSettle();

      _expectOneLoudAction(
        tester,
        state: 'Settings with a query that matched no section',
        expectedLabel: l10n.actionClearSearch,
      );
    });
  });

  group('Feedback', () {
    /// Drives the form to the thank-you state on the platform [isWindows]
    /// describes.
    Future<void> pumpAndSubmit(
      WidgetTester tester, {
      required bool isWindows,
    }) async {
      SharedPreferences.setMockInitialValues({});
      feedbackPlatformIsWindowsOverride = isWindows;
      addTearDown(() => feedbackPlatformIsWindowsOverride = null);

      await tester.pumpWidget(
        makeTestable(
          FeedbackPage(
            submissionService: FeedbackSubmissionService(
              client: MockClient((_) async => http.Response('', 201)),
              supabaseUrl: 'https://example.supabase.co',
              supabasePublishableKey: 'test-key',
              breadcrumbSink: (_) {},
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.feedbackCategoryGeneral));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🤩'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('feedbackCommentField')),
        'Test feedback',
      );
      await tester.pumpAndSettle();

      final submit = find.widgetWithText(WpButton, l10n.feedbackSubmit);
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
    }

    testWidgets('the unsent form points at "Send feedback"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        makeTestable(const FeedbackPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Disabled until all three inputs are filled, and still the loud one:
      // the rule counts what the screen *points at*, and a greyed-out submit
      // is what the form is for even before it can be pressed.
      _expectOneLoudAction(
        tester,
        state: 'Feedback with the form still empty',
        expectedLabel: l10n.feedbackSubmit,
      );
    });

    testWidgets('the thank-you state asks Windows readers for a store rating', (
      tester,
    ) async {
      await pumpAndSubmit(tester, isWindows: true);

      expect(find.text(l10n.feedbackThankYou), findsOneWidget);
      _expectOneLoudAction(
        tester,
        state: 'Feedback after sending, on Windows',
        expectedLabel: l10n.reviewPromptRateStore,
      );
    });

    testWidgets('and everyone else for a GitHub star', (tester) async {
      await pumpAndSubmit(tester, isWindows: false);

      expect(find.text(l10n.feedbackThankYou), findsOneWidget);
      // The half this ticket changed. macOS and Linux have no store listing,
      // so the store CTA is absent — and while GitHub stayed `secondary` on
      // those platforms, the same screen handed a Windows reader one obvious
      // next step and everyone else none, decided by a platform branch rather
      // than by anything about the page. One loud action per state means per
      // state, not per platform.
      _expectOneLoudAction(
        tester,
        state: 'Feedback after sending, on macOS/Linux',
        expectedLabel: l10n.reviewPromptStarGitHub,
      );
    });
  });

  group('Analytics', () {
    Future<void> pump(WidgetTester tester, Object override) async {
      await tester.pumpWidget(
        makeTestable(
          const AnalyticsPage(),
          overrides: [override],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
    }

    const data = AnalyticsData(
      totalRecordings: 42,
      totalDurationMinutes: 120,
      totalWords: 5000,
      timeSavedMinutes: 80,
      weeklyActivity: [1, 2, 3, 4, 5, 6, 7],
      modelUsage: <AnalyticsModelUsage>[],
      durationBuckets: [5, 3, 2, 1, 0],
      localSavingsUsd: 2.5,
      cloudCostUsd: 0.75,
    );

    testWidgets('a dashboard full of numbers is quiet', (tester) async {
      await pump(tester, analyticsProvider.overrideWith((ref) async => data));

      // Non-vacuity, as above.
      expect(find.text(l10n.analyticsOverview), findsOneWidget);

      expect(
        loudActionLabels(tester),
        isEmpty,
        reason:
            'The zero form again, for the same reason About and Settings '
            'spend it: this page is read, not acted on. Its one control is '
            '"Reset statistics", which is destructive — the last button on '
            'the app that should be the one the page points at, and it is '
            '`secondary` with the `danger` tone for exactly that reason. '
            'Found ${loudActionLabels(tester)}.',
      );
    });

    testWidgets('so is the empty state — there is nothing to press', (
      tester,
    ) async {
      await pump(
        tester,
        analyticsProvider.overrideWith((ref) async => AnalyticsData.empty),
      );

      // Non-vacuity, as above.
      expect(find.text(l10n.analyticsEmptyTitle), findsOneWidget);

      expect(
        loudActionLabels(tester),
        isEmpty,
        reason:
            'The one empty state in the app that deliberately carries no CTA, '
            'and the exception that proves the list screens\' rule: their '
            'empty states offer "Add" because adding is what fills them. '
            'Statistics fill themselves, by dictating — which happens on a '
            'hotkey, in another app, and a button here could only send the '
            'reader somewhere that is not the answer. Found '
            '${loudActionLabels(tester)}.',
      );
    });

    testWidgets('a load error hands it to "Try again"', (tester) async {
      await pump(
        tester,
        // An `Error` subclass rather than an `Exception`: Riverpod retries the
        // latter and would leave the page in `AsyncLoading` forever (see
        // `analytics_page_test.dart`).
        analyticsProvider.overrideWith(
          (ref) => Future<AnalyticsData>.error(
            StateError('test error'),
            StackTrace.empty,
          ),
        ),
      );

      _expectOneLoudAction(
        tester,
        state: 'Analytics after a failed load',
        expectedLabel: l10n.actionRetry,
      );
    });
  });
}
