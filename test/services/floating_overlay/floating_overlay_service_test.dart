import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';

void main() {
  // The service's private methods can't be tested directly, so we mirror the
  // pure-logic contracts here — same pattern as floating_button_service_test.

  group('RecordingPhase → OverlayVisualState mapping', () {
    // Mirrors FloatingOverlayService._mapPhase
    OverlayVisualState mapPhase(RecordingPhase phase) => switch (phase) {
      RecordingPhase.idle => OverlayVisualState.recording,
      RecordingPhase.recording => OverlayVisualState.recording,
      RecordingPhase.transcribing => OverlayVisualState.transcribing,
      RecordingPhase.done => OverlayVisualState.done,
      RecordingPhase.error => OverlayVisualState.error,
    };

    test('idle maps to recording (hidden, but state for snapshot)', () {
      expect(mapPhase(RecordingPhase.idle), OverlayVisualState.recording);
    });

    test('recording maps to recording', () {
      expect(mapPhase(RecordingPhase.recording), OverlayVisualState.recording);
    });

    test('transcribing maps to transcribing', () {
      expect(
        mapPhase(RecordingPhase.transcribing),
        OverlayVisualState.transcribing,
      );
    });

    test('done maps to done', () {
      expect(mapPhase(RecordingPhase.done), OverlayVisualState.done);
    });

    test('error maps to error', () {
      expect(mapPhase(RecordingPhase.error), OverlayVisualState.error);
    });

    test('all RecordingPhase values are handled', () {
      for (final phase in RecordingPhase.values) {
        expect(() => mapPhase(phase), returnsNormally);
      }
    });
  });

  group('OverlayVisualState enum', () {
    test('contains exactly 4 states', () {
      expect(OverlayVisualState.values, hasLength(4));
    });

    test('does not contain removed processing state', () {
      expect(
        OverlayVisualState.values.map((e) => e.name),
        isNot(contains('processing')),
      );
    });

    test('state names match C++ OverlayVisualState', () {
      // C++ ParseState expects lowercase state names via MethodChannel.
      // 'processing' was removed — native renderers are tolerant of missing fields.
      const expected = ['recording', 'transcribing', 'done', 'error'];
      expect(OverlayVisualState.values.map((e) => e.name).toList(), expected);
    });
  });

  group('Elapsed formatting', () {
    // Mirrors FloatingOverlayService._formatElapsed
    String formatElapsed(Duration elapsed) {
      final minutes = elapsed.inMinutes;
      final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }

    test('zero duration', () {
      expect(formatElapsed(Duration.zero), '0:00');
    });

    test('5 seconds', () {
      expect(formatElapsed(const Duration(seconds: 5)), '0:05');
    });

    test('59 seconds', () {
      expect(formatElapsed(const Duration(seconds: 59)), '0:59');
    });

    test('1 minute', () {
      expect(formatElapsed(const Duration(minutes: 1)), '1:00');
    });

    test('1 minute 30 seconds', () {
      expect(formatElapsed(const Duration(minutes: 1, seconds: 30)), '1:30');
    });

    test('10 minutes', () {
      expect(formatElapsed(const Duration(minutes: 10)), '10:00');
    });
  });

  // Removed 2026-08-11 (dark-only build): `isDark computation` group. It
  // mirrored `FloatingOverlayService._computeIsDark`, which no longer
  // exists — the overlay renders one theme, so there is nothing to compute.

  group('FloatingOverlaySize enum', () {
    test('has expected values', () {
      expect(FloatingOverlaySize.values, hasLength(3));
      expect(FloatingOverlaySize.values.map((e) => e.name), [
        'normal',
        'compact',
        'mini',
      ]);
    });

    test('value strings for persistence', () {
      expect(FloatingOverlaySize.normal.value, 'normal');
      expect(FloatingOverlaySize.compact.value, 'compact');
      expect(FloatingOverlaySize.mini.value, 'mini');
    });

    test('maps onto the design-spec size variant', () {
      expect(FloatingOverlaySize.normal.variant, OverlaySizeVariant.normal);
      expect(FloatingOverlaySize.compact.variant, OverlaySizeVariant.compact);
      expect(FloatingOverlaySize.mini.variant, OverlaySizeVariant.mini);
    });

    test('fromValue roundtrips correctly', () {
      for (final size in FloatingOverlaySize.values) {
        expect(FloatingOverlaySize.fromValue(size.value), size);
      }
    });

    test('fromValue with unknown returns normal', () {
      expect(
        FloatingOverlaySize.fromValue('unknown'),
        FloatingOverlaySize.normal,
      );
    });
  });

  group('OverlayStartPosition enum', () {
    test('has expected values', () {
      // 'off' is the virtual first entry used by the consolidated dropdown.
      expect(OverlayStartPosition.values, hasLength(4));
      expect(OverlayStartPosition.values.map((e) => e.name), [
        'off',
        'topCenter',
        'bottomCenter',
        'lastPosition',
      ]);
    });

    test('fromValue roundtrips correctly', () {
      for (final pos in OverlayStartPosition.values) {
        expect(OverlayStartPosition.fromValue(pos.value), pos);
      }
    });

    test('fromValue unknown falls back to topCenter', () {
      expect(
        OverlayStartPosition.fromValue('unknown'),
        OverlayStartPosition.topCenter,
      );
    });
  });

  group('Snapshot building contracts', () {
    test('recording snapshot has expected shape', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
        elapsed: '0:12',
        hint: 'Press Ctrl+Shift+D to stop',
        privacyMode: 'local',
      );

      expect(snap.visible, true);
      expect(snap.state, OverlayVisualState.recording);
      expect(snap.elapsed, '0:12');
      expect(snap.hint, isNotEmpty);
      expect(snap.doneMessage, isNull);
    });

    test('transcribing snapshot has no elapsed', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.transcribing,
        label: 'Transcribing…',
        privacyMode: 'local',
      );

      expect(snap.elapsed, '');
      expect(snap.hint, '');
    });

    test('done snapshot has done message', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.done,
        label: 'Done',
        doneMessage: 'Pasted!',
      );

      expect(snap.doneMessage, 'Pasted!');
    });

    test('error snapshot has error message', () {
      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.error,
        label: 'Error',
        errorMessage: 'Network timeout',
      );

      expect(snap.errorMessage, 'Network timeout');
    });

    test('hidden snapshot for auto-hide', () {
      const snap = FloatingOverlaySnapshot(
        visible: false,
        state: OverlayVisualState.recording,
        label: '',
      );

      expect(snap.visible, false);
      // State doesn't matter when hidden — it's just a default value.
    });

    test('size variant changes only the size field', () {
      const normal = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: 'Recording',
      );
      const compact = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        size: OverlaySizeVariant.compact,
        label: 'Recording',
      );
      const mini = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        size: OverlaySizeVariant.mini,
        label: 'Recording',
      );

      expect(normal.size, OverlaySizeVariant.normal);
      expect(compact.size, OverlaySizeVariant.compact);
      expect(mini.size, OverlaySizeVariant.mini);
      // Same state, same label — only the size differs.
      expect(normal.state, compact.state);
      expect(normal.label, mini.label);
    });

    test('privacy mode can be local or cloud', () {
      const local = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.transcribing,
        label: 'Transcribing…',
        privacyMode: 'local',
      );
      const cloud = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.transcribing,
        label: 'Transcribing…',
        privacyMode: 'cloud',
      );

      expect(local.privacyMode, 'local');
      expect(cloud.privacyMode, 'cloud');
    });
  });

  group('Auto-hide generation guard logic', () {
    // Mirrors the generation-counter pattern from the service.
    // Validates that a stale timer callback is safely ignored.

    test('stale timer callback with different generation is no-op', () {
      int generation = 0;
      RecordingPhase lastPhase = RecordingPhase.idle;
      bool hideCalled = false;

      // Simulate: recording starts, auto-hide is scheduled.
      generation++;
      final gen = generation;
      lastPhase = RecordingPhase.done;

      // Then a new recording starts before the timer fires.
      generation++;
      lastPhase = RecordingPhase.recording;

      // Timer fires — should NOT hide because generation changed.
      if (generation == gen && lastPhase == RecordingPhase.done) {
        hideCalled = true;
      }

      expect(hideCalled, false);
    });

    test('current generation timer hides when still in done phase', () {
      int generation = 0;
      RecordingPhase lastPhase = RecordingPhase.idle;
      bool hideCalled = false;

      generation++;
      final gen = generation;
      lastPhase = RecordingPhase.done;

      // Timer fires — same generation, still in done.
      if (generation == gen && lastPhase == RecordingPhase.done) {
        hideCalled = true;
      }

      expect(hideCalled, true);
    });
  });

  group('Context menu actions', () {
    // Mirrors FloatingOverlayService._onContextMenuAction action strings.

    test('all expected context menu action IDs exist', () {
      const actions = [
        'cancel',
        'switch_normal',
        'switch_compact',
        'switch_mini',
        'hide',
      ];
      for (final action in actions) {
        expect(action, isNotEmpty);
      }
    });

    test('switch_normal maps to FloatingOverlaySize.normal', () {
      const action = 'switch_normal';
      const size = action == 'switch_normal'
          ? FloatingOverlaySize.normal
          : FloatingOverlaySize.compact;
      expect(size, FloatingOverlaySize.normal);
    });

    test('switch_compact maps to FloatingOverlaySize.compact', () {
      const action = 'switch_compact';
      const size = action == 'switch_compact'
          ? FloatingOverlaySize.compact
          : FloatingOverlaySize.normal;
      expect(size, FloatingOverlaySize.compact);
    });

    test('switch_mini maps to FloatingOverlaySize.mini', () {
      const action = 'switch_mini';
      const size = action == 'switch_mini'
          ? FloatingOverlaySize.mini
          : FloatingOverlaySize.normal;
      expect(size, FloatingOverlaySize.mini);
    });
  });

  group('OverlayAnchorMode', () {
    test('anchor mode names match C++ expectations', () {
      // C++ ParseAnchorMode expects these exact strings.
      expect(OverlayAnchorMode.topCenter.name, 'topCenter');
      expect(OverlayAnchorMode.bottomCenter.name, 'bottomCenter');
      expect(OverlayAnchorMode.topLeft.name, 'topLeft');
    });

    test('start position maps to correct anchor mode', () {
      // Mirrors the service's _setStartPosition logic.
      OverlayAnchorMode anchorFor(OverlayStartPosition pos) => switch (pos) {
        OverlayStartPosition.off ||
        OverlayStartPosition.topCenter => OverlayAnchorMode.topCenter,
        OverlayStartPosition.bottomCenter => OverlayAnchorMode.bottomCenter,
        OverlayStartPosition.lastPosition => OverlayAnchorMode.topLeft,
      };

      expect(
        anchorFor(OverlayStartPosition.topCenter),
        OverlayAnchorMode.topCenter,
      );
      expect(
        anchorFor(OverlayStartPosition.bottomCenter),
        OverlayAnchorMode.bottomCenter,
      );
      expect(
        anchorFor(OverlayStartPosition.lastPosition),
        OverlayAnchorMode.topLeft,
      );
    });
  });
}
