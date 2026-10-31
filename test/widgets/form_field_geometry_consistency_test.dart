/// Cross-area geometry guard for [WpTextField]'s form-value variants.
///
/// Sister to `search_field_geometry_consistency_test.dart`, for the other
/// half of the family. Before this, the app's plain text inputs carried five
/// different geometries: Settings' API key at a forced 34 dp with a 12/8
/// inset, Settings' generic field at 12/8, the custom-vocabulary box at
/// 12/12, the Snippets/Replacements dialog fields at 16/12, and the two
/// feedback fields borderless-at-16 inside a warm-gradient box of their own.
/// A user who opened Settings and then a dialog saw two different controls
/// for the same job.
///
/// The assertions come in two kinds, and both are deliberate:
///
///  * **Equalities between call sites** — the same shape this family has
///    actually drifted in. A future change to the variant's inset moves all
///    of them together and keeps these green.
///  * **A few pinned numbers**, because two of them are load-bearing rather
///    than arbitrary: the 48 dp resting height is `WpLayout.minTouchTarget`
///    *and* [WpSearchField]'s height, and the fact that it comes from padding
///    rather than from a `SizedBox` is what stops an accessibility text size
///    from clipping the line — which is exactly what the old 34 dp API-key
///    field did (its text overflowed its box by 0.3 dp at 1.5x).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/history/widgets/history_notes_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

/// What "does this field look like the others" actually depends on. Width and
/// the trailing inset are absent on purpose: width is the caller's (240 dp in
/// Settings, the dialog's own width in a dialog), and the trailing inset is
/// 48 dp wider wherever a field carries a reveal button.
typedef _FieldGeometry = ({
  double boxHeight,
  double textLeftInset,
  double textTopInset,
  double textBottomInset,
});

Rect _rect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Measures the field inside [of] against the box that draws its contour —
/// the field's own for [WpTextFieldVariant.form], the host's for
/// [WpTextFieldVariant.embedded], which is the box the user actually sees.
_FieldGeometry _measure(WidgetTester tester, {required Finder box}) {
  final outer = _rect(tester, box);
  final text = _rect(
    tester,
    find.descendant(of: box, matching: find.byType(EditableText)),
  );
  return (
    boxHeight: outer.height,
    textLeftInset: text.left - outer.left,
    textTopInset: text.top - outer.top,
    textBottomInset: outer.bottom - text.bottom,
  );
}

Finder _fieldBox() => find
    .descendant(
      of: find.byType(WpTextField),
      matching: find.byType(AnimatedContainer),
    )
    .first;

Widget _scaled(Widget child, double scale) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

void main() {
  // ---------------------------------------------------------------------
  // form — the standalone field
  // ---------------------------------------------------------------------

  for (final scale in const [1.0, 1.5]) {
    final at = scale == 1.0 ? 'normal text size' : 'accessibility text size';

    testWidgets('every single-line form field renders identically at $at', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Wert');
      addTearDown(controller.dispose);
      final measured = <String, _FieldGeometry>{};

      Future<void> probe(
        String area,
        Widget Function(BuildContext) build,
      ) async {
        await tester.pumpWidget(
          makeTestable(
            _scaled(
              Align(
                alignment: Alignment.topLeft,
                child: Builder(builder: build),
              ),
              scale,
            ),
          ),
        );
        await tester.pump();
        measured[area] = _measure(tester, box: _fieldBox());
      }

      // The component's own spec — what the Snippets/Replacements dialogs and
      // the feedback form render, none of which style their fields locally
      // any more (`wp_text_field_guard_test.dart` keeps it that way).
      await probe(
        'plain WpTextField',
        (_) => SizedBox(
          width: 280,
          child: WpTextField(
            controller: controller,
            variant: WpTextFieldVariant.form,
            hintText: 'hint',
          ),
        ),
      );
      await probe(
        'settingsTextField',
        (context) =>
            settingsTextField(context: context, controller: controller),
      );
      // Carries a reveal button in its trailing slot — which must change
      // nothing about the box or where the text starts.
      await probe(
        'settingsApiKeyField',
        (context) => settingsApiKeyField(
          context: context,
          controller: controller,
          obscure: true,
          onToggle: () {},
        ),
      );

      final reference = measured['plain WpTextField']!;
      for (final entry in measured.entries) {
        expect(
          entry.value,
          reference,
          reason:
              'A form field must look the same wherever it stands — what sits '
              'beside or inside it may change, never the field. '
              '"${entry.key}" drifted at $at.\n'
              '  reference:    $reference\n'
              '  ${entry.key}: ${entry.value}',
        );
      }
    });
  }

  testWidgets('the form field rests at the touch-target height and grows '
      'into its padding rather than clipping', (tester) async {
    final controller = TextEditingController(text: 'Wert');
    addTearDown(controller.dispose);

    Future<_FieldGeometry> at(double scale) async {
      await tester.pumpWidget(
        makeTestable(
          _scaled(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                child: WpTextField(
                  controller: controller,
                  variant: WpTextFieldVariant.form,
                ),
              ),
            ),
            scale,
          ),
        ),
      );
      await tester.pump();
      return _measure(tester, box: _fieldBox());
    }

    final normal = await at(1.0);
    final large = await at(1.5);

    expect(
      normal.boxHeight,
      WpLayout.minTouchTarget,
      reason:
          'a single-line form field rests at 48 dp — the touch-target floor, '
          'and the height WpSearchField settles at, so the two field families '
          'a user meets on one screen share a silhouette',
    );
    expect(
      normal.textLeftInset,
      WpSpacing.md,
      reason: 'one horizontal inset, the same 16 dp the search glyph sits at',
    );
    expect(
      (normal.textTopInset, normal.textBottomInset),
      (WpSpacing.sm + 2, WpSpacing.sm + 2),
      reason:
          'the 48 dp comes from symmetric padding around the line, not from a '
          'fixed height — that is what lets the box grow instead of clipping',
    );
    expect(
      large.boxHeight,
      greaterThan(normal.boxHeight),
      reason:
          'the old 34 dp-tall API key field could not do this: at 1.5x its '
          'text overflowed the box and was cut off at the top',
    );
    expect(
      (large.textTopInset, large.textBottomInset),
      (normal.textTopInset, normal.textBottomInset),
      reason: 'the padding is what grew the box, so it survives the growth',
    );
  });

  testWidgets('a multi-line form field keeps the single-line insets and '
      'differs only in the lines it holds', (tester) async {
    final controller = TextEditingController(text: 'Wert');
    addTearDown(controller.dispose);

    Future<_FieldGeometry> withLines(int? minLines) async {
      await tester.pumpWidget(
        makeTestable(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: WpTextField(
                controller: controller,
                variant: WpTextFieldVariant.form,
                minLines: minLines,
                maxLines: minLines == null ? 1 : 5,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return _measure(tester, box: _fieldBox());
    }

    final single = await withLines(null);
    final double2 = await withLines(2);

    expect(
      (double2.textLeftInset, double2.textTopInset, double2.textBottomInset),
      (single.textLeftInset, single.textTopInset, single.textBottomInset),
      reason:
          'how many lines a value needs is the call site\'s to say; how the '
          'field is inset is not',
    );
    expect(
      double2.boxHeight,
      greaterThan(single.boxHeight),
      reason: 'a two-line field is exactly one line taller than a one-line one',
    );
  });

  // ---------------------------------------------------------------------
  // form, in the place it actually stands
  // ---------------------------------------------------------------------

  // The probes above measure the helpers on their own. In the app all three
  // of their call sites (Settings' blocklist, the STT API key, the Snippets
  // picker trigger) hand them to a [SettingRow]'s trailing slot, and the
  // field grew from 34/36 dp to 48 dp there — the largest visual change in
  // this family. A field that grows with the text scaler is the point, so
  // the row it grows inside is what needs checking.
  for (final scale in const [1.0, 1.5]) {
    final at = scale == 1.0 ? 'normal text size' : 'accessibility text size';

    testWidgets('a settings row makes room for its field at $at', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Wert');
      addTearDown(controller.dispose);

      Future<void> pumpRow(Widget Function(BuildContext) trailing) async {
        await tester.pumpWidget(
          makeTestable(
            _scaled(
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  // The narrowest the settings pane gets: the 800 dp minimum
                  // window from `main.dart`, less its sidebar and insets.
                  width: 540,
                  child: Builder(
                    builder: (context) => SettingRow(
                      icon: Icons.key,
                      label: 'Label',
                      subtitle: 'Eine erklärende Zeile darunter',
                      trailing: trailing(context),
                    ),
                  ),
                ),
              ),
              scale,
            ),
          ),
        );
        await tester.pump();
      }

      for (final probe in <String, Widget Function(BuildContext)>{
        'settingsTextField': (context) =>
            settingsTextField(context: context, controller: controller),
        'settingsApiKeyField': (context) => settingsApiKeyField(
          context: context,
          controller: controller,
          obscure: true,
          onToggle: () {},
        ),
      }.entries) {
        await pumpRow(probe.value);

        expect(
          tester.takeException(),
          isNull,
          reason:
              '"${probe.key}" overflowed its settings row at $at — the row '
              'has to grow around the field, not clip it',
        );

        final row = _rect(tester, find.byType(SettingRow));
        final field = _rect(tester, _fieldBox());
        expect(
          field.height + 2 * WpSpacing.sm,
          lessThanOrEqualTo(row.height),
          reason:
              'the row keeps its own 12 dp breathing room above and below '
              '"${probe.key}" instead of being pushed flush against it',
        );
        expect(
          row.height,
          greaterThanOrEqualTo(WpLayout.minTouchTarget),
          reason: 'and never falls below the touch-target floor',
        );
      }
    });
  }

  testWidgets('a form field with a character counter keeps the box the '
      'others have', (tester) async {
    final controller = TextEditingController(text: 'Ein Kommentar');
    addTearDown(controller.dispose);

    Future<_FieldGeometry> withCounter(int? maxLength) async {
      await tester.pumpWidget(
        makeTestable(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: WpTextField(
                controller: controller,
                variant: WpTextFieldVariant.form,
                maxLength: maxLength,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return _measure(tester, box: _fieldBox());
    }

    final plain = await withCounter(null);
    final counted = await withCounter(1000);

    expect(
      counted,
      plain,
      reason:
          'the feedback form is the one place a form field counts its '
          'characters, and the counter belongs under the box — inside it, it '
          'would make that one field taller than every other one.\n'
          '  without counter: $plain\n'
          '  with counter:    $counted',
    );
  });

  // ---------------------------------------------------------------------
  // embedded — the field inside a row the caller draws
  // ---------------------------------------------------------------------

  group('History note rows', () {
    late L10n l10n;

    setUpAll(() async => l10n = await L10n.delegate.load(const Locale('en')));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// The bordered row the user sees — the field itself paints nothing.
    Finder hostBox() => find.ancestor(
      of: find.byType(WpTextField),
      matching: find.byType(DecoratedBox),
    );

    testWidgets('the add-note row and an edited note row are the same row', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const HistoryNotesSection(entryId: 'geometry-test-entry'),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Adding a note.
      await tester.tap(find.text(l10n.historyAddNote));
      await tester.pumpAndSettle();
      final adding = _measure(tester, box: hostBox().first);

      // Where the note's text sits once it is only being read.
      await tester.enterText(find.byType(WpTextField), 'Eine Notiz');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.actionSave));
      await tester.pumpAndSettle();
      final readingText = _rect(tester, find.text('Eine Notiz'));
      final readingRow = _rect(
        tester,
        find
            .ancestor(
              of: find.text('Eine Notiz'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );

      // Editing that same note.
      await tester.tap(find.byTooltip(l10n.actionEdit));
      await tester.pumpAndSettle();
      final editing = _measure(tester, box: hostBox().first);

      expect(
        editing,
        adding,
        reason:
            'authoring a new note and editing an existing one are one state, '
            'so they get one row: same height, same inset.\n'
            '  adding:  $adding\n'
            '  editing: $editing',
      );
      expect(
        (editing.textLeftInset, editing.textTopInset),
        (readingText.left - readingRow.left, readingText.top - readingRow.top),
        reason:
            'the note must not move when edit mode opens — the row hands its '
            'inset to the field so the text stays on the line it was on',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
