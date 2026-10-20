import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_banner.dart';
import 'package:whispaste/widgets/wp_text_link.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('shows the message with the icon for its tone', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const WpBanner(
          tone: WpBannerTone.warning,
          message: 'Paste needs a restart',
        ),
      ),
    );

    expect(find.text('Paste needs a restart'), findsOneWidget);
    expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
  });

  testWidgets('each tone uses its own icon', (tester) async {
    const expected = {
      WpBannerTone.info: LucideIcons.info,
      WpBannerTone.warning: LucideIcons.triangleAlert,
      WpBannerTone.error: LucideIcons.circleAlert,
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(
        makeTestable(WpBanner(tone: entry.key, message: 'x')),
      );
      expect(find.byIcon(entry.value), findsOneWidget, reason: entry.key.name);
    }
  });

  testWidgets('renders the action when given', (tester) async {
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

    await tester.tap(find.text('Details'));
    expect(taps, 1);
  });

  testWidgets('error fill comes from the error role', (tester) async {
    await tester.pumpWidget(
      makeTestable(const WpBanner(tone: WpBannerTone.error, message: 'Failed')),
    );

    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(WpBanner),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, WpColors.errorActiveFill);
  });

  testWidgets('warning is an amber soft fill with amber text and icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const WpBanner(tone: WpBannerTone.warning, message: 'Paste is off'),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(WpBanner),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, WpColors.highlightSoft);
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.triangleAlert));
    expect(icon.color, WpColors.highlightText);
  });
}
