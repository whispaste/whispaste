/// A recording refused by the onboarding guard gets no error toast while the
/// onboarding is open: the hotkey step shows its own reaction (the key caps
/// light up), and the toast contradicted it on win-vm (Onboarding v6, V05).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

/// Recording state the test can put into the error phase.
class _FakeRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();

  void refuse(String code) =>
      state = RecordingState(phase: RecordingPhase.error, errorMessage: code);

  void finish(String text) =>
      state = RecordingState(phase: RecordingPhase.done, transcript: text);
}

/// Lets the toast timers and animations run out, then unmounts the tree and
/// flushes the zero-length timer the database close leaves behind.
Future<void> _settleAndUnmount(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(seconds: 11));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

late L10n l10n;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool onboardingActive,
}) async {
  await tester.pumpWidget(
    makeTestable(
      const WpRecordingBehavior(child: Scaffold(body: SizedBox())),
      overrides: [
        onboardingSurfaceActiveProvider.overrideWithValue(onboardingActive),
        recordingProvider.overrideWith(_FakeRecording.new),
        settingsProvider.overrideWith(_OnboardingSettings.new),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(WpRecordingBehavior)),
  );
}

class _OnboardingSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('refused recording while onboarding is open', () {
    test('only the onboarding guard code is silenced, and only while '
        'onboarding is open', () {
      expect(
        isSilentOnboardingRefusal(
          'onboarding_not_completed',
          onboardingActive: true,
        ),
        isTrue,
      );
      expect(
        isSilentOnboardingRefusal(
          'onboarding_not_completed',
          onboardingActive: false,
        ),
        isFalse,
        reason: 'after onboarding the same refusal is a real error',
      );
      expect(
        isSilentOnboardingRefusal(
          'stt_model_not_found',
          onboardingActive: true,
        ),
        isFalse,
        reason: 'other errors still reach the user during onboarding',
      );
    });

    testWidgets('shows no error toast and no error line for the guard code', (
      tester,
    ) async {
      final container = await _pump(tester, onboardingActive: true);

      (container.read(recordingProvider.notifier) as _FakeRecording).refuse(
        'onboarding_not_completed',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l10n.errorOnboardingNotCompleted), findsNothing);
      await _settleAndUnmount(tester);
    });

    testWidgets('the same refusal shows its toast once onboarding is over', (
      tester,
    ) async {
      final container = await _pump(tester, onboardingActive: false);

      (container.read(recordingProvider.notifier) as _FakeRecording).refuse(
        'onboarding_not_completed',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l10n.errorOnboardingNotCompleted), findsOneWidget);
      await _settleAndUnmount(tester);
    });
  });

  group('app toasts while onboarding is open', () {
    testWidgets(
      'the success toast of a dictation is dropped during onboarding',
      (tester) async {
        final container = await _pump(tester, onboardingActive: true);

        (container.read(recordingProvider.notifier) as _FakeRecording).finish(
          'Hallo, hallo.',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('Hallo, hallo.'), findsNothing);
        await _settleAndUnmount(tester);
      },
    );

    testWidgets('a recording error toast is dropped during onboarding', (
      tester,
    ) async {
      final container = await _pump(tester, onboardingActive: true);

      (container.read(recordingProvider.notifier) as _FakeRecording).refuse(
        'stt_model_not_found',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(localizeRecordingError(l10n, 'stt_model_not_found')),
        findsNothing,
      );
      await _settleAndUnmount(tester);
    });

    testWidgets('a recording info toast is dropped during onboarding, and the '
        'notice is consumed so it cannot replay later', (tester) async {
      final container = await _pump(tester, onboardingActive: true);

      container.read(recordingInfoProvider.notifier).show('info_pipeline_busy');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(localizeRecordingInfo(l10n, 'info_pipeline_busy')),
        findsNothing,
      );
      expect(container.read(recordingInfoProvider), isNull);
      await _settleAndUnmount(tester);
    });

    testWidgets('the same info toast shows once onboarding is over', (
      tester,
    ) async {
      final container = await _pump(tester, onboardingActive: false);

      container.read(recordingInfoProvider.notifier).show('info_pipeline_busy');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(localizeRecordingInfo(l10n, 'info_pipeline_busy')),
        findsOneWidget,
      );
      await _settleAndUnmount(tester);
    });
  });
}
