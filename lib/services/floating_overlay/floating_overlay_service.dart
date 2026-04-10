import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_labels.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import '../../widgets/recording_pill.dart';
import '../recording_orchestrator.dart';
import 'floating_overlay_controller.dart';
import 'floating_overlay_events.dart';

final _log = AppLogger('FloatingOverlayService');

/// Manages the native floating overlay window lifecycle.
///
/// Layer 3 — business logic. Watches recording state, settings, and theme,
/// builds fully-localized [FloatingOverlaySnapshot]s, and sends them to the
/// native overlay window via the platform controller (Layer 2).
///
/// Follows the same pattern as [FloatingButtonService]: Riverpod Notifier
/// with keepAlive, ref.listen for reactive updates, generation-guarded timers.
class FloatingOverlayService extends Notifier<void> {
  FloatingOverlayController? _controller;
  StreamSubscription<FloatingOverlayEvent>? _eventSub;
  Timer? _autoHideTimer;
  Timer? _audioThrottleTimer;

  /// Generation counter to prevent stale auto-hide callbacks from dismissing
  /// a new recording session's overlay.
  int _generation = 0;

  /// Tracks the last phase we sent to the overlay, so we know when to
  /// trigger show/hide transitions.
  RecordingPhase _lastPhase = RecordingPhase.idle;

  /// Cached L10n — updated whenever settings change (locale could change).
  L10n? _l10n;

  @override
  void build() {
    _controller = FloatingOverlayController.create();
    if (_controller == null) {
      _log.debug('Platform does not support native floating overlay');
      return;
    }

    _eventSub = _controller!.events.listen(_onEvent);

    ref.onDispose(() {
      _autoHideTimer?.cancel();
      _audioThrottleTimer?.cancel();
      _eventSub?.cancel();
      _controller?.dispose();
      _controller = null;
    });

    // Watch settings for overlay configuration changes.
    ref.listen(settingsProvider, (_, next) {
      next.whenData((s) => _syncSettings(s));
    });

    // Watch recording phase for state transitions.
    ref.listen(recordingPhaseProvider, (prev, next) {
      _onPhaseChanged(prev ?? RecordingPhase.idle, next);
    });

    // Watch audio level for waveform during recording.
    ref.listen(audioLevelProvider, (_, next) {
      _onAudioLevel(next);
    });

    // Watch elapsed for timer updates during recording.
    ref.listen(recordingElapsedProvider, (_, next) {
      _onElapsedChanged(next);
    });

    // Apply initial settings if already loaded.
    final settings = ref.read(settingsProvider);
    settings.whenData((s) => _syncSettings(s));
  }

  // ── Settings sync ─────────────────────────────────────────────────

  void _syncSettings(AppSettings s) {
    if (_controller == null) return;

    // Only active when overlay mode is floating.
    final active = s.effectiveOverlayMode == OverlayMode.floating;
    if (!active) {
      _hideOverlay();
      return;
    }

    // Cache L10n for snapshot building (English fallback if not available).
    _l10n = _resolveL10n();

    // Send context menu items with localized strings.
    _sendContextMenuItems();

    // If currently in a non-idle phase, re-send snapshot with updated settings.
    final phase = ref.read(recordingPhaseProvider);
    if (phase != RecordingPhase.idle) {
      _sendSnapshot(s, phase);
    }
  }

  // ── Phase transitions ─────────────────────────────────────────────

  void _onPhaseChanged(RecordingPhase prev, RecordingPhase next) {
    if (_controller == null) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;

    _lastPhase = next;

    switch (next) {
      case RecordingPhase.idle:
        _hideOverlay();

      case RecordingPhase.recording:
        // New recording session — bump generation to invalidate stale timers.
        _generation++;
        _autoHideTimer?.cancel();
        _sendSnapshot(settings, next);

      case RecordingPhase.transcribing:
      case RecordingPhase.processing:
        _sendSnapshot(settings, next);

      case RecordingPhase.done:
        _sendSnapshot(settings, next);
        _scheduleAutoHide(settings);

      case RecordingPhase.error:
        _sendSnapshot(settings, next);
        // Errors persist — no auto-hide. Only manual dismiss or 30s timeout.
        _scheduleErrorTimeout();
    }
  }

  // ── Audio level (throttled to ~20Hz) ──────────────────────────────

  double _pendingLevel = 0.0;
  bool _levelThrottled = false;

  void _onAudioLevel(double level) {
    if (_controller == null) return;
    if (_lastPhase != RecordingPhase.recording) return;

    _pendingLevel = level;
    if (_levelThrottled) return;

    _levelThrottled = true;
    _audioThrottleTimer = Timer(const Duration(milliseconds: 50), () {
      _levelThrottled = false;
      _controller?.setAudioLevel(_pendingLevel);
    });
  }

  // ── Elapsed timer updates ─────────────────────────────────────────

  void _onElapsedChanged(Duration elapsed) {
    if (_controller == null) return;
    if (_lastPhase != RecordingPhase.recording) return;

    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    if (settings.effectiveOverlayMode != OverlayMode.floating) return;

    _sendSnapshot(settings, RecordingPhase.recording);
  }

  // ── Snapshot building ─────────────────────────────────────────────

  void _sendSnapshot(AppSettings s, RecordingPhase phase) {
    if (_controller == null) return;

    final l10n = _l10n ?? _resolveL10n();
    final isDark = _computeIsDark(s);
    final compact = s.overlaySizeType == FloatingOverlaySize.compact;
    final elapsed = ref.read(recordingElapsedProvider);
    final recording = ref.read(recordingProvider);
    final isLocal = s.sttProviderType.isLocal;

    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: _mapPhase(phase),
      isDark: isDark,
      compact: compact,
      label: _labelFor(phase, l10n),
      elapsed: phase == RecordingPhase.recording ? _formatElapsed(elapsed) : '',
      hint: _hintFor(phase, s, l10n),
      transcript: recording.transcript,
      errorMessage: recording.errorMessage,
      privacyMode: isLocal ? 'local' : 'cloud',
      showRetry: phase == RecordingPhase.error,
      doneMessage: phase == RecordingPhase.done && l10n != null
          ? RecordingPill.doneMessageFor(s.afterTranscription, l10n)
          : null,
      processingLabel: phase == RecordingPhase.processing
          ? (l10n?.overlayRefining ?? 'Refining…')
          : null,
    );

    _controller!.updateSnapshot(snapshot).catchError((e, st) {
      _log.error('Failed to send overlay snapshot', e, st);
    });

    // Set initial position on first show.
    if (phase == RecordingPhase.recording &&
        _lastPhase == RecordingPhase.idle) {
      _setStartPosition(s);
    }
  }

  void _hideOverlay() {
    if (_controller == null) return;
    _autoHideTimer?.cancel();

    const hidden = FloatingOverlaySnapshot(
      visible: false,
      state: OverlayVisualState.recording,
      isDark: true,
      compact: false,
      label: '',
    );

    _controller!.updateSnapshot(hidden).catchError((e, st) {
      _log.error('Failed to hide overlay', e, st);
    });
  }

  // ── Auto-hide ─────────────────────────────────────────────────────

  void _scheduleAutoHide(AppSettings s) {
    _autoHideTimer?.cancel();

    final autoHide = s.overlayAutoHideType;
    if (autoHide == OverlayAutoHide.manual) return;

    final gen = _generation;
    _autoHideTimer = Timer(Duration(seconds: autoHide.seconds), () {
      // Only dismiss if we're still in the same generation (no new recording).
      if (_generation == gen && _lastPhase == RecordingPhase.done) {
        _hideOverlay();
      }
    });
  }

  void _scheduleErrorTimeout() {
    _autoHideTimer?.cancel();

    final gen = _generation;
    // Error auto-dismisses after 30s if no user interaction.
    _autoHideTimer = Timer(const Duration(seconds: 30), () {
      if (_generation == gen && _lastPhase == RecordingPhase.error) {
        _hideOverlay();
      }
    });
  }

  // ── Start position ────────────────────────────────────────────────

  Future<void> _setStartPosition(AppSettings s) async {
    if (_controller == null) return;

    try {
      final pos = s.overlayStartPositionType;

      if (pos == OverlayStartPosition.lastPosition &&
          s.floatingOverlayX >= 0 &&
          s.floatingOverlayY >= 0) {
        await _controller!.setPosition(
          s.floatingOverlayX,
          s.floatingOverlayY,
          OverlayAnchorMode.topLeft,
        );
      } else {
        final anchor = pos == OverlayStartPosition.bottomCenter
            ? OverlayAnchorMode.bottomCenter
            : OverlayAnchorMode.topCenter;
        // x=-1, y=-1 signals C++ to compute centered position.
        await _controller!.setPosition(-1, -1, anchor);
      }
    } catch (e, st) {
      _log.error('Failed to set overlay start position', e, st);
    }
  }

  // ── Context menu ──────────────────────────────────────────────────

  void _sendContextMenuItems() {
    if (_controller == null) return;
    final l10n = _l10n;
    if (l10n == null) return;

    _controller!
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

  // ── Event handling ────────────────────────────────────────────────

  void _onEvent(FloatingOverlayEvent event) {
    switch (event) {
      case OverlayCloseClicked():
        _onCloseClicked();

      case OverlayBodyClicked():
        _log.debug('Overlay body clicked → toggleRecording');
        ref.read(recordingOrchestratorProvider.notifier).toggleRecording();

      case OverlayRetryClicked():
        _log.debug('Overlay retry clicked → toggleRecording');
        // Reset to idle, then the user can start a new recording.
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
      // During recording, ✕ = stop recording (same as toggling).
      _log.debug('Overlay close during recording → stopRecording');
      ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
    } else {
      // After completion or during processing, ✕ = dismiss.
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

  Future<void> _savePosition(double x, double y) async {
    try {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              floatingOverlayX: x,
              floatingOverlayY: y,
              overlayStartPosition: OverlayStartPosition.lastPosition.value,
            ),
          );
    } catch (e, st) {
      _log.error('Failed to save overlay position', e, st);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  static OverlayVisualState _mapPhase(RecordingPhase phase) => switch (phase) {
    RecordingPhase.idle => OverlayVisualState.recording,
    RecordingPhase.recording => OverlayVisualState.recording,
    RecordingPhase.transcribing => OverlayVisualState.transcribing,
    RecordingPhase.processing => OverlayVisualState.processing,
    RecordingPhase.done => OverlayVisualState.done,
    RecordingPhase.error => OverlayVisualState.error,
  };

  String _labelFor(RecordingPhase phase, L10n? l10n) => switch (phase) {
    RecordingPhase.recording => l10n?.overlayRecording ?? 'Recording',
    RecordingPhase.transcribing => l10n?.overlayTranscribing ?? 'Transcribing…',
    RecordingPhase.processing => l10n?.overlayRefining ?? 'Refining…',
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

  bool _computeIsDark(AppSettings s) {
    return switch (s.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
  }

  L10n? _resolveL10n() {
    // L10n is available from the widget tree. Since we're in a service
    // (not a widget), we use the platform dispatcher locale to look up
    // the correct localization delegate.
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    try {
      return lookupL10n(locale);
    } catch (_) {
      // Fallback to English if locale not supported.
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
