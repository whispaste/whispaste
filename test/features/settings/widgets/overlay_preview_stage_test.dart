/// WP-95: the settings preview stage is labelled, cannot be operated, and
/// reflows at large text scales and in RTL. Shows both button states, the
/// resting look and the recording look (2026-10-22).
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

const _idleKey = ValueKey('overlay-preview-floating-button-idle');
const _recordingKey = ValueKey('overlay-preview-floating-button-recording');

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

/// Opacity the button applies to its own disc (its resting fade).
double _opacityOf(WidgetTester tester, Key key) {
  return tester
      .widget<Opacity>(
        find.descendant(of: find.byKey(key), matching: find.byType(Opacity)),
      )
      .opacity;
}

void main() {
  testWidgets('recording button shows the recording look and ring', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(buttonLook: const FloatingButtonLook()));
    await tester.pump();

    final button = tester.widget<WpFloatingButtonView>(
      find.byKey(_recordingKey),
    );
    expect(button.state, FloatingButtonVisualState.recording);
    expect(
      WpFloatingButtonView.painterFor(
        state: button.state,
        look: button.look,
      ).spec.borderWidth,
      2.0,
      reason: 'the ring is drawn in the recording preview',
    );
  });

  testWidgets('resting button shows no ring and the resting opacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _stage(buttonLook: const FloatingButtonLook(idleOpacity: '40')),
    );
    await tester.pump();

    final idle = tester.widget<WpFloatingButtonView>(find.byKey(_idleKey));
    expect(idle.state, FloatingButtonVisualState.idle);
    expect(
      WpFloatingButtonView.painterFor(
        state: idle.state,
        look: idle.look,
      ).spec.borderWidth,
      isNot(2.0),
      reason: 'no ring at rest',
    );
    expect(_opacityOf(tester, _idleKey), 0.4);
    expect(
      _opacityOf(tester, _recordingKey),
      1.0,
      reason: 'a recording is always shown at full strength',
    );
  });

  testWidgets('both button states are shown with their own captions', (
    tester,
  ) async {
    await tester.pumpWidget(_stage());
    await tester.pump();
    final l10n = L10n.of(tester.element(find.byType(WpOverlayPreviewStage)));

    expect(find.text(l10n.settingsPreviewTitle), findsOneWidget);
    expect(find.text(l10n.settingsPreviewHint), findsOneWidget);
    expect(find.text(l10n.settingsPreviewOverlayCaption), findsOneWidget);
    expect(find.text(l10n.settingsFloatingButtonSection), findsOneWidget);
    expect(find.text(l10n.settingsPreviewButtonIdleCaption), findsOneWidget);
    expect(
      find.text(l10n.settingsPreviewButtonRecordingCaption),
      findsOneWidget,
    );
    expect(find.byKey(_idleKey), findsOneWidget);
    expect(find.byKey(_recordingKey), findsOneWidget);
  });

  testWidgets(
    'overlay and both button previews are excluded from hit testing',
    (tester) async {
      await tester.pumpWidget(_stage());
      await tester.pump();

      for (final key in [
        _idleKey,
        _recordingKey,
        const ValueKey('overlay-real-preview-normal'),
      ]) {
        final ignoring = find.ancestor(
          of: find.byKey(key),
          matching: find.byType(IgnorePointer),
        );
        expect(ignoring, findsWidgets, reason: '$key has no IgnorePointer');
        expect(
          tester.widget<IgnorePointer>(ignoring.first).ignoring,
          isTrue,
          reason: '$key takes pointer input',
        );
      }
    },
  );

  testWidgets(
    'the button previews are absent when the platform has no button',
    (tester) async {
      await tester.pumpWidget(_stage(showButton: false));
      await tester.pump();

      expect(find.byKey(_idleKey), findsNothing);
      expect(find.byKey(_recordingKey), findsNothing);
      expect(
        find.byKey(const ValueKey('overlay-real-preview-normal')),
        findsOneWidget,
      );
    },
  );

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

  // An 800 px window with the settings column, at the large text scale the
  // accessibility checks use, in both text directions.
  for (final direction in TextDirection.values) {
    testWidgets('fits an 800 px window at text scale 1.3 (${direction.name})', (
      tester,
    ) async {
      await tester.pumpWidget(
        _stage(
          width: 800,
          textScale: 1.3,
          direction: direction,
          locale: const Locale('de'),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(_recordingKey), findsOneWidget);
      expect(find.byKey(_idleKey), findsOneWidget);
    });
  }

  testWidgets('a wide stage keeps overlay and both button states in one row', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(width: 1100, locale: const Locale('de')));
    await tester.pump();

    final stage = tester.getRect(
      find.byKey(const ValueKey('overlay-preview-stage')),
    );
    final overlay = tester.getRect(find.byType(WpOverlayRealPreview));
    final idle = tester.getRect(find.byKey(_idleKey));
    final recording = tester.getRect(find.byKey(_recordingKey));

    // The pill keeps its own width instead of filling the stage, so both
    // buttons sit beside it and the stage is not a large empty panel.
    expect(tester.takeException(), isNull);
    expect(idle.left, greaterThan(overlay.right));
    expect(idle.top, lessThan(overlay.bottom));
    expect(recording.left, greaterThan(idle.right));
    expect(stage.height, lessThan(200));
  });

  testWidgets(
    'a narrow stage stacks the buttons below the pill without overflow',
    (tester) async {
      await tester.pumpWidget(_stage(width: 480, locale: const Locale('de')));
      await tester.pump();

      final overlay = tester.getRect(find.byType(WpOverlayRealPreview));
      final idle = tester.getRect(find.byKey(_idleKey));
      final recording = tester.getRect(find.byKey(_recordingKey));

      expect(tester.takeException(), isNull);
      expect(idle.top, greaterThanOrEqualTo(overlay.bottom));
      expect(recording.left, greaterThan(idle.right));
    },
  );
}
