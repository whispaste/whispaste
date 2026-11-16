import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_notice_card.dart';

void main() {
  testWidgets('a screen-reader tap triggers the button and the close cross', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final pressed = <OverlayNoticeActionId>[];
    final colors = OverlayDesignSpec.colorsFor();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: WpOverlayNoticeCard(
            notice: const OverlayNotice(
              kind: OverlayNoticeKind.message,
              tone: OverlayNoticeTone.hint,
              title: 'Title',
              body: 'Body',
              footer: 'F12: close',
              actions: [
                OverlayNoticeAction(
                  action: OverlayNoticeActionId.notice1,
                  label: 'Open',
                  name: 'open',
                ),
                OverlayNoticeAction(
                  action: OverlayNoticeActionId.dismiss,
                  label: 'Close',
                ),
              ],
            ),
            colors: colors,
            onAction: pressed.add,
          ),
        ),
      ),
    );
    for (final id in ['open', 'dismiss']) {
      final finder = find.semantics.byPredicate(
        (n) => n.identifier == 'overlay-notice-action-$id',
      );
      expect(finder, findsOneWidget);
      tester.semantics.tap(finder);
    }
    expect(pressed, [
      OverlayNoticeActionId.notice1,
      OverlayNoticeActionId.dismiss,
    ]);
    handle.dispose();
  });

  // The native shell may still have the pill's window for a frame when the
  // card arrives or leaves (#1193); that frame must not raise an overflow.
  for (final variant in OverlaySizeVariant.values) {
    testWidgets('the card in a ${variant.name} window raises no overflow', (
      tester,
    ) async {
      final window = OverlayDesignSpec.windowSizeFor(variant);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Center(
              child: SizedBox.fromSize(
                size: window,
                child: WpOverlayNoticeCard(
                  notice: const OverlayNotice(
                    kind: OverlayNoticeKind.message,
                    tone: OverlayNoticeTone.error,
                    title: 'Title',
                    body: 'Body',
                    footer: 'F12: close',
                    actions: [
                      OverlayNoticeAction(
                        action: OverlayNoticeActionId.notice1,
                        label: 'Open',
                        name: 'open',
                      ),
                    ],
                  ),
                  colors: OverlayDesignSpec.colorsFor(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
