import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/empty_state.dart';
import 'package:whispaste/widgets/wp_cut_illustration.dart';

import '../fixtures/test_helpers.dart';

// Paper-cut empty-state motifs (#1595, design-tokens/illustration/STYLE.md).
void main() {
  group('SVG sources', () {
    final sources = {
      WpCutColorMapper.sourceGround,
      WpCutColorMapper.sourceBack,
      WpCutColorMapper.sourceCarrier,
      WpCutColorMapper.sourceLine,
      WpCutColorMapper.sourceRest,
      WpCutColorMapper.sourceMark,
    };
    String hexOf(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
            .toUpperCase();

    for (final motif in WpEmptyMotif.values) {
      test('${motif.name}: only mapped palette colours, no text, no cyan', () {
        final svg = File(motif.asset).readAsStringSync();
        final used = RegExp(
          r'#[0-9A-Fa-f]{6}\b',
        ).allMatches(svg).map((m) => m.group(0)!.toUpperCase()).toSet();
        // Every colour is swapped for a WpColors role at runtime; one that
        // the mapper does not know would bypass the theme.
        expect(used, everyElement(isIn(sources.map(hexOf))));
        // STYLE.md §3.4/§9: the resting pill has no cyan, the image no text.
        expect(svg, isNot(contains('<text')));
        expect(svg, isNot(contains('<image')));
        // §2: amber exactly once.
        expect(hexOf(WpCutColorMapper.sourceMark).allMatchesIn(svg), 1);
      });
    }
  });

  group('WpCutColorMapper', () {
    test('light and Marine land on the STYLE.md palette exactly', () {
      for (final colors in [wpLightColors, wpNavyColors]) {
        final m = WpCutColorMapper.of(colors);
        expect(m.ground, WpCutColorMapper.sourceGround);
        expect(m.back, WpCutColorMapper.sourceBack);
        expect(m.carrier, WpCutColorMapper.sourceCarrier);
        expect(m.line, WpCutColorMapper.sourceLine);
        expect(m.rest, WpCutColorMapper.sourceRest);
        expect(m.mark, WpCutColorMapper.sourceMark);
      }
    });

    test('dark keeps the layers apart and the carrier off white', () {
      final m = WpCutColorMapper.of(wpDarkColors);
      expect({m.ground, m.back, m.carrier}, hasLength(3));
      expect(m.carrier, isNot(WpCutColorMapper.sourceCarrier));
      expect(m.mark, WpCutColorMapper.sourceMark);
    });

    test('each source colour is substituted, others pass through', () {
      final m = WpCutColorMapper.of(wpDarkColors);
      Color sub(Color c) => m.substitute(null, 'rect', 'fill', c);
      expect(sub(WpCutColorMapper.sourceGround), m.ground);
      expect(sub(WpCutColorMapper.sourceBack), m.back);
      expect(sub(WpCutColorMapper.sourceCarrier), m.carrier);
      expect(sub(WpCutColorMapper.sourceLine), m.line);
      expect(sub(WpCutColorMapper.sourceRest), m.rest);
      expect(sub(WpCutColorMapper.sourceMark), m.mark);
      expect(sub(const Color(0xFF000000)), const Color(0xFF000000));
    });

    test('equal per colour set, so the SVG cache keeps sets apart', () {
      expect(
        WpCutColorMapper.of(wpLightColors),
        WpCutColorMapper.of(wpNavyColors),
      );
      expect(
        WpCutColorMapper.of(wpLightColors),
        isNot(WpCutColorMapper.of(wpDarkColors)),
      );
    });
  });

  group('WpEmptyState motif', () {
    Widget pane(Widget child) => makeTestable(
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 600, height: 700, child: child),
      ),
    );

    testWidgets('a motif replaces the icon still life', (tester) async {
      await tester.pumpWidget(
        pane(
          const WpEmptyState(
            icon: LucideIcons.mic,
            motif: WpEmptyMotif.recordings,
            title: 'No recordings yet',
          ),
        ),
      );
      expect(find.byType(WpCutIllustration), findsOneWidget);
      expect(find.byType(WpEmptyIllustration), findsNothing);
    });

    testWidgets('without a motif the icon still life stays', (tester) async {
      await tester.pumpWidget(
        pane(const WpEmptyState(icon: LucideIcons.trash2, title: 'Empty')),
      );
      expect(find.byType(WpEmptyIllustration), findsOneWidget);
      expect(find.byType(WpCutIllustration), findsNothing);
    });

    testWidgets('the taller motif drops earlier in a low pane', (tester) async {
      // Just above the icon threshold, below the motif's.
      await tester.pumpWidget(
        makeTestable(
          const SizedBox(
            height: WpEmptyState.compactBelowHeight + 20,
            child: WpEmptyState(
              icon: LucideIcons.mic,
              motif: WpEmptyMotif.recordings,
              title: 'No recordings yet',
            ),
          ),
        ),
      );
      expect(find.byType(WpCutIllustration), findsNothing);
    });
  });
}

extension on String {
  int allMatchesIn(String haystack) => RegExp(
    RegExp.escape(this),
    caseSensitive: false,
  ).allMatches(haystack).length;
}
