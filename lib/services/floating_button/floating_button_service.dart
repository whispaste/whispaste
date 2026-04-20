import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/macos_lifecycle_channel.dart';
import '../../core/recording/recording_state.dart';
import '../recording_orchestrator.dart';
import 'floating_button_controller.dart';
import 'floating_button_events.dart';

final _log = AppLogger('FloatingButtonService');

/// Maps [RecordingPhase] to the native button's visual state.
FloatingButtonVisualState _mapPhase(RecordingPhase phase) => switch (phase) {
      RecordingPhase.idle => FloatingButtonVisualState.idle,
      RecordingPhase.recording => FloatingButtonVisualState.recording,
      RecordingPhase.transcribing => FloatingButtonVisualState.transcribing,
      RecordingPhase.processing => FloatingButtonVisualState.transcribing,
      RecordingPhase.done => FloatingButtonVisualState.done,
      RecordingPhase.error => FloatingButtonVisualState.error,
    };

/// Manages the native floating button lifecycle.
///
/// Layer 3 — business logic. Watches settings and recording state,
/// forwards visual commands to the platform controller (Layer 2),
/// and handles events (click → toggle recording, drag → save position).
class FloatingButtonService extends Notifier<void> {
  FloatingButtonController? _controller;
  StreamSubscription<FloatingButtonEvent>? _eventSub;
  Timer? _autoResetTimer;

  @override
  void build() {
    _controller = FloatingButtonController.create();
    if (_controller == null) {
      _log.debug('Platform does not support native floating button');
      return;
    }

    _eventSub = _controller!.events.listen(_onEvent);

    // Clean up on provider dispose.
    ref.onDispose(() {
      _autoResetTimer?.cancel();
      _eventSub?.cancel();
      _controller?.dispose();
      _controller = null;
    });

    // Watch settings for show/hide + configuration.
    ref.listen(settingsProvider, (_, next) {
      next.whenData((s) => _syncSettings(s));
    });

    // Watch recording phase for visual state changes.
    ref.listen(recordingPhaseProvider, (prev, next) {
      _syncPhase(next);
    });

    // Apply initial settings if already loaded.
    final settings = ref.read(settingsProvider);
    settings.whenData((s) => _syncSettings(s));
  }

  // ── Settings sync ─────────────────────────────────────────────────

  Future<void> _syncSettings(AppSettings s) async {
    if (_controller == null) return;

    try {
      if (s.showFloatingButton) {
        final size = s.floatingButtonSizeType.pixels;
        final x = s.floatingButtonX;
        final y = s.floatingButtonY;

        await _controller!.show(x: x, y: y, size: size);
        await _controller!.setOpacity(s.floatingButtonOpacity);

        // Send theme based on current themeMode.
        final isDark = s.themeMode != ThemeMode.light;
        await _controller!.setTheme(isDark: isDark);

        // Send current recording phase.
        final phase = ref.read(recordingPhaseProvider);
        await _controller!.setState(_mapPhase(phase));
      } else {
        await _controller!.hide();
      }
    } catch (e, st) {
      _log.error('Failed to sync floating button settings', e, st);
    }
  }

  // ── Recording phase sync ──────────────────────────────────────────

  Future<void> _syncPhase(RecordingPhase phase) async {
    if (_controller == null) return;

    try {
      await _controller!.setState(_mapPhase(phase));

      // Auto-reset done/error back to idle after a delay.
      _autoResetTimer?.cancel();
      if (phase == RecordingPhase.done) {
        _autoResetTimer = Timer(const Duration(seconds: 2), () {
          _controller?.setState(FloatingButtonVisualState.idle);
        });
      } else if (phase == RecordingPhase.error) {
        _autoResetTimer = Timer(const Duration(seconds: 3), () {
          _controller?.setState(FloatingButtonVisualState.idle);
        });
      }
    } catch (e, st) {
      _log.error('Failed to sync recording phase', e, st);
    }
  }

  // ── Event handling ────────────────────────────────────────────────

  void _onEvent(FloatingButtonEvent event) {
    switch (event) {
      case FloatingButtonClicked():
        _log.debug('Floating button clicked → toggleRecording');
        ref.read(recordingOrchestratorProvider.notifier).toggleRecording();

      case FloatingButtonSecondaryClicked():
        _log.debug('Floating button secondary click → show main window');
        _bringMainWindowToFront();

      case FloatingButtonDragEnded(x: final x, y: final y):
        _log.debug('Floating button dragged to ($x, $y)');
        _savePosition(x, y);
    }
  }

  Future<void> _bringMainWindowToFront() async {
    try {
      // On macOS, restore Dock presence before showing the window.
      await MacOSLifecycleChannel.setRegular();
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      _log.error('Failed to bring main window to front', e, st);
    }
  }

  Future<void> _savePosition(double x, double y) async {
    try {
      await ref.read(settingsProvider.notifier).updateSettings(
            (s) => s.copyWith(floatingButtonX: x, floatingButtonY: y),
          );
    } catch (e, st) {
      _log.error('Failed to save floating button position', e, st);
    }
  }
}

/// Provider for the floating button service (keepAlive — lives for app lifetime).
final floatingButtonServiceProvider =
    NotifierProvider<FloatingButtonService, void>(
  FloatingButtonService.new,
);
