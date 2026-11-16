import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart'
    show OverlayVisualState;
import 'package:whispaste/services/floating_overlay/overlay_notice_rules.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_notice_card.dart';

/// The lost-signal card in every window the shell may still hold while the
/// card arrives or leaves (#1059): no overflow, and in its own window the
/// stop and discard buttons are laid out inside the window.
void main() {
  for (final locale in L10n.supportedLocales) {
    final l10n = lookupL10n(locale);
    final notice = noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      signalLost: true,
    )!;
    final windows = <String, Size>{
      'notice': OverlayDesignSpec.noticeWindowSize,
      for (final v in OverlaySizeVariant.values)
        v.name: OverlayDesignSpec.windowSizeFor(v),
    };
    windows.forEach((name, window) {
      testWidgets('signal-lost card, $locale in $name window: no overflow', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Center(
                child: SizedBox.fromSize(
                  key: const ValueKey('window'),
                  size: window,
                  child: WpOverlayNoticeCard(
                    notice: notice,
                    colors: OverlayDesignSpec.colorsFor(),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        if (name == 'notice') {
          for (final id in const ['pasteSoFar', 'discardRecording']) {
            final a = notice.actions.firstWhere((x) => x.action.name == id);
            final rect = tester.getRect(
              find.bySemanticsIdentifier('overlay-notice-action-${a.testName}'),
            );
            expect(
              tester.getRect(find.byKey(const ValueKey('window'))),
              predicate<Rect>(
                (w) =>
                    w.inflate(1).contains(rect.topLeft) &&
                    w.inflate(1).contains(rect.bottomRight),
              ),
              reason: id,
            );
          }
        }
        handle.dispose();
      });
    });
  }
}
