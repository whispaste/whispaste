import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_labels.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/perf_instrumentation.dart';
import '../../core/platform/display_bounds.dart';
import '../../core/platform/window_position_clamp.dart';
import '../../core/recording/recording_state.dart';
import '../../core/recording/recording_helpers.dart';
import '../../core/theme/overlay_design_spec.dart'
    show
        OverlayArcMotion,
        OverlayDesignSpec,
        OverlaySizeVariant,
        OverlayStyleVariant;
import '../floating_platform_service_base.dart';
import '../recording_orchestrator.dart';
import '../snippets/interactive_snippet_controller.dart';
import 'floating_overlay_controller.dart';
import 'floating_overlay_events.dart';
import 'overlay_positioning.dart';
import 'waveform_pipeline.dart';
import '../../widgets/recording_behavior.dart' show localizeRecordingError;

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
  RecordingPhase _lastPhase = RecordingPhase.idle;
  L10n? _l10n;

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
      _waveformTimer?.cancel();
    });

    ref.listen(settingsProvider, (_, next) {
      next.whenData((s) => _syncSettings(s));
    });
    ref.listen(recordingPhaseProvider, (prev, next) {
      _onPhaseChanged(prev ?? RecordingPhase.idle, next);
    });
    ref.listen(audioLevelProvider, (_, next) {
      _onAudioLevel(next);
    });
    ref.listen(recordingElapsedProvider, (_, next) {
      _onElapsedChanged(next);
    });

    final settings = ref.read(settingsProvider);
    settings.whenData((s) => _syncSettings(s));
  }

  // ── Settings sync ─────────────────────────────────────────────────────────

  void _syncSettings(AppSettings s) {
    final c = controller;
    if (c == null) return;

    final active = s.effectiveOverlayMode == OverlayMode.floating;
    if (!active) {
      _hideOverlay();
      return;
    }

    _l10n = _resolveL10n(s.locale);
    _sendContextMenuItems();

    final phase = ref.read(recordingPhaseProvider);
    if (phase != RecordingPhase.idle) {
      _sendSnapshot(s, phase);
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
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;

    _lastPhase = next;

    _updateWaveformLifecycle(prev, next);
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
    switch (next) {
      case RecordingPhase.idle:
        if (prev == RecordingPhase.done &&
            (_autoHideTimer?.isActive ?? false)) {
          return;
        }
        _hideOverlay();

      case RecordingPhase.recording:
        _generation++;
        _autoHideTimer?.cancel();
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

      case RecordingPhase.refining:
        // Smart Mode v2 (ticket 02): same "keep showing the busy pill,
        // update the label" treatment as the transcribing → transcribing
        // case above — no auto-hide/error-timeout scheduling here either,
        // this phase always resolves to done (never error, ADR 0009).
        _sendSnapshot(settings, next);

      case RecordingPhase.done:
        _sendSnapshot(settings, next);
        _scheduleAutoHide();

      case RecordingPhase.error:
        _sendSnapshot(settings, next);
        _scheduleErrorTimeout();
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

  // ── Elapsed timer updates ─────────────────────────────────────────────────

  void _onElapsedChanged(Duration elapsed) {
    if (controller == null) return;
    if (_lastPhase != RecordingPhase.recording) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;

    _sendSnapshot(settings, RecordingPhase.recording);
  }

  // ── Snapshot building ─────────────────────────────────────────────────────

  void _sendSnapshot(AppSettings s, RecordingPhase phase) {
    final c = controller;
    if (c == null) return;

    final l10n = _l10n ?? _resolveL10n();
    final sizeVariant = s.overlaySizeType.variant;
    final styleVariant = s.overlayStyleType.variant;
    final elapsed = ref.read(recordingElapsedProvider);
    final recording = ref.read(recordingProvider);
    final isLocal = s.sttProviderType.isLocal;
    // Ziel des LAUFENDEN Vorgangs (Ticket 25). Wird zu jedem Aufnahmestart
    // gesetzt und nie zurückgesetzt — deshalb hier bei jedem Schnappschuss neu
    // lesen statt zu merken, damit der nächste Vorgang nie das Ziel des
    // vorigen erbt.
    final target = ref.read(recordingTargetProvider);

    double progress = 0.0;
    if (phase == RecordingPhase.recording && s.maxRecordDuration > 0) {
      progress = elapsed.inSeconds / s.maxRecordDuration;
      if (progress > 1.0) progress = 1.0;
    }

    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: _mapPhase(phase),
      size: sizeVariant,
      style: styleVariant,
      label: _labelFor(phase, l10n, target),
      elapsed: phase == RecordingPhase.recording
          ? _recordingTextFor(elapsed, sizeVariant, target, l10n)
          : '',
      hint: _hintFor(phase, s, l10n, target),
      transcript: recording.transcript,
      errorMessage: recording.errorMessage != null && l10n != null
          ? localizeRecordingError(l10n, recording.errorMessage!)
          : recording.errorMessage,
      privacyMode: isLocal ? 'local' : 'cloud',
      doneMessage: phase == RecordingPhase.done && l10n != null
          ? doneMessageFor(s.afterTranscription, l10n, target: target)
          : null,
      progress: progress,
    );

    _log.debug(
      'Overlay show: phase=${phase.name} size=${sizeVariant.name} '
      'visible=true',
    );
    c.updateSnapshot(snapshot).catchError((e, st) {
      _log.error('Failed to send overlay snapshot', e, st);
    });
  }

  void _hideOverlay() {
    final c = controller;
    if (c == null) return;
    _autoHideTimer?.cancel();

    // Preserve the configured size on hide. Forcing the normal size here made
    // the native shell needlessly resize on every hide (and could flash the
    // wrong size on the next show); keep the real setting so the panel size
    // never flips. Falls back to normal only if settings are unavailable.
    final s = ref.read(settingsProvider).value;
    final sizeVariant = s?.overlaySizeType.variant ?? OverlaySizeVariant.normal;
    final styleVariant =
        s?.overlayStyleType.variant ?? OverlayStyleVariant.glass;
    final hidden = FloatingOverlaySnapshot(
      visible: false,
      state: OverlayVisualState.recording,
      size: sizeVariant,
      style: styleVariant,
      label: '',
    );

    _log.debug('Overlay hide (size=${sizeVariant.name})');
    // A `visible:false` snapshot orders the native shell off-screen
    // (macOS `orderOut`, Windows `SW_HIDE`, Linux `gtk_widget_hide`), so the
    // hidden window no longer intercepts mouse events.
    c.updateSnapshot(hidden).catchError((e, st) {
      _log.error('Failed to hide overlay', e, st);
    });
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
        final clamped = WindowPositionClamp.clamp(
          position: Offset(s.floatingOverlayX, s.floatingOverlayY),
          size: OverlayPositioning.overlaySize(compact: false),
          displays: displays,
        );
        if (clamped.dx != s.floatingOverlayX ||
            clamped.dy != s.floatingOverlayY) {
          await c.setPosition(
            clamped.dx,
            clamped.dy,
            OverlayAnchorMode.topLeft,
          );
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

  void _sendContextMenuItems() {
    final c = controller;
    if (c == null) return;
    final l10n = _l10n;
    if (l10n == null) return;

    c
        .setContextMenuItems([
          (id: 'cancel', label: l10n.overlayContextCancel),
          (id: 'switch_normal', label: l10n.overlayContextSwitchNormal),
          (id: 'switch_compact', label: l10n.overlayContextSwitchCompact),
          (id: 'switch_mini', label: l10n.overlayContextSwitchMini),
          (id: 'hide', label: l10n.overlayContextHide),
        ])
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
        if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
          _log.debug('Overlay body clicked → advanceField');
          ref
              .read(interactiveSnippetControllerProvider.notifier)
              .advanceField();
        } else {
          _log.debug('Overlay body clicked → toggleRecording');
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
        }

      case OverlayRetryClicked():
        _log.debug('Overlay retry clicked → toggleRecording');
        ref.read(recordingProvider.notifier).reset();
        _hideOverlay();

      case OverlayDragEnded(x: final x, y: final y):
        _log.debug('Overlay dragged to ($x, $y)');
        _savePosition(x, y);

      case OverlayContextMenuAction(action: final action):
        _onContextMenuAction(action);

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

  void _onCloseClicked() {
    if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
      _log.debug('Overlay close during interactive snippet → cancel sequence');
      ref.read(interactiveSnippetControllerProvider.notifier).cancel();
      return;
    }
    final phase = ref.read(recordingPhaseProvider);
    if (phase == RecordingPhase.recording) {
      _log.debug('Overlay close during recording → stopRecording');
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    } else {
      _log.debug('Overlay close → dismiss');
      _hideOverlay();
    }
  }

  void _onContextMenuAction(String action) {
    switch (action) {
      case 'cancel':
        _log.debug('Context menu: cancel recording');
        if (ref.read(interactiveSnippetControllerProvider.notifier).isActive) {
          ref.read(interactiveSnippetControllerProvider.notifier).cancel();
          _hideOverlay();
          return;
        }
        final phase = ref.read(recordingPhaseProvider);
        if (phase == RecordingPhase.recording) {
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
        }
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

  Future<void> _savePosition(double x, double y) => saveSettingsSafely(
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

  /// Haupttext je Phase. Bei laufender Aufnahme in die Schnellnotiz benennt er
  /// das Ziel: gemalt wird er in dieser Phase zwar nicht (dort zeigt die Pille
  /// den Zeitzähler), aber die Bildschirmleseansage der Overlay-Schale spricht
  /// genau dieses Feld beim Zustandswechsel aus.
  String _labelFor(RecordingPhase phase, L10n? l10n, RecordingTarget target) =>
      switch (phase) {
        RecordingPhase.recording =>
          target == RecordingTarget.templateField
              ? _interactiveSnippetFieldLabel(l10n)
              : target == RecordingTarget.quickNote
              ? (l10n?.overlayRecordingQuickNote ?? 'Recording to note')
              : (l10n?.overlayRecording ?? 'Recording'),
        RecordingPhase.transcribing =>
          l10n?.overlayTranscribing ?? 'Transcribing…',
        RecordingPhase.refining => l10n?.overlayRefining ?? 'Refining…',
        RecordingPhase.done => l10n?.overlayDoneReady ?? 'Done',
        RecordingPhase.error => l10n?.overlayError ?? 'Error',
        RecordingPhase.idle => '',
      };

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
  String _recordingTextFor(
    Duration elapsed,
    OverlaySizeVariant size,
    RecordingTarget target,
    L10n? l10n,
  ) {
    final timer = _formatElapsed(elapsed);
    final targetName = switch (target) {
      RecordingTarget.quickNote => l10n?.overlayTargetQuickNote ?? 'Note',
      RecordingTarget.templateField => _interactiveSnippetFieldLabel(l10n),
      RecordingTarget.clipboard => null,
    };
    if (targetName == null) return timer;
    return switch (size) {
      OverlaySizeVariant.normal =>
        l10n?.overlayRecordingTargetTimer(timer, targetName) ??
            '$timer · $targetName',
      OverlaySizeVariant.compact || OverlaySizeVariant.mini => targetName,
    };
  }

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
      if (enabled) {
        final hotkey = quickNote
            ? formatHotkeyShortcut(
                s.quickNoteHotkey.quickNoteHotkeyModifiers,
                s.quickNoteHotkey.quickNoteHotkeyKey,
                l10n: l10n,
                displayOverride: s.quickNoteHotkey.quickNoteHotkeyKeyDisplay,
              )
            : formatHotkeyShortcut(
                s.hotkeyModifiers,
                s.hotkeyKey,
                l10n: l10n,
                displayOverride: s.hotkey.hotkeyKeyDisplay,
              );
        if (target == RecordingTarget.templateField) {
          return l10n?.overlayKeyboardHintNextField(hotkey) ??
              'Press $hotkey for the next field';
        }
        return l10n?.overlayKeyboardHint(hotkey) ?? 'Press $hotkey to stop';
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

  /// "Field i/N: `<name>`" label for the field currently being recorded in an
  /// interactive-snippet sequence (PRD `interactive-snippets` User Story 8).
  /// Falls back to the plain recording label if, unexpectedly, no sequence
  /// is active (e.g. a stray `templateField` snapshot).
  String _interactiveSnippetFieldLabel(L10n? l10n) {
    final session = ref.read(interactiveSnippetControllerProvider);
    if (session == null) return l10n?.overlayRecording ?? 'Recording';
    return l10n?.interactiveSnippetFieldLabel(
          session.fieldIndex + 1,
          session.fieldCount,
          session.fieldName,
        ) ??
        'Field ${session.fieldIndex + 1}/${session.fieldCount}: '
            '${session.fieldName}';
  }

  String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
