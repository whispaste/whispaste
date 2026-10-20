/// WP-95: the settings preview stage is labelled, cannot be operated, and
/// reflows at large text scales and in RTL.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/features/settings/widgets/overlay_preview_stage.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';
import 'package:whispaste/widgets/overlay_preview.dart';

import '../../../fixtures/test_helpers.dart';

Widget _stage({
  bool showButton = true,
  FloatingButtonLook buttonLook = FloatingButtonLook.defaults,
  double width = 900,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  Locale? locale,
}) {
  return makeTestable(
    Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: WpOverlayPreviewStage(
              size: FloatingOverlaySize.normal,
              background: OverlayBackground.marine,
              wave: OverlayWave.cyan,
              showButton: showButton,
              buttonLook: buttonLook,
            ),
          ),
        ),
      ),
    ),
    locale: locale,
  );
}

void main() {
  testWidgets('floating button preview shows the recording look and ring', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(buttonLook: const FloatingButtonLook()));
    await tester.pump();

    final button = tester.widget<WpFloatingButtonView>(
      find.byKey(const ValueKey('overlay-preview-floating-button')),
    );
    expect(button.state, FloatingButtonVisualState.recording);
    expect(
      WpFloatingButtonView.painterFor(
        state: button.state,
        look: button.look,
      ).spec.borderWidth,
      2.0,
      reason: 'preview ring should be drawn while the preview is recording',
    );
  });

  testWidgets('is labelled as a preview with captions for both elements', (
    tester,
  ) async {
    await tester.pumpWidget(_stage());
    await tester.pump();
    final l10n = L10n.of(tester.element(find.byType(WpOverlayPreviewStage)));

    expect(find.text(l10n.settingsPreviewTitle), findsOneWidget);
    expect(find.text(l10n.settingsPreviewHint), findsOneWidget);
    expect(find.text(l10n.settingsPreviewOverlayCaption), findsOneWidget);
    expect(find.text(l10n.settingsFloatingButtonSection), findsOneWidget);
    expect(
      find.byKey(const ValueKey('overlay-preview-floating-button')),
      findsOneWidget,
    );
  });

  testWidgets('both previews are excluded from hit testing', (tester) async {
    await tester.pumpWidget(_stage());
    await tester.pump();

    final ignoring = find.ancestor(
      of: find.byKey(const ValueKey('overlay-preview-floating-button')),
      matching: find.byType(IgnorePointer),
    );
    expect(ignoring, findsWidgets);
    expect(tester.widget<IgnorePointer>(ignoring.first).ignoring, isTrue);

    final overlayIgnoring = find.ancestor(
      of: find.byKey(const ValueKey('overlay-real-preview-normal')),
      matching: find.byType(IgnorePointer),
    );
    expect(overlayIgnoring, findsWidgets);
    expect(
      tester.widget<IgnorePointer>(overlayIgnoring.first).ignoring,
      isTrue,
    );
  });

  testWidgets('the button preview is absent when the platform has no button', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(showButton: false));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('overlay-preview-floating-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('overlay-real-preview-normal')),
      findsOneWidget,
    );
  });

  testWidgets('reflows without overflow at text scale 2.0 and a narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(width: 360, textScale: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out in right-to-left order without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _stage(width: 360, textScale: 2, direction: TextDirection.rtl),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // 480 is the settings content width in a 1100 px window; German has the
  // longest button caption ("Schwebender Button").
  for (final width in [480.0, 1100.0]) {
    testWidgets('stays compact at $width: overlay and button share one row', (
      tester,
    ) async {
      await tester.pumpWidget(_stage(width: width, locale: const Locale('de')));
      await tester.pump();

      final stage = tester.getRect(
        find.byKey(const ValueKey('overlay-preview-stage')),
      );
      final overlay = tester.getRect(find.byType(WpOverlayRealPreview));
      final button = tester.getRect(
        find.byKey(const ValueKey('overlay-preview-floating-button')),
      );

      // The pill keeps its own width (scaling down when space is short)
      // instead of filling the stage, so the button sits beside it and the
      // stage is not a large empty panel.
      expect(tester.takeException(), isNull);
      expect(button.left, greaterThan(overlay.right));
      expect(button.top, lessThan(overlay.bottom));
      expect(stage.height, lessThan(200));
    });
  }
}
