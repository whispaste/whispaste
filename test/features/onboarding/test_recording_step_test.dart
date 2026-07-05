/// Widget tests for [TestRecordingStep] (onboarding — guided test recording
/// shown right before the Ready step).
///
/// Verifies the three visual states (Default / Recording / Done) driven by
/// [recordingProvider]'s phase and by [RecordingOrchestrator.sandboxTranscriptSink]
/// — the seam that redirects a finished transcript into the sandbox field
/// instead of the real clipboard/paste path. Recording is simulated through
/// this fake seam rather than a full real-pipeline integration test (audio
/// capture, STT server) per the issue's testing guidance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

import '../../fixtures/test_helpers.dart';

void _noop() {}

/// Skips the real pipeline wiring ([RecordingOrchestrator.build] normally
/// initialises a state machine, OOM handler, and prewarms the STT server) —
/// this suite only exercises the sandbox-transcript seam
/// ([RecordingOrchestrator.sandboxTranscriptSink]), never the real pipeline.
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  @override
  void build() {}
}

late L10n l10n;

Future<_FakeRecordingOrchestrator> _pumpStep(WidgetTester tester) async {
  late _FakeRecordingOrchestrator captured;
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(
        child: TestRecordingStep(onNext: _noop, onBack: _noop),
      ),
      size: const Size(1280, 980),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
        recordingOrchestratorProvider.overrideWith(() {
          captured = _FakeRecordingOrchestrator();
          return captured;
        }),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('TestRecordingStep — Default state', () {
    testWidgets('renders title, hotkey chip, placeholder, and skip link', (
      tester,
    ) async {
      await _pumpStep(tester);

      expect(find.text(l10n.onboardingTestRecordingTitle), findsOneWidget);
      expect(find.byType(HotkeyDisplay), findsOneWidget);
      expect(
        find.text(l10n.onboardingTestRecordingPlaceholder),
        findsOneWidget,
      );
      expect(find.byKey(kTestRecordingStepSkipLinkKey), findsOneWidget);
    });

    testWidgets('"Weiter" (Next) is enabled with no recording attempted', (
      tester,
    ) async {
      await _pumpStep(tester);

      final button = tester.widget<WpAccentButton>(
        find.byKey(kTestRecordingStepNextButtonKey),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('TestRecordingStep — Recording state', () {
    testWidgets(
      'shows the in-progress status line while recordingProvider.phase is '
      'recording, and keeps "Weiter" enabled',
      (tester) async {
        await _pumpStep(tester);

        final element = tester.element(find.byType(TestRecordingStep));
        final container = ProviderScope.containerOf(element);
        container.read(recordingProvider.notifier).startRecording();
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.onboardingTestRecordingInProgress),
          findsOneWidget,
        );
        expect(
          find.text(l10n.onboardingTestRecordingPlaceholder),
          findsNothing,
        );

        final button = tester.widget<WpAccentButton>(
          find.byKey(kTestRecordingStepNextButtonKey),
        );
        expect(button.onPressed, isNotNull);
      },
    );
  });

  group('TestRecordingStep — Done state', () {
    testWidgets(
      'delivering a transcript via sandboxTranscriptSink shows the text and '
      'success message, and hides the skip link',
      (tester) async {
        final orchestrator = await _pumpStep(tester);

        orchestrator.sandboxTranscriptSink!('Hallo Welt, das ist ein Test.');
        await tester.pumpAndSettle();

        expect(find.text('Hallo Welt, das ist ein Test.'), findsOneWidget);
        expect(
          find.text(l10n.onboardingTestRecordingDoneMessage),
          findsOneWidget,
        );
        expect(find.byKey(kTestRecordingStepSkipLinkKey), findsNothing);

        final button = tester.widget<WpAccentButton>(
          find.byKey(kTestRecordingStepNextButtonKey),
        );
        expect(
          button.onPressed,
          isNotNull,
          reason:
              '"Weiter" must stay enabled after a successful test — neither '
              'path is gated on recording success.',
        );
      },
    );
  });

  group('TestRecordingStep — navigation', () {
    testWidgets('tapping the skip link invokes onNext', (tester) async {
      var nextCalled = false;
      await tester.pumpWidget(
        makeTestable(
          SingleChildScrollView(
            child: TestRecordingStep(
              onNext: () => nextCalled = true,
              onBack: _noop,
            ),
          ),
          size: const Size(1280, 980),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
            recordingOrchestratorProvider.overrideWith(
              _FakeRecordingOrchestrator.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kTestRecordingStepSkipLinkKey));
      await tester.pumpAndSettle();

      expect(nextCalled, isTrue);
    });
  });

  group('TestRecordingStep — sandbox seam disposal', () {
    testWidgets(
      'unmounting the step clears sandboxTranscriptSink so later callers are '
      'unaffected',
      (tester) async {
        final orchestrator = await _pumpStep(tester);
        expect(orchestrator.sandboxTranscriptSink, isNotNull);

        // Replace the tree to trigger dispose. Riverpod's ProviderScope
        // forbids changing the number of overrides on a rebuild of the same
        // scope element, so the override count must match the initial pump.
        await tester.pumpWidget(
          makeTestable(
            const SizedBox.shrink(),
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
              recordingOrchestratorProvider.overrideWith(
                _FakeRecordingOrchestrator.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(orchestrator.sandboxTranscriptSink, isNull);
      },
    );
  });
}
