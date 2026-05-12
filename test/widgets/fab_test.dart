import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/fab.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpRecordingFab', () {
    testWidgets('renders without error in idle state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.idle, onPressed: () {}),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('shows mic icon when idle', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.idle, onPressed: () {}),
        ),
      );

      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.byIcon(LucideIcons.square), findsNothing);
    });

    testWidgets('shows stop (square) icon when recording', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.recording, onPressed: () {}),
        ),
      );
      await tester.pump(); // allow animation frame

      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.mic), findsNothing);
    });

    testWidgets('shows loader icon when transcribing', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.transcribing, onPressed: () {}),
        ),
      );
      await tester.pump();

      expect(find.byIcon(LucideIcons.loaderCircle), findsOneWidget);
    });

    testWidgets('shows check icon when done', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.done, onPressed: () {}),
        ),
      );

      expect(find.byIcon(LucideIcons.check), findsOneWidget);
    });

    testWidgets('shows alert icon when error', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.error, onPressed: () {}),
        ),
      );

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    });

    testWidgets('onPressed callback fires on tap in idle state', (
      tester,
    ) async {
      var pressed = false;

      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(
            phase: RecordingPhase.idle,
            onPressed: () => pressed = true,
          ),
        ),
      );

      await tester.tap(find.byType(WpRecordingFab));
      expect(pressed, isTrue);
    });

    testWidgets('tap is ignored during transcribing phase', (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(
            phase: RecordingPhase.transcribing,
            onPressed: () => pressed = true,
          ),
        ),
      );

      await tester.tap(find.byType(WpRecordingFab));
      expect(pressed, isFalse);
    });

    testWidgets('renders without error in recording state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.recording, onPressed: () {}),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('FAB container has the expected circular shape', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpRecordingFab(phase: RecordingPhase.idle, onPressed: () {}),
        ),
      );

      final container = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(WpRecordingFab),
              matching: find.byType(AnimatedContainer),
            )
            .last,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.shape, BoxShape.circle);
    });
  });
}
