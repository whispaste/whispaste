import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';

void main() {
  group('OverlayVisualState', () {
    test('has all expected values', () {
      expect(OverlayVisualState.values, hasLength(5));
      expect(
        OverlayVisualState.values.map((e) => e.name),
        containsAll([
          'recording',
          'transcribing',
          'processing',
          'done',
          'error',
        ]),
      );
    });

    test('state names match C++ OverlayVisualState enum', () {
      // C++ ParseState expects lowercase names via MethodChannel.
      const expected = [
        'recording',
        'transcribing',
        'processing',
        'done',
        'error',
      ];
      expect(OverlayVisualState.values.map((e) => e.name).toList(), expected);
    });
  });

  group('OverlayAnchorMode', () {
    test('has all expected values', () {
      expect(OverlayAnchorMode.values, hasLength(3));
      expect(
        OverlayAnchorMode.values.map((e) => e.name),
        containsAll(['topCenter', 'bottomCenter', 'topLeft']),
      );
    });
  });

  group('FloatingOverlaySnapshot', () {
    test('toMap() serializes all fields', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        isDark: true,
        compact: false,
        label: 'Recording',
        elapsed: '0:05',
        hint: 'Press Ctrl+D to stop',
        transcript: 'Hello world',
        errorMessage: null,
        privacyMode: 'local',
        showRetry: false,
        doneMessage: null,
        processingLabel: null,
      );

      final map = snap.toMap();
      expect(map['visible'], true);
      expect(map['state'], 'recording');
      expect(map['isDark'], true);
      expect(map['compact'], false);
      expect(map['label'], 'Recording');
      expect(map['elapsed'], '0:05');
      expect(map['hint'], 'Press Ctrl+D to stop');
      expect(map['transcript'], 'Hello world');
      expect(map['errorMessage'], isNull);
      expect(map['privacyMode'], 'local');
      expect(map['showRetry'], false);
      expect(map['doneMessage'], isNull);
      expect(map['processingLabel'], isNull);
      expect(map['progress'], 0.0);
    });

    test('toMap() serializes nullable fields when present', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.error,
        isDark: false,
        compact: true,
        label: 'Error',
        errorMessage: 'Connection failed',
        showRetry: true,
      );

      final map = snap.toMap();
      expect(map['state'], 'error');
      expect(map['isDark'], false);
      expect(map['compact'], true);
      expect(map['errorMessage'], 'Connection failed');
      expect(map['showRetry'], true);
    });

    test('toMap() serializes done state correctly', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.done,
        isDark: true,
        compact: false,
        label: 'Done',
        doneMessage: 'Pasted!',
      );

      final map = snap.toMap();
      expect(map['state'], 'done');
      expect(map['doneMessage'], 'Pasted!');
    });

    test('toMap() serializes processing state correctly', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.processing,
        isDark: true,
        compact: false,
        label: 'Refining…',
        processingLabel: 'Polishing with AI…',
      );

      final map = snap.toMap();
      expect(map['state'], 'processing');
      expect(map['processingLabel'], 'Polishing with AI…');
    });

    test('toMap() includes all 14 keys', () {
      const snap = FloatingOverlaySnapshot(
        visible: false,
        state: OverlayVisualState.recording,
        isDark: true,
        compact: false,
        label: '',
      );

      final map = snap.toMap();
      expect(map.keys, hasLength(14));
      expect(map.keys.toSet(), {
        'visible',
        'state',
        'isDark',
        'compact',
        'label',
        'elapsed',
        'hint',
        'transcript',
        'errorMessage',
        'privacyMode',
        'showRetry',
        'doneMessage',
        'processingLabel',
        'progress',
      });
    });

    test('defaults are applied correctly', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        isDark: true,
        compact: false,
        label: 'Recording',
      );

      expect(snap.elapsed, '');
      expect(snap.hint, '');
      expect(snap.transcript, isNull);
      expect(snap.errorMessage, isNull);
      expect(snap.privacyMode, 'local');
      expect(snap.showRetry, false);
      expect(snap.doneMessage, isNull);
      expect(snap.processingLabel, isNull);
      expect(snap.progress, 0.0);
    });
  });

  group('FloatingOverlayController factory', () {
    test('create() does not throw', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      // On Windows: creates WindowsFloatingOverlayController.
      // On CI (Linux): returns null since Platform.isWindows is false.
      final controller = FloatingOverlayController.create();
      if (controller != null) {
        expect(controller, isA<FloatingOverlayController>());
      }
      // Don't call dispose() — it invokes the MethodChannel which has
      // no native handler in test.
    });
  });

  group('FloatingOverlayEvent', () {
    test('OverlayCloseClicked is sealed', () {
      const event = OverlayCloseClicked();
      expect(event, isA<FloatingOverlayEvent>());
    });

    test('OverlayBodyClicked is sealed', () {
      const event = OverlayBodyClicked();
      expect(event, isA<FloatingOverlayEvent>());
    });

    test('OverlayRetryClicked is sealed', () {
      const event = OverlayRetryClicked();
      expect(event, isA<FloatingOverlayEvent>());
    });

    test('OverlayDragEnded carries coordinates and anchor', () {
      const event = OverlayDragEnded(150.5, 300.7, 'topLeft');
      expect(event.x, 150.5);
      expect(event.y, 300.7);
      expect(event.anchorMode, 'topLeft');
      expect(event, isA<FloatingOverlayEvent>());
    });

    test('OverlayContextMenuAction carries action string', () {
      const event = OverlayContextMenuAction('switch_compact');
      expect(event.action, 'switch_compact');
      expect(event, isA<FloatingOverlayEvent>());
    });
  });

  group('MockFloatingOverlayController', () {
    late MockFloatingOverlayController controller;

    setUp(() {
      controller = MockFloatingOverlayController();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('updateSnapshot() records call with serialized map', () async {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        isDark: true,
        compact: false,
        label: 'Recording',
        elapsed: '0:12',
      );
      await controller.updateSnapshot(snap);
      expect(controller.calls, hasLength(1));
      expect(controller.calls.first, startsWith('updateSnapshot('));
      expect(controller.lastSnapshot?.visible, true);
      expect(controller.lastSnapshot?.state, OverlayVisualState.recording);
      expect(controller.lastSnapshot?.elapsed, '0:12');
    });

    test('setAudioLevel() records level', () async {
      await controller.setAudioLevel(0.75);
      expect(controller.calls, ['setAudioLevel(0.75)']);
    });

    test('setPosition() records coordinates and anchor', () async {
      await controller.setPosition(100, 200, OverlayAnchorMode.bottomCenter);
      expect(controller.calls, ['setPosition(100.0, 200.0, bottomCenter)']);
    });

    test('setContextMenuItems() records items', () async {
      await controller.setContextMenuItems([
        (id: 'cancel', label: 'Cancel recording'),
        (id: 'hide', label: 'Hide overlay'),
      ]);
      expect(controller.calls, hasLength(1));
      expect(controller.calls.first, startsWith('setContextMenuItems('));
    });

    test('events stream emits events', () async {
      final events = <FloatingOverlayEvent>[];
      controller.events.listen(events.add);

      controller.emitEvent(const OverlayCloseClicked());
      controller.emitEvent(const OverlayDragEnded(10, 20, 'topLeft'));
      controller.emitEvent(const OverlayRetryClicked());
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(3));
      expect(events[0], isA<OverlayCloseClicked>());
      expect(events[1], isA<OverlayDragEnded>());
      expect(events[2], isA<OverlayRetryClicked>());
    });

    test('dispose() records call and closes stream', () async {
      await controller.dispose();
      expect(controller.calls, contains('dispose'));
      expect(controller.isDisposed, true);
    });

    test('calls after dispose() are no-ops', () async {
      await controller.dispose();
      // These should not throw.
      await controller.updateSnapshot(
        const FloatingOverlaySnapshot(
          visible: true,
          state: OverlayVisualState.done,
          isDark: true,
          compact: false,
          label: 'Done',
        ),
      );
      await controller.setAudioLevel(0.5);
      // Only 'dispose' should be in calls.
      expect(controller.calls, ['dispose']);
    });
  });
}

/// A mock [FloatingOverlayController] for testing service logic.
///
/// Records all calls, stores the last snapshot, and provides a way to emit
/// events for testing event handling.
class MockFloatingOverlayController extends FloatingOverlayController {
  final List<String> calls = [];
  final _eventController = StreamController<FloatingOverlayEvent>.broadcast();
  FloatingOverlaySnapshot? lastSnapshot;
  bool isDisposed = false;

  @override
  Stream<FloatingOverlayEvent> get events => _eventController.stream;

  void emitEvent(FloatingOverlayEvent event) {
    if (!isDisposed) _eventController.add(event);
  }

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    if (isDisposed) return;
    lastSnapshot = snapshot;
    calls.add(
      'updateSnapshot(${snapshot.state.name}, visible=${snapshot.visible})',
    );
  }

  @override
  Future<void> setAudioLevel(double level) async {
    if (isDisposed) return;
    calls.add('setAudioLevel($level)');
  }

  @override
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor) async {
    if (isDisposed) return;
    calls.add('setPosition($x, $y, ${anchor.name})');
  }

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {
    if (isDisposed) return;
    calls.add('setContextMenuItems(${items.length} items)');
  }

  @override
  Future<void> setOpacity(double opacity) async {
    if (isDisposed) return;
    calls.add('setOpacity($opacity)');
  }

  @override
  Future<void> dispose() async {
    if (isDisposed) return;
    isDisposed = true;
    calls.add('dispose');
    await _eventController.close();
  }
}
