/// Widget tests for [TestRecordingStep] (guided test recording content on
/// the final onboarding page).
///
/// Verifies the three visual states (Default / Recording / Done) driven by
/// [recordingProvider]'s phase and by [RecordingOrchestrator.sandboxTranscriptSink]
/// — the seam that redirects a finished transcript into the sandbox field
/// instead of the real clipboard/paste path. Recording is simulated through
/// this fake seam rather than a full real-pipeline integration test (audio
/// capture, STT server) per the issue's testing guidance. Navigation is
/// owned by the onboarding shell and covered in `onboarding_flow_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/features/onboarding/steps/mic_permission_chip.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

/// Skips the real pipeline wiring ([RecordingOrchestrator.build] normally
/// initialises a state machine, OOM handler, and prewarms the STT server) —
/// this suite only exercises the sandbox-transcript seam
/// ([RecordingOrchestrator.sandboxTranscriptSink]), never the real pipeline.
///
/// [toggleRecording] is faked to (a) count invocations — proving the step's
/// record button routes through the exact orchestrator method the hotkey
/// handler uses — and (b) drive the shared [recordingProvider] phase plus,
/// on stop, run the same transcript-routing decision as the real
/// `_handleAfterTranscription`: sink set → sandbox, sink null → the real
/// paste/clipboard route (recorded in [deliveredToPasteRoute], which must
/// stay empty for the safety guarantee).
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  int toggleRecordingCalls = 0;

  /// Transcript the next stop delivers.
  String transcriptToDeliver = 'Sandboxed test transcript.';

  /// Every transcript that would have reached the REAL clipboard/paste
  /// route (i.e. was delivered while [sandboxTranscriptSink] was null).
  final deliveredToPasteRoute = <String>[];

  @override
  void build() {}

  @override
  Future<void> toggleRecording() async {
    toggleRecordingCalls++;
    final recording = ref.read(recordingProvider);
    if (recording.isRecording) {
      ref.read(recordingProvider.notifier).stopRecording();
      _deliver(transcriptToDeliver);
      ref
          .read(recordingProvider.notifier)
          .completeTranscription(transcriptToDeliver);
      return;
    }
    if (recording.phase == RecordingPhase.transcribing) return;
    ref.read(recordingProvider.notifier).startRecording();
  }

  /// Mirrors the real orchestrator's `_handleAfterTranscription` routing:
  /// the sandbox sink short-circuits the real paste path if and only if it
  /// is currently wired.
  void _deliver(String text) {
    final sink = sandboxTranscriptSink;
    if (sink != null) {
      sink(text);
    } else {
      deliveredToPasteRoute.add(text);
    }
  }
}

late L10n l10n;

Future<_FakeRecordingOrchestrator> _pumpStep(
  WidgetTester tester, {
  AppSettings? settings,
}) async {
  late _FakeRecordingOrchestrator captured;
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: TestRecordingStep()),
      size: const Size(1280, 980),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
        // The mic chip beside the hotkey checks its status on mount; keep
        // that off the real audio plugin.
        micPermissionCheckerProvider.overrideWithValue(
          const _InertMicPermissionChecker(),
        ),
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
  _FakeSettingsNotifier([this._settings]);

  final AppSettings? _settings;

  @override
  Future<AppSettings> build() async => _settings ?? AppSettings.defaults;
}

class _InertMicPermissionChecker implements MicPermissionChecker {
  const _InertMicPermissionChecker();

  @override
  Future<bool> check({required bool request}) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('TestRecordingStep — Default state', () {
    testWidgets('renders title, hotkey chip, and placeholder', (tester) async {
      await _pumpStep(tester);

      expect(find.text(l10n.onboardingTestRecordingTitle), findsOneWidget);
      expect(find.byType(HotkeyDisplay), findsOneWidget);
      // The microphone status sits beside the hotkey, on the page that
      // actually needs a microphone — it used to announce itself on page 1,
      // four pages before anything could use it.
      expect(find.byType(MicPermissionChip), findsOneWidget);
      expect(find.text(l10n.onboardingMicChipPending), findsOneWidget);
      expect(
        find.text(l10n.onboardingTestRecordingPlaceholder),
        findsOneWidget,
      );
    });
  });

  group('TestRecordingStep — Recording state', () {
    testWidgets(
      'shows the in-progress status line while recordingProvider.phase is '
      'recording',
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
      },
    );
  });

  group('TestRecordingStep — Done state', () {
    testWidgets(
      'delivering a transcript via sandboxTranscriptSink shows the text in '
      'the sandbox field (not the clipboard) plus the success message',
      (tester) async {
        final orchestrator = await _pumpStep(tester);

        orchestrator.sandboxTranscriptSink!('Hallo Welt, das ist ein Test.');
        await tester.pumpAndSettle();

        expect(find.text('Hallo Welt, das ist ein Test.'), findsOneWidget);
        expect(
          find.text(l10n.onboardingTestRecordingDoneMessage),
          findsOneWidget,
        );
      },
    );
  });

  group('TestRecordingStep — record button (UI-driven start/stop)', () {
    testWidgets('idle: button shows the start label and a tap routes through '
        'toggleRecording() — the same orchestrator method the hotkey uses', (
      tester,
    ) async {
      final orchestrator = await _pumpStep(tester);

      expect(find.text(l10n.onboardingTestRecordingStartCta), findsOneWidget);
      await tester.tap(find.byKey(kTestRecordingStepRecordButtonKey));
      await tester.pumpAndSettle();

      expect(orchestrator.toggleRecordingCalls, 1);
      // The fake mirrors the real toggle: idle → recording.
      expect(find.text(l10n.onboardingTestRecordingStopCta), findsOneWidget);
      expect(find.text(l10n.onboardingTestRecordingInProgress), findsOneWidget);
    });

    testWidgets('button state follows recordingPhaseProvider: stop label while '
        'recording, disabled while transcribing', (tester) async {
      await _pumpStep(tester);
      final element = tester.element(find.byType(TestRecordingStep));
      final container = ProviderScope.containerOf(element);

      container.read(recordingProvider.notifier).startRecording();
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingTestRecordingStopCta), findsOneWidget);
      expect(
        tester
            .widget<WpHeroButton>(find.byKey(kTestRecordingStepRecordButtonKey))
            .onPressed,
        isNotNull,
      );

      container.read(recordingProvider.notifier).stopRecording();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WpHeroButton>(find.byKey(kTestRecordingStepRecordButtonKey))
            .onPressed,
        isNull,
        reason: 'While transcribing the button must be disabled.',
      );
    });

    testWidgets('SAFETY: a full button-driven start→stop cycle delivers the '
        'transcript exclusively to the sandbox sink — never to the real '
        'paste/clipboard route', (tester) async {
      final orchestrator = await _pumpStep(tester);

      // Start via button …
      await tester.tap(find.byKey(kTestRecordingStepRecordButtonKey));
      await tester.pumpAndSettle();
      // … the sandbox seam must still be wired mid-recording …
      expect(
        orchestrator.sandboxTranscriptSink,
        isNotNull,
        reason:
            'The sandbox sink must stay wired across a button-driven '
            'start — a lost sink would write into the last-focused '
            'foreign app.',
      );
      // … stop via button: the fake runs the real routing decision
      // (sink set → sandbox, sink null → paste route).
      await tester.tap(find.byKey(kTestRecordingStepRecordButtonKey));
      await tester.pumpAndSettle();

      expect(
        orchestrator.deliveredToPasteRoute,
        isEmpty,
        reason:
            'Under no circumstances may a test-recording transcript reach '
            'the real clipboard/paste route.',
      );
      expect(find.text('Sandboxed test transcript.'), findsOneWidget);
      expect(
        find.text(l10n.onboardingTestRecordingDoneMessage),
        findsOneWidget,
      );
    });
  });

  group('TestRecordingStep — completion gate state', () {
    testWidgets('a non-empty sandbox transcript flips '
        'onboardingTestRecordingSucceededProvider to true and hides the '
        'completion hint', (tester) async {
      final orchestrator = await _pumpStep(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TestRecordingStep)),
      );

      expect(container.read(onboardingTestRecordingSucceededProvider), false);
      expect(
        find.text(l10n.onboardingTestRecordingCompletionHint),
        findsOneWidget,
        reason:
            'While the gate is unmet the step must name the reason the '
            'completion CTA is disabled.',
      );

      orchestrator.sandboxTranscriptSink!('Hello sandbox');
      await tester.pumpAndSettle();

      expect(container.read(onboardingTestRecordingSucceededProvider), true);
      expect(
        find.text(l10n.onboardingTestRecordingCompletionHint),
        findsNothing,
      );
    });

    testWidgets(
      'a whitespace-only transcript does NOT count as recognised speech',
      (tester) async {
        final orchestrator = await _pumpStep(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TestRecordingStep)),
        );

        orchestrator.sandboxTranscriptSink!('   ');
        await tester.pumpAndSettle();

        expect(
          container.read(onboardingTestRecordingSucceededProvider),
          false,
          reason:
              'Silence must not unlock the completion gate — the gate is '
              'the proof that speech was recognised.',
        );
      },
    );

    testWidgets('escape hatch: tapping "continue without a microphone" sets '
        'onboardingMicBypassProvider and shows the honest consequence note', (
      tester,
    ) async {
      await _pumpStep(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TestRecordingStep)),
      );

      expect(container.read(onboardingMicBypassProvider), false);
      expect(
        find.text(l10n.onboardingTestRecordingMicBypassHint),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(kTestRecordingStepMicBypassButtonKey),
      );
      await tester.tap(find.byKey(kTestRecordingStepMicBypassButtonKey));
      await tester.pumpAndSettle();

      expect(container.read(onboardingMicBypassProvider), true);
      expect(
        find.text(l10n.onboardingTestRecordingMicBypassHint),
        findsOneWidget,
      );
      expect(
        find.byKey(kTestRecordingStepMicBypassButtonKey),
        findsNothing,
        reason: 'The one-shot escape hatch disappears once taken.',
      );
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
              micPermissionCheckerProvider.overrideWithValue(
                const _InertMicPermissionChecker(),
              ),
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

  // Migrated from the appearance block when that became its own page: the
  // note answers "when does a recording stop by itself", so it belongs on
  // the page where the first recording is made.
  group('TestRecordingStep — recording duration note', () {
    testWidgets('shows the configured maxRecordDuration value, not a '
        'hard-coded default', (tester) async {
      await _pumpStep(
        tester,
        settings: const AppSettings(
          behavior: BehaviorSettings(maxRecordDuration: 90),
        ),
      );

      expect(find.byKey(kTestRecordingStepMaxDurationHintKey), findsOneWidget);
      expect(
        find.text(
          l10n.onboardingMaxRecordDurationHint(
            90,
            l10n.settingsRecordingSafety,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows 120 seconds with the untouched defaults', (
      tester,
    ) async {
      await _pumpStep(tester);

      expect(AppSettings.defaults.behavior.maxRecordDuration, 120);
      expect(
        find.text(
          l10n.onboardingMaxRecordDurationHint(
            120,
            l10n.settingsRecordingSafety,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides the note entirely when the limit is 0 (unlimited)', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        settings: const AppSettings(
          behavior: BehaviorSettings(maxRecordDuration: 0),
        ),
      );

      expect(find.byKey(kTestRecordingStepMaxDurationHintKey), findsNothing);
    });
  });
}
