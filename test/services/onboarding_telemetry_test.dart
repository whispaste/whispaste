/// Hand-over of [OnboardingTelemetry]: which category/action/name each call
/// emits, the dwell and time-to-first-dictation buckets, that unchecked
/// values fall back to `other`, and that events wait for the committed privacy choice
/// in [OnboardingTelemetryBuffer] (sent once on "on", dropped on "off").
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/telemetry/onboarding_telemetry_buffer.dart';
import 'package:whispaste/services/onboarding_telemetry.dart';

typedef _Event = (String, String, String?);

void main() {
  late List<_Event> events;
  late DateTime now;
  late OnboardingTelemetry telemetry;

  setUp(() {
    events = [];
    now = DateTime.utc(2026, 10, 30, 12);
    telemetry = OnboardingTelemetry(
      track: ({required category, required action, name}) =>
          events.add((category, action, name)),
      decide: ({required shareUsageStats}) {},
      clock: () => now,
    );
  });

  final wireName = RegExp(r'^[a-z0-9_.:-]+$');

  test('buckets', () {
    expect(dwellBucket(const Duration(seconds: 4)), 'lt5s');
    expect(dwellBucket(const Duration(seconds: 5)), '5_15s');
    expect(dwellBucket(const Duration(seconds: 59)), '15_60s');
    expect(dwellBucket(const Duration(minutes: 2)), '1_3m');
    expect(dwellBucket(const Duration(minutes: 3)), 'gt3m');
    expect(ttfdBucket(const Duration(seconds: 90)), 'lt2m');
    expect(ttfdBucket(const Duration(minutes: 4)), '2_5m');
    expect(ttfdBucket(const Duration(minutes: 9)), '5_10m');
    expect(ttfdBucket(const Duration(minutes: 29)), '10_30m');
    expect(ttfdBucket(const Duration(hours: 1)), 'gt30m');
  });

  test('a screen emits shown, its action and its dwell bucket', () {
    telemetry.stepShown(OnboardingScreen.welcome);
    now = now.add(const Duration(seconds: 20));
    telemetry.stepNext(OnboardingScreen.welcome);
    telemetry.stepShown(OnboardingScreen.about);
    now = now.add(const Duration(seconds: 3));
    telemetry.stepSkip(OnboardingScreen.about);

    expect(events, [
      ('onboarding', 'step', 'welcome'),
      ('onboarding', 'step_next', 'welcome'),
      ('onboarding', 'step_time', 'welcome:15_60s'),
      ('onboarding', 'step', 'about_you'),
      ('onboarding', 'step_skip', 'about_you'),
      ('onboarding', 'step_time', 'about_you:lt5s'),
    ]);
  });

  test('showing the next screen without leaving still closes the dwell', () {
    telemetry.stepShown(OnboardingScreen.mic);
    now = now.add(const Duration(seconds: 7));
    telemetry.stepShown(OnboardingScreen.access);
    expect(events[1], ('onboarding', 'step_time', 'mic:5_15s'));
  });

  test('time to first dictation is sent once, from the first welcome', () {
    telemetry.stepShown(OnboardingScreen.welcome);
    now = now.add(const Duration(minutes: 6));
    telemetry.firstDictation(OnboardingFirstDictation.ok);
    telemetry.firstDictation(OnboardingFirstDictation.ok);
    final ttfd = events.where((e) => e.$2 == 'ttfd').toList();
    expect(ttfd, [('onboarding', 'ttfd', '5_10m')]);
  });

  test('roles send one event per selected role, none when empty', () {
    telemetry
      ..roles({OnboardingRole.legal, OnboardingRole.dev})
      ..roles({});
    expect(events, [
      ('onboarding', 'role', 'dev'),
      ('onboarding', 'role', 'legal'),
      ('onboarding', 'role', 'none'),
    ]);
  });

  test('unchecked values never reach the wire', () {
    telemetry
      ..dictationLanguageChanged('de')
      ..dictationLanguageChanged('auto')
      ..dictationLanguageChanged('Deutsch (Österreich)')
      ..download(OnboardingDownloadEvent.started, 'small')
      ..download(OnboardingDownloadEvent.started, '/Users/me/models/x.bin')
      ..firstDictation(
        OnboardingFirstDictation.failed,
        failureCode: 'no_speech',
      )
      ..firstDictation(OnboardingFirstDictation.failed, failureCode: 'Oops: x')
      ..download(
        OnboardingDownloadEvent.failed,
        'parakeet-v3',
        cause: OnboardingDownloadFailure.disk,
      );
    expect(events.map((e) => e.$3), [
      'de',
      'auto',
      'other',
      'small',
      'other',
      'failed:no_speech',
      'failed:other',
      'parakeet-v3:disk',
    ]);
  });

  test('every call emits only fixed wire names', () {
    telemetry
      ..stepShown(OnboardingScreen.tryOut)
      ..paused(OnboardingScreen.tryOut)
      ..quit(OnboardingScreen.hotkey)
      ..stepBack(OnboardingScreen.privacy)
      ..complete()
      ..contactOpened(OnboardingScreen.mic)
      ..modelSwitchOpened(OnboardingScreen.welcome)
      ..nameEdit(OnboardingNameEdit.cleared)
      ..micLevel(detected: true)
      ..micDeviceChanged()
      ..introSound(played: false)
      ..firstDictation(OnboardingFirstDictation.waitedForModel);
    telemetry
      ..roles({})
      ..roles(OnboardingRole.values.toSet());
    for (final a in OnboardingAttribution.values) {
      telemetry.attribution(a);
    }
    for (final m in OnboardingHotkeyMode.values) {
      for (final s in OnboardingHotkeyShape.values) {
        telemetry.hotkeyChosen(m, s);
      }
    }
    for (final r in OnboardingHotkeyResult.values) {
      telemetry.hotkeyResult(r);
    }
    for (final k in OnboardingPermission.values) {
      for (final r in OnboardingPermissionResult.values) {
        telemetry.permission(k, r);
      }
    }
    for (final e in OnboardingDownloadEvent.values) {
      telemetry.download(e, 'whisper-base');
    }

    for (final (category, action, name) in events) {
      expect(category, matches(wireName));
      expect(action, matches(wireName));
      if (name != null) expect(name, matches(wireName));
    }
    expect(
      events,
      contains(('permission', 'paste_access', 'continued_without')),
    );
    expect(
      events,
      contains(('onboarding', 'hotkey_chosen', 'hold:modifier_only')),
    );
    expect(events, contains(('onboarding', 'hotkey_result', 'not_recognized')));
  });

  test('reruns report their own actions, never the funnel ones', () {
    telemetry
      ..rerun(
        OnboardingRerun.review,
        OnboardingRerunEvent.step,
        OnboardingScreen.mic,
      )
      ..rerun(
        OnboardingRerun.revision,
        OnboardingRerunEvent.exit,
        OnboardingScreen.about,
      )
      ..rerun(
        OnboardingRerun.revision,
        OnboardingRerunEvent.complete,
        OnboardingScreen.privacy,
      );
    expect(events, [
      ('onboarding', 'review_step', 'mic'),
      ('onboarding', 'revision_exit', 'about_you'),
      ('onboarding', 'revision_complete', 'privacy'),
    ]);
  });

  test('completing leaves the closing page and then completes', () {
    telemetry
      ..stepShown(OnboardingScreen.privacy)
      ..complete();
    expect(events.map((e) => (e.$2, e.$3)), [
      ('step', 'privacy'),
      ('step_next', 'privacy'),
      ('step_time', 'privacy:lt5s'),
      ('complete', null),
    ]);
  });

  group('with the buffer', () {
    late List<BufferedTelemetryEvent> sent;
    late OnboardingTelemetryBuffer buffer;
    late OnboardingTelemetry wired;

    setUp(() {
      sent = [];
      buffer = OnboardingTelemetryBuffer(send: sent.add)..begin();
      wired = OnboardingTelemetry(track: buffer.track, decide: buffer.decide);
    });

    test(
      'nothing leaves before the committed privacy choice; "on" sends once',
      () {
        wired.stepShown(OnboardingScreen.welcome);
        wired.stepNext(OnboardingScreen.welcome);
        expect(sent, isEmpty);

        wired.consentDecided(shareUsageStats: true);
        expect(sent.map((e) => e.action), ['step', 'step_next', 'step_time']);

        wired.stepShown(OnboardingScreen.mic);
        expect(sent, hasLength(4));
      },
    );

    test('"off" drops held and later events', () {
      wired.stepShown(OnboardingScreen.welcome);
      wired.consentDecided(shareUsageStats: false);
      wired.stepShown(OnboardingScreen.mic);
      wired.consentDecided(shareUsageStats: true);
      expect(sent, isEmpty);
    });
  });
}
