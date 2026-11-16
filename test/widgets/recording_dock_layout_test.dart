/// Unit tests for the dock row plan (ticket, ADR 0024): which selectors show
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
    show WpDockTokens, WpShellTokens;
import 'package:whispaste/core/theme/tokens.dart' show WpLayout;
import 'package:whispaste/widgets/recording_dock_layout.dart';

const _smart = WpDockSelectorSpec(
  id: 'smart',
  labelledWidth: 150,
  compactWidth: 110,
  iconWidth: WpDockTokens.controlHeight,
  dropRank: 3,
  keepsValue: true,
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
  keepsValue: true,
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
  double keycapWidth = 80,
  double? available,
}) => WpDockRowMetrics(
  available: available ?? dockWidth - 24,
  dictateFull: 232,
  dictateCompact: 176,
  dictateNeed: 120,
  dictateIcon: WpDockTokens.controlHeight,
  keycapWidth: keycapWidth,
  statusFull: 160,
  statusShort: 90,
  overflowWidth: 48,
  gap: 8,
  allowLabels: allowLabels,
  belowCompactBreakpoint: dockWidth < WpDockTokens.breakpointCompact,
  selectors: _selectors,
);

void main() {
  group('planDockRow', () {
    test('the other selectors give way first, in drop-rank order', () {
      // Wide enough once the mic is an icon and the output selector still
      // shows its value.
      final plan = planDockRow(_metrics(dockWidth: 1290));

      expect(plan.fits, isTrue);
      expect(plan.keycap, isTrue);
      expect(plan.formOf('mic'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('output'), WpDockSelectorForm.compact);
    });

    test('the keycap outlasts the selectors that show no state', () {
      final plan = planDockRow(_metrics(dockWidth: 950));

      expect(plan.fits, isTrue);
      expect(plan.keycap, isTrue);
      expect(plan.formOf('mic'), WpDockSelectorForm.inMenu);
      expect(plan.formOf('output'), WpDockSelectorForm.inMenu);
      expect(plan.formOf('smart'), WpDockSelectorForm.compact);
      expect(plan.formOf('language'), WpDockSelectorForm.compact);
    });

    test('Smart Mode and language keep their value longer than the keycap', () {
      // A long hotkey label: with the keycap the row is too wide, without it
      // both values still fit.
      final plan = planDockRow(_metrics(dockWidth: 700, keycapWidth: 200));

      expect(plan.fits, isTrue);
      expect(plan.keycap, isFalse);
      expect(plan.formOf('smart'), WpDockSelectorForm.compact);
      expect(plan.formOf('language'), WpDockSelectorForm.compact);
    });

    test('the smallest window stays above the compact breakpoint', () {
      const dockWidth =
          WpLayout.minWindowWidth -
          WpShellTokens.sidebarWidthCompact -
          2 * WpShellTokens.dockInset;
      expect(dockWidth, greaterThanOrEqualTo(WpDockTokens.breakpointCompact));
    });

    test('the keycap uses the room inside the button before widening it', () {
      expect(dockDictateWidth(base: 176, need: 120, keycap: 50), 176);
      expect(dockDictateWidth(base: 176, need: 120, keycap: 80), 200);
    });

    test('the engine value gives way before the keycap and the values', () {
      final plan = planDockRow(_metrics(dockWidth: 800));

      expect(plan.fits, isTrue);
      expect(plan.keycap, isTrue);
      expect(plan.formOf('engine'), WpDockSelectorForm.iconOnly);
      expect(plan.formOf('smart'), WpDockSelectorForm.compact);
      expect(plan.formOf('language'), WpDockSelectorForm.compact);
    });

    test('Smart Mode and language shrink once the keycap is gone', () {
      final plan = planDockRow(_metrics(dockWidth: 800, available: 570));

      expect(plan.fits, isTrue);
      expect(plan.keycap, isFalse);
      expect(plan.formOf('language'), WpDockSelectorForm.iconOnly);
    });

    test('the engine never moves into Mehr', () {
      final plan = planDockRow(_metrics(dockWidth: 300));

      expect(plan.formOf('engine'), WpDockSelectorForm.iconOnly);
    });
  });
}
