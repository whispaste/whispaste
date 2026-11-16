/// #454: hotkey and tray confirmations show briefly at the overlay pill.
/// Fast presses replace each other, a busy pill makes them wait, and with the
/// overlay off they go to the main window banner.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/floating_overlay/hotkey_hint_notices.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/services/floating_overlay/pill_hint.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

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

class _OverlayOffSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings().copyWith(
    overlayMode: OverlayMode.off.value,
    showOverlay: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var activations = 0;

  void run(
    void Function(
      _FakeController fake,
      ProviderContainer container,
      FakeAsync async,
    )
    body,
  ) {
    FakeAsync().run((async) {
      activations = 0;
      final fake = _FakeController();
      final container = ProviderContainer(
        overrides: [
          windowActivatorProvider.overrideWithValue(() async => activations++),
          settingsProvider.overrideWith(_CapturingSettingsNotifier.new),
          audioServiceProvider.overrideWith(_MicOpenAudioNotifier.new),
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
        body(fake, container, async);
      } finally {
        container.dispose();
      }
    });
  }

  void settle(FakeAsync async) {
    async.elapse(const Duration(milliseconds: 5));
    async.flushMicrotasks();
  }

  void hint(ProviderContainer c, String text) =>
      c.read(overlayPillHintProvider.notifier).show(id: 'test', text: text);

  test('a hint shows at the pill while idle and hides again', () {
    run((fake, c, async) {
      hint(c, 'Language: German');
      settle(async);
      expect(fake.lastSnapshot!.visible, isTrue);
      expect(fake.lastSnapshot!.doneMessage, 'Language: German');
      expect(fake.lastSnapshot!.donePasteFailed, isFalse);
      async.elapse(kOverlayAutoHideDelay + const Duration(milliseconds: 10));
      expect(fake.lastSnapshot!.visible, isFalse);
    });
  });

  test('the pill snapshot names the hint and keeps the read-out flag', () {
    run((fake, c, async) {
      c
          .read(overlayPillHintProvider.notifier)
          .show(id: 'profile-switched', text: 'Profile: Mail', announced: true);
      settle(async);
      expect(fake.lastSnapshot!.pillHintId, 'profile-switched');
      expect(fake.lastSnapshot!.announced, isTrue);
      final back = FloatingOverlaySnapshot.fromMap(fake.lastSnapshot!.toMap());
      expect(back.pillHintId, 'profile-switched');
      expect(back.announced, isTrue);
      async.elapse(kOverlayAutoHideDelay + const Duration(milliseconds: 10));
      expect(fake.lastSnapshot!.pillHintId, isNull);
      expect(fake.lastSnapshot!.announced, isFalse);
    });
  });

  test('fast presses replace each other, only the last one stays', () {
    run((fake, c, async) {
      hint(c, 'Language: German');
      settle(async);
      hint(c, 'Language: English');
      settle(async);
      hint(c, 'Language: French');
      settle(async);
      expect(fake.lastSnapshot!.doneMessage, 'Language: French');
      async.elapse(kOverlayAutoHideDelay + const Duration(milliseconds: 10));
      // Nothing queued behind it: the pill hides instead of replaying.
      expect(fake.lastSnapshot!.visible, isFalse);
    });
  });

  test('a hint during a recording waits and shows after the result', () {
    run((fake, c, async) {
      final rec = c.read(recordingProvider.notifier);
      rec.startRecording();
      settle(async);
      hint(c, 'Language: German');
      hint(c, 'Language: English');
      settle(async);
      expect(fake.lastSnapshot!.doneMessage, isNot('Language: English'));
      rec.stopRecording();
      settle(async);
      rec.completeTranscription('hello');
      settle(async);
      expect(fake.lastSnapshot!.doneMessage, isNot('Language: English'));
      async.elapse(kOverlayAutoHideDelay + const Duration(milliseconds: 10));
      expect(fake.lastSnapshot!.visible, isTrue);
      expect(fake.lastSnapshot!.doneMessage, 'Language: English');
      async.elapse(kOverlayAutoHideDelay + const Duration(milliseconds: 10));
      expect(fake.lastSnapshot!.visible, isFalse);
    });
  });

  test('a hint never covers an open card, it shows once the card closes', () {
    run((fake, c, async) {
      c
          .read(dictationNoticeProvider.notifier)
          .show(DictationNotice(id: 'card', cause: 'Paste failed'));
      settle(async);
      hint(c, 'Profile: Mail');
      settle(async);
      expect(fake.lastSnapshot!.notice, isNotNull);
      fake.emit(const OverlayNoticeActionClicked('dismiss'));
      settle(async);
      expect(fake.lastSnapshot!.visible, isTrue);
      expect(fake.lastSnapshot!.doneMessage, 'Profile: Mail');
    });
  });

  test('a hint waiting behind an error shows once the error times out', () {
    run((fake, c, async) {
      final rec = c.read(recordingProvider.notifier);
      rec.startRecording();
      settle(async);
      rec.fail('test_plain_error');
      settle(async);
      hint(c, 'Language: German');
      settle(async);
      async.elapse(const Duration(seconds: 31));
      expect(fake.lastSnapshot!.visible, isTrue);
      expect(fake.lastSnapshot!.doneMessage, 'Language: German');
    });
  });

  final l10n = lookupL10n(const Locale('en'));

  test('the short-press card button turns on "Tap or hold"', () {
    run((fake, c, async) {
      c
          .read(dictationNoticeProvider.notifier)
          .show(shortPressHintNotice(l10n, c.read));
      settle(async);
      expect(fake.lastSnapshot!.notice!.actions.first.action.id, 'notice_1');
      fake.emit(const OverlayNoticeActionClicked('notice_1'));
      settle(async);
      expect(c.read(settingsProvider).value!.audioInput.holdOrTap, isTrue);
      expect(c.read(dictationNoticeProvider), isNull);
      // The card is gone, so the pill confirms the switch (#827).
      expect(c.read(overlayPillHintProvider), isNotNull);
    });
  });

  test('the short-press card button "Don\'t show again" is remembered', () {
    run((fake, c, async) {
      c
          .read(dictationNoticeProvider.notifier)
          .show(shortPressHintNotice(l10n, c.read));
      settle(async);
      // Addressed by its testID suffix, not by its place on the card.
      final hide = fake.lastSnapshot!.notice!.actions.singleWhere(
        (a) => a.testName == 'hide-short-press-hint',
      );
      fake.emit(OverlayNoticeActionClicked(hide.action.id));
      settle(async);
      final audio = c.read(settingsProvider).value!.audioInput;
      expect(audio.shortPressHintHidden, isTrue);
      expect(audio.holdOrTap, isFalse);
      expect(c.read(dictationNoticeProvider), isNull);
    });
  });

  test('the no-favorites card button opens the language row in front', () {
    run((fake, c, async) {
      c
          .read(dictationNoticeProvider.notifier)
          .show(noFavoriteLanguagesNotice(l10n, c.read));
      settle(async);
      fake.emit(const OverlayNoticeActionClicked('notice_1'));
      settle(async);
      expect(c.read(activePageProvider), 'settings');
      expect(c.read(settingsScrollTargetProvider), 'speech-language');
      // The stars live in the language dialog (#1610): it opens on top.
      expect(c.read(settingsLanguageDialogRequestProvider), isTrue);
      expect(activations, 1);
    });
  });

  testWidgets('with the overlay on the hint is marked as read out once', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_CapturingSettingsNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    late BuildContext ctx;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showOverlayPillHint(ctx, id: 'language-cycle', text: 'Language: German');
    final hint = container.read(overlayPillHintProvider);
    expect(hint?.id, 'language-cycle');
    expect(hint?.announced, isTrue);
  });

  testWidgets('with the overlay off the hint goes to the main window', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_OverlayOffSettingsNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    late BuildContext ctx;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showOverlayPillHint(ctx, id: 'language-cycle', text: 'Language: German');
    final notice = container.read(wpPageNoticeProvider(kWpAppNoticePage));
    expect(notice?.message, 'Language: German');
    expect(notice?.autoDismiss, isNotNull);
    expect(container.read(overlayPillHintProvider), isNull);
    await tester.pump(kPillHintBannerTime);
    expect(container.read(wpPageNoticeProvider(kWpAppNoticePage)), isNull);
  });
}
