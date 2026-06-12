import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';

void main() {
  group('FloatingButtonVisualState', () {
    test('has all expected values', () {
      expect(FloatingButtonVisualState.values, hasLength(6));
      expect(
        FloatingButtonVisualState.values.map((e) => e.name),
        containsAll([
          'idle',
          'recording',
          'transcribing',
          'done',
          'error',
          'disabled',
        ]),
      );
    });
  });

  group('FloatingButtonController factory', () {
    test('create() does not throw', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      // On Windows test VM: creates a WindowsFloatingButtonController.
      // On CI (Linux): returns null since Platform.isWindows is false.
      // We just verify the factory doesn't throw.
      final controller = createFloatingButtonController();
      // On Windows: non-null controller. On Linux/macOS CI: null.
      if (controller != null) {
        expect(controller, isA<FloatingButtonController>());
      }
      // Don't call dispose() — it would invoke the MethodChannel which has
      // no native handler in test. The controller is GC'd.
    });
  });

  group('FloatingButtonEvent', () {
    test('FloatingButtonClicked is sealed', () {
      const event = FloatingButtonClicked();
      expect(event, isA<FloatingButtonEvent>());
    });

    test('FloatingButtonSecondaryClicked is sealed', () {
      const event = FloatingButtonSecondaryClicked();
      expect(event, isA<FloatingButtonEvent>());
    });

    test('FloatingButtonDragEnded carries coordinates', () {
      const event = FloatingButtonDragEnded(100.5, 200.3);
      expect(event.x, 100.5);
      expect(event.y, 200.3);
      expect(event, isA<FloatingButtonEvent>());
    });
  });

  group('MockFloatingButtonController', () {
    late _MockController controller;

    setUp(() {
      controller = _MockController();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('show() records call', () async {
      await controller.show(x: 10, y: 20, size: 48);
      expect(controller.calls, ['show(10.0, 20.0, 48)']);
    });

    test('hide() records call', () async {
      await controller.hide();
      expect(controller.calls, ['hide']);
    });

    test('setState() records call', () async {
      await controller.setState(FloatingButtonVisualState.recording);
      expect(controller.calls, ['setState(recording)']);
    });

    test('setTheme() records call', () async {
      await controller.setTheme(isDark: true);
      expect(controller.calls, ['setTheme(true)']);
    });

    test('setPosition() records call', () async {
      await controller.setPosition(50, 60);
      expect(controller.calls, ['setPosition(50.0, 60.0)']);
    });

    test('setSize() records call', () async {
      await controller.setSize(72);
      expect(controller.calls, ['setSize(72)']);
    });

    test('getPosition() returns stored position', () async {
      controller.positionToReturn = (x: 42.0, y: 84.0);
      final pos = await controller.getPosition();
      expect(pos?.x, 42.0);
      expect(pos?.y, 84.0);
    });

    test('events stream emits events', () async {
      final events = <FloatingButtonEvent>[];
      controller.events.listen(events.add);

      controller.emitEvent(const FloatingButtonClicked());
      controller.emitEvent(const FloatingButtonDragEnded(1, 2));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[0], isA<FloatingButtonClicked>());
      expect(events[1], isA<FloatingButtonDragEnded>());
    });
  });
}

/// A mock [FloatingButtonController] for testing service logic.
class _MockController extends FloatingButtonController {
  final List<String> calls = [];
  final _eventController = StreamController<FloatingButtonEvent>.broadcast();
  ({double x, double y})? positionToReturn;

  @override
  Stream<FloatingButtonEvent> get events => _eventController.stream;

  void emitEvent(FloatingButtonEvent event) {
    _eventController.add(event);
  }

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {
    calls.add('show($x, $y, $size)');
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
  }

  @override
  Future<void> setState(FloatingButtonVisualState state) async {
    calls.add('setState(${state.name})');
  }

  @override
  Future<void> setTheme({required bool isDark}) async {
    calls.add('setTheme($isDark)');
  }

  @override
  Future<void> setPosition(double x, double y) async {
    calls.add('setPosition($x, $y)');
  }

  @override
  Future<void> setSize(int size) async {
    calls.add('setSize($size)');
  }

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async {
    calls.add('setContextMenuItems(${items.length})');
  }

  @override
  Future<({double x, double y})?> getPosition() async {
    calls.add('getPosition');
    return positionToReturn;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _eventController.close();
  }
}
