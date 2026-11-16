/// Overlay F2: what a notice-card button triggers. The render engine relays
/// a click as `onNoticeAction {id}`; the service turns it into an
/// orchestrator call or a settings change. No button discards what was said.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/recording/discard_confirmation.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio/quiet_microphone_watch.dart';
import 'package:whispaste/services/audio/signal_loss_detector.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/floating_overlay/pill_hint.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

class _FakeController implements FloatingOverlayController {
  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();
  FloatingOverlaySnapshot? lastSnapshot;

  void emit(FloatingOverlayEvent event) => _eventCtrl.add(event);

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> dispose() async => _eventCtrl.close();

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    lastSnapshot = snapshot;
  }

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

  @override
  Future<void> setPosition(
    double x,
    double y,
    OverlayAnchorMode anchor,
  ) async {}

  @override
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  }) async {}
}

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake);
  final _FakeController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

class _CapturingSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? const AppSettings()));
  }
}

class _MicOpenAudioNotifier extends AudioServiceNotifier {
  @override
  AudioStatus build() => const AudioStatus(
    captureState: AudioCaptureState.recording,
    hasLiveSamples: true,
  );
}

/// Counts what the card asks of the orchestrator; toggling moves the
/// recording phase the way the real one does (recording → transcribing).
class _FakeOrchestrator extends RecordingOrchestrator {
  int toggles = 0;
  int extensions = 0;

  @override
  void build() {}

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
    String? languageOverride,
    double? silenceTimeoutOverride,
  }) async {
    toggles++;
    final rec = ref.read(recordingProvider.notifier);
    if (ref.read(recordingProvider).phase == RecordingPhase.recording) {
      rec.stopRecording();
    } else {
      rec.startRecording();
    }
  }

  @override
  bool extendDurationLimitOnce() {
    extensions++;
    return true;
  }
}

class _Harness {
  _Harness(this.fake, this.orchestrator, this.container);
  final _FakeController fake;
  final _FakeOrchestrator orchestrator;
  final ProviderContainer container;

  void click(FakeAsync async, String id) {
    fake.emit(OverlayNoticeActionClicked(id));
    async.elapse(const Duration(milliseconds: 5));
    async.flushMicrotasks();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void run(void Function(_Harness h, FakeAsync async) body) {
    FakeAsync().run((async) {
      final fake = _FakeController();
      final orchestrator = _FakeOrchestrator();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_CapturingSettingsNotifier.new),
          audioServiceProvider.overrideWith(_MicOpenAudioNotifier.new),
          recordingOrchestratorProvider.overrideWith(() => orchestrator),
          floatingOverlayServiceProvider.overrideWith(
            () => _TestableService(fake),
          ),
        ],
      );
      container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      try {
        body(_Harness(fake, orchestrator, container), async);
      } finally {
        container.dispose();
      }
    });
  }

  void startRecording(_Harness h, FakeAsync async) {
    h.container.read(recordingProvider.notifier).startRecording();
    async.elapse(const Duration(milliseconds: 5));
    async.flushMicrotasks();
  }

  RecordingPhase phase(_Harness h) => h.container.read(recordingProvider).phase;

  test('paste so far stops and transcribes the recording', () {
    run((h, async) {
      startRecording(h, async);
      h.click(async, 'paste_so_far');
      expect(h.orchestrator.toggles, 1);
      expect(phase(h), RecordingPhase.transcribing);
    });
  });

  test('stop now outside a recording does nothing', () {
    run((h, async) {
      h.click(async, 'stop_now');
      expect(h.orchestrator.toggles, 0);
    });
  });

  test('keep going extends the duration limit', () {
    run((h, async) {
      startRecording(h, async);
      h.click(async, 'keep_recording');
      expect(h.orchestrator.extensions, 1);
      expect(h.orchestrator.toggles, 0, reason: 'the click is never a stop');
      expect(phase(h), RecordingPhase.recording);
      // #858: the click is answered at the pill.
      expect(h.container.read(overlayPillHintProvider)?.id, 'limit-extended');
    });
  });

  test('change microphone during a dictation waits until it is done', () {
    run((h, async) {
      startRecording(h, async);
      h.click(async, 'change_microphone');
      expect(h.orchestrator.toggles, 0, reason: 'the recording goes on');
      expect(h.container.read(activePageProvider), isNot('settings'));

      final rec = h.container.read(recordingProvider.notifier);
      rec.stopRecording();
      rec.completeTranscription('kept');
      async.elapse(const Duration(milliseconds: 5));
      async.flushMicrotasks();

      expect(h.container.read(activePageProvider), 'settings');
      expect(
        h.container.read(settingsScrollTargetProvider),
        'recording-microphone',
      );
    });
  });

  test(
    'the lost-signal paste button pastes, then a card offers the microphone',
    () {
      run((h, async) {
        startRecording(h, async);
        h.container.read(micSignalLostProvider.notifier).set(true);
        async.elapse(const Duration(milliseconds: 5));
        expect(
          h.fake.lastSnapshot?.notice?.actions
              .where((a) => !a.action.isClose)
              .map((a) => a.action),
          [
            OverlayNoticeActionId.pasteSoFar,
            // Discard sits next to paste since #138.
            OverlayNoticeActionId.discardRecording,
          ],
        );
        h.click(async, 'paste_so_far');
        expect(h.orchestrator.toggles, 1, reason: 'stop and transcribe');
        expect(phase(h), RecordingPhase.transcribing);
        expect(h.container.read(dictationNoticeProvider), isNull);

        final rec = h.container.read(recordingProvider.notifier);
        rec.completeTranscription('kept');
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();

        final follow = h.container.read(dictationNoticeProvider);
        expect(follow?.id, 'signal-lost-follow-up');
        expect(follow?.actions.single.id, 'choose-microphone');
        follow!.actions.single.onPressed();
        expect(h.container.read(activePageProvider), 'settings');
      });
    },
  );

  test('the cross of a recording card hides it and keeps recording', () {
    run((h, async) {
      startRecording(h, async);
      h.container.read(micQuietProvider.notifier).set(true);
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.notice?.kind, OverlayNoticeKind.quiet);

      h.click(async, 'hide_hint');

      expect(h.orchestrator.toggles, 0);
      expect(phase(h), RecordingPhase.recording);
      expect(h.fake.lastSnapshot?.notice, isNull);
    });
  });

  test('a card over the recording makes Esc ask, and says so on the card', () {
    run((h, async) {
      startRecording(h, async);
      expect(h.container.read(recordingCardOpenProvider), isFalse);
      h.container.read(micQuietProvider.notifier).set(true);
      async.elapse(const Duration(milliseconds: 5));
      expect(h.container.read(recordingCardOpenProvider), isTrue);

      final confirm = h.container.read(discardConfirmProvider.notifier);
      final discardNow = cancelPressDiscardsNow(
        RecordingPhase.recording,
        const Duration(seconds: 5),
        confirm,
        cardOpen: h.container.read(recordingCardOpenProvider),
      );
      async.elapse(const Duration(milliseconds: 5));

      expect(discardNow, isFalse, reason: 'the first Esc only asks');
      expect(h.fake.lastSnapshot?.notice?.title, contains('Discard'));
      expect(h.fake.lastSnapshot?.notice?.actions, isNotEmpty);
    });
  });

  test('change microphone without a dictation opens Settings at once', () {
    run((h, async) {
      h.container.read(recordingProvider.notifier).fail('no_microphone');
      async.elapse(const Duration(milliseconds: 5));
      h.click(async, 'change_microphone');
      expect(h.container.read(activePageProvider), 'settings');
      expect(h.fake.lastSnapshot?.visible, isFalse);
    });
  });

  test('retry starts a new recording after a failed start', () {
    run((h, async) {
      h.container
          .read(recordingProvider.notifier)
          .fail('recording_start_failed');
      async.elapse(const Duration(milliseconds: 5));
      h.click(async, 'retry');
      expect(h.orchestrator.toggles, 1);
    });
  });

  test('the cross over a recording hides only the card (#781)', () {
    run((h, async) {
      startRecording(h, async);
      h.container.read(micSignalLostProvider.notifier).set(true);
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.notice, isNotNull);
      h.click(async, 'dismiss');
      expect(h.fake.lastSnapshot?.notice, isNull);
      expect(h.orchestrator.toggles, 0, reason: 'nothing is discarded');
      expect(phase(h), RecordingPhase.recording);
    });
  });

  test('a standing error card survives the error reset until closed', () {
    run((h, async) {
      h.container.read(recordingProvider.notifier).fail('no_microphone');
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.notice, isNotNull);
      async.elapse(const Duration(minutes: 2));
      expect(h.fake.lastSnapshot?.notice, isNotNull);
      expect(h.fake.lastSnapshot?.visible, isTrue);
      h.click(async, 'dismiss');
      expect(h.fake.lastSnapshot?.visible, isFalse);
    });
  });

  test('a standing error card is gone when the overlay is switched off', () {
    run((h, async) {
      h.container.read(recordingProvider.notifier).fail('no_microphone');
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.visible, isTrue);
      h.container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(overlayMode: OverlayMode.off.value),
          );
      async.elapse(const Duration(milliseconds: 5));
      async.flushMicrotasks();
      expect(h.fake.lastSnapshot?.visible, isFalse);
      expect(h.fake.lastSnapshot?.notice, isNull);
    });
  });

  test('a standing error card does not come back after a new recording', () {
    run((h, async) {
      h.container.read(recordingProvider.notifier).fail('no_microphone');
      async.elapse(const Duration(milliseconds: 5));
      // The error reset returns the pipeline to idle; the card stands on.
      h.container.read(recordingProvider.notifier).reset();
      async.elapse(const Duration(seconds: 10));
      expect(h.fake.lastSnapshot?.notice, isNotNull);
      startRecording(h, async);
      expect(h.fake.lastSnapshot?.notice, isNull);
      h.container.read(recordingProvider.notifier).reset();
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(h.fake.lastSnapshot?.notice, isNull);
    });
  });

  test('a notice that must be kept open does not close by itself', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'hotkey-heal-failed',
              cause: 'Hotkey not restored',
              tone: OverlayNoticeTone.error,
              autoDismiss: const Duration(seconds: 8),
            ),
          );
      async.elapse(const Duration(minutes: 5));
      expect(h.container.read(dictationNoticeProvider), isNotNull);
      expect(h.fake.lastSnapshot?.visible, isTrue);
    });
  });

  test('a card names the valid keys in a footer (#781)', () {
    run((h, async) {
      startRecording(h, async);
      h.container.read(micSignalLostProvider.notifier).set(true);
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.notice?.footer, isNotEmpty);
    });
  });

  test('a button without a visible effect is confirmed at the pill (#781)', () {
    run((h, async) {
      var ran = 0;
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'download',
              cause: 'Model missing',
              actions: [
                DictationNoticeAction(
                  id: 'download',
                  label: 'Download now',
                  onPressed: () => ran++,
                  confirmation: 'Downloading',
                ),
              ],
            ),
          );
      async.elapse(const Duration(milliseconds: 5));
      h.click(async, 'notice_1');
      expect(ran, 1);
      expect(h.container.read(overlayPillHintProvider)?.text, 'Downloading');
    });
  });

  // #921: a click that misses the card's cross reaches the pill's body click.
  // While a card is on screen that click closes it like Escape and never
  // starts a recording.
  test('a body click on a message card closes it and starts nothing', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'paste-no-target',
              cause: 'Could not paste',
              tone: OverlayNoticeTone.error,
            ),
          );
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.notice, isNotNull);

      h.fake.emit(const OverlayBodyClicked());
      async.elapse(const Duration(milliseconds: 5));
      async.flushMicrotasks();

      expect(h.orchestrator.toggles, 0);
      expect(phase(h), isNot(RecordingPhase.recording));
      expect(h.container.read(dictationNoticeProvider), isNull);
    });
  });

  test('a body click on a recording card hides it and keeps recording', () {
    run((h, async) {
      startRecording(h, async);
      h.container.read(micSignalLostProvider.notifier).set(true);
      async.elapse(const Duration(milliseconds: 5));
      expect(h.fake.lastSnapshot?.notice, isNotNull);

      h.fake.emit(const OverlayBodyClicked());
      async.elapse(const Duration(milliseconds: 5));
      async.flushMicrotasks();

      expect(h.orchestrator.toggles, 0);
      expect(phase(h), RecordingPhase.recording);
      expect(h.fake.lastSnapshot?.notice, isNull);
    });
  });

  test('a body click on the plain pill still toggles the recording', () {
    run((h, async) {
      startRecording(h, async);
      expect(h.fake.lastSnapshot?.notice, isNull);

      h.fake.emit(const OverlayBodyClicked());
      async.elapse(const Duration(milliseconds: 5));
      async.flushMicrotasks();

      expect(h.orchestrator.toggles, 1);
    });
  });

  test('an unknown id is ignored', () {
    run((h, async) {
      startRecording(h, async);
      h.click(async, 'nonsense');
      expect(h.orchestrator.toggles, 0);
      expect(phase(h), RecordingPhase.recording);
    });
  });
}
