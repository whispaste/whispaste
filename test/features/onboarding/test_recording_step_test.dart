/// Widget tests for [TestRecordingStep] — the first-dictation practice chat
/// (Onboarding v6, V06, acceptance criteria 1–5).
///
/// The orchestrator is faked: its [toggleRecording] drives the shared
/// [recordingProvider] phase and, on stop, routes the transcript the way the
/// real `_deliverToSandbox` does (sink + the step's paster). History and the
/// native paste are covered by `recording_orchestrator_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
import 'package:whispaste/features/onboarding/onboarding_download_provider.dart';
import 'package:whispaste/features/onboarding/onboarding_download_status.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show HotkeyService, hotkeyServiceProvider;
import 'package:whispaste/services/download_error_kind.dart';
import 'package:whispaste/services/download_tls_failure.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

/// Replaces the real pipeline: [toggleRecording] flips the recording phase and
/// on stop delivers [transcriptToDeliver] through the practice seam, exactly
/// as `_deliverToSandbox` does (sink receives the paste outcome).
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  int toggleRecordingCalls = 0;

  /// Transcript the next stop delivers. Blank means silence.
  String transcriptToDeliver = 'Hallo Welt, das ist ein Test.';

  @override
  void build() {}

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
    String? languageOverride,
    double? silenceTimeoutOverride,
  }) async {
    toggleRecordingCalls++;
    final recording = ref.read(recordingProvider);
    if (recording.isRecording) {
      ref.read(recordingProvider.notifier).stopRecording();
      await _deliver(transcriptToDeliver);
      ref
          .read(recordingProvider.notifier)
          .completeTranscription(transcriptToDeliver);
      return;
    }
    if (recording.phase == RecordingPhase.transcribing) return;
    ref.read(recordingProvider.notifier).startRecording();
  }

  Future<void> _deliver(String text) async {
    final sink = sandboxTranscriptSink;
    if (sink == null) return;
    if (text.trim().isEmpty) {
      sink(text, null);
      return;
    }
    final paster = sandboxPaster;
    if (paster == null) {
      sink(text, PasteOutcome.platformUnavailable);
      return;
    }
    final outcome = await paster.paste(
      text,
      const PasteOptions(autoPasteDelayMs: 0, blocklist: ''),
    );
    sink(text, outcome);
  }
}

/// A paster that reports a fixed outcome, to exercise the receipt states
/// without a real insert: `success` for a read receipt, `unconfirmedNoBridge`
/// for a paste nothing could confirm.
class _FixedOutcomePaster implements Paster {
  _FixedOutcomePaster(this.outcome);

  final PasteOutcome outcome;

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async =>
      outcome;

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      outcome;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);

  @override
  Future<String?> getTargetBundleId() async => null;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([this._settings]);

  final AppSettings? _settings;

  @override
  Future<AppSettings> build() async => _settings ?? AppSettings.defaults;
}

/// Hotkey service that reports the platform key-up capability it is given.
class _HotkeyService extends HotkeyService {
  _HotkeyService({required this.keyUp});

  final bool keyUp;

  @override
  void build() {}

  @override
  bool get supportsKeyUp => keyUp;
}

class _MicNotifier extends MicPermissionNotifier {
  _MicNotifier(this.status);

  final MicPermissionStatus status;

  @override
  MicPermissionState build() => MicPermissionState(status: status);
}

class _PasteNotifier extends PasteCapabilityNotifier {
  _PasteNotifier({this.missing = false});

  final bool missing;

  @override
  PasteCapabilityState build() => PasteCapabilityState(
    capability: PasteCapability(
      status: missing
          ? PasteCapabilityStatus.permissionMissing
          : PasteCapabilityStatus.ready,
    ),
  );
}

/// Parakeet bundle downloader with a fixed starting state. Retries are counted
/// in [starts] and never fetch.
class _ParakeetNotifier extends ParakeetDownloadNotifier {
  _ParakeetNotifier(this.initial, this.starts);

  final ParakeetDownloadState initial;
  final List<int> starts;

  @override
  ParakeetDownloadState build() => initial;

  @override
  Future<void> downloadBundle() async {
    starts.add(starts.length + 1);
    state = const ParakeetDownloadState(
      phase: ParakeetDownloadPhase.downloading,
    );
  }
}

class _DownloadingNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(
    phase: DownloadPhase.downloading,
    progressPercent: 42,
    bytesDownloaded: 42,
    totalBytes: 100,
  );
}

/// A download status the test can move, to drive the lock from loading to
/// ready while the page is on screen.
class _SettableStatus extends OnboardingDownloadStatusNotifier {
  _SettableStatus(this._initial);
  final OnboardingDownloadStatus _initial;

  @override
  OnboardingDownloadStatus build() => _initial;

  void set(OnboardingDownloadStatus status) => state = status;
}

class _FixedStatus extends OnboardingDownloadStatusNotifier {
  _FixedStatus(this._status);
  final OnboardingDownloadStatus _status;

  @override
  OnboardingDownloadStatus build() => _status;
}

late L10n l10n;

class _Harness {
  _Harness(this.orchestrator);

  final _FakeRecordingOrchestrator orchestrator;
}

Future<_Harness> _pumpStep(
  WidgetTester tester, {
  bool modelReady = true,
  bool downloading = false,
  MicPermissionStatus mic = MicPermissionStatus.granted,
  bool pasteMissing = false,
  Locale locale = const Locale('en'),
  Size size = const Size(1280, 980),
  Widget? wrapper,
  bool downloadState = false,
  AppSettings? settings,
  bool keyUp = true,
  ParakeetDownloadState? parakeet,
  List<int>? parakeetStarts,
  OnboardingDownloadStatus? movingStatus,
}) async {
  late _FakeRecordingOrchestrator captured;
  const step = TestRecordingStep();
  await tester.pumpWidget(
    makeTestable(
      wrapper ?? const SingleChildScrollView(child: step),
      size: size,
      locale: locale,
      disableAnimations: true,
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
        hotkeyServiceProvider.overrideWith(() => _HotkeyService(keyUp: keyUp)),
        // The practice page reads the selected engine's status. A fixed status
        // stands in unless the test drives a real download fake below, whose
        // phase then reaches the page through the real status provider.
        if (movingStatus != null)
          onboardingDownloadStatusProvider.overrideWith(
            () => _SettableStatus(movingStatus),
          )
        else if (!downloadState && parakeet == null)
          onboardingDownloadStatusProvider.overrideWith(
            () => _FixedStatus(
              modelReady
                  ? const OnboardingDownloadStatus(
                      phase: OnboardingDownloadPhase.ready,
                    )
                  : downloading
                  ? const OnboardingDownloadStatus(
                      phase: OnboardingDownloadPhase.running,
                      bytesDone: 42,
                      bytesTotal: 100,
                    )
                  : const OnboardingDownloadStatus(
                      phase: OnboardingDownloadPhase.idle,
                    ),
            ),
          ),
        if (downloadState)
          modelDownloadProvider.overrideWith(_DownloadingNotifier.new),
        if (parakeet != null)
          parakeetDownloadProvider.overrideWith(
            () => _ParakeetNotifier(parakeet, parakeetStarts ?? []),
          ),
        micPermissionNotifierProvider.overrideWith(() => _MicNotifier(mic)),
        pasteCapabilityNotifierProvider.overrideWith(
          () => _PasteNotifier(missing: pasteMissing),
        ),
        recordingOrchestratorProvider.overrideWith(() {
          captured = _FakeRecordingOrchestrator();
          return captured;
        }),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(captured);
}

/// Starts or stops a dictation the way the hotkey does, through the
/// orchestrator. The practice chat has no microphone button any more.
Future<void> _toggle(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TestRecordingStep)),
  );
  await container
      .read(recordingOrchestratorProvider.notifier)
      .toggleRecording();
  await tester.pumpAndSettle();
}

/// Starts, then stops, a dictation, which delivers the orchestrator's transcript.
Future<void> _dictate(WidgetTester tester) async {
  await _toggle(tester);
  await _toggle(tester);
}

bool _hasText(String text) => find.text(text).evaluate().isNotEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = lookupL10n(const Locale('en'));
  });

  group('practice chat — default state', () {
    testWidgets('WhisPaste asks the question, without an input row', (
      tester,
    ) async {
      await _pumpStep(tester);

      expect(_hasText(l10n.onboardingPracticeQuestion), isTrue);
      expect(
        find.byType(WpTextField),
        findsNothing,
        reason: 'the practice chat has no typed reply, only dictation',
      );
      expect(_hasText(l10n.onboardingPracticeWaiting), isFalse);
    });
  });

  group('AK 1–2: dictation lands in the field, then the chat confirms', () {
    testWidgets(
      'the dictated text becomes the user message, WhisPaste confirms, and the gate opens',
      (tester) async {
        final h = await _pumpStep(tester);

        await _dictate(tester);

        expect(_hasText('Hallo Welt, das ist ein Test.'), isTrue);
        expect(_hasText(l10n.onboardingPracticeReceived), isTrue);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TestRecordingStep)),
        );
        expect(
          container.read(onboardingTestRecordingSucceededProvider),
          isTrue,
        );
        expect(h.orchestrator.toggleRecordingCalls, 2);
      },
    );

    testWidgets(
      'a dictation the field took with a read receipt counts as success',
      (tester) async {
        final h = await _pumpStep(tester);
        h.orchestrator.sandboxPaster = _FixedOutcomePaster(
          PasteOutcome.success,
        );

        await _dictate(tester);

        expect(_hasText(l10n.onboardingPracticeReceived), isTrue);
      },
    );
  });

  group('AK 3: silence is a message, not a result', () {
    testWidgets('a blank transcript shows the silence message and no success', (
      tester,
    ) async {
      final h = await _pumpStep(tester);
      h.orchestrator.transcriptToDeliver = '   ';

      await _dictate(tester);

      expect(_hasText(l10n.onboardingPracticeSilence), isTrue);
      expect(_hasText(l10n.onboardingPracticeReceived), isFalse);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TestRecordingStep)),
      );
      expect(container.read(onboardingTestRecordingSucceededProvider), isFalse);
    });
  });

  group('AK 4: a failed or unconfirmed paste never reads as success', () {
    testWidgets(
      'an unconfirmed paste says the text is on the clipboard and does not succeed',
      (tester) async {
        final h = await _pumpStep(tester);
        h.orchestrator.sandboxPaster = _FixedOutcomePaster(
          PasteOutcome.unconfirmedNoBridge,
        );

        await _dictate(tester);

        expect(_hasText(l10n.onboardingPracticePasteFailed), isTrue);
        expect(_hasText(l10n.onboardingPracticeReceived), isFalse);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TestRecordingStep)),
        );
        expect(
          container.read(onboardingTestRecordingSucceededProvider),
          isFalse,
        );
      },
    );
  });

  group('hold or toggle wording follows the mode in effect (V05)', () {
    AppSettings toggleSettings() => AppSettings.defaults.copyWithSections(
      audioInput: AudioInputSettings.defaults.copyWith(pushToTalk: false),
    );

    testWidgets('a recording in hold mode says that release stops it', (
      tester,
    ) async {
      await _pumpStep(tester);

      await _toggle(tester);

      expect(_hasText(l10n.onboardingTestRecordingInProgressHold), isTrue);
      expect(_hasText(l10n.onboardingTestRecordingInProgress), isFalse);
    });

    testWidgets(
      'a recording in toggle mode says that pressing again stops it',
      (tester) async {
        await _pumpStep(tester, settings: toggleSettings());

        await _toggle(tester);

        expect(_hasText(l10n.onboardingTestRecordingInProgress), isTrue);
        expect(_hasText(l10n.onboardingTestRecordingInProgressHold), isFalse);
      },
    );
  });

  group('model download failures are visible with a next step', () {
    testWidgets(
      'a failed Parakeet download names the cause and offers a retry that '
      'starts the download again',
      (tester) async {
        final starts = <int>[];
        await _pumpStep(
          tester,
          modelReady: false,
          settings: AppSettings.defaults.copyWith(
            sttEngine: OnDeviceEngine.parakeet.value,
          ),
          parakeet: const ParakeetDownloadState(
            phase: ParakeetDownloadPhase.error,
            errorKind: DownloadErrorKind.tls,
            errorMessage: downloadTlsErrorCode,
          ),
          parakeetStarts: starts,
        );

        expect(
          _hasText(l10n.onboardingPracticeModelMissing),
          isFalse,
          reason: 'a failure is not the same as a model that was never loaded',
        );
        expect(_hasText(l10n.downloadTlsError), isTrue);
        await tester.tap(find.text(l10n.actionRetry));
        await tester.pumpAndSettle();

        expect(starts, hasLength(1));
      },
    );

    testWidgets(
      'without a download the chat says why and offers to load the model',
      (tester) async {
        final starts = <int>[];
        await _pumpStep(
          tester,
          modelReady: false,
          settings: AppSettings.defaults.copyWith(
            sttEngine: OnDeviceEngine.parakeet.value,
          ),
          parakeet: const ParakeetDownloadState(),
          parakeetStarts: starts,
        );

        expect(_hasText(l10n.onboardingPracticeModelMissing), isTrue);
        await tester.tap(find.text(l10n.onboardingLoadModel));
        await tester.pumpAndSettle();

        expect(starts, hasLength(1));
      },
    );
  });

  group('model download and missing permissions', () {
    testWidgets(
      'while the speech model downloads, the chat shows the progress and dictation is off',
      (tester) async {
        await _pumpStep(
          tester,
          modelReady: false,
          downloading: true,
          downloadState: true,
        );

        expect(
          find.textContaining('42'),
          findsWidgets,
          reason: 'progress comes from the running download, shown in chat',
        );
        expect(
          find.byType(WpTextField),
          findsNothing,
          reason: 'no typed fallback while the model downloads',
        );
      },
    );

    testWidgets(
      'a missing microphone permission is one WhisPaste note with one action',
      (tester) async {
        await _pumpStep(tester, mic: MicPermissionStatus.denied);

        expect(_hasText(l10n.onboardingPracticeMicMissing), isTrue);
        expect(find.text(l10n.onboardingPracticeMicAllow), findsOneWidget);
      },
    );
  });

  group('the try-out lock while the speech model is not ready', () {
    testWidgets('the page hands the orchestrator a lock and shows the card, '
        'not the practice field', (tester) async {
      final h = await _pumpStep(
        tester,
        movingStatus: const OnboardingDownloadStatus(
          phase: OnboardingDownloadPhase.running,
          bytesDone: 42,
          bytesTotal: 100,
        ),
      );

      expect(h.orchestrator.sandboxLocked?.call(), isTrue);
      expect(h.orchestrator.sandboxPressRefused, isNotNull);
      expect(_hasText(l10n.onboardingTryoutLockTitle), isTrue);
      expect(find.byType(WpTextField), findsNothing);
    });

    testWidgets('the lock lifts by itself when the model is ready, and the '
        'practice field comes back without an error', (tester) async {
      final h = await _pumpStep(
        tester,
        movingStatus: const OnboardingDownloadStatus(
          phase: OnboardingDownloadPhase.running,
          bytesDone: 42,
          bytesTotal: 100,
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TestRecordingStep)),
      );

      (container.read(onboardingDownloadStatusProvider.notifier)
              as _SettableStatus)
          .set(
            const OnboardingDownloadStatus(
              phase: OnboardingDownloadPhase.ready,
            ),
          );
      await tester.pumpAndSettle();

      expect(h.orchestrator.sandboxLocked?.call(), isFalse);
      expect(_hasText(l10n.onboardingTryoutLockTitle), isFalse);
      expect(_hasText(l10n.onboardingPracticeQuestion), isTrue);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the unlock must not notify the page during its own build',
      );
    });
  });
}

/// The hotkey text the chat names: the default hotkey, as the step resolves
/// it from [AppSettings.defaults] without a fallback.
