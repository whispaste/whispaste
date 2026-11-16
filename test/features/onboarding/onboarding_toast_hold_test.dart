/// While the onboarding overlay is open no toast appears: a message the setup
/// needs shows on the page instead, and toasts return when the overlay goes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;
import 'package:whispaste/services/hotkey_service.dart'
    show HotkeyService, hotkeyRegistrationStatusProvider, hotkeyServiceProvider;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/widgets/onboarding_hold.dart';

import '../../fixtures/test_helpers.dart';
import 'onboarding_test_doubles.dart';

class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

void main() {
  const noticeKey = ValueKey('onboarding-notice');
  const dismissKey = ValueKey('onboarding-notice-dismiss');
  const actionKey = ValueKey('onboarding-notice-action');
  const hostKey = ValueKey('host');

  /// The overlay while [open], an empty page afterwards: one scope, so the
  /// swap disposes the overlay the way the app shell does.
  Widget app({required bool open}) => makeTestable(
    disableAnimations: true,
    open ? const OnboardingOverlay() : const SizedBox.expand(key: hostKey),
    size: const Size(1280, 1600),
    locale: const Locale('en'),
    overrides: [
      onboardingMicSpeechHeardProvider.overrideWith(
        OnboardingFixedMicSpeech.new,
      ),
      onboardingMicProbeProvider.overrideWithValue(OnboardingFakeMicProbe()),
      audioInputDevicesProvider.overrideWith((ref) async => const ['Default']),
      settingsProvider.overrideWith(
        () => OnboardingFakeSettings(AppSettings.defaults),
      ),
      micPermissionCheckerProvider.overrideWithValue(
        OnboardingCountingMicChecker(),
      ),
      hotkeyRegistrationStatusProvider.overrideWith(OnboardingFakeHotkey.new),
      hotkeyServiceProvider.overrideWith(_NoopHotkeyService.new),
      recordingOrchestratorProvider.overrideWith(
        OnboardingFakeOrchestrator.new,
      ),
      modelDownloadProvider.overrideWith(OnboardingFakeWhisper.new),
      parakeetDownloadProvider.overrideWith(OnboardingFakeParakeet.new),
    ],
  );

  Future<BuildContext> pumpOverlay(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(open: true));
    await tester.pumpAndSettle();
    return tester.element(find.byType(OnboardingOverlay));
  }

  testWidgets('a plain message stays away while onboarding is open', (
    tester,
  ) async {
    final context = await pumpOverlay(tester);

    WpOnboardingHold.add(
      context,
      message: 'saved',
      type: WpMessageType.success,
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(noticeKey), findsNothing);
  });

  testWidgets('an error shows on the page until it is dismissed', (
    tester,
  ) async {
    final context = await pumpOverlay(tester);

    WpOnboardingHold.add(context, message: 'first', type: WpMessageType.error);
    WpOnboardingHold.add(
      context,
      message: 'second',
      type: WpMessageType.warning,
    );
    await tester.pump();
    expect(find.byKey(noticeKey), findsOneWidget);

    await tester.tap(find.byKey(dismissKey));
    await tester.pump();

    await tester.tap(find.byKey(dismissKey));
    await tester.pump();
    expect(find.byKey(noticeKey), findsNothing);
  });

  testWidgets('the action of a held message runs and clears it', (
    tester,
  ) async {
    final context = await pumpOverlay(tester);
    var taps = 0;

    WpOnboardingHold.add(
      context,
      message: 'failed',
      type: WpMessageType.error,
      actionLabel: 'Retry',
      onAction: () => taps++,
    );
    await tester.pump();
    await tester.tap(find.byKey(actionKey));
    await tester.pump();

    expect(taps, 1);
    expect(find.byKey(noticeKey), findsNothing);
  });

  testWidgets('held messages are cleared once the overlay is gone', (
    tester,
  ) async {
    final context = await pumpOverlay(tester);
    WpOnboardingHold.add(
      context,
      message: 'left over',
      type: WpMessageType.error,
    );

    await tester.pumpWidget(app(open: false));
    await tester.pumpAndSettle();
    expect(WpOnboardingHold.held.value, isEmpty);
    expect(WpOnboardingHold.holding, isFalse);
  });
}
