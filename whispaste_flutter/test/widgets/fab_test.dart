import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/fab.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpRecordingFab', () {
    testWidgets('renders without error in idle state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(isRecording: false, onPressed: () {}),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('shows mic icon when not recording', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(isRecording: false, onPressed: () {}),
        ),
      );

      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.byIcon(LucideIcons.square), findsNothing);
    });

    testWidgets('shows stop (square) icon when recording', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(isRecording: true, onPressed: () {}),
        ),
      );
      await tester.pump(); // allow animation frame

      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.mic), findsNothing);
    });

    testWidgets('onPressed callback fires on tap', (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(
            isRecording: false,
            onPressed: () => pressed = true,
          ),
        ),
      );

      await tester.tap(find.byType(WpRecordingFab));
      expect(pressed, isTrue);
    });

    testWidgets('renders without error in recording state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(isRecording: true, onPressed: () {}),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('FAB container has the expected circular shape',
        (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(isRecording: false, onPressed: () {}),
        ),
      );

      // The outermost Container inside GestureDetector has a circular shape
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(WpRecordingFab),
          matching: find.byType(Container),
        ).last,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.shape, BoxShape.circle);
    });
  });
}
