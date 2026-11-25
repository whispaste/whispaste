/// #453: dictation messages show on the overlay card, their buttons act and
/// close it, and a new recording is never blocked by a card.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:flutter/services.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice_rules.dart'
    show noticeSecondPressWindow;
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';

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

class _RecordingHotkeys extends HotkeyService {
  int registered = 0;
  int released = 0;
  VoidCallback? onCancel;
  VoidCallback? onAction;
  LogicalKeyboardKey? actionKey;

  @override
  Future<bool> registerNoticeActionKey({
    required VoidCallback onPressed,
    required LogicalKeyboardKey key,
  }) async {
    onAction = onPressed;
    actionKey = key;
    return true;
  }

  @override
  Future<void> unregisterNoticeActionKey() async {
    onAction = null;
  }

  @override
  Future<bool> registerCancelDictationKey({
    required VoidCallback onCancel,
    LogicalKeyboardKey key = LogicalKeyboardKey.escape,
  }) async {
    registered++;
    this.onCancel = onCancel;
    return true;
  }

  @override
  Future<void> unregisterCancelDictationKey() async {
    released++;
    onCancel = null;
  }
}

class _Harness {
  _Harness(this.fake, this.container);
  final _FakeController fake;
  final ProviderContainer container;

  void settle(FakeAsync async) {
    async.elapse(const Duration(milliseconds: 5));
    async.flushMicrotasks();
  }

  void click(FakeAsync async, String id) {
    fake.emit(OverlayNoticeActionClicked(id));
    settle(async);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void run(void Function(_Harness h, FakeAsync async) body) {
    FakeAsync().run((async) {
      final fake = _FakeController();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_CapturingSettingsNotifier.new),
          audioServiceProvider.overrideWith(_MicOpenAudioNotifier.new),
          recordingOrchestratorProvider.overrideWith(_FakeOrchestrator.new),
          hotkeyServiceProvider.overrideWith(_RecordingHotkeys.new),
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
        body(_Harness(fake, container), async);
      } finally {
        container.dispose();
      }
    });
  }

  DictationNotice notice(List<String> log, {bool error = true}) =>
      DictationNotice(
        id: 'paste-failed',
        cause: 'Paste failed',
        nextStep: 'Press the paste shortcut',
        tone: error ? OverlayNoticeTone.error : OverlayNoticeTone.hint,
        autoDismiss: const Duration(seconds: 8),
        actions: [
          DictationNoticeAction(
            id: 'open-settings',
            label: 'Open',
            onPressed: () => log.add('open'),
          ),
        ],
      );

  test('a notice raised while idle shows on the card with its button', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      final card = h.fake.lastSnapshot!.notice!;
      expect(h.fake.lastSnapshot!.visible, isTrue);
      expect(card.kind, OverlayNoticeKind.message);
      expect(card.title, 'Paste failed');
      expect(card.actions.map((a) => a.action.id), ['notice_1', 'dismiss']);
      // The button is named by what it does, not by its place.
      expect(card.actions.first.testName, 'open-settings');
    });
  });

  test('session-owned preview stays visible during its action', () {
    run((h, async) {
      var pressed = false;
      final draft = DictationNotice(
        id: 'smart-write-preview',
        cause: 'Draft',
        managesOwnKeys: true,
        offersNewDictation: false,
        actions: [
          DictationNoticeAction(
            id: 'insert',
            label: 'Insert',
            onPressed: () => pressed = true,
          ),
        ],
      );
      h.container.read(dictationNoticeProvider.notifier).show(draft);
      h.settle(async);
      h.click(async, 'notice_1');
      expect(pressed, isTrue);
      expect(h.container.read(dictationNoticeProvider), same(draft));
      expect(h.fake.lastSnapshot!.visible, isTrue);
    });
  });

  test('the card button runs its action and closes the card', () {
    run((h, async) {
      final log = <String>[];
      h.container.read(dictationNoticeProvider.notifier).show(notice(log));
      h.settle(async);
      h.click(async, 'notice_1');
      expect(log, ['open']);
      expect(h.container.read(dictationNoticeProvider), isNull);
      expect(h.fake.lastSnapshot!.visible, isFalse);
    });
  });

  test('close hides the card without running the action', () {
    run((h, async) {
      final log = <String>[];
      h.container.read(dictationNoticeProvider.notifier).show(notice(log));
      h.settle(async);
      h.click(async, 'dismiss');
      expect(log, isEmpty);
      expect(h.fake.lastSnapshot!.visible, isFalse);
    });
  });

  test('an error stays, a pure status hint closes itself', () {
    run((h, async) {
      final n = h.container.read(dictationNoticeProvider.notifier);
      n.show(notice([]));
      async.elapse(const Duration(seconds: 30));
      expect(h.container.read(dictationNoticeProvider), isNotNull);
      n.show(
        DictationNotice(
          id: 'status',
          cause: 'Saved',
          autoDismiss: const Duration(seconds: 8),
        ),
      );
      async.elapse(const Duration(seconds: 9));
      expect(h.container.read(dictationNoticeProvider), isNull);
    });
  });

  test('the error reset after 5 s leaves the no-microphone card standing', () {
    run((h, async) {
      final rec = h.container.read(recordingProvider.notifier);
      rec.fail(RecordingStartFailure.noMicrophone.errorCode);
      h.settle(async);
      expect(h.fake.lastSnapshot!.visible, isTrue);
      expect(h.fake.lastSnapshot!.notice?.kind, OverlayNoticeKind.noMicrophone);

      // The recording UI resets the error state to idle after 5 s
      // (recording_behavior.dart, F1) ...
      async.elapse(const Duration(seconds: 5));
      rec.reset();
      h.settle(async);
      expect(h.container.read(recordingProvider).phase, RecordingPhase.idle);

      // ... but the card stays until it is closed.
      async.elapse(const Duration(minutes: 5));
      expect(h.fake.lastSnapshot!.visible, isTrue);
      expect(h.fake.lastSnapshot!.notice?.kind, OverlayNoticeKind.noMicrophone);

      h.click(async, 'dismiss');
      expect(h.fake.lastSnapshot!.visible, isFalse);
    });
  });

  test('a new recording closes an open card instead of waiting for it', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      h.container.read(recordingProvider.notifier).startRecording();
      h.settle(async);
      expect(h.container.read(dictationNoticeProvider), isNull);
      expect(h.fake.lastSnapshot!.notice, isNull);
    });
  });

  test(
    'with the overlay off, the message is not lost but shown as a banner',
    () {
      run((h, async) {
        h.container
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(overlayMode: OverlayMode.off.value),
            );
        h.settle(async);
        h.container.read(dictationNoticeProvider.notifier).show(notice([]));
        h.settle(async);
        final banner = h.container.read(wpPageNoticeProvider(kAppNoticePage));
        expect(banner, isNotNull);
        expect(banner!.id, 'dictation-paste-failed');
        expect(h.fake.lastSnapshot?.notice, isNull);
        expect(h.container.read(dictationNoticeProvider), isNull);
      });
    },
  );

  _RecordingHotkeys keys(_Harness h) =>
      h.container.read(hotkeyServiceProvider.notifier) as _RecordingHotkeys;

  test('a standing card takes the cancel key; pressing it closes the card', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      expect(keys(h).registered, 1);
      keys(h).onCancel!();
      h.settle(async);
      expect(h.container.read(dictationNoticeProvider), isNull);
      expect(keys(h).released, greaterThan(0));
      expect(keys(h).onCancel, isNull);
    });
  });

  test('a standing card keeps the cancel key for as long as it stands', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      async.elapse(const Duration(minutes: 5));
      expect(keys(h).onCancel, isNotNull);
      expect(h.container.read(dictationNoticeProvider), isNotNull);
    });
  });

  test('a card without a button grabs no global key and closes by time', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'status',
              cause: 'Saved',
              autoDismiss: const Duration(seconds: 8),
            ),
          );
      h.settle(async);
      expect(keys(h).registered, 0);
      expect(keys(h).onCancel, isNull);
      expect(keys(h).onAction, isNull);
      async.elapse(const Duration(seconds: 9));
      expect(h.container.read(dictationNoticeProvider), isNull);
    });
  });

  test('a standing card without a button keeps the cancel key', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'lost',
              cause: 'Paste failed',
              tone: OverlayNoticeTone.error,
            ),
          );
      h.settle(async);
      expect(keys(h).onCancel, isNotNull);
      async.elapse(const Duration(minutes: 5));
      expect(keys(h).onCancel, isNotNull);
      expect(h.container.read(dictationNoticeProvider), isNotNull);
    });
  });

  test('a card with a button gives the key back the moment it closes', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      expect(keys(h).onCancel, isNotNull);
      h.click(async, 'dismiss');
      expect(keys(h).onCancel, isNull);
      expect(keys(h).onAction, isNull);
    });
  });

  test('a button-less card that replaces a button card drops the key', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      expect(keys(h).onCancel, isNotNull);
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'status',
              cause: 'Saved',
              autoDismiss: const Duration(seconds: 8),
            ),
          );
      h.settle(async);
      expect(keys(h).onCancel, isNull);
      expect(keys(h).onAction, isNull);
    });
  });

  test('the card releases the key when it goes away with the overlay off', () {
    run((h, async) {
      h.container.read(dictationNoticeProvider.notifier).show(notice([]));
      h.settle(async);
      h.container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(overlayMode: OverlayMode.off.value),
          );
      h.settle(async);
      h.container.read(dictationNoticeProvider.notifier).dismiss();
      h.settle(async);
      expect(keys(h).onCancel, isNull);
    });
  });

  test('a card with a button also holds the other key, which runs it', () {
    run((h, async) {
      final log = <String>[];
      h.container.read(dictationNoticeProvider.notifier).show(notice(log));
      h.settle(async);
      expect(keys(h).actionKey, LogicalKeyboardKey.f12);
      expect(
        h.fake.lastSnapshot!.notice!.actions.first.fullLabel,
        'Open (F12)',
      );
      keys(h).onAction!();
      h.settle(async);
      expect(log, ['open']);
      expect(h.container.read(dictationNoticeProvider), isNull);
      expect(keys(h).onAction, isNull);
    });
  });

  // #816: the one action key reaches both buttons; no third global key.
  test('on a two-button card one press runs the first, two the second', () {
    run((h, async) {
      final log = <String>[];
      DictationNotice twoButtons() => DictationNotice(
        id: 'short-press-hint',
        cause: 'Hold to dictate',
        autoDismiss: null,
        actions: [
          DictationNoticeAction(
            id: 'open-settings',
            label: 'Open',
            onPressed: () => log.add('open'),
          ),
          DictationNoticeAction(
            id: 'hide-short-press-hint',
            label: 'Hide',
            onPressed: () => log.add('hide'),
          ),
        ],
      );
      final notices = h.container.read(dictationNoticeProvider.notifier);
      notices.show(twoButtons());
      h.settle(async);
      final card = h.fake.lastSnapshot!.notice!;
      expect(card.actions.map((a) => a.fullLabel).take(2), [
        'Open (F12)',
        'Hide (2× F12)',
      ]);
      // The keys stand on the buttons; the footer does not repeat them.
      expect(card.footer, isNot(contains('F12')));
      expect(card.footer, isNotEmpty);
      expect(card.actions.map((a) => a.action).take(2), [
        OverlayNoticeActionId.notice1,
        OverlayNoticeActionId.notice2,
      ]);

      // A single press waits for a second one, then runs the first button.
      keys(h).onAction!();
      async.elapse(noticeSecondPressWindow ~/ 2);
      expect(log, isEmpty);
      async.elapse(noticeSecondPressWindow);
      h.settle(async);
      expect(log, ['open']);

      // Two quick presses run the second button only.
      notices.show(twoButtons());
      h.settle(async);
      keys(h).onAction!();
      async.elapse(noticeSecondPressWindow ~/ 2);
      keys(h).onAction!();
      async.elapse(noticeSecondPressWindow * 2);
      h.settle(async);
      expect(log, ['open', 'hide']);
      expect(h.container.read(dictationNoticeProvider), isNull);
    });
  });

  test('a waiting press does nothing once its card was closed', () {
    run((h, async) {
      final log = <String>[];
      final notices = h.container.read(dictationNoticeProvider.notifier);
      notices.show(
        DictationNotice(
          id: 'two',
          cause: 'Two',
          autoDismiss: null,
          actions: [
            DictationNoticeAction(
              id: 'a',
              label: 'A',
              onPressed: () => log.add('a'),
            ),
            DictationNoticeAction(
              id: 'b',
              label: 'B',
              onPressed: () => log.add('b'),
            ),
          ],
        ),
      );
      h.settle(async);
      keys(h).onAction!();
      keys(h).onCancel!();
      async.elapse(noticeSecondPressWindow * 2);
      h.settle(async);
      expect(log, isEmpty);
    });
  });

  test('a card without a button holds no action key', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(id: 'plain', cause: 'Just so', autoDismiss: null),
          );
      h.settle(async);
      expect(keys(h).onAction, isNull);
    });
  });

  test('a card with a button never closes itself (WCAG 2.2.1)', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(notice([], error: false));
      h.settle(async);
      async.elapse(const Duration(minutes: 5));
      expect(h.container.read(dictationNoticeProvider), isNotNull);
      expect(keys(h).onAction, isNotNull);
    });
  });

  test('a pure status notice closes itself after its time', () {
    run((h, async) {
      h.container
          .read(dictationNoticeProvider.notifier)
          .show(
            DictationNotice(
              id: 'status',
              cause: 'Saved',
              autoDismiss: const Duration(seconds: 8),
            ),
          );
      h.settle(async);
      async.elapse(const Duration(seconds: 9));
      expect(h.container.read(dictationNoticeProvider), isNull);
    });
  });
}
