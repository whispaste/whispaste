import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_banner.dart';
import 'package:whispaste/widgets/wp_text_link.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('the banner action fires its callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      makeTestable(
        WpBanner(
          tone: WpBannerTone.info,
          message: 'Update available',
          action: WpTextLink(label: 'Details', onPressed: () => taps++),
        ),
      ),
    );

    await tester.tap(find.byType(WpTextLink));
    expect(taps, 1);
  });

  // #835: the action goes under the message whenever the room beside it is
  // short, at any text scale; with room it stays beside the message.
  for (final (width, scale, below) in [
    (360.0, 1.0, true),
    (640.0, 1.3, true),
    (640.0, 1.0, false),
    (900.0, 1.3, false),
    (900.0, 1.5, true),
  ]) {
    testWidgets('action below the message: ${width}px, x$scale -> $below', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: WpBanner(
                    tone: WpBannerTone.warning,
                    message: 'The model could not be loaded right now.',
                    action: Wrap(
                      children: [
                        WpTextLink(label: 'Try again', onPressed: () {}),
                        WpTextLink(label: 'Settings', onPressed: () {}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final message = tester.getRect(
        find.text('The model could not be loaded right now.'),
      );
      final action = tester.getRect(find.byType(Wrap));
      expect(action.top >= message.bottom, below);
    });
  }
}
