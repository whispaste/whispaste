/// The transcript zone is **one** surface, read or edited (Ticket 16).
///
/// History's transcript is the one paragraph on that screen a user is
/// genuinely *reading*, and it toggles between a read view and an edit view of
/// the same text. `WpTextField.styleFor` has always kept the two at one set of
/// metrics; until this ticket only the edit view carried a material at all, so
/// the moment Ticket 09 gave `passage` the card fill the same paragraph read
/// as bare prose on the ambient while reading and as a frosted card while
/// editing.
///
/// What is pinned here is deliberately a *comparison*, not two literals. Two
/// separately pinned colours pass happily while the surfaces they describe
/// drift apart — the failure this file exists to catch. Both decorations are
/// captured from the same pumped panel, across one toggle, and compared to
/// each other.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/highlighted_text.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

const _entryTitle = 'Weekly standup notes';

/// Long enough to wrap several times at the 720 dp measure, so the enlarged
/// text-size case below has a real paragraph to grow rather than one line.
const _transcript =
    'Recording the standup for the third week running. The migration is '
    'unblocked, the installer signs on both runners again, and the crash we '
    'were chasing in the overlay turned out to be a stale handle rather than '
    'anything in the audio path. Next week: the model picker, then the long '
    'tail of settings copy nobody has read since the rewrite.';

/// The detail panel has long-standing tight-fit overflow at some widths, and
/// these tests assert *material*, not layout — same waiver as
/// `history_markdown_shortcuts_test.dart` and `history_export_wiring_test.dart`
/// carry. The enlarged-text case below states what it does check in its own
/// comment.
void _ignoreOverflowErrors() {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.toString().contains('overflowed')) return;
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

HistoryEntry _entry() => HistoryEntry(
  id: 'demo-0',
  timestamp: DateTime(2026, 4, 14, 10, 30),
  content: _transcript,
  title: _entryTitle,
  durationSec: 12,
  processingDurationSec: 0.8,
  language: 'en',
  languageHint: '',
  tags: '',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0,
  source: 'dictation',
  pinned: false,
  archived: false,
  titleEdited: false,
  colorSlot: 0,
);

List<Object> _overrides() => [
  historyEntriesProvider.overrideWith((ref) => Stream.value([_entry()])),
  archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
  trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
];

/// The read view's painted box.
AnimatedContainer _readBox(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(WpTextFieldSurface),
        matching: find.byType(AnimatedContainer),
      ),
    );

/// The transcript's own field — the page also renders a search field, so
/// `find.byType(WpTextField)` alone would be ambiguous.
Finder _transcriptField() => find.byWidgetPredicate(
  (widget) =>
      widget is WpTextField &&
      widget.semanticsLabel == l10n.historyEditTranscript,
);

/// The edit view's painted box — the field's own.
AnimatedContainer _editBox(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: _transcriptField(),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

/// The inset the field applies through its `InputDecoration` rather than
/// through its box — read back so the comparison stays a comparison between
/// two live surfaces instead of two pinned literals.
EdgeInsetsGeometry? _fieldContentPadding(WidgetTester tester) => tester
    .widget<TextField>(
      find
          .descendant(of: _transcriptField(), matching: find.byType(TextField))
          .first,
    )
    .decoration!
    .contentPadding;

/// Drains Drift/Riverpod teardown timers before the framework's
/// `!timersPending` invariant runs.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// Opens the seeded entry's detail panel and scrolls the transcript into view.
Future<void> _openDetail(WidgetTester tester, {double textScale = 1.0}) async {
  await tester.pumpWidget(
    makeTestable(
      // Inside `makeTestable`, not around it: the helper installs its own
      // `MediaQuery` below the app, so a scaler set above it never arrives.
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const HistoryPage(),
        ),
      ),
      size: const Size(1800, 900),
      overrides: _overrides(),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(_entryTitle).first);
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byType(WpTextFieldSurface));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('read and edit mode paint the same transcript material', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _openDetail(tester);

    // Guard against a hollow pass: if the panel ever stops rendering the
    // transcript, every comparison below would compare nothing.
    expect(
      find.byType(WpTextFieldSurface),
      findsOneWidget,
      reason: 'the read view must render the transcript on its own surface',
    );

    final readBox = _readBox(tester);
    final readFill = readBox.decoration! as BoxDecoration;
    final readStroke = readBox.foregroundDecoration as BoxDecoration?;
    // The list rows render `HighlightedText` too — only the one on the read
    // surface is the transcript.
    final readTextOrigin = tester.getTopLeft(
      find.descendant(
        of: find.byType(WpTextFieldSurface),
        matching: find.byType(HighlightedText),
      ),
    );
    final readSurfaceOrigin = tester.getTopLeft(
      find.byType(WpTextFieldSurface),
    );

    // Into edit mode the way a reader gets there: the read view carries the
    // "Edit transcript" tooltip and opens the editor on tap.
    await tester.tap(
      find.byTooltip(l10n.historyEditTranscript).first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(WpTextFieldSurface),
      findsNothing,
      reason: 'the read surface must give way to the field, not stack with it',
    );

    final editBox = _editBox(tester);
    final editFill = editBox.decoration! as BoxDecoration;

    expect(
      readFill.color,
      editFill.color,
      reason:
          'the transcript changes material between reading and editing — the '
          'read view must carry the field\'s own resting fill, not just its '
          'text metrics',
    );
    expect(
      readFill.borderRadius,
      editFill.borderRadius,
      reason: 'the same fill in a different shape is still two materials',
    );
    expect(
      readBox.padding,
      _fieldContentPadding(tester),
      reason:
          'the paragraph shifts sideways on toggle unless the read view '
          'carries the field\'s inset too',
    );

    // The point of matching the inset: the paragraph must not jump when the
    // reader taps into the editor. Checked where it is actually visible — at
    // the first glyph's origin — because the field's inset reaches the text
    // through `InputDecorator`, not through the box alone.
    final editTextOrigin = tester.getTopLeft(
      find.descendant(
        of: _transcriptField(),
        matching: find.byType(EditableText),
      ),
    );
    expect(
      editTextOrigin.dx,
      moreOrLessEquals(readTextOrigin.dx, epsilon: 0.5),
      reason: 'the transcript shifts sideways when the reader starts editing',
    );
    // Vertically the comparison has to be made *within* each view: edit mode
    // reveals the markdown toolbar above the transcript, so the whole zone
    // sits lower — behaviour that predates this ticket. What must match is
    // the text's offset inside its own surface.
    final editFieldOrigin = tester.getTopLeft(_transcriptField());
    expect(
      editTextOrigin.dy - editFieldOrigin.dy,
      moreOrLessEquals(readTextOrigin.dy - readSurfaceOrigin.dy, epsilon: 0.5),
      reason:
          'the transcript sits at a different height inside its own surface '
          'when the reader starts editing',
    );

    // Contour-free at rest on both sides: `passage` paints a *transparent*
    // 1 dp stroke so the focus contour can cross-fade a colour. A visible
    // hairline in the read view would be the two-materials failure again,
    // one property along.
    expect(readStroke, isNotNull);
    expect(
      (readStroke!.border! as Border).top.color.a,
      0,
      reason: 'the read view must show no contour at rest',
    );

    await _teardownTree(tester);
  });

  testWidgets('the read surface grows with an accessibility text size instead '
      'of clipping the transcript', (tester) async {
    // The project's enlarged-system-font convention, applied to the surface
    // this ticket added. It checks growth rather than "no overflow anywhere":
    // the panel's own tight-fit overflow at some widths predates this ticket
    // and is waived above, but a card that swallowed the extra lines instead
    // of getting taller would be this ticket's own regression.
    _ignoreOverflowErrors();

    await _openDetail(tester);
    final restingHeight = tester
        .getSize(find.byType(WpTextFieldSurface))
        .height;
    await _teardownTree(tester);

    await _openDetail(tester, textScale: 1.5);
    final grownHeight = tester.getSize(find.byType(WpTextFieldSurface)).height;

    expect(
      grownHeight,
      greaterThan(restingHeight),
      reason:
          'at 1.5x the same transcript needs more lines — a surface that '
          'stayed its resting height would be clipping them',
    );
    expect(tester.takeException(), isNull);

    await _teardownTree(tester);
  });
}
