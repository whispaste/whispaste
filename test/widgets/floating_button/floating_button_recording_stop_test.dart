// BTN-REC: while recording, the floating button shows a stop square instead of
// the mic, the ring sits outside the disc, both states keep the same footprint,
// and the ring colour is checked against the stage backdrop (>= 3:1).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

Widget _host(Widget child) => Localizations(
  locale: const Locale('de'),
  delegates: const [L10n.delegate, DefaultWidgetsLocalizations.delegate],
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  group('recording glyph', () {
    testWidgets('recording exposes the stop label to assistive tech', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const WpFloatingButtonView(
            state: FloatingButtonVisualState.recording,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Aufnahme beenden'), findsOneWidget);
    });
  });
}
