/// Unit tests for the dock row plan (WP-79, ADR 0024): which selectors show
/// their label, which show icon and value or the icon alone, and which move
/// into Mehr for a given dock width. Pure arithmetic, no widget tree.
///
/// Widths are the measured ones of the design (text at 14 px semibold, 48 px
/// hit targets, 8 px gaps). The dock width is the window minus the sidebar
/// (232 px, or 72 px below 960 px) minus 24 px of dock inset; the row has
/// 12 px of padding on each side.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart'
    show WpDockTokens;
import 'package:whispaste/widgets/recording_dock_layout.dart';

const _smart = WpDockSelectorSpec(
  id: 'smart',
  labelledWidth: 150,
  compactWidth: 110,
  iconWidth: WpDockTokens.controlHeight,
  dropRank: 3,
);
const _engine = WpDockSelectorSpec(
  id: 'engine',
  labelledWidth: 280,
  compactWidth: 250,
  iconWidth: WpDockTokens.controlHeight,
);
const _language = WpDockSelectorSpec(
  id: 'language',
  labelledWidth: 100,
  compactWidth: 70,
  iconWidth: WpDockTokens.controlHeight,
  dropRank: 2,
);
const _output = WpDockSelectorSpec(
  id: 'output',
  labelledWidth: 240,
  compactWidth: 210,
  iconWidth: WpDockTokens.controlHeight,
  dropRank: 1,
);
const _mic = WpDockSelectorSpec(
  id: 'mic',
  labelledWidth: 230,
  compactWidth: 200,
  iconWidth: WpDockTokens.controlHeight,
  dropRank: 0,
);

const _selectors = [_smart, _engine, _language, _output, _mic];

/// [dockWidth] is the dock's own width (window minus sidebar and insets).
WpDockRowMetrics _metrics({
  required double dockWidth,
  bool allowLabels = true,
  bool keycap = true,
}) => WpDockRowMetrics(
  available: dockWidth - 24,
  dictateFull: 232,
  dictateCompact: 176,
  dictateIcon: WpDockTokens.controlHeight,
  keycapWidth: keycap ? 80 : 0,
  statusFull: 160,
  statusShort: 90,
  overflowWidth: 48,
  gap: 8,
  allowLabels: allowLabels,
  belowCompactBreakpoint: dockWidth < 720,
  selectors: _selectors,
);

void main() {
  group('planDockRow', () {
    test('a dock with room for everything shows labels and the keycap', () {
      final plan = planDockRow(_metrics(dockWidth: 1700));

      expect(plan.fits, isTrue);
      expect(plan.keycap, isTrue);
      expect(plan.dictateCompact, isFalse);
      expect(plan.statusShort, isFalse);
      for (final s in _selectors) {
        expect(plan.formOf(s.id), WpDockSelectorForm.labelled, reason: s.id);
      }
    });

    test('without the labels breakpoint the selectors show icon and value', () {
      final plan = planDockRow(_metrics(dockWidth: 1700, allowLabels: false));

      expect(plan.fits, isTrue);
      expect(plan.formOf('smart'), WpDockSelectorForm.compact);
      expect(plan.formOf('output'), WpDockSelectorForm.compact);
    });

    test('the keycap goes before any selector shrinks to its icon', () {
      // 1144 px dock (1400 px window): icon and value fit only without the
      // keycap, so the keycap is the first thing to go.
      final plan = planDockRow(_metrics(dockWidth: 1144));

      expect(plan.keycap, isFalse);
      expect(plan.formOf('mic'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('smart'), WpDockSelectorForm.compact);
      expect(plan.fits, isTrue);
    });

    test('selectors shrink to their icon in drop-rank order, mic first', () {
      // 976 px available: all four droppable selectors become icons, none
      // moves into Mehr yet.
      final plan = planDockRow(_metrics(dockWidth: 1000));

      expect(plan.fits, isTrue);
      expect(plan.formOf('mic'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('output'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('language'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('smart'), WpDockSelectorForm.iconOnly);
    });

    test('a selector moves into Mehr only after every icon step', () {
      // 936 px available: all icons (938 px) do not fit, so mic moves into
      // Mehr first and the other three stay as icons.
      final plan = planDockRow(_metrics(dockWidth: 960));

      expect(plan.fits, isTrue);
      expect(plan.formOf('mic'), WpDockSelectorForm.inMenu);
      expect(plan.formOf('output'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('language'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('smart'), WpDockSelectorForm.iconOnly);
    });

    test('the engine never shrinks and never moves into Mehr', () {
      for (final width in [704.0, 720.0, 800.0, 1000.0, 1400.0]) {
        final plan = planDockRow(_metrics(dockWidth: width));
        final form = plan.formOf('engine');
        expect(form, isNot(WpDockSelectorForm.inMenu), reason: 'dock $width');
        expect(form, isNot(WpDockSelectorForm.iconOnly), reason: 'dock $width');
      }
    });

    test(
      'below the compact breakpoint every droppable selector is in Mehr',
      () {
        final plan = planDockRow(_metrics(dockWidth: 700));

        expect(plan.belowCompactBreakpoint, isTrue);
        for (final id in ['smart', 'language', 'output', 'mic']) {
          expect(plan.formOf(id), WpDockSelectorForm.inMenu, reason: id);
        }
        expect(plan.formOf('engine'), WpDockSelectorForm.compact);
      },
    );

    test('the narrowest supported dock (800 px window) fits', () {
      // 800 px window, compact sidebar of 72 px: dock 800 - 72 - 24 = 704.
      final plan = planDockRow(_metrics(dockWidth: 704));

      expect(plan.fits, isTrue, reason: 'the minimum window must not overflow');
      expect(plan.dictateCompact, isTrue);
      expect(plan.statusShort, isTrue);
    });

    test(
      'a dock too narrow for even its minimum reports that it does not fit',
      () {
        final plan = planDockRow(_metrics(dockWidth: 300));

        expect(plan.fits, isFalse);
        expect(plan.formOf('engine'), WpDockSelectorForm.compact);
      },
    );

    test('below 720 px every movable control is in Mehr and the row fits', () {
      final plan = planDockRow(_metrics(dockWidth: 700));

      expect(plan.fits, isTrue);
      expect(plan.dictateIcon, isFalse);
      for (final id in ['smart', 'language', 'output', 'mic']) {
        expect(plan.formOf(id), WpDockSelectorForm.inMenu, reason: id);
      }
    });

    test('a narrower dock shrinks the Dictate button to its icon and fits', () {
      final plan = planDockRow(_metrics(dockWidth: 600));

      expect(plan.dictateIcon, isTrue);
      expect(plan.fits, isTrue);
      expect(plan.formOf('engine'), WpDockSelectorForm.compact);
    });

    test('the minimal row fits at 612 and 560 px dock width', () {
      for (final width in [612.0, 560.0]) {
        final plan = planDockRow(_metrics(dockWidth: width));
        expect(plan.fits, isTrue, reason: 'dock $width');
        expect(plan.formOf('engine'), WpDockSelectorForm.compact);
      }
      expect(planDockRow(_metrics(dockWidth: 560)).dictateIcon, isTrue);
    });

    test('when even the minimal row does not fit, fits is false', () {
      final plan = planDockRow(_metrics(dockWidth: 300));

      expect(plan.fits, isFalse);
      expect(plan.dictateIcon, isTrue);
      expect(plan.keycap, isFalse);
      for (final id in ['smart', 'language', 'output', 'mic']) {
        expect(plan.formOf(id), WpDockSelectorForm.inMenu, reason: id);
      }
    });

    test(
      'the Dictate button narrows only when nothing else is left to give',
      () {
        expect(planDockRow(_metrics(dockWidth: 1700)).dictateCompact, isFalse);
        expect(planDockRow(_metrics(dockWidth: 704)).dictateCompact, isTrue);
      },
    );

    test('a dock without a hotkey has no keycap to drop', () {
      final plan = planDockRow(_metrics(dockWidth: 1144, keycap: false));

      expect(plan.keycap, isFalse);
      expect(plan.fits, isTrue);
    });
  });
}
