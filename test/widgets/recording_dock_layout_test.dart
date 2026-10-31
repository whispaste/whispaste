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
  });
}
