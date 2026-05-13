import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('KeyboardShortcutSection', () {
    testWidgets('renders Hold to Record toggle inside the hotkey block', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(const KeyboardShortcutSection()));
      await tester.pumpAndSettle();

      expect(find.text('Hold to Record'), findsOneWidget);
    });
  });

  group('AudioSection', () {
    testWidgets('does NOT render Hold to Record toggle in audio block', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(const AudioSection()));
      await tester.pumpAndSettle();

      expect(find.text('Hold to Record'), findsNothing);
    });
  });
}
