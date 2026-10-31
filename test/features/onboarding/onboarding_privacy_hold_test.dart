/// Widget tests for the first-run privacy hold (ticket 01 of
/// `internal-notes`, decision 5a) and for the microphone
/// prompt timing (decision 2a: no OS request before the access step).
///
/// The telemetry transport is a counting [MockClient], so "sent" means "an
/// HTTP request left the app", which is what the ticket's acceptance criteria
/// are about.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart'
    show kPrivacyStepPageKey;
import 'package:whispaste/services/hotkey_service.dart'
    show HotkeyService, hotkeyRegistrationStatusProvider, hotkeyServiceProvider;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';
import 'onboarding_test_doubles.dart';
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

/// The practice step holds "Next" until a dictation succeeds; these tests
/// are about the privacy hold, so the practice step counts as done.
class _PracticeDone extends OnboardingTestRecordingSucceededNotifier {
  @override
  bool build() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int posts;
  late List<String> actions;
  late OnboardingCountingMicChecker mic;

  Future<void> pump(WidgetTester tester, {AppSettings? settings}) async {
    posts = 0;
    actions = [];
    mic = OnboardingCountingMicChecker();
    final client = MockClient((request) async {
      posts++;
      final fields = request.bodyFields;
      if (fields['e_a'] != null) actions.add(fields['e_a']!);
      return http.Response('', 204);
    });
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        disableAnimations: true,
        const OnboardingOverlay(),
        size: const Size(1280, 1600),
        locale: const Locale('en'),
        overrides: [
          onboardingMicSpeechHeardProvider.overrideWith(
            OnboardingFixedMicSpeech.new,
          ),
          onboardingMicProbeProvider.overrideWithValue(
            OnboardingFakeMicProbe(),
          ),
          audioInputDevicesProvider.overrideWith(
            (ref) async => const ['Default'],
          ),
          settingsProvider.overrideWith(
            () => OnboardingFakeSettings(settings ?? AppSettings.defaults),
          ),
          micPermissionCheckerProvider.overrideWithValue(mic),
          hotkeyRegistrationStatusProvider.overrideWith(
            OnboardingFakeHotkey.new,
          ),
          // The trigger step reads the real HotkeyService, whose native
          // registration never answers in tests. Its timeout would report a
          // hotkey conflict and close the completion gate.
          hotkeyServiceProvider.overrideWith(_NoopHotkeyService.new),
          recordingOrchestratorProvider.overrideWith(
            OnboardingFakeOrchestrator.new,
          ),
          onboardingTestRecordingSucceededProvider.overrideWith(
            _PracticeDone.new,
          ),
          modelDownloadProvider.overrideWith(OnboardingFakeWhisper.new),
          parakeetDownloadProvider.overrideWith(OnboardingFakeParakeet.new),
          telemetryProvider.overrideWith(
            (ref) => TelemetryService(
              client: client,
              endpointUrl: 'https://stats.example.invalid',
              siteId: 1,
              consentGranted: true,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('paging through welcome and privacy holds every event', (
    tester,
  ) async {
    await pump(tester);
    await tapOnboardingNext(tester); // welcome -> about
    expect(onboardingPage(OnboardingStepId.about), findsOneWidget);
    expect(posts, 0, reason: 'no event may leave before the privacy choice');
    expect(mic.requests, 0, reason: 'no OS microphone prompt on paging');
  });

  // The privacy switches live on the last page, next to the start
  // action. The choice is committed when the flow completes there, so the
  // held events wait until then.
  Future<void> walkToLastPage(WidgetTester tester) async {
    final total = buildOnboardingStepIds().length;
    for (var page = 1; page < total; page++) {
      await tapOnboardingNext(tester);
    }
    expect(onboardingPage(OnboardingStepId.privacy), findsOneWidget);
    expect(
      find.byKey(kPrivacyStepPageKey),
      findsOneWidget,
      reason: 'the privacy switches are on the last page',
    );
  }

  testWidgets('the held events go out only when the flow starts on the last '
      'page with the default switches', (tester) async {
    await pump(tester);
    await walkToLastPage(tester);
    expect(posts, 0, reason: 'nothing is committed before completion');
    expect(
      tester
          .widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey))
          .onPressed,
      isNotNull,
      reason: 'the start action is open',
    );
    await tapOnboardingNext(tester);
    expect(posts, greaterThan(0), reason: 'the commit releases the hold');
    expect(
      actions,
      containsAllInOrder(['step', 'step_next', 'step', 'complete']),
      reason: 'the funnel: pages shown and left, then complete',
    );
    expect(
      actions.where(
        (a) => a.startsWith('review_') || a.startsWith('revision_'),
      ),
      isEmpty,
      reason: 'a first run never sends rerun actions',
    );
    expect(mic.requests, 0, reason: 'the mic prompt waits for the access step');
  });

  testWidgets('choice "off" drops the held events and nothing is sent later', (
    tester,
  ) async {
    await pump(
      tester,
      settings: AppSettings.defaults.copyWith(shareUsageStats: false),
    );
    await walkToLastPage(tester);
    await tapOnboardingNext(tester);
    expect(posts, 0);
  });
}
