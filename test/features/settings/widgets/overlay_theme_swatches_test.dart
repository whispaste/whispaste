// Keyboard and label behaviour of the overlay theme swatch rows (WP-75, ADR
// 0024). The rows follow the appearance cards: Tab reaches a row, the arrow
// keys and Home/End move focus only, and Enter or Space select the focused
// swatch. Every swatch prints its name underneath.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/features/settings/widgets/overlay_theme_swatches.dart';

import '../../../fixtures/test_helpers.dart';

class _Host extends StatefulWidget {
  const _Host({required this.onBackground, required this.onWave});

  final ValueChanged<OverlayBackground> onBackground;
  final ValueChanged<OverlayWave> onWave;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  OverlayBackground _background = OverlayBackground.marine;
  OverlayWave _wave = OverlayWave.cyan;

  @override
  Widget build(BuildContext context) {
    // The settings page scrolls. At text scale 2.0 the two rows together are
    // taller than the 600 px test surface, so the host scrolls like the page.
    return SingleChildScrollView(
      child: Column(
        children: [
          WpOverlayBackgroundSwatches(
            value: _background,
            onChanged: (value) {
              setState(() => _background = value);
              widget.onBackground(value);
            },
          ),
          WpOverlayWaveSwatches(
            value: _wave,
            background: _background,
            onChanged: (value) {
              setState(() => _wave = value);
              widget.onWave(value);
            },
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('arrow keys move focus only; Enter selects the focused swatch', (
    tester,
  ) async {
    final picked = <OverlayBackground>[];
    await tester.pumpWidget(
      makeTestable(_Host(onBackground: picked.add, onWave: (_) {})),
    );
    await tester.pump();

    // Tab enters the background row at the first swatch (marine).
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // Moving focus does not change the selection.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(picked, isEmpty);

    // Enter selects the swatch that has focus: gletscher.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, [OverlayBackground.gletscher]);

    // The fourth swatch (amber) is reached by moving focus right; focus stops
    // at the end instead of wrapping around.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked.last, OverlayBackground.amber);

    // Home jumps focus to marine; Space selects it.
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(picked, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(picked.last, OverlayBackground.marine);
  });

  testWidgets('arrow keys work in the wave row too', (tester) async {
    final picked = <OverlayWave>[];
    await tester.pumpWidget(
      makeTestable(_Host(onBackground: (_) {}, onWave: picked.add)),
    );
    await tester.pump();

    // Background row has four swatches; tab past them into the wave row.
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    // Five Tabs land on the first wave swatch (cyan). Moving focus right and
    // selecting with Enter picks the neighbour, violett.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(picked, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, [OverlayWave.violett]);
  });

  testWidgets('every swatch prints its name under the colour', (tester) async {
    await tester.pumpWidget(
      makeTestable(_Host(onBackground: (_) {}, onWave: (_) {})),
    );
    await tester.pump();
    final l10n = lookupL10n(const Locale('en'));
    for (final text in [
      l10n.settingsOverlayBackgroundMarine,
      l10n.settingsOverlayBackgroundGraphit,
      l10n.settingsOverlayBackgroundGletscher,
      l10n.settingsOverlayWaveCyan,
      l10n.settingsOverlayWaveViolett,
      l10n.settingsOverlayWaveNeutral,
      l10n.settingsOverlayWaveInk,
      l10n.settingsOverlayWaveCoral,
      l10n.settingsOverlayWaveMint,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // Amber is offered in both rows and carries the same name in each.
    expect(find.text(l10n.settingsOverlayBackgroundAmber), findsNWidgets(2));
  });

  testWidgets('amber is offered in the background and the wave row', (
    tester,
  ) async {
    final picked = <OverlayBackground>[];
    final waves = <OverlayWave>[];
    await tester.pumpWidget(
      makeTestable(_Host(onBackground: picked.add, onWave: waves.add)),
    );
    await tester.pump();
    expect(
      find.bySemanticsIdentifier('overlay-background-amber'),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier('overlay-wave-amber'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('overlay-background-amber'));
    await tester.tap(find.bySemanticsIdentifier('overlay-wave-amber'));
    await tester.pump();
    expect(picked, [OverlayBackground.amber]);
    expect(waves, [OverlayWave.amber]);
  });

  // UX-040: at text scale 2.0 the names were cut off with an ellipsis
  // ("Mari…") because each swatch column was fixed at 72 px. The name is the
  // only text encoding of a preset, so it must stay whole: one line or wrapped
  // at spaces, and no word broken apart.
  testWidgets('names stay whole at text scale 2.0 (UX-040)', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _Host(onBackground: (_) {}, onWave: (_) {}),
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.pump();
    final l10n = lookupL10n(const Locale('de'));
    for (final label in [
      l10n.settingsOverlayBackgroundMarine,
      l10n.settingsOverlayBackgroundGraphit,
      l10n.settingsOverlayBackgroundGletscher,
      l10n.settingsOverlayBackgroundAmber,
      l10n.settingsOverlayWaveCyan,
      l10n.settingsOverlayWaveViolett,
      l10n.settingsOverlayWaveNeutral,
      l10n.settingsOverlayWaveInk,
      l10n.settingsOverlayWaveCoral,
      l10n.settingsOverlayWaveMint,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(label).first,
      );
      // The widest unbroken word must fit the name's box at this scale.
      final longestWord = label
          .split(' ')
          .reduce((a, b) => a.length >= b.length ? a : b);
      final wordPainter = TextPainter(
        text: TextSpan(text: longestWord, style: paragraph.text.style),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(2),
      )..layout();
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(wordPainter.width),
        reason: '$label is cut off or broken inside a word',
      );
    }
  });

  testWidgets(
    'a wave invalid on the background is disabled and does not select',
    (tester) async {
      final waves = <OverlayWave>[];
      await tester.pumpWidget(
        makeTestable(_Host(onBackground: (_) {}, onWave: waves.add)),
      );
      await tester.pump();
      final ink = find.bySemanticsIdentifier('overlay-wave-ink');
      expect(ink, findsOneWidget);
      expect(
        tester.getSemantics(ink),
        isNot(matchesSemantics(isEnabled: true)),
      );

      await tester.tap(ink);
      await tester.pump();
      expect(waves, isEmpty);
    },
  );

  // UX-052: a disabled wave is reachable by keyboard so its reason can be read,
  // but it never selects. The reason is printed while the swatch has focus, so
  // it does not depend on hover.
  testWidgets('a disabled wave takes focus, shows its reason and does not '
      'select (UX-052)', (tester) async {
    final waves = <OverlayWave>[];
    await tester.pumpWidget(
      makeTestable(_Host(onBackground: (_) {}, onWave: waves.add)),
    );
    await tester.pump();
    final l10n = L10n.of(tester.element(find.byType(WpOverlayWaveSwatches)));
    final reason = l10n.settingsOverlayWaveUnavailable;
    expect(find.text(reason), findsNothing);

    // Five Tabs land on cyan; three Rights go violett, neutral, ink (disabled
    // on the marine background).
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(find.text(reason), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(waves, isEmpty);
    expect(find.text(reason), findsOneWidget);

    // Leaving the swatch takes the explanation away again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text(reason), findsNothing);
  });

  testWidgets('a tap on a disabled wave focuses it and shows the reason, '
      'without selecting (UX-052)', (tester) async {
    final waves = <OverlayWave>[];
    await tester.pumpWidget(
      makeTestable(_Host(onBackground: (_) {}, onWave: waves.add)),
    );
    await tester.pump();
    final reason = L10n.of(
      tester.element(find.byType(WpOverlayWaveSwatches)),
    ).settingsOverlayWaveUnavailable;

    await tester.tap(find.bySemanticsIdentifier('overlay-wave-ink'));
    await tester.pump();
    expect(waves, isEmpty);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets(
    'each swatch row is a radio group with one checked swatch (UX-039)',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(_Host(onBackground: (_) {}, onWave: (_) {})),
        );
        await tester.pump();

        void expectRadio(String id, {required bool checked}) {
          final flags = tester
              .getSemantics(find.bySemanticsIdentifier(id))
              .getSemanticsData()
              .flagsCollection;
          expect(flags.isInMutuallyExclusiveGroup, isTrue, reason: id);
          expect(
            flags.isChecked,
            checked ? ui.CheckedState.isTrue : ui.CheckedState.isFalse,
            reason: id,
          );
        }

        expectRadio('overlay-background-marine', checked: true);
        expectRadio('overlay-background-graphit', checked: false);
        expectRadio('overlay-wave-cyan', checked: true);
        expectRadio('overlay-wave-neutral', checked: false);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('names wrap instead of truncating at text scale 2.0 (UX-040)', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 320,
            child: _Host(onBackground: (_) {}, onWave: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    final l10n = lookupL10n(const Locale('en'));
    for (final text in [
      l10n.settingsOverlayBackgroundGletscher,
      l10n.settingsOverlayBackgroundGraphit,
      l10n.settingsOverlayWaveViolett,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      expect(paragraph.text.toPlainText(), text);
    }
  });
}
