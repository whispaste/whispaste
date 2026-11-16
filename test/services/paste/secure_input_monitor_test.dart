import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/paste/secure_input_monitor.dart';

/// Replays [states] one sample per call (the last one repeats) and counts
/// holder lookups.
class _FakeProbe implements SecureInputProbe {
  _FakeProbe(this._states, {this.holder, this.holderError});

  final List<SecureInputState> _states;
  final SecureInputHolder? holder;
  final Object? holderError;
  int holderCalls = 0;
  int _next = 0;

  @override
  Future<SecureInputState> secureInputState() async {
    final i = _next < _states.length ? _next : _states.length - 1;
    _next++;
    return _states[i];
  }

  @override
  Future<SecureInputHolder?> secureInputHolder() async {
    holderCalls++;
    if (holderError != null) throw holderError!;
    return holder;
  }
}

void main() {
  group('SecureInputTransitionTracker', () {
    test('a first sample with secure input off is no change', () {
      expect(SecureInputTransitionTracker().observe(false), isNull);
    });

    test('a first sample with secure input on is a change to on', () {
      expect(
        SecureInputTransitionTracker().observe(true),
        SecureInputTransition.on,
      );
    });

    test('a steady state yields no transition', () {
      final tracker = SecureInputTransitionTracker()..observe(true);
      expect(tracker.observe(true), isNull);
      expect(tracker.observe(true), isNull);
    });

    test('off to on and back yields one transition each', () {
      final tracker = SecureInputTransitionTracker()..observe(false);
      expect(tracker.observe(true), SecureInputTransition.on);
      expect(tracker.observe(true), isNull);
      expect(tracker.observe(false), SecureInputTransition.off);
      expect(tracker.observe(false), isNull);
    });
  });

  group('SecureInputLogMonitor', () {
    test(
      'logs on with the holder and off when it ends, nothing between',
      () async {
        final probe = _FakeProbe(
          [
            SecureInputState.inactive,
            SecureInputState.active,
            SecureInputState.active,
            SecureInputState.active,
            SecureInputState.inactive,
          ],
          holder: const SecureInputHolder(
            name: 'Terminal',
            bundleId: 'com.apple.Terminal',
            pid: 4242,
          ),
        );
        final lines = <String>[];
        final monitor = SecureInputLogMonitor(probe, log: lines.add);

        for (var i = 0; i < 5; i++) {
          await monitor.tick();
        }

        expect(lines, [
          'Secure input on, held by Terminal (pid 4242).',
          'Secure input off.',
        ]);
        // The holder is looked up once, on the change to on, never while it
        // stays on.
        expect(probe.holderCalls, 1);
      },
    );

    test('a failing holder lookup still logs the transition to on', () async {
      final probe = _FakeProbe([
        SecureInputState.active,
      ], holderError: StateError('no holder'));
      final lines = <String>[];

      await SecureInputLogMonitor(probe, log: lines.add).tick();

      expect(lines, ['Secure input on, holder unknown.']);
    });

    test(
      'an app without a name is named by its bundle id, else generically',
      () async {
        final lines = <String>[];
        await SecureInputLogMonitor(
          _FakeProbe([
            SecureInputState.active,
          ], holder: const SecureInputHolder(bundleId: 'com.example.Tool')),
          log: lines.add,
        ).tick();
        await SecureInputLogMonitor(
          _FakeProbe([
            SecureInputState.active,
          ], holder: const SecureInputHolder()),
          log: lines.add,
        ).tick();

        expect(lines, [
          'Secure input on, held by com.example.Tool.',
          'Secure input on, held by an unnamed app.',
        ]);
      },
    );

    test(
      'unsupported samples are ignored and never count as a change',
      () async {
        final probe = _FakeProbe([
          SecureInputState.unsupported,
          SecureInputState.inactive,
          SecureInputState.unsupported,
        ]);
        final lines = <String>[];
        final monitor = SecureInputLogMonitor(probe, log: lines.add);

        for (var i = 0; i < 3; i++) {
          await monitor.tick();
        }

        expect(lines, isEmpty);
        expect(probe.holderCalls, 0);
      },
    );
  });
}
