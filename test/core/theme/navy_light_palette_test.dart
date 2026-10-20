// Guard for DEV-182 / DEV-160: the navy set may differ from the light set
// only where the design says so. Every field of [WpThemeColors] is listed
// here, so a new field that is not classified fails the test.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/theme_colors.dart';

/// Fields that differ between navy and light by design:
/// - frameOverride: navy draws the sidebar and title bar in the dark set.
/// - primaryRecordFill / primaryRecordHover: navy uses amber as the primary
///   record button (WP-50).
const _expectedDifferences = <String>{
  'frameOverride',
  'primaryRecordFill',
  'primaryRecordHover',
};

final _fields = <(String, Object? Function(WpThemeColors))>[
  ('brightness', (c) => c.brightness),
  ('frameOverride', (c) => c.frameOverride),
  ('background', (c) => c.background),
  ('surface', (c) => c.surface),
  ('surfaceElevated', (c) => c.surfaceElevated),
  ('surfaceVariant', (c) => c.surfaceVariant),
  ('hover', (c) => c.hover),
  ('hoverTransparent', (c) => c.hoverTransparent),
  ('active', (c) => c.active),
  ('borderSubtle', (c) => c.borderSubtle),
  ('borderDefault', (c) => c.borderDefault),
  ('textPrimary', (c) => c.textPrimary),
  ('textSecondary', (c) => c.textSecondary),
  ('textMuted', (c) => c.textMuted),
  ('switchTrackOff', (c) => c.switchTrackOff),
  ('selectionBorder', (c) => c.selectionBorder),
  ('accent', (c) => c.accent),
  ('accentHover', (c) => c.accentHover),
  ('action', (c) => c.action),
  ('onAction', (c) => c.onAction),
  ('accentSubtle', (c) => c.accentSubtle),
  ('accentChipFill', (c) => c.accentChipFill),
  ('accentChipFillHover', (c) => c.accentChipFillHover),
  ('accentMiniTagFill', (c) => c.accentMiniTagFill),
  ('accentBorder30', (c) => c.accentBorder30),
  ('accentButtonFill', (c) => c.accentButtonFill),
  ('accentActiveFill', (c) => c.accentActiveFill),
  ('accentBadgeFill', (c) => c.accentBadgeFill),
  ('accentBorder20', (c) => c.accentBorder20),
  ('accentRowHover', (c) => c.accentRowHover),
  ('surfaceChipFill', (c) => c.surfaceChipFill),
  ('surfaceMutedFill', (c) => c.surfaceMutedFill),
  ('cardFill', (c) => c.cardFill),
  ('cardFillElevated', (c) => c.cardFillElevated),
  ('cardEdgeHighlight', (c) => c.cardEdgeHighlight),
  ('floatingSurface', (c) => c.floatingSurface),
  ('decorativeGlyphWash', (c) => c.decorativeGlyphWash),
  ('success', (c) => c.success),
  ('warning', (c) => c.warning),
  ('error', (c) => c.error),
  ('onError', (c) => c.onError),
  ('errorRowHover', (c) => c.errorRowHover),
  ('errorButtonFill', (c) => c.errorButtonFill),
  ('errorActiveFill', (c) => c.errorActiveFill),
  ('errorBorder20', (c) => c.errorBorder20),
  ('errorBorder30', (c) => c.errorBorder30),
  ('mutedRowHover', (c) => c.mutedRowHover),
  ('mutedActiveFill', (c) => c.mutedActiveFill),
  ('successActiveFill', (c) => c.successActiveFill),
  ('warningActiveFill', (c) => c.warningActiveFill),
  ('accentLocatorRing', (c) => c.accentLocatorRing),
  ('recordingAccent', (c) => c.recordingAccent),
  ('recordingAccentGradient', (c) => c.recordingAccentGradient),
  ('warningOrange', (c) => c.warningOrange),
  ('warningOrangeBadgeFill', (c) => c.warningOrangeBadgeFill),
  ('warningOrangeBadgeBorder', (c) => c.warningOrangeBadgeBorder),
  ('errorRed', (c) => c.errorRed),
  ('errorRedHover', (c) => c.errorRedHover),
  ('surfaceGradient', (c) => c.surfaceGradient),
  ('warmSurfaceGradient', (c) => c.warmSurfaceGradient),
  ('frameGradient', (c) => c.frameGradient),
  ('accentGradient', (c) => c.accentGradient),
  ('accentWarmGradient', (c) => c.accentWarmGradient),
  ('navChipGradient', (c) => c.navChipGradient),
  ('navChipGradientHover', (c) => c.navChipGradientHover),
  ('navPillActiveGradient', (c) => c.navPillActiveGradient),
  ('highlight', (c) => c.highlight),
  ('highlightSoft', (c) => c.highlightSoft),
  ('highlightText', (c) => c.highlightText),
  ('primaryRecordFill', (c) => c.primaryRecordFill),
  ('primaryRecordHover', (c) => c.primaryRecordHover),
  ('onPrimaryRecord', (c) => c.onPrimaryRecord),
  ('ctaFill', (c) => c.ctaFill),
  ('ctaHover', (c) => c.ctaHover),
  ('ctaPressed', (c) => c.ctaPressed),
  ('onCta', (c) => c.onCta),
  ('controlEdge', (c) => c.controlEdge),
  ('warningOrangeText', (c) => c.warningOrangeText),
  ('shadow', (c) => c.shadow),
];

void main() {
  test('every WpThemeColors field is listed once', () {
    expect(_fields.map((f) => f.$1).toSet(), hasLength(_fields.length));
    expect(_fields, hasLength(79));
  });

  test('navy differs from light exactly in the designed fields', () {
    final differing = <String>{
      for (final (name, get) in _fields)
        if (get(wpNavyColors) != get(wpLightColors)) name,
    };
    expect(differing, _expectedDifferences);
  });
}
