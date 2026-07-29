import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/permissions/startup_permission_gate.dart';

/// Records every hook invocation in order so tests can assert both outcomes
/// and sequencing (mic strictly before Auto-Paste, alert before settings,
/// no probe on the happy path, …).
class _GateHarness {
  final List<String> calls = [];

  /// Permission answers consumed per call, keyed by the `request` flag.
  /// When a queue runs empty the last value is repeated.
  List<bool> statusReads = [false];
  List<bool> promptedReads = [false];
  bool captureWorks = true;
  bool micGrantAlertThrows = false;
  bool micGrantAlertConfirmed = true;
  bool autoPasteGrantAlertConfirmed = true;

  AutoPasteGateStatus autoPasteStatus = AutoPasteGateStatus.notNeeded;

  int _statusIndex = 0;

  Future<bool> checkPermission({required bool request}) async {
    if (request) {
      calls.add('mic.prompt');
      return promptedReads.first;
    }
    calls.add('mic.status');
    final index = _statusIndex < statusReads.length
        ? _statusIndex
        : statusReads.length - 1;
    _statusIndex++;
    return statusReads[index];
  }

  MicGateHooks get mic => MicGateHooks(
    checkPermission: checkPermission,
    verifyCapture: () async {
      calls.add('mic.verifyCapture');
      return captureWorks;
    },
    showGrantAlert: () async {
      calls.add('mic.grantAlert');
      if (micGrantAlertThrows) throw StateError('channel down');
      return micGrantAlertConfirmed;
    },
    openSettings: () async => calls.add('mic.openSettings'),
    showRestartAlert: () async => calls.add('mic.restartAlert'),
  );

  AutoPasteGateHooks get autoPaste => AutoPasteGateHooks(
    readStatus: () async {
      calls.add('ap.readStatus');
      return autoPasteStatus;
    },
    showGrantAlert: () async {
      calls.add('ap.grantAlert');
      return autoPasteGrantAlertConfirmed;
    },
    startGrantFlow: () async => calls.add('ap.startGrantFlow'),
    showManualGrantAlert: () async => calls.add('ap.manualAlert'),
  );

  StartupPermissionGate gate({bool withAutoPaste = true}) =>
      StartupPermissionGate(
        mic: mic,
        autoPaste: withAutoPaste ? autoPaste : null,
        micPollInterval: const Duration(milliseconds: 5),
        micPollTimeout: const Duration(milliseconds: 40),
      );
}

void main() {
  group('microphone leg', () {
    test('already granted: no prompt, no alert, no capture probe', () async {
      final h = _GateHarness()..statusReads = [true];
      final result = await h.gate(withAutoPaste: false).run();

      expect(result.mic, MicGateOutcome.alreadyGranted);
      expect(h.calls, ['mic.status']);
    });

    test('notDetermined: OS prompt fires once and grants live', () async {
      final h = _GateHarness()
        ..statusReads = [false]
        ..promptedReads = [true];
      final result = await h.gate(withAutoPaste: false).run();

      expect(result.mic, MicGateOutcome.grantedViaPrompt);
      expect(h.calls, ['mic.status', 'mic.prompt']);
    });

    test(
      'denied → settings handoff → poll sees grant → capture works live',
      () async {
        final h = _GateHarness()
          // First status read false (initial), polls: false, then true.
          ..statusReads = [false, false, true]
          ..promptedReads = [false]
          ..captureWorks = true;
        final result = await h.gate(withAutoPaste: false).run();

        expect(result.mic, MicGateOutcome.recoveredLive);
        expect(h.calls, [
          'mic.status',
          'mic.prompt',
          'mic.grantAlert',
          'mic.openSettings',
          'mic.status',
          'mic.status',
          'mic.verifyCapture',
        ]);
      },
    );

    test(
      'poll sees grant but capture still fails → forced restart alert',
      () async {
        final h = _GateHarness()
          ..statusReads = [false, true]
          ..promptedReads = [false]
          ..captureWorks = false;
        final result = await h.gate(withAutoPaste: false).run();

        expect(result.mic, MicGateOutcome.recoveredNeedsRestart);
        expect(h.calls, contains('mic.restartAlert'));
        // Restart is a last resort — only after the live probe failed.
        expect(
          h.calls.indexOf('mic.verifyCapture'),
          lessThan(h.calls.indexOf('mic.restartAlert')),
        );
      },
    );

    test('poll timeout without grant → unresolved, nothing forced', () async {
      final h = _GateHarness()
        ..statusReads = [false]
        ..promptedReads = [false];
      final result = await h.gate(withAutoPaste: false).run();

      expect(result.mic, MicGateOutcome.unresolved);
      expect(h.calls, isNot(contains('mic.verifyCapture')));
      expect(h.calls, isNot(contains('mic.restartAlert')));
    });

    test(
      'declining the guided fix ends the leg with zero side effects',
      () async {
        final h = _GateHarness()
          ..statusReads = [false]
          ..promptedReads = [false]
          ..micGrantAlertConfirmed = false;
        final result = await h.gate(withAutoPaste: false).run();

        expect(result.mic, MicGateOutcome.declined);
        expect(h.calls, isNot(contains('mic.openSettings')));
        expect(h.calls, isNot(contains('mic.verifyCapture')));
        expect(h.calls, isNot(contains('mic.restartAlert')));
      },
    );

    test('a throwing hook degrades to unresolved, never rethrows', () async {
      final h = _GateHarness()
        ..statusReads = [false]
        ..promptedReads = [false]
        ..micGrantAlertThrows = true;
      final result = await h.gate().run();

      expect(result.mic, MicGateOutcome.unresolved);
      // Auto-Paste leg still runs despite the mic failure.
      expect(h.calls, contains('ap.readStatus'));
    });
  });

  group('auto-paste leg', () {
    test('no hooks (non-macOS / unsupported build) → notNeeded', () async {
      final h = _GateHarness()..statusReads = [true];
      final result = await h.gate(withAutoPaste: false).run();

      expect(result.autoPaste, AutoPasteGateOutcome.notNeeded);
    });

    test('capability ready / paste-free action → no alerts', () async {
      final h = _GateHarness()
        ..statusReads = [true]
        ..autoPasteStatus = AutoPasteGateStatus.notNeeded;
      final result = await h.gate().run();

      expect(result.autoPaste, AutoPasteGateOutcome.notNeeded);
      expect(h.calls, ['mic.status', 'ap.readStatus']);
    });

    test('missing → guided alert, then the shared grant flow', () async {
      final h = _GateHarness()
        ..statusReads = [true]
        ..autoPasteStatus = AutoPasteGateStatus.missing;
      final result = await h.gate().run();

      expect(result.autoPaste, AutoPasteGateOutcome.grantFlowStarted);
      expect(h.calls, [
        'mic.status',
        'ap.readStatus',
        'ap.grantAlert',
        'ap.startGrantFlow',
      ]);
    });

    test('still missing after an ineffective restart → honest manual alert, '
        'no new grant flow (no restart loop)', () async {
      final h = _GateHarness()
        ..statusReads = [true]
        ..autoPasteStatus = AutoPasteGateStatus.missingAfterIneffectiveRestart;
      final result = await h.gate().run();

      expect(result.autoPaste, AutoPasteGateOutcome.manualAlertShown);
      expect(h.calls, contains('ap.manualAlert'));
      expect(h.calls, isNot(contains('ap.startGrantFlow')));
    });

    test('declining the grant alert never starts the grant flow', () async {
      final h = _GateHarness()
        ..statusReads = [true]
        ..autoPasteStatus = AutoPasteGateStatus.missing
        ..autoPasteGrantAlertConfirmed = false;
      final result = await h.gate().run();

      expect(result.autoPaste, AutoPasteGateOutcome.declined);
      expect(h.calls, isNot(contains('ap.startGrantFlow')));
    });

    test('runs strictly after the mic leg', () async {
      final h = _GateHarness()
        ..statusReads = [false, true]
        ..promptedReads = [false]
        ..autoPasteStatus = AutoPasteGateStatus.missing;
      await h.gate().run();

      final lastMicCall = h.calls.lastIndexWhere((c) => c.startsWith('mic.'));
      final firstApCall = h.calls.indexWhere((c) => c.startsWith('ap.'));
      expect(lastMicCall, lessThan(firstApCall));
    });
  });
}
