import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/shared_render_engine_helpers.dart';

void main() {
  group('ClickOrDragGate', () {
    test('a press released without movement is a click', () {
      final gate = ClickOrDragGate();
      gate.press(const Offset(100, 100));
      expect(gate.release(), isTrue);
    });

    test('tremor up to 6 px still counts as a click and never drags', () {
      final gate = ClickOrDragGate();
      gate.press(const Offset(100, 100));
      expect(gate.move(const Offset(106, 100)), isFalse);
      expect(gate.move(const Offset(104, 104)), isFalse);
      expect(gate.move(const Offset(100, 94)), isFalse);
      expect(gate.release(), isTrue);
    });

    test('movement beyond the threshold starts a drag exactly once', () {
      final gate = ClickOrDragGate();
      gate.press(const Offset(100, 100));
      expect(gate.move(const Offset(120, 100)), isTrue);
      expect(gate.move(const Offset(130, 100)), isFalse);
      expect(gate.release(), isFalse, reason: 'a drag is not a click');
    });

    test('the threshold is measured from the press point, not from the last '
        'move', () {
      final gate = ClickOrDragGate(dragThreshold: 8);
      gate.press(const Offset(0, 0));
      expect(gate.move(const Offset(5, 0)), isFalse);
      expect(gate.move(const Offset(7, 0)), isFalse);
      expect(gate.move(const Offset(9, 0)), isTrue);
    });

    test('release resets the gate for the next press', () {
      final gate = ClickOrDragGate();
      gate.press(const Offset(0, 0));
      gate.move(const Offset(50, 0));
      gate.release();
      gate.press(const Offset(0, 0));
      expect(gate.release(), isTrue);
    });

    test('a release without a press is never a click', () {
      final gate = ClickOrDragGate();
      expect(gate.release(), isFalse);
    });

    test('cancel ends the gesture without a click', () {
      final gate = ClickOrDragGate();
      gate.press(const Offset(0, 0));
      gate.cancel();
      expect(gate.release(), isFalse);
    });
  });

  group('RenderEngineGestureLayer', () {
    Future<void> pumpLayer(
      WidgetTester tester, {
      required VoidCallback onTap,
      required VoidCallback onPanStart,
    }) {
      return tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 80,
              height: 80,
              child: RenderEngineGestureLayer(
                semanticsLabel: 'button',
                onTap: onTap,
                onPanStart: onPanStart,
                onSecondaryOrLongPress: () {},
                child: const ColoredBox(color: Color(0xFF000000)),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a click with 6 px tremor fires onTap and never onPanStart', (
      tester,
    ) async {
      var taps = 0;
      var drags = 0;
      await pumpLayer(tester, onTap: () => taps++, onPanStart: () => drags++);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(RenderEngineGestureLayer)),
      );
      await gesture.moveBy(const Offset(6, 0));
      await gesture.moveBy(const Offset(-3, 0));
      await gesture.up();
      await tester.pump();

      expect(taps, 1);
      expect(drags, 0);
    });

    testWidgets('moving past the threshold starts a drag and suppresses the '
        'click', (tester) async {
      var taps = 0;
      var drags = 0;
      await pumpLayer(tester, onTap: () => taps++, onPanStart: () => drags++);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(RenderEngineGestureLayer)),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pump();

      expect(drags, 1);
      expect(taps, 0);
    });
  });
}
