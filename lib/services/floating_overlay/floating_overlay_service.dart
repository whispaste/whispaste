import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/accessibility/announce.dart';
import '../../core/config/language_cycle.dart' show languageChipLabelFor;
import '../../core/config/settings_enums.dart';
import '../../core/config/settings_labels.dart';
import '../../core/config/settings_sections.dart' show cancelDictationKeyEscape;
import '../../core/config/settings_provider.dart';
import '../../core/config/smart_mode_labels.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/ltr_isolate.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/perf_instrumentation.dart';
import '../../core/navigation/page_state.dart'
    show activePageProvider, settingsScrollTargetProvider;
import '../../core/platform/macos_lifecycle_channel.dart';
import '../../core/platform/display_bounds.dart';
import '../../core/platform/monitor_relative_position.dart';
import '../../core/platform/window_position_clamp.dart';
import '../../core/recording/discard_confirmation.dart';
import '../../core/recording/recording_state.dart';
import '../../core/recording/recording_helpers.dart';
import '../../core/theme/overlay_customization.dart';
import '../../core/theme/overlay_design_spec.dart'
    show
        OverlayArcMotion,
        OverlayDesignSpec,
        OverlaySizeVariant,
        OverlayBackground,
        OverlayWave;
import '../audio/quiet_microphone_watch.dart' show micQuietProvider;
import '../recording/duration_countdown.dart';
import '../system_speech/system_speech_channel.dart'
    show systemSpeechOsSupported;
import '../system_speech/system_speech_live_preview.dart';
import '../audio/signal_loss_detector.dart'
    show micNoSignalYetProvider, micSignalLostProvider;
import '../app_commands/app_command.dart';
import '../app_commands/native_menu_adapter.dart';
import '../app_profiles/app_profile_choice.dart';
import '../audio_service.dart' show AudioStatus, audioServiceProvider;
import '../mic_busy_app.dart' show micBusyApp;
import '../floating_platform_service_base.dart';
import '../../widgets/wp_page_notice.dart';
import 'dictation_notice.dart';
import 'pill_hint.dart';
import 'retry_processing.dart';
import 'overlay_notice.dart';
import 'overlay_notice_rules.dart';
import '../hotkey_service.dart'
    show
        activeGlobalHotkey,
        doubleTapFallbackActiveProvider,
        globalHotkeyFallbackActiveProvider,
        hotkeyServiceProvider,
        logicalKeyForCancelDictation,
        logicalKeyForNoticeAction;
import '../paste/repaste_service.dart' show repasteEmptyNoticeProvider;
import '../replacements/learn_correction_hotkey.dart';
import '../recording_orchestrator.dart';
import '../snippets/interactive_snippet_controller.dart';
import '../stt/stt_bundle.dart' show localSttBundleProvider;
import '../transcription/slice_progress.dart';
import 'floating_overlay_controller.dart';
import 'floating_overlay_events.dart';
import 'overlay_positioning.dart';
import 'overlay_key_hints.dart';
import 'overlay_render_recovery.dart';
import 'overlay_shell_gate.dart';
import 'overlay_start_feedback.dart';
import 'waveform_pipeline.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../widgets/recording_behavior.dart'
    show isSilentOnboardingRefusal, localizeRecordingError;

final _log = AppLogger('FloatingOverlayService');

// ── Waveform animation-timer constants ───────────────────────────────────────
//
// The waveform's SHAPE (bar count, min height, attack/release smoothing) lives
// entirely in the SSOT [OverlayDesignSpec.waveform] and is owned by the
// [WaveformPipeline]; the service holds no waveform-shape constants. What
// remains here is only the animation-timer cadence that drives the pipeline.

/// Animation tick period (~33 ms ≈ 30 fps). One bar of waveform history scrolls
/// per tick.
const Duration _kTickPeriod = Duration(milliseconds: 33);

/// Duration (ms) of the trailing release-out animation that follows the
/// `recording → transcribing` phase transition. During this window the
/// pipeline keeps ticking with `pushSample(0.0, …)` so the waveform decays
/// gracefully toward the rest floor instead of freezing at the snapshot
/// moment. After the window elapses the animation timer stops and the last
/// snapshot remains frozen on screen.
///
/// Read from the spec, not spelled out again here: the overlay view's content
/// crossfade ([OverlayArcMotion.releaseOutDuration]) has to cover exactly this
/// window — it is what actually paints the decaying bars — and a private copy
/// of the number is how the two drifted apart in the first place.
const int releaseOutDurationMs = OverlayDesignSpec.waveformReleaseOutMs;

/// Fixed auto-hide delay after the overlay enters the done state.
const Duration kOverlayAutoHideDelay = Duration(seconds: 2);

// ── FloatingPlatformHost note ─────────────────────────────────────────────────
//
// Initialization ordering of the two floating-window services:
//
//   floatingButtonServiceProvider  (FAB)
//   floatingOverlayServiceProvider (Overlay)
//
// Both are keepAlive Notifier providers that are read once during app startup
// in main.dart / app.dart.  The Riverpod dependency graph does NOT impose an
// ordering between them — they are independent.
//
// Race conditions are not possible in practice because each service owns a
// separate native window and communicates with it via its own platform channel.
// The only shared resource is the Riverpod container, which is thread-safe.
//
// If a strict ordering ever becomes necessary (e.g. a shared native host
// process), introduce a `FloatingPlatformHostProvider` that both services
// `ref.watch`, making it a hard dependency node in the graph.  For now the
// comment above is the explicit documentation of the deliberate choice.
//
// ─────────────────────────────────────────────────────────────────────────────

/// Manages the native floating overlay window lifecycle.
///
/// Layer 3 — business logic. Watches recording state, settings, and theme,
/// builds fully-localized [FloatingOverlaySnapshot]s, and sends them to the
/// native overlay window via the platform controller (Layer 2).
///
/// Extends [FloatingPlatformServiceBase] which handles controller creation,
/// event-stream subscription, and cleanup in [ref.onDispose].
class FloatingOverlayService
    extends
        FloatingPlatformServiceBase<
          FloatingOverlayController,
          FloatingOverlayEvent
        > {
  /// Constructs the service.
  ///
  /// [now] is the wall-clock source consumed by the [WaveformPipeline] and
  /// the animation timer. Tests inject a deterministic clock (e.g. via
  /// `package:fake_async`); production code keeps the default
  /// [DateTime.now].
  FloatingOverlayService({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  Timer? _autoHideTimer;

  /// Presses of the card's action key: one runs the first button, two quick
  /// presses the second (#816). A press only acts on the card it was made
  /// for; a card that replaced it in the meantime is left alone.
  late final _noticeKeyPresses = NoticeKeyPresses<DictationNotice>((
    card,
    action,
  ) {
    if (identical(ref.read(dictationNoticeProvider), card)) {
      _onNoticeAction(action.id);
    }
  });

  /// The user asked to change the microphone during a dictation (overlay F2);
  /// Settings open once that dictation is done.
  bool _openMicSettingsWhenDone = false;

  /// Cards the user hid with the cross during the running recording. Cleared
  /// when the next recording starts.
  final Set<OverlayNoticeKind> _hiddenNotices = {};

  /// The lost-signal dictation was ended with its one button; a follow-up card
  /// offers the microphone choice once the text is pasted.
  bool _micFollowUpDue = false;

  /// Animation timer that ticks the [WaveformPipeline] at ~30 Hz and pushes
  /// each snapshot to the native renderer via [FloatingOverlayController.
  /// setWaveformBars]. Active during [RecordingPhase.recording] and during
  /// the trailing release-out window after `recording → transcribing`.
  Timer? _waveformTimer;

  /// True while the service is in the release-out tail that follows the
  /// `recording → transcribing` transition. While set, `audioLevelProvider`
  /// updates are ignored and the timer tick pushes `pushSample(0.0, _now())`
  /// instead, so the waveform decays gracefully via the pipeline's release
  /// smoothing.
  bool _isInReleaseOut = false;

  /// Wall-clock instant at which the current release-out window started.
  /// `null` outside of release-out.
  DateTime? _releaseOutStart;

  /// Single owner of the waveform smoothing + history state. Created lazily
  /// in [onControllerReady] so subclasses can override `createController`
  /// without paying the allocation cost when the platform has no overlay.
  late final WaveformPipeline _pipeline;

  int _generation = 0;

  /// A pill hint (#454) that waits until the pill is free.
  OverlayPillHint? _pendingPillHint;

  /// The pill shows a hint right now, so a newer one may replace it.
  bool _pillHintShowing = false;
  RecordingPhase _lastPhase = RecordingPhase.idle;

  /// Frame-heartbeat recovery for the render engine (macOS, Windows and
  /// Linux; see [RenderEngineRecovery]). Pure policy, driven by the timer below.
  final RenderRecoveryMachine _renderRecovery = RenderRecoveryMachine(
    frameDeadline: kRenderFrameDeadline,
    sessionBudget: kRenderRebootBudget,
    firstEpisodeGrace: kRenderFirstBootGrace,
  );
  Timer? _renderFrameTimer;

  /// Whether the native shell is currently shown, so the heartbeat arms only
  /// on a hidden→visible transition.
  bool _shellShown = false;

  /// Drops redundant hides before they reach the native shell.
  final OverlayShellGate _shellGate = OverlayShellGate();
  L10n? _l10n;

  /// True from the first guided-sequence frame (briefing/announce) until the
  /// overlay next hides. While set, every snapshot forces the NORMAL size
  /// variant regardless of the configured overlay size: the guided flow is
  /// text (field names, positions, key mechanics), and the mini pill paints
  /// no text at all during recording while compact/mini ellipsise the
  /// announce into noise — field-tested root cause of "I see no guidance
  /// whatsoever" (2026-09-01, user ran `overlay_size: mini`). Sticky until
  /// hide on purpose: the sequence's final done frame arrives after the
  /// session state is already null, and flipping back to mini exactly on
  /// the paste-confirmation frame would resize the native shell on the one
  /// frame the user is meant to read.
  bool _interactiveGuidanceActive = false;

  // ── Live/partial transcript (ticket 11 + live-transcript-streaming) ─────

  /// Subscription to the active STT engine's live-transcript stream — either
  /// [SttServerStateNotifier.livePreviewStream] (during
  /// [RecordingPhase.recording]) or [PartialTranscriptSource]'s
  /// `partialTranscript` (during [RecordingPhase.transcribing]), whichever
  /// matches [_lastPhase] — active only while the user opted into
  /// `AppSettings.overlayShowLiveTranscript`. Started/stopped in
  /// [_updateLiveTranscriptLifecycle] rather than once for the service's
  /// whole lifetime: re-reading the stream fresh on every episode picks up
  /// an engine swap (e.g. the GPU→CPU fallback) instead of listening to a
  /// stream a since-replaced engine no longer feeds.
  StreamSubscription<String>? _partialSub;

  /// Text emitted so far by [_partialSub] for the current recording/
  /// transcribing episode. Empty when no live text has arrived yet, the
  /// setting is off, or the active engine has no live-preview/partial
  /// support — [_sendSnapshot] then falls back to the classic timer/
  /// "Transcribing…" text.
  String _liveTranscript = '';

  // ── FloatingPlatformServiceBase contract ──────────────────────────────────

  @override
  FloatingOverlayController? createController() =>
      createFloatingOverlayController();

  @override
  Stream<FloatingOverlayEvent> eventsFrom(FloatingOverlayController c) =>
      c.events;

  @override
  Future<void> disposeController(FloatingOverlayController c) => c.dispose();

  @override
  void onEvent(FloatingOverlayEvent event) => _onEvent(event);

  @override
  void onControllerReady(FloatingOverlayController controller) {
    _pipeline = WaveformPipeline();

    ref.onDispose(() {
      _autoHideTimer?.cancel();
      _noticeKeyPresses.cancel();
      _waveformTimer?.cancel();
      _renderFrameTimer?.cancel();
      _partialSub?.cancel();
    });

    ref.listen(settingsProvider, (_, next) {
      next.whenData((s) => _syncSettings(s));
    });
    ref.listen(recordingPhaseProvider, (prev, next) {
      _onPhaseChanged(prev ?? RecordingPhase.idle, next);
      // The dictation Escape is released when a run ends; a card that still
      // stands takes the key back.
      if (ref.read(dictationNoticeProvider) != null) {
        Future<void>.delayed(Duration.zero, () {
          if (ref.read(dictationNoticeProvider) != null) {
            _grabNoticeEscape(ref.read(recordingPhaseProvider));
          }
        });
      }
    });
    ref.listen(audioLevelProvider, (_, next) {
      _onAudioLevel(next);
    });
    ref.listen(recordingElapsedProvider, (_, next) {
      _onElapsedChanged(next);
    });
    ref.listen(audioServiceProvider, (prev, next) {
      _onMicStateChanged(prev, next);
    });
    ref.listen(micSignalLostProvider, (_, _) {
      _onElapsedChanged(ref.read(recordingElapsedProvider));
    });
    ref.listen(micNoSignalYetProvider, (_, _) {
      _onElapsedChanged(ref.read(recordingElapsedProvider));
    });
    ref.listen(micQuietProvider, (_, _) {
      _onElapsedChanged(ref.read(recordingElapsedProvider));
    });
    ref.listen(durationLimitExtensionProvider, (_, _) {
      _onElapsedChanged(ref.read(recordingElapsedProvider));
    });
    ref.listen(discardConfirmProvider, (_, _) {
      _onElapsedChanged(ref.read(recordingElapsedProvider));
    });
    ref.listen(interactiveSnippetControllerProvider, (prev, next) {
      _onInteractiveSessionChanged(prev, next);
    });
    ref.listen(repasteEmptyNoticeProvider, (_, _) => _showRepasteEmpty());
    ref.listen(learnCorrectionFeedbackProvider, (_, next) {
      if (next != null) _showLearnCorrection(next.outcome);
    });
    ref.listen(overlayPillHintProvider, (_, next) {
      if (next != null) _onPillHint(next);
    });
    ref.listen(dictationNoticeProvider, (prev, next) {
      _onDictationNoticeChanged(next);
    });
    ref.listen(retryProcessingProvider, (_, running) {
      _onRetryProcessingChanged(running);
    });
    ref.listen(recordingLanguageProvider, (_, _) {
      _onRecordingLanguageChanged();
    });
    ref.listen(recordingProfileProvider, (_, _) {
      _onRecordingLanguageChanged();
    });
    ref.listen(transcriptionSliceProgressProvider, (_, _) {
      _onSliceProgressChanged();
    });

    final settings = ref.read(settingsProvider);
    settings.whenData((s) => _syncSettings(s));
  }

  /// A retry from the error card (#837) started or ended. While it runs the
  /// pill shows the same processing frame as after a dictation. At its end
  /// the frame is taken down one event-loop turn later, so a result card the
  /// caller raises right after the retry replaces it without a flicker.
  void _onRetryProcessingChanged(bool running) {
    final s = ref.read(settingsProvider).value;
    if (s == null || s.effectiveOverlayMode != OverlayMode.floating) return;
    if (running) {
      // A running dictation owns the pill; an open card or a guided
      // sequence is not covered.
      if (ref.read(recordingPhaseProvider) != RecordingPhase.idle ||
          ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
        return;
      }
      _generation++;
      _autoHideTimer?.cancel();
      if (!_shellShown) unawaited(_setStartPosition(s));
      _sendSnapshot(s, RecordingPhase.transcribing);
      return;
    }
    Timer(Duration.zero, () {
      if (ref.read(retryProcessingProvider) ||
          ref.read(recordingPhaseProvider) != RecordingPhase.idle ||
          ref.read(dictationNoticeProvider) != null ||
          _pillHintShowing ||
          (_autoHideTimer?.isActive ?? false)) {
        return;
      }
      _hideOverlay();
    });
  }

  /// A dictation message (#453) opened or closed. It replaces the pill while
  /// no recording runs; one raised during a recording waits for its end. The
  /// card stays until it is closed, so the overlay is not hidden meanwhile.
  void _onDictationNoticeChanged(DictationNotice? notice) {
    // Before every early return below: a card that goes away in any way
    // (timer, close, overlay off, banner fallback) must give the Escape key
    // back, or it stays grabbed system-wide.
    if (notice == null) _releaseNoticeEscape(ref.read(recordingPhaseProvider));
    if (notice == null && _clearingNoticeForBanner) return;
    final s = ref.read(settingsProvider).value;
    final c = controller;
    if (notice != null && (s == null || c == null)) {
      _noticeToBanner(notice, 'overlay not ready');
      return;
    }
    if (s == null || c == null) return;
    if (s.effectiveOverlayMode != OverlayMode.floating) {
      if (notice != null) _noticeToBanner(notice, 'overlay mode is off');
      return;
    }
    final phase = ref.read(recordingPhaseProvider);
    if (notice == null) {
      if (phase == RecordingPhase.idle || phase == RecordingPhase.done) {
        _hideOverlay(force: true);
      } else {
        _sendSnapshot(s, phase);
      }
      return;
    }
    if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      _noticeToBanner(notice, 'a guided snippet sequence owns the overlay');
      return;
    }
    if (phase == RecordingPhase.recording &&
        ref.read(audioServiceProvider).hasLiveSamples) {
      return;
    }
    _generation++;
    _autoHideTimer?.cancel();
    if (!_shellShown) unawaited(_setStartPosition(s));
    _sendSnapshot(s, phase);
    ref.read(dictationNoticeProvider.notifier).restartTimer();
    _grabNoticeEscape(phase);
  }

  /// Whether the button key is held for a standing card: not while a dictation
  /// runs (it owns the keys), not in the error phase (the error card, not the
  /// message, is on screen) and not in a guided snippet sequence.
  bool _holdsNoticeActionKey(RecordingPhase phase) =>
      phase != RecordingPhase.recording &&
      phase != RecordingPhase.transcribing &&
      phase != RecordingPhase.refining &&
      phase != RecordingPhase.error &&
      !ref.read(interactiveSnippetControllerProvider.notifier).isActive;

  /// The key that runs a standing card's first button, as shown on it; null
  /// when the key is not held, so the card never promises a dead key.
  String? _noticeActionKeyLabel(
    AppSettings s,
    RecordingPhase phase,
    DictationNotice notice,
  ) => !_holdsNoticeActionKey(phase)
      ? null
      : notice.firstActionOnEnter
      ? 'Enter'
      : s.audioInput.cancelDictationKey == 'f12'
      ? 'Esc'
      : 'F12';

  /// Keyboard way to close the card without clicking and without taking focus
  /// from the target window (#585): while the card stands, the global cancel
  /// key (Escape or F12, as chosen in Settings) closes it. A running dictation
  /// already owns that key for cancelling, so nothing is registered then.
  void _grabNoticeEscape(RecordingPhase phase) {
    // The button key only belongs to a card with a button and no dictation.
    unawaited(
      ref.read(hotkeyServiceProvider.notifier).unregisterNoticeActionKey(),
    );
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.refining) {
      return;
    }
    // A guided snippet sequence owns Escape for its own cancel.
    if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      return;
    }
    // Escape belongs to the target app unless the card needs it: a card with
    // a button or one that stands until closed holds it, a card that closes
    // itself by time does not (#728, north star: no leaving the active
    // window). A card that replaced one that held it drops the key.
    final open = ref.read(dictationNoticeProvider);
    if (!noticeHoldsCancelKey(
      buttons: open?.actions.length ?? 0,
      standing: _noticeStanding(),
    )) {
      _releaseNoticeEscape(phase);
      return;
    }
    final s = ref.read(settingsProvider).value ?? AppSettings.defaults;
    unawaited(
      ref
          .read(hotkeyServiceProvider.notifier)
          .registerCancelDictationKey(
            key: logicalKeyForCancelDictation(s.audioInput.cancelDictationKey),
            onCancel: () => _onNoticeAction(OverlayNoticeActionId.dismiss.id),
          ),
    );
    final withButton = ref.read(dictationNoticeProvider);
    if (_holdsNoticeActionKey(phase) &&
        withButton != null &&
        withButton.actions.isNotEmpty) {
      unawaited(
        ref
            .read(hotkeyServiceProvider.notifier)
            .registerNoticeActionKey(
              key: withButton.firstActionOnEnter
                  ? LogicalKeyboardKey.enter
                  : logicalKeyForNoticeAction(s.audioInput.cancelDictationKey),
              onPressed: _onNoticeActionKey,
            ),
      );
    }
  }

  /// The card's action key was pressed (#816): the press counter decides
  /// which button runs.
  void _onNoticeActionKey() {
    final card = ref.read(dictationNoticeProvider);
    if (card == null || card.firstActionOnEnter) {
      _onNoticeAction(OverlayNoticeActionId.notice1.id);
      return;
    }
    _noticeKeyPresses.press(card, buttons: card.actions.length);
  }

  /// True while the card stays until it is closed (error, button, loss, fixed
  /// error card); false for a card that closes itself.
  bool _noticeStanding() {
    final open = ref.read(dictationNoticeProvider);
    return _standingError != null || open == null || !open.closesItself;
  }

  /// Gives the cancel key back once the card is gone and no dictation runs.
  void _releaseNoticeEscape(RecordingPhase phase) {
    _noticeKeyPresses.cancel();
    unawaited(
      ref.read(hotkeyServiceProvider.notifier).unregisterNoticeActionKey(),
    );
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.refining) {
      return;
    }
    unawaited(
      ref.read(hotkeyServiceProvider.notifier).unregisterCancelDictationKey(),
    );
  }

  /// The overlay cannot show [notice] right now. It is logged and shown as a
  /// banner in the main window instead of being dropped (#585); the card
  /// state is cleared so it does not pop up later out of context.
  void _noticeToBanner(DictationNotice notice, String reason) {
    _log.warning(
      'Dictation notice ${notice.id} not shown on the overlay '
      '($reason); showing it as a banner',
    );
    final pageNotifier = ref.read(
      wpPageNoticeProvider(kAppNoticePage).notifier,
    );
    pageNotifier.show(
      dictationBannerFor(
        notice,
        pageNotifier.dismiss,
        showNotice: pageNotifier.show,
      ),
    );
    _clearingNoticeForBanner = true;
    try {
      ref.read(dictationNoticeProvider.notifier).dismiss();
    } finally {
      _clearingNoticeForBanner = false;
    }
  }

  /// True while [_noticeToBanner] clears the card state: that clearing must
  /// not hide an overlay which shows something else.
  bool _clearingNoticeForBanner = false;

  /// The run's language changed (start, or the one-time profile resolution):
  /// refresh the chip on the frame that is already showing.
  void _onRecordingLanguageChanged() {
    final settings = ref.read(settingsProvider).value;
    final phase = ref.read(recordingPhaseProvider);
    if (settings == null || phase == RecordingPhase.idle) return;
    _sendSnapshot(settings, phase);
  }

  /// A slice of the running transcription finished: refresh the label on the
  /// frame that is already showing.
  void _onSliceProgressChanged() {
    final settings = ref.read(settingsProvider).value;
    final phase = ref.read(recordingPhaseProvider);
    if (settings == null || phase != RecordingPhase.transcribing) return;
    _sendSnapshot(settings, phase);
  }

  // ── Settings sync ─────────────────────────────────────────────────────────

  void _syncSettings(AppSettings s) {
    final c = controller;
    if (c == null) return;

    final active = s.effectiveOverlayMode == OverlayMode.floating;
    if (!active) {
      // Overlay off: a standing error card must not outlive the window it
      // stood on (#781).
      _standingError = null;
      _hideOverlay(force: true);
      return;
    }

    _l10n = _resolveL10n(s.locale);
    _sendContextMenuItems(s);

    final phase = ref.read(recordingPhaseProvider);
    if (phase != RecordingPhase.idle) {
      _sendSnapshot(s, phase);
      return;
    }

    // A guided sequence's briefing/announce frames run with the pipeline
    // still idle — a settings sync must not hide them (the idle pre-sync
    // below exists only for truly idle, off-screen moments).
    if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      return;
    }

    // Idle size pre-sync (log-evidenced fix, 2026-08-17): a size switched in
    // Settings while idle used to reach the native shell only inside the FIRST
    // visible snapshot of the next recording — the shell then ran its
    // synchronous `resizePanelToContent` right on the hotkey→overlay hot path,
    // where the known ~1 s Flutter resize-synchronizer stall (see
    // FloatingOverlayHost.swift, `panelOperationStallThreshold`) blanked the
    // overlay for the first ~1.3 s of the recording and triggered a full shell
    // rebuild (whispaste.log 2026-08-17T03:25:57 ff., three consecutive
    // `resizePanelToContent took ~1s` rebuilds, each at a recording start
    // right after a size switch). Pushing a hidden snapshot now lets the
    // shell resize while hidden, during settings interaction — off the hot
    // path. Skipped while the done-state overlay is still lingering
    // (auto-hide pending): hiding it early would cut the paste confirmation
    // short.
    if (!(_autoHideTimer?.isActive ?? false)) {
      _hideOverlay();
    }
  }

  // ── Phase transitions ─────────────────────────────────────────────────────

  Future<void> _onPhaseChanged(RecordingPhase prev, RecordingPhase next) async {
    if (controller == null) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) {
      // The overlay may have been switched off mid-recording. The waveform
      // timer and the live-transcript subscription belong to the recording
      // that started them, so tear them down here; otherwise the 33 ms timer
      // keeps waking the engine for the rest of the session (CORE-IDLE-CPU).
      _stopWaveformLoop();
      _partialSub?.cancel();
      _partialSub = null;
      _liveTranscript = '';
      return;
    }

    // A hotkey press refused during onboarding is no recording error: the
    // overlay stays out of the onboarding surface (V11-10, MP-3, also on macOS).
    if (next == RecordingPhase.error &&
        isSilentOnboardingRefusal(
          ref.read(recordingProvider).errorMessage ?? '',
          onboardingActive: ref.read(onboardingSurfaceActiveProvider),
        )) {
      return;
    }

    _lastPhase = next;

    _updateWaveformLifecycle(prev, next);
    _updateLiveTranscriptLifecycle(prev, next, settings);
    await _handlePhaseUi(prev, next, settings);
  }

  /// Updates the waveform-pipeline and animation-timer lifecycle based on the
  /// phase transition.
  ///
  //   idle → recording: start the animation timer with a fresh pipeline.
  //   recording → transcribing: enter release-out — keep the timer alive
  //       for ~releaseOutDurationMs, but feed it `pushSample(0.0, …)` so
  //       the waveform decays gracefully via the pipeline's release-tau.
  //   recording → done / error: skip release-out, stop hard.
  //   anything → done / error during release-out: stop hard immediately.
  void _updateWaveformLifecycle(RecordingPhase prev, RecordingPhase next) {
    if (next == RecordingPhase.recording) {
      _startWaveformLoop();
    } else if (prev == RecordingPhase.recording &&
        next == RecordingPhase.transcribing) {
      _startReleaseOut();
    } else if (prev == RecordingPhase.recording) {
      // recording → done / error / idle: no release-out, stop hard.
      _stopWaveformLoop();
    } else if (_isInReleaseOut &&
        (next == RecordingPhase.done ||
            next == RecordingPhase.error ||
            next == RecordingPhase.idle)) {
      // transcribing → done / error / idle mid-release-out: stop hard.
      _stopWaveformLoop();
    }
  }

  /// Sends overlay UI updates and schedules timers for the given phase.
  Future<void> _handlePhaseUi(
    RecordingPhase prev,
    RecordingPhase next,
    AppSettings settings,
  ) async {
    if (_micFollowUpDue && next == RecordingPhase.done) {
      _micFollowUpDue = false;
      // A queued microphone change already opens the settings below.
      if (!_openMicSettingsWhenDone) _showMicFollowUp();
    } else if (_micFollowUpDue &&
        (next == RecordingPhase.error || next == RecordingPhase.idle)) {
      _micFollowUpDue = false;
    }
    if (_openMicSettingsWhenDone &&
        (next == RecordingPhase.done ||
            next == RecordingPhase.error ||
            next == RecordingPhase.idle)) {
      _openMicSettingsWhenDone = false;
      unawaited(_openMicSettings());
    }
    // No card covers a recording that is not running: Esc must not ask for
    // a card that is gone.
    if (next != RecordingPhase.recording) {
      ref.read(recordingCardOpenProvider.notifier).set(false);
    }
    // A card about the run that just ended must not outlive it (#1195): "still
    // processing" closes once the text is out. The "still busy" card follows
    // the pipeline lock, which the orchestrator releases and closes it with,
    // so it counts as busy here.
    if (!isDictationBusy(next)) {
      ref
          .read(dictationNoticeProvider.notifier)
          .dismissIfStale(phase: next, pipelineBusy: true);
    }
    switch (next) {
      case RecordingPhase.idle:
        if (prev == RecordingPhase.done &&
            (_autoHideTimer?.isActive ?? false)) {
          return;
        }
        // A card that stays open now stands in the idle state: send it again
        // so its footer offers a new dictation instead of "stop and paste".
        if (ref.read(dictationNoticeProvider) != null &&
            isDictationBusy(prev)) {
          _sendSnapshot(settings, next);
          _grabNoticeEscape(next);
          return;
        }
        _hideOverlay();

      case RecordingPhase.recording:
        _generation++;
        _micFollowUpDue = false;
        _autoHideTimer?.cancel();
        if (prev != RecordingPhase.recording) {
          _hiddenNotices.clear();
          _standingError = null;
        }
        // A pill hint from before this run is out of date once it starts;
        // one raised during the run shows after it (#454).
        _pendingPillHint = null;
        _pillHintShowing = false;
        // A message from the last run never covers the next recording.
        if (ref.read(dictationNoticeProvider) != null) {
          ref.read(dictationNoticeProvider.notifier).dismiss();
        }
        // Position first, content second. Both go through the same
        // MethodChannel (com.whispaste.floating_overlay), which delivers in
        // FIFO order, so this ordering decides which side the native host
        // sees first — not which Dart call blocks the other, since neither
        // is awaited here. Sending setPosition first lets
        // EnsureOverlayWindow() (linux/runner/floating_overlay_host.cc)
        // apply the pending anchor before the window's first Show(),
        // avoiding a (0,0) flash on cold creation. This is still safe for
        // the "fast second recording preempts a lingering done overlay"
        // case the old ordering guarded against: that hazard was about
        // _setStartPosition's *internal* currentDisplayBounds() await
        // delaying _sendSnapshot if it were awaited at the call site — it
        // still isn't (unawaited), so _sendSnapshot still fires in the same
        // synchronous turn regardless of source order.
        if (prev == RecordingPhase.idle) {
          unawaited(_setStartPosition(settings));
        }
        _sendSnapshot(settings, next);
        // t₁ for hotkey→overlay latency: snapshot sent, native side can now
        // show the overlay. Counterpart: PerfMarkers.markHotkeyPressed() in
        // HotkeyService. HUMAN GATE (issue 16): read the log during dogfooding.
        PerfMarkers.instance.markOverlayShown();

      case RecordingPhase.transcribing:
        _sendSnapshot(settings, next);
        // A message that waited for the recording now shows: its close timer
        // starts here, not when it was raised.
        if (ref.read(dictationNoticeProvider) != null) {
          ref.read(dictationNoticeProvider.notifier).restartTimer();
        }

      case RecordingPhase.refining:
        // Smart Mode v2 (ticket 02): same "keep showing the busy pill,
        // update the label" treatment as the transcribing → transcribing
        // case above — no auto-hide/error-timeout scheduling here either,
        // this phase always resolves to done (never error, ADR 0009).
        _sendSnapshot(settings, next);

      case RecordingPhase.done:
        _sendSnapshot(settings, next);
        // During an interactive sequence the done frame is only a beat
        // between fields — the next announce replaces it and cancels the
        // timer anyway. But if the sequence stalls there (a field's
        // recording auto-stopped on max-duration/silence, no advance yet),
        // auto-hiding would remove the user's only visible anchor while
        // Enter still works — keep the pill up until the sequence moves on
        // or ends (the session-end listener schedules the hide then).
        if (!ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
          _scheduleAutoHide();
        }

      case RecordingPhase.error:
        // A notice card with actions stays until the user acts or closes it
        // (overlay F2); a plain error times out as before.
        if (_sendSnapshot(settings, next) == null) _scheduleErrorTimeout();
    }
  }

  // ── Audio level → waveform pipeline ──────────────────────────────────────

  void _onAudioLevel(double level) {
    if (controller == null) return;
    if (_lastPhase != RecordingPhase.recording) return;
    // While the release-out tail is running we deliberately ignore live audio
    // levels — the timer feeds the pipeline `pushSample(0.0, …)` instead.
    if (_isInReleaseOut) return;
    _pipeline.pushSample(level, _now());
  }

  // ── Waveform animation loop ──────────────────────────────────────────────

  void _startWaveformLoop() {
    _pipeline.reset();
    _isInReleaseOut = false;
    _releaseOutStart = null;
    _waveformTimer?.cancel();
    _waveformTimer = Timer.periodic(_kTickPeriod, _onWaveformTick);
  }

  /// Enters the trailing release-out window: the timer keeps ticking but the
  /// pipeline is fed silence (`pushSample(0.0, …)`) so the waveform decays
  /// via the configured release time constant. After `releaseOutDurationMs`
  /// elapses, the tick callback stops the timer itself.
  void _startReleaseOut() {
    _isInReleaseOut = true;
    _releaseOutStart = _now();
    // If the timer was somehow cancelled (e.g. controller went away), arm a
    // fresh one — otherwise we just keep the recording-phase timer alive.
    if (_waveformTimer == null || !_waveformTimer!.isActive) {
      _waveformTimer = Timer.periodic(_kTickPeriod, _onWaveformTick);
    }
  }

  void _onWaveformTick(Timer _) {
    final c = controller;
    if (c == null) return;
    final now = _now();
    if (_isInReleaseOut) {
      final start = _releaseOutStart;
      if (start != null &&
          now.difference(start).inMilliseconds >= releaseOutDurationMs) {
        // Release-out window over — last snapshot stays frozen.
        _stopWaveformLoop();
        return;
      }
      _pipeline.pushSample(0.0, now);
    }
    _pipeline.tick(now);
    c.setWaveformBars(_pipeline.snapshot()).catchError((e, st) {
      _log.error('Failed to push waveform bars', e, st);
    });
  }

  void _stopWaveformLoop() {
    _waveformTimer?.cancel();
    _waveformTimer = null;
    _isInReleaseOut = false;
    _releaseOutStart = null;
  }

  // ── Live/partial transcript lifecycle ─────────────────────────────────────

  /// Starts/stops [_partialSub] around the two windows in which the STT
  /// side can actually produce live text:
  ///
  /// - [RecordingPhase.recording] — the DURING-recording preview
  ///   ([SttServerStateNotifier.livePreviewStream], live-transcript-
  ///   streaming ticket): a sliding-window decode of the audio captured so
  ///   far, updated on a timer while the user is still speaking.
  /// - [RecordingPhase.transcribing] — the existing POST-recording partial
  ///   transcript (`WhisperFfiEngine.partialTranscript`, wired via
  ///   [PartialTranscriptSource]): whisper.cpp's per-segment callback
  ///   firing during the one batch decode after capture stops.
  ///
  /// The transition between the two (recording → transcribing) tears down
  /// the first subscription and starts the second fresh — [_liveTranscript]
  /// resets so the transcribing phase never briefly shows a stale
  /// during-recording preview.
  void _updateLiveTranscriptLifecycle(
    RecordingPhase prev,
    RecordingPhase next,
    AppSettings settings,
  ) {
    final enteringRecording =
        next == RecordingPhase.recording && prev != RecordingPhase.recording;
    final enteringTranscribing =
        next == RecordingPhase.transcribing &&
        prev != RecordingPhase.transcribing;

    if (enteringRecording || enteringTranscribing) {
      _partialSub?.cancel();
      _liveTranscript = '';
      if (!settings.overlayShowLiveTranscript) return;
      final notifier = ref.read(localSttBundleProvider.notifier);
      final systemPreview =
          enteringRecording &&
          settings.wantsSystemLivePreview &&
          systemSpeechOsSupported();
      final stream = systemPreview
          ? ref.read(systemSpeechLivePreviewProvider).preview
          : enteringRecording
          ? notifier.livePreviewStream
          : notifier.partialTranscriptStream;
      if (stream == null) return;
      _partialSub = stream.listen(_onLiveTranscriptUpdate);
      return;
    }

    final leavingLiveWindow =
        (prev == RecordingPhase.recording ||
            prev == RecordingPhase.transcribing) &&
        next != RecordingPhase.recording &&
        next != RecordingPhase.transcribing;
    if (leavingLiveWindow) {
      _partialSub?.cancel();
      _partialSub = null;
      _liveTranscript = '';
    }
  }

  void _onLiveTranscriptUpdate(String text) {
    _liveTranscript = text;
    if (controller == null) return;
    if (_lastPhase != RecordingPhase.recording &&
        _lastPhase != RecordingPhase.transcribing) {
      return;
    }
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    _sendSnapshot(settings, _lastPhase);
  }

  // ── Elapsed timer updates ─────────────────────────────────────────────────

  void _onElapsedChanged(Duration elapsed) {
    if (controller == null) return;
    if (_lastPhase != RecordingPhase.recording) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;

    _sendSnapshot(settings, RecordingPhase.recording);
  }

  // ── Interactive-snippet announce pre-roll ─────────────────────────────────

  /// Reacts to interactive-snippet session changes (guided-sequence UX
  /// pass). Three cases matter here; everything else is already driven by
  /// the recording phase:
  ///
  /// - A session starts its BRIEFING (Enter-gated orientation before
  ///   field 1): the pipeline is idle, no phase change will paint anything —
  ///   this listener shows the orientation frame and it stays up until the
  ///   user's Enter.
  /// - A session enters a field's ANNOUNCE pre-roll: the recording pipeline
  ///   is idle/done in that window — this listener shows the announce frame.
  /// - The session ends: while the pipeline is idle (cancel during
  ///   briefing/announce) the pill is hidden here; while it is `done` (the
  ///   sequence just finished its last field) the normal done auto-hide is
  ///   armed here, because [_handlePhaseUi] deliberately skipped it while
  ///   the session was still active.
  void _onInteractiveSessionChanged(
    InteractiveSnippetSessionState? prev,
    InteractiveSnippetSessionState? next,
  ) {
    if (controller == null) return;
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;

    if (next != null && (next.briefing || next.announcing || next.assigning)) {
      _generation++;
      _interactiveGuidanceActive = true;
      // A between-fields announce arrives right after the previous field's
      // `done` armed the auto-hide — the pill must stay up for the pre-roll.
      _autoHideTimer?.cancel();
      if (ref.read(recordingPhaseProvider) == RecordingPhase.idle &&
          (prev == null || next.briefing)) {
        // Sequence start: the overlay comes up cold here (mirrors the
        // idle → recording branch of _handlePhaseUi, same ordering rules).
        unawaited(_setStartPosition(settings));
      }
      if (next.briefing) {
        _sendBriefingSnapshot(settings, next);
      } else {
        _sendFieldAnnounceSnapshot(settings, next);
      }
      return;
    }

    if (next == null && prev != null) {
      final phase = ref.read(recordingPhaseProvider);
      if (phase == RecordingPhase.idle) {
        _hideOverlay();
      } else if (phase == RecordingPhase.done) {
        // Sequence finished: give the paste-confirmation frame its normal
        // linger, then hide (skipped in _handlePhaseUi while active).
        _scheduleAutoHide();
      }
    }
  }

  /// Shows the Enter-gated orientation frame at sequence start: the field
  /// count plus the first field's name and the Enter/Escape mechanics on
  /// the secondary line. Stays up until the user presses Enter — no timer.
  ///
  /// Reuses [OverlayVisualState.transcribing] as the vehicle (same
  /// reasoning as [_sendFieldAnnounceSnapshot]).
  void _sendBriefingSnapshot(
    AppSettings s,
    InteractiveSnippetSessionState session,
  ) {
    final c = controller;
    if (c == null) return;

    final l10n = _l10n ?? _resolveL10n();
    final label =
        l10n?.interactiveSnippetBriefingLabel(session.fieldCount) ??
        '${session.fieldCount} fields · Enter to start';
    final hint =
        l10n?.interactiveSnippetBriefingHint(session.fieldName) ??
        'Field 1: ${session.fieldName} · Esc: cancel';

    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.transcribing,
      size: _guidanceSize(),
      background: s.overlayBackgroundType,
      wave: s.overlayWaveType,
      appearance: s.overlayAppearance,
      label: label,
      secondaryLabel: hint,
      privacyMode: s.sttProviderType.isLocal ? 'local' : 'cloud',
    );

    _log.debug(
      'Overlay show: interactive-snippet briefing '
      'fields=${session.fieldCount}',
    );
    _pushToShell(c, snapshot, 'Failed to send overlay briefing snapshot');
  }

  /// Shows the announce pre-roll frame: "Field i/N: name" with a quieter
  /// "get ready" secondary line.
  ///
  /// Reuses [OverlayVisualState.transcribing] as the vehicle on purpose —
  /// it is the ONE composition that paints a prominent text label in all
  /// three size variants (normal, compact AND mini share
  /// `WpOverlayPainter._drawTranscribing`), which is exactly what a guiding
  /// instruction needs; the recording composition paints no text at all in
  /// mini. The spinner reads as "preparing", and no new visual state has to
  /// travel through the snapshot serialisation and every platform shell.
  void _sendFieldAnnounceSnapshot(
    AppSettings s,
    InteractiveSnippetSessionState session,
  ) {
    final c = controller;
    if (c == null) return;

    final l10n = _l10n ?? _resolveL10n();
    // "In einem Satz" has one take for all fields: name them all instead of
    // counting fields, and say so while the fields are being filled in.
    final String text;
    final String hint;
    if (session.assigning) {
      text = l10n?.interactiveSnippetAssigningLabel ?? 'Filling in the fields…';
      hint = l10n?.interactiveSnippetAssigningHint ?? 'Esc: cancel';
    } else {
      text = session.sentence
          ? l10n?.interactiveSnippetSentenceLabel(session.fieldName) ??
                'In one sentence: ${session.fieldName}'
          : l10n?.interactiveSnippetAnnounceLabel(
                  session.fieldIndex + 1,
                  session.fieldCount,
                  session.fieldName,
                ) ??
                'Field ${session.fieldIndex + 1}/${session.fieldCount}: '
                    '${session.fieldName}';
      hint = l10n?.interactiveSnippetAnnounceHint ?? 'Get ready to speak…';
    }

    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.transcribing,
      size: _guidanceSize(),
      background: s.overlayBackgroundType,
      wave: s.overlayWaveType,
      appearance: s.overlayAppearance,
      label: text,
      secondaryLabel: hint,
      privacyMode: s.sttProviderType.isLocal ? 'local' : 'cloud',
    );

    _log.debug(
      'Overlay show: interactive-snippet announce '
      'field=${session.fieldIndex + 1}/${session.fieldCount}',
    );
    _pushToShell(c, snapshot, 'Failed to send overlay announce snapshot');
  }

  /// "Nothing to paste yet" after the repaste hotkey: a short neutral pill
  /// that hides by itself, plus a screen-reader announcement. Only while
  /// idle, so it never covers a recording or a guided sequence.
  /// The result of one "Learn correction" press (#934), short and read out.
  void _showLearnCorrection(LearnCorrectionOutcome outcome) {
    final s = ref.read(settingsProvider).value;
    if (s == null) return;
    final l10n = _l10n ?? _resolveL10n(s.locale);
    final text = switch (outcome) {
      LearnCorrectionOutcome.proposed =>
        l10n?.learnCorrectionProposed ?? 'Suggestion in the Dictionary',
      LearnCorrectionOutcome.nothingFound =>
        l10n?.learnCorrectionNothingFound ??
            'No matching word in the last dictation',
      LearnCorrectionOutcome.noSelection =>
        l10n?.learnCorrectionNoSelection ?? 'Select the corrected word first',
      LearnCorrectionOutcome.learningOff =>
        l10n?.learnCorrectionLearningOff ?? 'Learning from corrections is off',
    };
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      announce(
        view,
        text,
        s.locale == 'he' ? TextDirection.rtl : TextDirection.ltr,
      );
    }
    if (ref.read(recordingPhaseProvider) != RecordingPhase.idle) return;
    _showPillText(
      s,
      text,
      failed:
          outcome == LearnCorrectionOutcome.nothingFound ||
          outcome == LearnCorrectionOutcome.noSelection,
      what: 'learn correction ${outcome.name}',
      announced: view != null,
    );
  }

  void _showRepasteEmpty() {
    final s = ref.read(settingsProvider).value;
    if (s == null) return;
    final l10n = _l10n ?? _resolveL10n(s.locale);
    final text = l10n?.repasteNothingYet ?? 'No dictation to paste yet';
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view != null) {
      announce(
        view,
        text,
        s.locale == 'he' ? TextDirection.rtl : TextDirection.ltr,
      );
    }
    if (ref.read(recordingPhaseProvider) != RecordingPhase.idle) return;
    _showPillText(
      s,
      text,
      failed: true,
      what: 'repaste found nothing',
      announced: view != null,
    );
  }

  /// A confirmation for the pill (#454), already read out by its caller.
  /// While the pill is busy (a recording, its result, an open card) it waits
  /// and shows when the pill would otherwise hide. A newer hint replaces a
  /// waiting or showing one, so fast presses never stack.
  void _onPillHint(OverlayPillHint hint) {
    final s = ref.read(settingsProvider).value;
    if (s == null || s.effectiveOverlayMode != OverlayMode.floating) return;
    if (ref.read(recordingPhaseProvider) != RecordingPhase.idle ||
        ref.read(dictationNoticeProvider) != null ||
        (_autoHideTimer?.isActive ?? false) && !_pillHintShowing) {
      _pendingPillHint = hint;
      return;
    }
    // The pill may refuse (controller not ready, guided snippet running);
    // then the hint waits for the next hide instead of vanishing.
    _pendingPillHint = null;
    if (_showPillHint(s, hint)) {
      _pillHintShowing = true;
    } else {
      _pendingPillHint = hint;
    }
  }

  /// Shows a waiting pill hint instead of hiding; true when it did.
  bool _showPendingPillHint() {
    final hint = _pendingPillHint;
    final s = ref.read(settingsProvider).value;
    if (hint == null || s == null) return false;
    final phase = ref.read(recordingPhaseProvider);
    // Free once no dictation runs: idle, its result, or an error that timed
    // out; otherwise the hint would vanish behind the hide.
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.refining) {
      return false;
    }
    if (s.effectiveOverlayMode != OverlayMode.floating) {
      _pendingPillHint = null;
      return false;
    }
    // Only a shown hint leaves the queue; a refused one stays for the next hide.
    if (!_showPillHint(s, hint)) return false;
    _pendingPillHint = null;
    _pillHintShowing = true;
    return true;
  }

  bool _showPillHint(AppSettings s, OverlayPillHint hint) => _showPillText(
    s,
    hint.text,
    failed: false,
    what: 'hint ${hint.id}',
    hintId: hint.id,
    announced: hint.announced,
  );

  /// One short line in the done frame of the pill, hidden again after the
  /// usual delay. False when the pill cannot show it now. [announced] says
  /// the caller has read [text] out already, so the overlay stays quiet.
  bool _showPillText(
    AppSettings s,
    String text, {
    required bool failed,
    required String what,
    String? hintId,
    bool announced = false,
  }) {
    final c = controller;
    if (c == null ||
        s.effectiveOverlayMode != OverlayMode.floating ||
        ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      return false;
    }
    _generation++;
    if (!_shellShown) unawaited(_setStartPosition(s));
    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.done,
      size: s.overlaySizeType.variant,
      background: s.overlayBackgroundType,
      wave: s.overlayWaveType,
      appearance: s.overlayAppearance,
      label: text,
      doneMessage: text,
      donePasteFailed: failed,
      privacyMode: s.sttProviderType.isLocal ? 'local' : 'cloud',
      pillHintId: hintId,
      announced: announced,
    );
    _log.debug('Overlay show: $what');
    _pushToShell(c, snapshot, 'Failed to send overlay pill text');
    _scheduleAutoHide();
    return true;
  }

  /// The size variant for guided-sequence frames — always normal (see
  /// [_interactiveGuidanceActive]).
  OverlaySizeVariant _guidanceSize() => OverlaySizeVariant.normal;

  // ── Snapshot building ─────────────────────────────────────────────────────

  /// Fraction of the maximum recording length elapsed, clamped to `[0, 1]`.
  /// Zero outside the recording phase or when no maximum is configured.
  double _progressFor(RecordingPhase phase, AppSettings s, Duration elapsed) {
    if (phase != RecordingPhase.recording || s.maxRecordDuration <= 0) {
      return 0.0;
    }
    final fraction = elapsed.inSeconds / s.maxRecordDuration;
    return fraction > 1.0 ? 1.0 : fraction;
  }

  /// Chip label for the run in [phase]: the language this recording actually
  /// runs with ([recordingLanguageProvider], SW-03/SW-07), never the live
  /// setting. Nothing is shown while idle or for `auto`.
  String? _languageChipFor(RecordingPhase phase) {
    if (phase == RecordingPhase.idle) return null;
    final language = ref.read(recordingLanguageProvider);
    return language == null ? null : languageChipLabelFor(language);
  }

  /// Chip label for the profile this run actually uses: the manual choice or
  /// the one the per-app rules matched at start ([recordingProfileProvider],
  /// ticket 13 part 3). Nothing while idle or when no profile applies.
  String? _profileChipFor(RecordingPhase phase) {
    if (phase == RecordingPhase.idle) return null;
    final name = ref.read(recordingProfileProvider);
    return name == null ? null : profileChipLabelFor(name);
  }

  /// Sends the frame for [phase]; returns its notice card (overlay F2), so
  /// the caller can keep a card with actions on screen.
  OverlayNotice? _sendSnapshot(AppSettings s, RecordingPhase phase) {
    final c = controller;
    if (c == null) return null;

    final l10n = _l10n ?? _resolveL10n();
    // Guided sequences force the normal size for the whole episode (see
    // _interactiveGuidanceActive): the field-position/name text is the
    // guidance, and mini/compact cannot carry it.
    if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      _interactiveGuidanceActive = true;
    }
    final sizeVariant = _interactiveGuidanceActive
        ? _guidanceSize()
        : s.overlaySizeType.variant;
    final elapsed = ref.read(recordingElapsedProvider);
    final recording = ref.read(recordingProvider);
    final isLocal = s.sttProviderType.isLocal;
    // Ziel des LAUFENDEN Vorgangs (Ticket 25). Wird zu jedem Aufnahmestart
    // gesetzt und nie zurückgesetzt — deshalb hier bei jedem Schnappschuss neu
    // lesen statt zu merken, damit der nächste Vorgang nie das Ziel des
    // vorigen erbt.
    final target = ref.read(recordingTargetProvider);

    final progress = _progressFor(phase, s, elapsed);

    // Briefing criterion 4: until the first sample arrives the recording phase
    // shows the preparing state, not the live recording (see
    // [showsStartingFeedback]).
    final starting = showsStartingFeedback(
      phase: phase,
      firstSampleSeen: ref.read(audioServiceProvider).hasLiveSamples,
    );
    final live = phase == RecordingPhase.recording && !starting;
    final countdown = _countdownDue(live, elapsed, s);
    final notice = _noticeFor(phase, live, elapsed, s, l10n);
    ref.read(recordingCardOpenProvider.notifier).set(live && notice != null);

    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: starting ? OverlayVisualState.transcribing : _mapPhase(phase),
      size: sizeVariant,
      background: s.overlayBackgroundType,
      wave: s.overlayWaveType,
      appearance: s.overlayAppearance,
      label: starting
          ? (l10n?.overlayStarting ?? 'Starting…')
          : _labelFor(phase, l10n, target, s),
      elapsed: live
          ? _recordingElapsedTextFor(elapsed, sizeVariant, target, l10n, s)
          : '',
      countdown: countdown,
      hint: starting ? '' : _hintFor(phase, s, l10n, target),
      transcript: recording.transcript,
      errorMessage: recording.errorMessage != null && l10n != null
          ? localizeRecordingError(
              l10n,
              recording.errorMessage!,
              provider: s.sttProviderType,
            )
          : recording.errorMessage,
      privacyMode: isLocal ? 'local' : 'cloud',
      doneMessage: phase == RecordingPhase.done && l10n != null
          ? doneMessageFor(
              s.afterTranscription,
              l10n,
              target: target,
              pasteFailed: recording.pasteFailed,
              copiedOnly: recording.copiedOnly,
              historyOnly: recording.historyOnly,
              pasteUnconfirmed: recording.pasteUnconfirmed,
              pastedInto: ref.read(pastedAppNameProvider),
            )
          : null,
      donePasteFailed: phase == RecordingPhase.done && recording.pasteFailed,
      progress: progress,
      languageChip: _languageChipFor(phase),
      profileChip: _profileChipFor(phase),
      liveTranscript:
          (phase == RecordingPhase.recording ||
                  phase == RecordingPhase.transcribing) &&
              s.overlayShowLiveTranscript
          ? _liveTranscript
          : null,
      keyHints: _keyHintsFor(sizeVariant, live, s, l10n),
      notice: notice,
    );

    _log.debug(
      'Overlay show: phase=${phase.name} size=${sizeVariant.name} '
      'visible=true',
    );
    _pushToShell(c, snapshot, 'Failed to send overlay snapshot');
    return notice;
  }

  /// Kind of the card on screen in the last frame, so the cross knows what it
  /// hides.
  OverlayNoticeKind? _shownNoticeKind;

  /// A fixed error card (no microphone, start failed) that stays until it is
  /// closed or a new recording starts: the error reset after a few seconds
  /// must not take it off the screen (#781).
  OverlayNotice? _standingError;

  /// The notice card for this frame (overlay F2) with the footer of valid
  /// keys, or null for the pill.
  OverlayNotice? _noticeFor(
    RecordingPhase phase,
    bool live,
    Duration elapsed,
    AppSettings s,
    L10n? l10n,
  ) {
    var notice = _pickNotice(phase, live, elapsed, s, l10n);
    if (notice != null &&
        phase == RecordingPhase.error &&
        notice.kind != OverlayNoticeKind.message) {
      _standingError = notice;
    } else if (notice == null &&
        phase == RecordingPhase.idle &&
        _standingError != null) {
      notice = _standingError;
    }
    _shownNoticeKind = notice?.kind;
    if (notice == null || l10n == null) return notice;
    // A paste warning that did not follow a dictation must not offer "dictate
    // again" (#1147): it keeps its card without that footer line.
    if (notice.kind == OverlayNoticeKind.message &&
        phase == RecordingPhase.idle &&
        ref.read(dictationNoticeProvider)?.offersNewDictation == false) {
      return notice;
    }
    return notice.withFooter(_noticeFooter(s, phase, l10n, notice));
  }

  /// The footer of a card: the keys that work in [phase] (#984). While the
  /// text is processed the hotkey is ignored, so only the cancel key shows.
  String _noticeFooter(
    AppSettings s,
    RecordingPhase phase,
    L10n l10n,
    OverlayNotice notice,
  ) {
    final message = ref.read(dictationNoticeProvider);
    final actionKey = message == null
        ? null
        : _noticeActionKeyLabel(s, phase, message);
    return noticeFooterFor(
      l10n: l10n,
      // Same rule as [_grabNoticeEscape]: a self-closing card without a
      // button holds no cancel key, so its footer names only the hotkey.
      holdsCancelKey:
          notice.kind != OverlayNoticeKind.message ||
          noticeHoldsCancelKey(
            buttons: notice.actions.where((a) => !a.action.isClose).length,
            standing: _noticeStanding(),
          ),
      phase: noticeFooterPhaseFor(phase),
      // Only a dictation message card carries buttons the action key runs.
      actionKey: notice.kind == OverlayNoticeKind.message ? actionKey : null,
      buttons: notice.actions.where((a) => !a.action.isClose).length,
      // Isolated so the keys keep their order inside right-to-left text.
      hotkey: ltrIsolate(_triggerLabel(s, l10n)),
      cancelKey: ltrIsolate(
        hotkeyKeyLabel(s.audioInput.cancelDictationKey, l10n: l10n),
      ),
    );
  }

  OverlayNotice? _pickNotice(
    RecordingPhase phase,
    bool live,
    Duration elapsed,
    AppSettings s,
    L10n? l10n,
  ) {
    if (l10n == null || _interactiveGuidanceActive) return null;
    final message = ref.read(dictationNoticeProvider);
    if (phase == RecordingPhase.error) {
      return noticeFor(
            state: OverlayVisualState.error,
            l10n: l10n,
            errorCode: ref.read(recordingProvider).errorMessage,
            busyApp: micBusyApp,
          ) ??
          (message == null
              ? null
              : overlayNoticeFor(
                  message,
                  l10n,
                  actionKey: _noticeActionKeyLabel(s, phase, message),
                ));
    }
    if (!live) {
      return message == null
          ? null
          : overlayNoticeFor(
              message,
              l10n,
              actionKey: _noticeActionKeyLabel(s, phase, message),
            );
    }
    final remaining = _countdownFor(elapsed, s);
    final card = noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      signalLost: ref.read(micSignalLostProvider),
      quiet: ref.read(micQuietProvider),
      quietHintEnabled: s.overlayQuietHint,
      remaining: remaining == null ? null : formatOverlayElapsed(remaining),
      canExtend: ref.read(durationLimitExtensionProvider) == 0,
      extendMinutes: (s.behavior.maxRecordDuration / 60).ceil().clamp(
        1,
        1 << 20,
      ),
      micChangeQueued: _openMicSettingsWhenDone,
      hiddenKinds: _hiddenNotices,
    );
    return card == null ? null : _withDiscardAsk(card, s, l10n);
  }

  /// [card] while a cancel confirmation is armed: the card says what Esc does
  /// instead of its own text, so the line never promises what Esc undoes.
  OverlayNotice _withDiscardAsk(OverlayNotice card, AppSettings s, L10n l10n) {
    if (!ref.read(discardConfirmProvider)) return card;
    return OverlayNotice(
      kind: card.kind,
      tone: OverlayNoticeTone.error,
      title: l10n.overlayDiscardConfirm(_cancelKeyLabel(s)),
      body: '',
      actions: card.actions,
      footer: card.footer,
    );
  }

  /// Stop and cancel hints for the normal live recording pill, or null. The
  /// stop hint is the active dictation hotkey; the cancel hint is the cancel
  /// key, shown only while its glyph is.
  OverlayKeyHints? _keyHintsFor(
    OverlaySizeVariant size,
    bool live,
    AppSettings s,
    L10n? l10n,
  ) {
    if (!OverlayKeyHints.showsFor(size: size, live: live)) return null;
    final stop = _triggerLabel(s, l10n, compact: true);
    final cancel = s.overlayAppearance.showCancel
        ? hotkeyKeyLabel(s.audioInput.cancelDictationKey, l10n: l10n)
        : null;
    return OverlayKeyHints.forRecording(
      size: size,
      live: live,
      stopLabel: stop,
      cancelLabel: cancel,
    );
  }

  /// Single exit to the native shell for every overlay snapshot. Routes the
  /// snapshot through [_shellGate] (redundant hides are dropped) and keeps the
  /// show/hide bookkeeping of the render-engine heartbeat in one place.
  void _pushToShell(
    FloatingOverlayController c,
    FloatingOverlaySnapshot snapshot,
    String failure,
  ) {
    final send = _shellGate.shouldSend(snapshot);
    if (snapshot.visible) {
      _markShellShown(c);
    } else {
      _markShellHidden();
    }
    if (!send) return;
    c.updateSnapshot(snapshot).catchError((e, st) {
      _log.error(failure, e, st);
    });
  }

  // ── Render-engine frame heartbeat (ticket phase 2, plan item 1) ───────────

  void _markShellShown(FloatingOverlayController c) {
    if (_shellShown) return;
    _shellShown = true;
    if (c is! RenderEngineRecovery) return;
    _renderRecovery.onShown(_now());
    _armRenderFrameTimer();
  }

  void _markShellHidden() {
    _shellShown = false;
    _renderRecovery.onHidden();
    _renderFrameTimer?.cancel();
    _renderFrameTimer = null;
  }

  void _armRenderFrameTimer() {
    _renderFrameTimer?.cancel();
    _renderFrameTimer = null;
    final due = _renderRecovery.deadline;
    if (due == null) return;
    final wait = due.difference(_now());
    _renderFrameTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      _onRenderFrameDeadline,
    );
  }

  void _onRenderFrameDeadline() {
    _renderFrameTimer = null;
    final now = _now();
    final due = _renderRecovery.deadline;
    final lag = due == null ? Duration.zero : now.difference(due);
    switch (_renderRecovery.onDeadline(now, lag: lag)) {
      case RenderRecoveryAction.none:
        break;
      case RenderRecoveryAction.repush:
        // The overlay's machine never asks for a re-push (no
        // repushBeforeReboot), so this is unreachable here.
        break;
      case RenderRecoveryAction.reboot:
        _log.warning(
          'Overlay render engine painted no frame within '
          '${kRenderFrameDeadline.inMilliseconds} ms of show — re-booting it '
          '(${_renderRecovery.reboots}/$kRenderRebootBudget)',
        );
        if (controller case final RenderEngineRecovery recovery) {
          recovery.rebootRenderEngine().catchError((e, st) {
            _log.error('Overlay render engine re-boot request failed', e, st);
          });
        }
      case RenderRecoveryAction.budgetExhausted:
        _log.error(
          'Overlay render engine stalled again; the session re-boot budget '
          '($kRenderRebootBudget) is spent — the overlay stays as is until the '
          'app restarts',
        );
    }
    if (_renderRecovery.armed) _armRenderFrameTimer();
  }

  void _onRenderFrame() {
    _renderRecovery.onFrame();
    _renderFrameTimer?.cancel();
    _renderFrameTimer = null;
    PerfMarkers.instance.markOverlayFirstFrame();
  }

  /// The first live sample completes the start feedback: while the recording
  /// phase shows the preparing state, switch to the live recording state.
  void _onMicStateChanged(AudioStatus? prev, AudioStatus next) {
    if (controller == null) return;
    if (_lastPhase != RecordingPhase.recording) return;
    if (!next.hasLiveSamples) return;
    if (prev?.hasLiveSamples == true) return;
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;
    _sendSnapshot(settings, RecordingPhase.recording);
  }

  void _hideOverlay({bool force = false}) {
    final c = controller;
    if (c == null) return;
    // An open dictation message stays until it is closed or its timer ends (#453).
    if (!force && ref.read(dictationNoticeProvider) != null) return;
    // A standing error card stays until it is closed (#781).
    if (!force && _standingError != null) return;
    _pillHintShowing = false;
    // A pill hint that waited for the pill (#454) shows now instead.
    if (_showPendingPillHint()) return;
    _autoHideTimer?.cancel();
    // The guided episode is over once the pill leaves the screen — the next
    // regular recording gets the user's configured size again.
    _interactiveGuidanceActive = false;

    // Preserve the configured size on hide. Forcing the normal size here made
    // the native shell needlessly resize on every hide (and could flash the
    // wrong size on the next show); keep the real setting so the panel size
    // never flips. Falls back to normal only if settings are unavailable.
    final s = ref.read(settingsProvider).value;
    final sizeVariant = s?.overlaySizeType.variant ?? OverlaySizeVariant.normal;
    final hidden = FloatingOverlaySnapshot(
      visible: false,
      state: OverlayVisualState.recording,
      size: sizeVariant,
      background: s?.overlayBackgroundType ?? OverlayBackground.marine,
      wave: s?.overlayWaveType ?? OverlayWave.cyan,
      appearance: s?.overlayAppearance ?? OverlayAppearance.defaults,
      label: '',
    );

    _log.debug('Overlay hide (size=${sizeVariant.name})');
    // A `visible:false` snapshot orders the native shell off-screen
    // (macOS `orderOut`, Windows `SW_HIDE`, Linux `gtk_widget_hide`), so the
    // hidden window no longer intercepts mouse events.
    _pushToShell(c, hidden, 'Failed to hide overlay');
  }

  // ── Auto-hide ─────────────────────────────────────────────────────────────

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();

    final gen = _generation;
    _autoHideTimer = Timer(kOverlayAutoHideDelay, () {
      if (_generation == gen) {
        _hideOverlay();
      }
    });
  }

  void _scheduleErrorTimeout() {
    _autoHideTimer?.cancel();

    final gen = _generation;
    _autoHideTimer = Timer(const Duration(seconds: 30), () {
      if (_generation == gen && _lastPhase == RecordingPhase.error) {
        _hideOverlay();
      }
    });
  }

  // ── Start position ────────────────────────────────────────────────────────

  Future<void> _setStartPosition(AppSettings s) async {
    final c = controller;
    if (c == null) return;

    try {
      final pos = s.overlayStartPositionType;

      if (pos == OverlayStartPosition.lastPosition &&
          s.floatingOverlayX >= 0 &&
          s.floatingOverlayY >= 0) {
        // Dispatch the saved position immediately, unclamped: this is the
        // first `await` in this branch, so the setPosition platform-channel
        // message still goes out synchronously at call time (Dart dispatches
        // a MethodChannel call's message before suspending on its reply) —
        // ahead of _sendSnapshot's updateSnapshot on the recording-phase
        // caller's next line. currentDisplayBounds() below is itself an
        // async plugin round trip; awaiting it before sending anything would
        // let updateSnapshot win that race instead, recreating the
        // (0,0)-flash-on-cold-creation bug this call ordering exists to
        // avoid. A monitor unplugged since the position was saved is
        // corrected a moment later by the clamped follow-up call below —
        // preferable to reintroducing the flash for every recording.
        await c.setPosition(
          s.floatingOverlayX,
          s.floatingOverlayY,
          OverlayAnchorMode.topLeft,
        );
        final displays = await currentDisplayBounds();
        final size = OverlayPositioning.overlaySize(compact: false);
        final clamped = WindowPositionClamp.clamp(
          position: Offset(s.floatingOverlayX, s.floatingOverlayY),
          size: size,
          displays: displays,
        );
        // A monitor the overlay was dragged to before keeps its own spot
        // (ticket, 9.4); otherwise the clamped position stands.
        final target =
            MonitorRelativePosition.restoreAt(
              topLeft: clamped,
              size: size,
              remembered: MonitorRelativePosition.decode(
                s.windowPosition.overlayPositionsByMonitor,
              ),
              displays: displays,
            ) ??
            clamped;
        if (target.dx != s.floatingOverlayX ||
            target.dy != s.floatingOverlayY) {
          await c.setPosition(target.dx, target.dy, OverlayAnchorMode.topLeft);
        }
      } else {
        final anchor = pos == OverlayStartPosition.bottomCenter
            ? OverlayAnchorMode.bottomCenter
            : OverlayAnchorMode.topCenter;
        await c.setPosition(-1, -1, anchor);
      }
    } catch (e, st) {
      _log.error('Failed to set overlay start position', e, st);
    }
  }

  // ── Context menu ──────────────────────────────────────────────────────────

  /// The overlay's own right-click menu (#393): the cancel entry names its
  /// key, the size entries check the current size, and the menu follows the
  /// app's light or dark appearance.
  void _sendContextMenuItems(AppSettings s) {
    final c = controller;
    if (c == null) return;
    final l10n = _l10n;
    if (l10n == null) return;
    final size = s.overlaySizeType;

    c
        .setContextMenuItems(
          nativeMenuItems([
            AppCommand(
              id: 'cancel',
              labelKey: l10n.overlayContextCancel,
              shortcut: _cancelKeyLabel(s),
            ),
            const AppCommand.separator(),
            AppCommand(
              id: 'switch_normal',
              labelKey: l10n.overlayContextSwitchNormal,
              checked: size == FloatingOverlaySize.normal,
            ),
            AppCommand(
              id: 'switch_compact',
              labelKey: l10n.overlayContextSwitchCompact,
              checked: size == FloatingOverlaySize.compact,
            ),
            AppCommand(
              id: 'switch_mini',
              labelKey: l10n.overlayContextSwitchMini,
              checked: size == FloatingOverlaySize.mini,
            ),
            AppCommand(
              id: 'switch_nano',
              labelKey: l10n.overlayContextSwitchNano,
              checked: size == FloatingOverlaySize.nano,
            ),
            const AppCommand.separator(),
            AppCommand(id: 'hide', labelKey: l10n.overlayContextHide),
          ], labelOf: (text) => text),
          appearance: nativeMenuAppearance(s.interface_.appearance),
        )
        .catchError((e, st) {
          _log.error('Failed to send context menu items', e, st);
        });
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _onEvent(FloatingOverlayEvent event) {
    switch (event) {
      case OverlayCloseClicked():
        _onCloseClicked();

      case OverlayBodyClicked():
        if (_shownNoticeKind != null) {
          // A card absorbs its own clicks, so a body click while one is on
          // screen is a stray one (a click on the close cross while the
          // window was being resized, #921). It closes the card like Escape
          // and never starts or stops a recording.
          _log.info(
            'Overlay body clicked while a ${_shownNoticeKind!.name} card '
            'was shown → closing it like Escape',
          );
          _onNoticeAction(OverlayNoticeActionId.dismiss.id);
        } else if (ref
            .read(interactiveSnippetControllerProvider.notifier)
            .isActive) {
          _log.debug('Overlay body clicked → advanceField');
          ref
              .read(interactiveSnippetControllerProvider.notifier)
              .advanceField();
        } else {
          // Info, not debug: a recording started by a click must be
          // traceable in the log (#921).
          _log.info('Overlay body clicked → toggleRecording');
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
        }

      case OverlayRetryClicked():
        _log.debug('Overlay retry clicked → orchestrator reset');
        ref.read(recordingOrchestratorProvider.notifier).reset();
        _hideOverlay();

      case OverlayDragEnded(x: final x, y: final y):
        _log.debug('Overlay dragged to ($x, $y)');
        _savePosition(x, y);

      case OverlayRenderFrame():
        _onRenderFrame();

      case OverlayContextMenuAction(action: final action):
        _onContextMenuAction(action);

      case OverlayNoticeActionClicked(id: final id):
        _onNoticeAction(id);

      case OverlayRenderEngineDiagnostic(
        message: final message,
        isError: final isError,
      ):
        if (isError) {
          _log.error('Render engine: $message');
        } else {
          _log.warning('Render engine: $message');
        }
    }
  }

  /// Hides the card on screen for the rest of this recording; a message
  /// waiting for the recording to start closes for good.
  void _hideShownCard(RecordingPhase phase) {
    final kind = _shownNoticeKind;
    if (kind == OverlayNoticeKind.message) {
      ref.read(dictationNoticeProvider.notifier).dismiss();
    } else if (kind != null) {
      _hiddenNotices.add(kind);
    }
    final s = ref.read(settingsProvider).value;
    if (s != null) _sendSnapshot(s, phase);
  }

  /// A notice-card button (overlay F2). No action discards what was said:
  /// each either keeps recording, or stops and transcribes.
  void _onNoticeAction(String id) {
    final action = OverlayNoticeActionId.fromId(id);
    _log.debug('Overlay notice action: $id');
    final orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    final phase = ref.read(recordingPhaseProvider);
    final recording = phase == RecordingPhase.recording;
    if (action == null) return;
    // Any button answers a standing error card.
    _standingError = null;
    switch (action) {
      case OverlayNoticeActionId.pasteSoFar || OverlayNoticeActionId.stopNow:
        if (recording) {
          _micFollowUpDue =
              action == OverlayNoticeActionId.pasteSoFar &&
              ref.read(micSignalLostProvider);
          orchestrator.toggleRecording();
        }
      case OverlayNoticeActionId.discardRecording:
        if (recording) unawaited(orchestrator.cancelRecording());
      case OverlayNoticeActionId.hideHint:
        // Only the card goes; the recording runs on and the card does not
        // return in this recording.
        _hideShownCard(phase);
      case OverlayNoticeActionId.retry:
        orchestrator.toggleRecording();
      case OverlayNoticeActionId.keepRecording:
        if (orchestrator.extendDurationLimitOnce()) {
          // The card goes away with the click; the pill says what happened.
          final minutes =
              (ref.read(settingsProvider).value?.behavior.maxRecordDuration ??
                  0) /
              60;
          final l10n = _l10n ?? _resolveL10n();
          if (l10n != null) {
            ref
                .read(overlayPillHintProvider.notifier)
                .show(
                  id: 'limit-extended',
                  text: l10n.overlayLimitExtended(
                    minutes.ceil().clamp(1, 1 << 20),
                  ),
                );
          }
        }
      case OverlayNoticeActionId.changeMicrophone:
        _changeMicrophone(phase);
      case OverlayNoticeActionId.dismiss when recording:
        // The cross over a running recording hides the card, nothing else:
        // the recording goes on and the card stays away for this run.
        _hideShownCard(phase);
      case OverlayNoticeActionId.dismiss:
        // Closing a dictation message hides through its listener, which may
        // show a waiting pill hint instead (#454); hiding again here would
        // take that hint straight off.
        final idle =
            phase == RecordingPhase.idle || phase == RecordingPhase.done;
        final closed = ref.read(dictationNoticeProvider);
        if (idle && closed != null) {
          ref.read(dictationNoticeProvider.notifier).dismiss();
        } else {
          ref.read(dictationNoticeProvider.notifier).dismiss();
          _hideOverlay(force: true);
        }
        closed?.onDismiss?.call();
      case OverlayNoticeActionId.notice1 || OverlayNoticeActionId.notice2:
        final notice = ref.read(dictationNoticeProvider);
        final index = action == OverlayNoticeActionId.notice1 ? 0 : 1;
        if (notice != null) {
          ref.read(dictationNoticeProvider.notifier).dismiss();
        } else if (phase == RecordingPhase.idle) {
          _hideOverlay(force: true);
        }
        if (notice != null && index < notice.actions.length) {
          final pressed = notice.actions[index];
          pressed.onPressed();
          final confirmation = pressed.confirmation;
          if (confirmation != null) {
            // A button without a visible effect is answered at the pill (#781).
            ref
                .read(overlayPillHintProvider.notifier)
                .show(id: 'notice-action', text: confirmation);
          }
        }
    }
  }

  /// The card after a lost-signal dictation was pasted: the one place that
  /// offers the microphone choice, so the lost-signal card keeps a single
  /// button.
  void _showMicFollowUp() {
    final l10n = _l10n ?? _resolveL10n();
    if (l10n == null) return;
    ref
        .read(dictationNoticeProvider.notifier)
        .show(
          DictationNotice(
            id: 'signal-lost-follow-up',
            cause: l10n.overlayNoticeSignalLostTitle,
            nextStep: l10n.overlayNoticeSignalLostNext,
            actions: [
              DictationNoticeAction(
                id: 'choose-microphone',
                label: l10n.overlayNoticeChooseMicrophone,
                onPressed: () => unawaited(_openMicSettings()),
              ),
            ],
          ),
        );
  }

  /// Opens Settings at the microphone. A running dictation finishes first, so
  /// its text still lands in the target app; the new microphone applies from
  /// the next dictation. After a lost signal nothing more can be captured, so
  /// that dictation is stopped and transcribed right away.
  void _changeMicrophone(RecordingPhase phase) {
    switch (phase) {
      case RecordingPhase.recording ||
          RecordingPhase.transcribing ||
          RecordingPhase.refining:
        _openMicSettingsWhenDone = true;
        if (phase == RecordingPhase.recording &&
            ref.read(micSignalLostProvider)) {
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
        } else {
          _onElapsedChanged(ref.read(recordingElapsedProvider));
        }
      case RecordingPhase.idle || RecordingPhase.done || RecordingPhase.error:
        _hideOverlay();
        unawaited(_openMicSettings());
    }
  }

  /// Brings the main window to the front at Settings > microphone.
  Future<void> _openMicSettings() async {
    ref.read(settingsScrollTargetProvider.notifier).set('recording-microphone');
    ref.read(activePageProvider.notifier).setPage('settings');
    try {
      await MacOSLifecycleChannel.setRegular();
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      _log.error('Failed to bring main window to front', e, st);
    }
  }

  void _onCloseClicked() {
    if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      _log.debug('Overlay close during interactive snippet → cancel sequence');
      ref.read(interactiveSnippetControllerProvider.notifier).cancel();
      return;
    }
    final phase = ref.read(recordingPhaseProvider);
    if (phase == RecordingPhase.recording ||
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.refining) {
      // Issue #145: the overlay X discards the active dictation — it must
      // not transcribe, save, copy, or paste anything, unlike the recording
      // hotkey / overlay-body click (toggleRecording → "stop and
      // transcribe").
      // #393: a long recording asks first, exactly like Escape.
      if (!_cancelPressDiscardsNow(phase)) return;
      _log.debug('Overlay close during $phase → cancelRecording');
      ref.read(recordingOrchestratorProvider.notifier).cancelRecording();
    } else {
      _log.debug('Overlay close → dismiss');
      _hideOverlay();
    }
  }

  bool _cancelPressDiscardsNow(RecordingPhase phase) => cancelPressDiscardsNow(
    phase,
    ref.read(recordingElapsedProvider),
    ref.read(discardConfirmProvider.notifier),
    cardOpen: ref.read(recordingCardOpenProvider),
  );

  void _onContextMenuAction(String action) {
    switch (action) {
      case 'cancel':
        _log.debug('Context menu: cancel recording');
        if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
          ref.read(interactiveSnippetControllerProvider.notifier).cancel();
          _hideOverlay();
          return;
        }
        // Issue #145: "Cancel recording" must actually discard the
        // dictation (no transcribe/save/copy/paste), not stop-and-
        // transcribe. cancelRecording() no-ops outside
        // recording/transcribing/refining, so no phase check is needed here.
        // #393: a long recording asks first, exactly like Escape; the overlay
        // stays up so the confirmation hint is visible.
        if (!_cancelPressDiscardsNow(ref.read(recordingPhaseProvider))) {
          return;
        }
        ref.read(recordingOrchestratorProvider.notifier).cancelRecording();
        _hideOverlay();

      case 'switch_normal':
        _log.debug('Context menu: switch to normal');
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(overlaySize: FloatingOverlaySize.normal.value),
            );

      case 'switch_compact':
        _log.debug('Context menu: switch to compact');
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(overlaySize: FloatingOverlaySize.compact.value),
            );

      case 'switch_mini':
        _log.debug('Context menu: switch to mini');
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(overlaySize: FloatingOverlaySize.mini.value),
            );

      case 'switch_nano':
        _log.debug('Context menu: switch to nano');
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(overlaySize: FloatingOverlaySize.nano.value),
            );

      case 'hide':
        _log.debug('Context menu: hide overlay');
        _hideOverlay();
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWith(overlayMode: OverlayMode.off.value),
            );

      default:
        _log.warning('Unknown context menu action: $action');
    }
  }

  Future<void> _savePosition(double x, double y) async {
    // The plain position is written first, so it survives even when the
    // display query never answers; the per-monitor memory follows as a
    // second, enrichment-only write.
    await _savePositionOnly(x, y);
    final List<Rect> displays;
    try {
      displays = await currentDisplayBounds();
    } on Exception catch (e) {
      _log.warning('Overlay position not remembered per monitor: $e');
      return;
    }
    await saveSettingsSafely(
      _log,
      'Failed to save overlay position',
      () => ref.read(settingsProvider.notifier).updateSettings((s) {
        final memory = MonitorRelativePosition.remember(
          MonitorRelativePosition.decode(
            s.windowPosition.overlayPositionsByMonitor,
          ),
          Offset(x, y),
          OverlayPositioning.overlaySize(compact: false),
          displays,
        );
        return s.copyWith(
          overlayPositionsByMonitor: MonitorRelativePosition.encode(memory),
        );
      }),
    );
  }

  Future<void> _savePositionOnly(double x, double y) => saveSettingsSafely(
    _log,
    'Failed to save overlay position',
    () => ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(floatingOverlayX: x, floatingOverlayY: y),
        ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────

  static OverlayVisualState _mapPhase(RecordingPhase phase) => switch (phase) {
    RecordingPhase.idle => OverlayVisualState.recording,
    RecordingPhase.recording => OverlayVisualState.recording,
    RecordingPhase.transcribing => OverlayVisualState.transcribing,
    // Smart Mode v2's refining phase (ticket 02) reuses the "transcribing"
    // pill animation on the native side — only the label text below
    // distinguishes it. Adding a fifth native visual state is out of scope
    // for this ticket (would touch macOS/Windows/Linux overlay hosts).
    RecordingPhase.refining => OverlayVisualState.transcribing,
    RecordingPhase.done => OverlayVisualState.done,
    RecordingPhase.error => OverlayVisualState.error,
  };

  /// The refining label names the running preset (#891), the same name the
  /// dock and Settings show: the Smart-Mode hotkey's bound preset wins over
  /// the standard preset, as in the pipeline.
  String _refiningLabel(L10n? l10n, AppSettings s) {
    if (l10n == null) return 'Refining…';
    final preset =
        ref.read(smartModeHotkeyOverridePresetProvider)?.name ??
        s.smartMode.standardPreset;
    if (preset == 'off') return l10n.overlayRefining;
    return l10n.overlayRefiningPreset(
      smartModePresetDisplayName(preset, l10n, settings: s.smartMode),
    );
  }

  /// Haupttext je Phase. Bei laufender Aufnahme in die Schnellnotiz benennt er
  /// das Ziel: gemalt wird er in dieser Phase zwar nicht (dort zeigt die Pille
  /// den Zeitzähler), aber die Bildschirmleseansage der Overlay-Schale spricht
  /// genau dieses Feld beim Zustandswechsel aus.
  String _labelFor(
    RecordingPhase phase,
    L10n? l10n,
    RecordingTarget target,
    AppSettings s,
  ) => switch (phase) {
    RecordingPhase.recording => switch (target) {
      RecordingTarget.templateField => _interactiveSnippetSpeakNowLabel(l10n),
      RecordingTarget.quickNote =>
        l10n?.overlayRecordingQuickNote ?? 'Recording to note',
      RecordingTarget.selectionEdit =>
        l10n?.overlayRecordingSelectionEdit ?? 'Say what to change',
      RecordingTarget.clipboard => l10n?.overlayRecording ?? 'Recording',
    },
    // Edit selection stays in `transcribing` while the engine runs (a
    // failure must be able to reach `error`, which `refining` never
    // does — ADR 0009), so the label names the actual work.
    RecordingPhase.transcribing =>
      target == RecordingTarget.selectionEdit
          ? (l10n?.overlayEditingSelection ?? 'Editing selection…')
          : _transcribingLabel(l10n),
    RecordingPhase.refining => _refiningLabel(l10n, s),
    RecordingPhase.done => l10n?.overlayDoneReady ?? 'Done',
    RecordingPhase.error => l10n?.overlayError ?? 'Error',
    RecordingPhase.idle => '',
  };

  /// "Processing part k of n…" while a long recording is transcribed in
  /// slices, so the pill and the screen reader name the progress. Otherwise
  /// the plain processing word.
  String _transcribingLabel(L10n? l10n) {
    final slice = ref.read(transcriptionSliceProgressProvider);
    if (slice == null || !slice.isSliced) {
      return l10n?.overlayTranscribing ?? 'Transcribing…';
    }
    return l10n?.transcribingSliceProgress(slice.current, slice.total) ??
        'Processing part ${slice.current} of ${slice.total}…';
  }

  /// Sichtbarer Text der Pille während der Aufnahme.
  ///
  /// Bei Ziel Zwischenablage ist das unverändert der reine Zeitzähler. Bei
  /// Ziel Schnellnotiz oder Vorlagenfeld tritt der Zielname hinzu — das ist
  /// die einzige Stelle, an der die Zielangabe während der Aufnahme
  /// tatsächlich auf dem Schirm landet. Größenabhängig, weil der Text der
  /// Wellenform ihren Platz nimmt:
  ///
  /// - normal: Zeitzähler + Ziel („0:05 · Notiz") — dort ist Platz für beides.
  /// - kompakt: nur das Ziel; Zeitzähler + Ziel würde die Wellenform auf ein
  ///   Drittel ihrer Breite drücken, und die Zielangabe ist in diesem Moment
  ///   die wichtigere Auskunft (der laufende Vorgang ist über Punkt,
  ///   Wellenform und Zeitleiste weiterhin erkennbar).
  /// - mini: ebenfalls nur das Ziel. Die mini-Pille malt überhaupt keinen
  ///   Text (sie ist wellenform-only), die Zielangabe erreicht dort also
  ///   niemanden — dieselbe dokumentierte Grenze wie heute schon bei
  ///   „Kopiert"/„Eingefügt". Irreführend wird sie dadurch nie.
  ///
  /// Für ein Vorlagenfeld (interaktives Snippet) war das vor diesem Fix ein
  /// blinder Fleck: `_labelFor` berechnete zwar "Feld i/N: Name", aber
  /// [WpOverlayPainter] malt während `recording` ausschließlich `timerText`
  /// (`overlay_painter.dart`, `_isRecording ? timerText : statusText`) — das
  /// Label erreichte den Bildschirm nie, nur den Screenreader. Der Nutzer sah
  /// beim Aufnehmen eines Feldes also nur eine Wellenform plus Zeitzähler,
  /// ohne zu wissen, welches Feld gerade läuft.
  /// Wraps [_recordingTextFor] with the during-recording live-preview
  /// override (live-transcript-streaming ticket): while a non-empty
  /// [_liveTranscript] is available and the setting is on, it replaces the
  /// normal timer/target text in the same slot [_isRecording ? timerText :
  /// statusText] paints for the recording composition — reusing the
  /// existing rendering path (arbitrary text, ellipsis on overflow) rather
  /// than adding a second one.
  String _recordingElapsedTextFor(
    Duration elapsed,
    OverlaySizeVariant size,
    RecordingTarget target,
    L10n? l10n,
    AppSettings s,
  ) {
    // XP-5-08: a lost microphone outranks the timer, the live text and the
    // target name. Alone, because the line does not grow and a truncated
    // notice is no notice; the pulsing dot still shows the recording runs.
    // The same line when nothing arrived since the start (#984): the overlay
    // carries that hint instead of a system notification.
    if (ref.read(micSignalLostProvider) || ref.read(micNoSignalYetProvider)) {
      return l10n?.overlayMicSignalLost ?? 'No microphone signal';
    }
    // The last 30 s before the duration limit replace the elapsed time.
    final remaining = _countdownFor(elapsed, s);
    if (remaining != null) {
      final time = formatOverlayElapsed(remaining);
      return l10n?.overlayRemainingTime(time) ?? '$time left';
    }
    // Too-quiet hint (5 s below the RMS threshold): recording keeps running.
    // Off together with its notice card (Settings > Overlay, overlay F2).
    if (s.overlayQuietHint && ref.read(micQuietProvider)) {
      return l10n?.overlayMicVeryQuiet ?? 'Microphone very quiet';
    }
    if (s.overlayShowLiveTranscript && _liveTranscript.trim().isNotEmpty) {
      return _liveTranscript;
    }
    return _recordingTextFor(elapsed, size, target, l10n);
  }

  /// Remaining time to the duration limit while the countdown is due.
  Duration? _countdownFor(Duration elapsed, AppSettings s) =>
      remainingUntilDurationLimit(
        elapsed: elapsed,
        maxDurationSeconds: s.behavior.maxRecordDuration > 0
            ? s.behavior.maxRecordDuration +
                  ref.read(durationLimitExtensionProvider)
            : 0,
        // The limit's grace belongs to the card until it was used (#858).
        graceSeconds: ref.read(durationLimitExtensionProvider) == 0
            ? durationLimitGraceSeconds
            : 0,
      );

  /// Whether the timer slot shows the countdown; only on a live recording.
  bool _countdownDue(bool live, Duration elapsed, AppSettings s) =>
      live && _countdownFor(elapsed, s) != null;

  String _recordingTextFor(
    Duration elapsed,
    OverlaySizeVariant size,
    RecordingTarget target,
    L10n? l10n,
  ) {
    final timer = formatOverlayElapsed(elapsed);
    final targetName = switch (target) {
      RecordingTarget.quickNote => l10n?.overlayTargetQuickNote ?? 'Note',
      RecordingTarget.templateField => _interactiveSnippetSpeakNowLabel(l10n),
      RecordingTarget.selectionEdit =>
        l10n?.overlayTargetSelectionEdit ?? 'Edit selection',
      RecordingTarget.clipboard => null,
    };
    if (targetName == null) return timer;
    return switch (size) {
      OverlaySizeVariant.normal =>
        l10n?.overlayRecordingTargetTimer(timer, targetName) ??
            '$timer · $targetName',
      OverlaySizeVariant.compact ||
      OverlaySizeVariant.mini ||
      OverlaySizeVariant.nano => targetName,
    };
  }

  /// Label of the cancel key shown in the recording hint (Escape or F12).
  static String _cancelKeyLabel(AppSettings s) =>
      s.audioInput.cancelDictationKey == cancelDictationKeyEscape
      ? 'Esc'
      : 'F12';

  /// The main hotkey as it currently listens (safe default while it stands
  /// in for a taken combination, XP-5-09).
  ({String key, String modifiers, String display}) _activeGlobalHotkey(
    AppSettings s,
  ) => activeGlobalHotkey(
    s,
    fallback: ref.read(globalHotkeyFallbackActiveProvider),
  );

  /// The dictation trigger as it listens right now: the single key, or the
  /// combination that stands in for it (#1195). [compact] gives the key cap.
  String _triggerLabel(AppSettings s, L10n? l10n, {bool compact = false}) =>
      activeTriggerLabel(
        s,
        combo: _activeGlobalHotkey(s),
        doubleTapFallback: ref.read(doubleTapFallbackActiveProvider),
        l10n: l10n,
        compact: compact,
      );

  String _hintFor(
    RecordingPhase phase,
    AppSettings s,
    L10n? l10n,
    RecordingTarget target,
  ) {
    if (phase == RecordingPhase.recording) {
      // Der Hinweis muss die Kombination nennen, mit der der Nutzer DIESEN
      // Vorgang gestartet hat — bei einer Schnellnotiz-Aufnahme ist das der
      // Schnellnotiz-Hotkey, nicht der Haupt-Hotkey.
      final quickNote = target == RecordingTarget.quickNote;
      final enabled = quickNote
          ? s.quickNoteHotkey.quickNoteHotkeyEnabled
          : s.hotkeyEnabled;
      if (target == RecordingTarget.selectionEdit) {
        // Quick actions are spoken keywords (the overlay has no per-element
        // hit regions) — the hint is where the user learns them.
        return l10n?.overlaySelectionEditHint ??
            'Say what to change — or: shorter · improve · translate';
      }
      if (target == RecordingTarget.templateField) {
        // Enter/Escape sind sequenz-gebunden immer registriert (siehe
        // InteractiveSnippetController) — der Hinweis nennt sie daher auch
        // dann, wenn der Haupt-Hotkey abgeschaltet ist.
        if (!enabled) {
          return l10n?.overlayKeyboardHintNextFieldEnterOnly ??
              'Enter: next field · Esc: cancel';
        }
        final hotkey = _triggerLabel(s, l10n);
        return l10n?.overlayKeyboardHintNextFieldEnter(hotkey) ??
            'Enter or $hotkey: next field · Esc: cancel';
      }
      final cancelKey = _cancelKeyLabel(s);
      if (ref.read(discardConfirmProvider)) {
        return l10n?.overlayDiscardConfirm(cancelKey) ??
            'Discard recording? Press $cancelKey again';
      }
      if (enabled) {
        final hotkey = quickNote
            ? formatHotkeyShortcut(
                s.quickNoteHotkey.quickNoteHotkeyModifiers,
                s.quickNoteHotkey.quickNoteHotkeyKey,
                l10n: l10n,
                displayOverride: s.quickNoteHotkey.quickNoteHotkeyKeyDisplay,
              )
            : _triggerLabel(s, l10n);
        return l10n?.overlayStopAndCancelHint(hotkey, cancelKey) ??
            'Press $hotkey to stop · $cancelKey to cancel';
      }
      return '';
    }
    if (phase == RecordingPhase.transcribing) {
      final isLocal = s.sttProviderType.isLocal;
      return isLocal
          ? (l10n?.overlayProcessingLocal ?? 'Local')
          : (l10n?.overlayProcessingCloud ?? 'Cloud');
    }
    // Smart Mode v2 (ticket 02): the Cleanup pass is always local-model
    // inference (this ticket's whole scope), regardless of which STT
    // provider produced the transcript.
    if (phase == RecordingPhase.refining) {
      return l10n?.overlayProcessingLocal ?? 'Local';
    }
    return '';
  }

  /// "Speak now: `<name>` (i/N)" instruction for the field currently being
  /// recorded in an interactive-snippet sequence (guided-sequence UX pass —
  /// the earlier "Field i/N: name" label named the field but did not TELL
  /// the user what to do, which is what the maintainer flagged). Falls back
  /// to the plain recording label if, unexpectedly, no sequence is active
  /// (e.g. a stray `templateField` snapshot).
  String _interactiveSnippetSpeakNowLabel(L10n? l10n) {
    final session = ref.read(interactiveSnippetControllerProvider);
    if (session == null) return l10n?.overlayRecording ?? 'Recording';
    if (session.sentence) {
      return l10n?.interactiveSnippetSentenceLabel(session.fieldName) ??
          'In one sentence: ${session.fieldName}';
    }
    return l10n?.interactiveSnippetSpeakNowLabel(
          session.fieldName,
          session.fieldIndex + 1,
          session.fieldCount,
        ) ??
        'Speak now: ${session.fieldName} '
            '(${session.fieldIndex + 1}/${session.fieldCount})';
  }

  L10n? _resolveL10n([String? localeCode]) {
    // Must follow the app's own language setting, not the OS locale — the
    // overlay used to read platformDispatcher.locale directly, so it stayed
    // in the system UI language even after switching WhisPaste's own
    // Settings → Language to something else.
    final locale = localeCode != null
        ? Locale(localeCode)
        : WidgetsBinding.instance.platformDispatcher.locale;
    try {
      return lookupL10n(locale);
    } catch (_) {
      try {
        return lookupL10n(const Locale('en'));
      } catch (_) {
        return null;
      }
    }
  }
}

/// Provider for the floating overlay service (keepAlive — lives for app
/// lifetime).
final floatingOverlayServiceProvider =
    NotifierProvider<FloatingOverlayService, void>(FloatingOverlayService.new);
