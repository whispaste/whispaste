import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hotkey_self_heal.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('hotkey recorder listening limit (#113)', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 11, 2, 9);
      HotkeyCaptureGuard.clock = () => now;
    });

    tearDown(HotkeyCaptureGuard.reset);

    DateTime pastLimit() =>
        now.add(kHotkeyCaptureListenLimit + const Duration(seconds: 1));

    testWidgets('the dialog closes as cancelled, and the hotkeys are back', (
      tester,
    ) async {
      var answered = false;
      WpHotkeyResult? result;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await WpHotkeyRecorderDialog.show(
                  context,
                  initialKey: 'D',
                  initialModifiers: 'ctrl+shift',
                );
                answered = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(HotkeyCaptureGuard.listening, isTrue);

      expect(HotkeyCaptureGuard.releaseStale(pastLimit()), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(WpHotkeyRecorderDialog), findsNothing);
      expect(answered, isTrue);
      expect(result, isNull, reason: 'same result as Cancel: nothing saved');
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(HotkeyCaptureGuard.active, isFalse);
    });

    testWidgets('inline, the card returns to the saved combination and '
        'records again only after a click', (tester) async {
      final submitted = <WpHotkeyResult>[];
      await tester.pumpWidget(
        makeTestable(
          WpHotkeyRecorderDialog(
            initialKey: 'R',
            initialModifiers: 'ctrl+shift',
            onSubmit: submitted.add,
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();
      expect(HotkeyCaptureGuard.listening, isTrue);

      final hint = find.byKey(
        const ValueKey('onboarding-hotkey-capture-timeout-hint'),
      );
      expect(hint, findsNothing);
      expect(HotkeyCaptureGuard.releaseStale(pastLimit()), isTrue);
      await tester.pump();
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(find.text('R'), findsOneWidget);
      expect(hint, findsOneWidget);

      // Keys do not reach the recorder while it is not listening.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(submitted, isEmpty);

      // A click on the card listens again and clears the hint.
      await tester.tap(find.byKey(const ValueKey('hotkey-recorder-field')));
      await tester.pump();
      expect(HotkeyCaptureGuard.listening, isTrue);
      expect(hint, findsNothing);
    });
  });
}
