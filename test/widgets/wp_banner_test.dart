import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
}
