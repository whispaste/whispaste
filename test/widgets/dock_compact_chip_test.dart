/// Compact (icon-only) dock chips must read as chips: a pill no taller than
/// the dock's dense control height, with an icon that has contrast on its
/// fill. Before the fix the capsule stretched to the full dock height and the
/// microphone icon in `colorScheme.secondary` was barely visible on the navy
/// stage, so the chip looked like an empty dark column.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart'
    show WpDockTokens, wpStagePalette;
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';
import 'package:whispaste/widgets/recording_dock_layout.dart';

import '../fixtures/test_helpers.dart';
import '../fixtures/dock_choice_fixtures.dart';

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets(
    'Windows: icon-only selectors are 48 px targets with a visible icon',
    (tester) async {
      await _onPlatform(TargetPlatform.windows, () async {
        // The icon-only stage sits between the all-in-Mehr minimum and the
        // labelled row; find the first width where a selector is icon-only.
        Finder iconOnlySelectors() => find.byWidgetPredicate(
          (w) => w is WpDockSelector && w.form == WpDockSelectorForm.iconOnly,
        );
        for (var width = 560.0; width <= 1100; width += 20) {
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = Size(width + 40, 800);
          await tester.pumpWidget(
            makeTestable(
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: width,
                  child: WpRecordingDock(
                    sttModeLabel: 'Whisper · small',
                    sttState: SttServerState.ready,
                    smartMode: dockTestSmartMode(label: 'Smart Mode · Aus'),
                    hotkeyLabel: 'Strg+Umschalt+D',
                    microphoneLabel: micDefaultLabel,
                    microphoneOptions: const [micDefaultLabel],
                    onMicrophoneChanged: (_) {},
                    afterActionLabel: 'Kopieren',
                    afterAction: AfterTranscriptionAction.clipboard,
                    onAfterActionChanged: (_) {},
                    language: dockTestLanguage(label: 'DE'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          if (iconOnlySelectors().evaluate().isNotEmpty) break;
        }
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pump();

        final iconOnly = find.byWidgetPredicate(
          (w) => w is WpDockSelector && w.form == WpDockSelectorForm.iconOnly,
        );
        expect(
          iconOnly,
          findsWidgets,
          reason: 'the dock must be in the icon-only stage for this test',
        );

        // Icon-only selectors keep the 48 px target; their fill is the stage
        // control colour composited over the dock surface.
        final fillOverSurface = Color.alphaBlend(
          wpStagePalette.control,
          wpStagePalette.surface,
        );
        for (var i = 0; i < iconOnly.evaluate().length; i++) {
          final selector = iconOnly.at(i);
          final size = tester.getSize(selector);
          expect(
            size.height,
            WpDockTokens.controlHeight,
            reason: 'selector $i is not a 48 px target (${size.height})',
          );
          final icon = tester.widget<Icon>(
            find.descendant(of: selector, matching: find.byType(Icon)).first,
          );
          expect(
            _contrast(icon.color!, fillOverSurface),
            greaterThanOrEqualTo(3),
            reason: 'icon in selector $i is too faint on its fill',
          );
        }
        expect(find.byIcon(LucideIcons.mic), findsWidgets);
      });
    },
  );
}
