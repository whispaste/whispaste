/// Hand-over point of #476: while the native shell draws the glass backdrop,
/// the render engine reports the animated pill width so the backdrop follows
/// the pill instead of staying as wide as the window.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap({
  required OverlayVisualState state,
  required bool nativeBackdrop,
}) => FloatingOverlaySnapshot(
  visible: true,
  state: state,
  background: OverlayBackground.glass,
  nativeBackdrop: nativeBackdrop,
  label: 'Done',
  elapsed: '0:03',
);

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  testWidgets('a width change under a native backdrop is reported', (
    tester,
  ) async {
    final widths = <double>[];
    Widget view(OverlayVisualState state, bool native) => _wrap(
      WpFloatingOverlayView(
        snapshot: _snap(state: state, nativeBackdrop: native),
        onPillWidth: (w, _) => widths.add(w),
      ),
    );

    await tester.pumpWidget(view(OverlayVisualState.recording, true));
    await tester.pump(const Duration(milliseconds: 16));
    final recording = widths.last;

    await tester.pumpWidget(view(OverlayVisualState.done, true));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));

    expect(widths.last, lessThan(recording));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('nothing is reported without a native backdrop', (tester) async {
    final widths = <double>[];
    await tester.pumpWidget(
      _wrap(
        WpFloatingOverlayView(
          snapshot: _snap(
            state: OverlayVisualState.recording,
            nativeBackdrop: false,
          ),
          onPillWidth: (w, _) => widths.add(w),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(widths, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a notice card reports 0 (full window width)', (tester) async {
    final widths = <double>[];
    await tester.pumpWidget(
      _wrap(
        WpFloatingOverlayView(
          snapshot: const FloatingOverlaySnapshot(
            visible: true,
            state: OverlayVisualState.recording,
            background: OverlayBackground.glass,
            nativeBackdrop: true,
            label: '',
            elapsed: '',
            notice: OverlayNotice(
              kind: OverlayNoticeKind.quiet,
              tone: OverlayNoticeTone.hint,
              title: 'Title',
              body: 'Body',
              actions: [],
            ),
          ),
          onPillWidth: (w, _) => widths.add(w),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(widths, isNotEmpty);
    expect(widths.last, 0.0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
