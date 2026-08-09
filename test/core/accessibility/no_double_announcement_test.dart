/// Regression guard for a defect class that had spread across the app: a
/// `Semantics(label: X)` wrapped around a subtree that *also* renders
/// `Text(X)`.
///
/// The framework does not treat such a label as a replacement for the
/// subtree's text — it is prepended to it. Every control built that way was
/// therefore announced twice ("Kopieren, Kopieren"), and the pattern had
/// reached the snippet picker, the export picker, the tag input, the status
/// bar, the hero button, the segmented selector and every settings row.
///
/// The house fix has two shapes, one per situation, and both are asserted
/// here so neither can silently regress:
///
///  * composed control, one tap target → `MergeSemantics` + a *label-less*
///    `Semantics`, so the name folds in from the rendered text while the
///    button role and the tap action survive the fold;
///  * settings row, arbitrary trailing control → no wrapper label at all and
///    deliberately no `MergeSemantics`, because merging would swallow a text
///    field or a slider into the row.
///
/// The list rows of the three sibling screens (Notizen / Snippets /
/// Ersetzungen) fall under the second shape for the same structural reason —
/// each carries a second tap target (delete, favourite) that merging would
/// swallow — and are asserted in their own group below.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

/// How often [needle] occurs in [haystack] — the whole question these row
/// tests ask.
int _occurrences(String haystack, String needle) =>
    needle.allMatches(haystack).length;

/// Snippets seeded without touching SQLite.
class _OneSnippet extends SnippetsNotifier {
  @override
  Future<List<SnippetItem>> build() async => const [
    SnippetItem(id: 's1', title: 'Mein Snippet', body: 'Body-Zeile'),
  ];
}

void main() {
  group('no double announcement', () {
    testWidgets('WpHeroButton announces its caption exactly once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: WpHeroButton(
                label: 'Weiter',
                onPressed: () {},
                gradient: const LinearGradient(
                  colors: [Colors.teal, Colors.cyan],
                ),
              ),
            ),
          ),
        );

        // "Weiter" once — not "Weiter\nWeiter" — and the fold must not cost
        // the button its role or its tap action.
        expect(
          tester.getSemantics(find.byType(WpHeroButton)),
          matchesSemantics(
            label: 'Weiter',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('SettingRow names itself once and keeps its toggle separate', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: SettingRow(
                icon: LucideIcons.bell,
                label: 'Benachrichtigungen',
                subtitle: 'Beim Abschluss einer Aufnahme',
                semanticToggledValue: true,
                trailing: settingsToggle(value: true, onChanged: (_) {}),
              ),
            ),
          ),
        );

        // The row node carries label and subtitle exactly once each. Before
        // the fix this read "Benachrichtigungen, Benachrichtigungen, Beim
        // Abschluss einer Aufnahme" and then repeated the subtitle a third
        // time as the node's hint.
        expect(
          tester.getSemantics(find.byType(SettingRow)),
          matchesSemantics(
            label: 'Benachrichtigungen',
            hint: 'Beim Abschluss einer Aufnahme',
            hasToggledState: true,
            isToggled: true,
          ),
        );

        // …and the Switch stays its own operable node rather than being
        // folded into the row. This is why SettingRow is pointedly *not*
        // wrapped in MergeSemantics like the single-target controls above.
        expect(
          tester.getSemantics(find.byType(Switch)),
          matchesSemantics(
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    });
  });

  // The three sibling list screens (Notizen / Snippets / Ersetzungen) each
  // had the same defect in their row: a wrapper label repeating a string the
  // row already renders. Because their rows carry a *conditionally mounted*
  // second tap target (the delete action appears on hover/focus; the notes
  // star is there permanently), `MergeSemantics` is not available to them —
  // it would swallow that second node. So all three take the other shape:
  // the rendered text names the row, and only the extra information
  // (the "opens an edit dialog" affordance) stays on the wrapper, as a hint.
  group('sibling list rows announce their identity once', () {
    testWidgets('NotesListTile', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            NotesListTile(
              note: Note(
                id: 'n1',
                content: 'Mein Titel\nZweite Zeile',
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
                pinned: false,
              ),
              tags: const [],
              isDark: true,
              isTrashView: false,
              isSelected: true,
              isFocused: true,
              onTap: () {},
              onFavoriteToggle: () {},
              onRestore: () {},
              onDeleteForever: () {},
            ),
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        final node = tester.getSemantics(find.byType(NotesListTile));
        expect(
          _occurrences(node.label, 'Mein Titel'),
          1,
          reason: 'was announced twice — label plus the rendered title',
        );
        // The row still says what it is and where the list cursor stands…
        expect(node, isSemantics(isButton: true, isSelected: true));
        // …and the favourite star survives as its own operable node, which
        // is exactly what MergeSemantics would have cost here.
        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(find.bySemanticsLabel(l10n.notesFavorite), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('snippet row', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            const SnippetsPage(),
            locale: const Locale('en'),
            overrides: [snippetsProvider.overrideWith(_OneSnippet.new)],
          ),
        );
        await tester.pumpAndSettle();

        // getSemantics on the rendered title resolves to the row's merged
        // node — the one a screen reader actually reads out.
        final node = tester.getSemantics(find.text('Mein Snippet'));
        expect(_occurrences(node.label, 'Mein Snippet'), 1);
        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(
          node.hint,
          l10n.snippetsEditSnippet,
          reason: 'the affordance moved from the label into the hint',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('replacement row', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(const ReplacementsPage(), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // 'mfg' is one of the three sample replacements seeded on an empty DB.
        final node = tester.getSemantics(find.text('mfg'));
        expect(_occurrences(node.label, 'mfg'), 1);
        final l10n = await L10n.delegate.load(const Locale('en'));
        expect(node.hint, l10n.replacementsEditShortcut);
      } finally {
        handle.dispose();
      }
    });
  });
}
