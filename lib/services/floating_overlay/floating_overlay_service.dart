import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_labels.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import '../../core/recording/recording_helpers.dart';
import '../floating_platform_service_base.dart';
import '../floating_theme_brightness.dart';
import '../recording_orchestrator.dart';
import 'floating_overlay_controller.dart';
import 'floating_overlay_events.dart';
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
const int releaseOutDurationMs = 300;

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

    _l10n = _resolveL10n();
    _sendContextMenuItems();

    final phase = ref.read(recordingPhaseProvider);
    if (phase != RecordingPhase.idle) {
      _sendSnapshot(s, phase);
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
        if (prev == RecordingPhase.idle) {
          await _setStartPosition(settings);
        }
        _sendSnapshot(settings, next);

      case RecordingPhase.transcribing:
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
    final isDark = _computeIsDark(s);
    final compact = s.overlaySizeType == FloatingOverlaySize.compact;
    final elapsed = ref.read(recordingElapsedProvider);
    final recording = ref.read(recordingProvider);
    final isLocal = s.sttProviderType.isLocal;

    double progress = 0.0;
    if (phase == RecordingPhase.recording && s.maxRecordDuration > 0) {
      progress = elapsed.inSeconds / s.maxRecordDuration;
      if (progress > 1.0) progress = 1.0;
    }

    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: _mapPhase(phase),
      isDark: isDark,
      compact: compact,
      label: _labelFor(phase, l10n),
      elapsed: phase == RecordingPhase.recording ? _formatElapsed(elapsed) : '',
      hint: _hintFor(phase, s, l10n),
      transcript: recording.transcript,
      errorMessage: recording.errorMessage != null && l10n != null
          ? localizeRecordingError(l10n, recording.errorMessage!)
          : recording.errorMessage,
      privacyMode: isLocal ? 'local' : 'cloud',
      doneMessage: phase == RecordingPhase.done && l10n != null
          ? doneMessageFor(s.afterTranscription, l10n)
          : null,
      progress: progress,
    );

    _log.debug(
      'Overlay show: phase=${phase.name} compact=$compact '
      'isDark=$isDark visible=true',
    );
    c.updateSnapshot(snapshot).catchError((e, st) {
      _log.error('Failed to send overlay snapshot', e, st);
    });
  }

  void _hideOverlay() {
    final c = controller;
    if (c == null) return;
    _autoHideTimer?.cancel();

    // Preserve the configured size on hide. Forcing `compact: false` here made
    // the native shell needlessly resize to normal on every hide (and could
    // flash the wrong size on the next show); keep the real setting so the
    // panel size never flips. Falls back to compact=false only if settings are
    // unavailable.
    final s = ref.read(settingsProvider).value;
    final compact = s?.overlaySizeType == FloatingOverlaySize.compact;
    final hidden = FloatingOverlaySnapshot(
      visible: false,
      state: OverlayVisualState.recording,
      isDark: true,
      compact: compact,
      label: '',
    );

    _log.debug('Overlay hide (compact=$compact)');
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
        await c.setPosition(
          s.floatingOverlayX,
          s.floatingOverlayY,
          OverlayAnchorMode.topLeft,
        );
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
        _log.debug('Overlay body clicked → toggleRecording');
        ref.read(recordingOrchestratorProvider.notifier).toggleRecording();

      case OverlayRetryClicked():
        _log.debug('Overlay retry clicked → toggleRecording');
        ref.read(recordingProvider.notifier).reset();
        _hideOverlay();

      case OverlayDragEnded(x: final x, y: final y):
        _log.debug('Overlay dragged to ($x, $y)');
        _savePosition(x, y);

      case OverlayContextMenuAction(action: final action):
        _onContextMenuAction(action);
    }
  }

  void _onCloseClicked() {
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
    RecordingPhase.done => OverlayVisualState.done,
    RecordingPhase.error => OverlayVisualState.error,
  };

  String _labelFor(RecordingPhase phase, L10n? l10n) => switch (phase) {
    RecordingPhase.recording => l10n?.overlayRecording ?? 'Recording',
    RecordingPhase.transcribing => l10n?.overlayTranscribing ?? 'Transcribing…',
    RecordingPhase.done => l10n?.overlayDoneReady ?? 'Done',
    RecordingPhase.error => l10n?.overlayError ?? 'Error',
    RecordingPhase.idle => '',
  };

  String _hintFor(RecordingPhase phase, AppSettings s, L10n? l10n) {
    if (phase == RecordingPhase.recording && s.hotkeyEnabled) {
      final hotkey = formatHotkeyShortcut(
        s.hotkeyModifiers,
        s.hotkeyKey,
        l10n: l10n,
        displayOverride: s.hotkey.hotkeyKeyDisplay,
      );
      return l10n?.overlayKeyboardHint(hotkey) ?? 'Press $hotkey to stop';
    }
    if (phase == RecordingPhase.transcribing) {
      final isLocal = s.sttProviderType.isLocal;
      return isLocal
          ? (l10n?.overlayProcessingLocal ?? 'Local')
          : (l10n?.overlayProcessingCloud ?? 'Cloud');
    }
    return '';
  }

  String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool _computeIsDark(AppSettings s) =>
      resolveFloatingSurfaceIsDark(s.themeMode);

  L10n? _resolveL10n() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
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
