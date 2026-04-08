/// Multi-window management for desktop floating overlay and floating button.
///
/// Uses `desktop_multi_window` to create secondary always-on-top Flutter
/// windows. Recording state is pushed from the main window via
/// [WindowController.invokeMethod]; commands flow back via
/// [WindowMethodChannel].
///
/// Robustness guarantees:
/// - Creation guards prevent concurrent window creation for the same type.
/// - Readiness probe (up to 6 attempts) verifies engine before use.
/// - Logged errors on channel failures (no silent catches).
/// - Fallback to in-window overlay when floating overlay creation fails.
/// - Shutdown sends 'shutdown' command → secondary hides + goes inert.
///   We NEVER call exit(0) from secondary windows because all engines
///   share the same OS process — exit(0) would kill the whole app.
/// - Recording-safe mode changes: overlay is not destroyed during recording.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/settings_enums.dart';
import '../core/config/settings_labels.dart' show formatHotkeyShortcut;
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/multi_window/multi_window_types.dart';
export '../core/multi_window/multi_window_types.dart';
import '../core/recording/recording_state.dart';
import '../app.dart' show activePageProvider;
import 'recording_orchestrator.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class MultiWindowState {
  const MultiWindowState({
    this.overlayVisible = false,
    this.buttonVisible = false,
  });

  final bool overlayVisible;
  final bool buttonVisible;

  MultiWindowState copyWith({bool? overlayVisible, bool? buttonVisible}) =>
      MultiWindowState(
        overlayVisible: overlayVisible ?? this.overlayVisible,
        buttonVisible: buttonVisible ?? this.buttonVisible,
      );
}

// ---------------------------------------------------------------------------
// Notifier (runs in the MAIN window only)
// ---------------------------------------------------------------------------

class MultiWindowNotifier extends Notifier<MultiWindowState> {
  static final _log = AppLogger('MultiWindow');

  // Static registry — survives hot reload (notifier instance recreation).
  // Secondary OS windows run in separate engines and persist across reloads.
  static WindowController? _overlayController;
  static WindowController? _buttonController;

  // Guards against concurrent creation of the same window type.
  static bool _creatingOverlay = false;
  static bool _creatingButton = false;
  static bool _reconcilingWindows = false;

  // Debounce timers — separate for button and overlay to avoid interference.
  Timer? _buttonDebounce;
  Timer? _overlayDebounce;
  // Timer for auto-dismissing the floating overlay after completion.
  Timer? _overlayDismissTimer;

  /// Whether recording is currently active (non-idle).
  bool get _isRecording {
    try {
      return ref.read(recordingProvider).phase != RecordingPhase.idle;
    } catch (_) {
      return false;
    }
  }

  @override
  MultiWindowState build() {
    // Register the main window's command handler for secondary -> main calls.
    commandChannel.setMethodCallHandler(_handleCommand);

    // Push recording state to secondary windows + auto-show/hide overlay.
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      _pushRecordingState(next);

      // Auto-show floating overlay when recording starts (if mode is floating).
      final settings = ref.read(settingsProvider).value;
      if (settings != null &&
          settings.overlayModeType == OverlayMode.floating) {
        if (prev?.phase == RecordingPhase.idle &&
            next.phase == RecordingPhase.recording) {
          _overlayDismissTimer?.cancel();
          // Set overlayVisible synchronously BEFORE the async show() to
          // prevent the in-window overlay fallback from flashing for one
          // frame while the floating window is opening.
          if (_overlayController != null) {
            state = state.copyWith(overlayVisible: true);
          }
          // Fire-and-forget — errors must not block the UI thread.
          showOverlay().catchError((Object e) {
            _log.warning('Auto-show overlay failed: $e');
          });
        }
        // Auto-hide overlay a few seconds after completion so the done pill
        // is readable. The pill holds for 3s, then we hide the window.
        if (next.phase == RecordingPhase.idle && state.overlayVisible) {
          _overlayDismissTimer?.cancel();
          _log.debug('Scheduling overlay dismiss in 4s (state → idle)');
          _overlayDismissTimer = Timer(const Duration(seconds: 4), () {
            _log.debug('Overlay dismiss timer fired (visible=${state.overlayVisible})');
            if (state.overlayVisible) hideOverlay();
          });
        }
      }
    });

    // React to settings changes: show/hide button + overlay, push updates.
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final settings = next.value;
      if (settings == null) return;

      // ── Floating button (separate debounce) ──
      _buttonDebounce?.cancel();
      _buttonDebounce = Timer(const Duration(milliseconds: 300), () {
        // Suppress floating button during onboarding.
        if (!settings.onboardingCompleted) {
          if (state.buttonVisible) hideButton();
          return;
        }
        if (settings.showFloatingButton && !state.buttonVisible) {
          _log.info('Settings → showing floating button');
          showButton();
        }
        if (!settings.showFloatingButton && state.buttonVisible) {
          _log.info('Settings → hiding floating button');
          hideButton();
        }
        if (state.buttonVisible && _buttonController != null) {
          _pushButtonSettings(settings);
        }
      });

      // ── Floating overlay mode changes (separate debounce) ──
      _overlayDebounce?.cancel();
      _overlayDebounce = Timer(const Duration(milliseconds: 300), () {
        final prevMode = prev?.value?.overlayModeType;
        if (prevMode == settings.overlayModeType) return;
        _log.info(
          'Settings → overlay mode changed: $prevMode → '
          '${settings.overlayModeType}',
        );

        if (settings.overlayModeType == OverlayMode.floating) {
          // Pre-create the overlay window so it's ready instantly.
          _ensureOverlayCreated().then((_) {
            // If recording is already active, auto-show the new overlay.
            if (_isRecording &&
                _overlayController != null &&
                !state.overlayVisible) {
              _log.info(
                'Recording active during mode switch → '
                'auto-showing overlay',
              );
              showOverlay();
            }
          });
        } else {
          // Switched away from floating — destroy the overlay window.
          // Safe during recording: the in-window overlay takes over.
          _shutdownOverlay();
        }
      });

      // ── Overlay start position live update ──
      final prevPos = prev?.value?.overlayStartPositionType;
      if (prevPos != null &&
          prevPos != settings.overlayStartPositionType &&
          state.overlayVisible &&
          _overlayController != null) {
        _log.info(
          'Settings → overlay position changed: $prevPos → '
          '${settings.overlayStartPositionType}',
        );
        _repositionOverlay(settings.overlayStartPositionType, settings);
      }
    });

    ref.onDispose(() {
      _buttonDebounce?.cancel();
      _overlayDebounce?.cancel();
      _overlayDismissTimer?.cancel();
      // Only clear our handler — do NOT close secondary windows.
      // They survive hot reload and will be reconnected by the next build().
      commandChannel.setMethodCallHandler(null);
    });

    // Recover state from surviving secondary windows (hot reload scenario).
    final initialState = MultiWindowState(
      overlayVisible: _overlayController != null,
      buttonVisible: _buttonController != null,
    );

    // Always reconcile with the actual OS windows after build returns. Static
    // refs survive hot reload, but they are not enough to dedupe orphaned
    // secondary engines or recover hidden windows reliably.
    Future.microtask(() async {
      await _restoreExistingWindows();
    });

    return initialState;
  }

  /// Shows the floating button if settings require it.
  ///
  /// When settings aren't loaded yet (first frame), schedules a retry.
  /// This covers both the common path (settings already in memory from
  /// main.dart bootstrap) and the cold-start path.
  void _applyInitialSettings() {
    final settings = ref.read(settingsProvider).value;
    if (settings != null) {
      _applySettingsNow(settings);
      return;
    }
    // Settings not yet loaded — retry after a short delay. The ref.listen
    // on settingsProvider (above) will handle subsequent changes, but we
    // need this initial trigger because listen doesn't fire for the first
    // resolved value when transitioning from loading → data.
    _log.debug('Settings not yet loaded — deferring initial window setup');
    Future.delayed(const Duration(milliseconds: 800), () {
      final s = ref.read(settingsProvider).value;
      if (s != null && !state.buttonVisible) {
        _applySettingsNow(s);
      }
    });
  }

  void _applySettingsNow(AppSettings settings) {
    // Don't show the floating button during onboarding — the overlay blocks
    // interaction with the main window but the button is a separate OS window.
    if (!settings.onboardingCompleted) return;

    if (settings.showFloatingButton && !state.buttonVisible) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!state.buttonVisible) showButton();
      });
    }
    // Pre-create the floating overlay window so it's ready when recording
    // starts. The window stays hidden until showOverlay() is called.
    if (settings.overlayModeType == OverlayMode.floating &&
        _overlayController == null) {
      Future.delayed(const Duration(milliseconds: 800), () {
        _ensureOverlayCreated();
      });
    }
  }

  Future<void> _restoreExistingWindows() async {
    await _reconcileExistingWindows();

    final settings = ref.read(settingsProvider).value;
    if (settings == null) {
      _applyInitialSettings();
      return;
    }

    if (settings.showFloatingButton && settings.onboardingCompleted) {
      if (_buttonController == null) {
        await showButton();
      } else {
        _pushButtonSettings(settings);
        // Re-sync recording state so the button reflects reality after
        // hot reload or window reconciliation.
        _pushRecordingStateTo(_buttonController!, ref.read(recordingProvider));
        if (!state.buttonVisible) {
          await _showSecondaryWindow(_buttonController!, target: 'button');
          state = state.copyWith(buttonVisible: true);
        }
      }
    } else if (_buttonController != null) {
      await hideButton();
    }

    if (settings.overlayModeType == OverlayMode.floating) {
      await _ensureOverlayCreated();
      if (_overlayController != null) {
        _pushRecordingStateTo(_overlayController!, ref.read(recordingProvider));
        if (_isRecording) {
          await showOverlay();
        } else if (state.overlayVisible) {
          await hideOverlay();
        }
      }
    } else if (_overlayController != null) {
      await _shutdownOverlay();
    }
  }

  Future<void> _reconcileExistingWindows() async {
    if (!_isDesktop || _reconcilingWindows) return;
    _reconcilingWindows = true;
    try {
      final controllers = await WindowController.getAll();
      final grouped = <String, List<_DiscoveredWindow>>{
        WindowType.floatingOverlay: <_DiscoveredWindow>[],
        WindowType.floatingButton: <_DiscoveredWindow>[],
      };
      final stale = <_ParsedWindowCandidate>[];

      for (final controller in controllers) {
        final parsed = _ParsedWindowCandidate.tryParse(controller);
        if (parsed == null) continue;
        final probe = await _probeWindow(parsed);
        if (probe == null) {
          stale.add(parsed);
          continue;
        }
        grouped[probe.type]!.add(probe);
      }

      final overlayWinner = _selectPreferredWindow(
        grouped[WindowType.floatingOverlay]!,
      );
      final buttonWinner = _selectPreferredWindow(
        grouped[WindowType.floatingButton]!,
      );

      for (final candidate in grouped[WindowType.floatingOverlay]!) {
        if (candidate.controller != overlayWinner?.controller) {
          await _retireWindow(
            candidate.controller,
            type: candidate.type,
            reason: 'duplicate overlay window',
          );
        }
      }
      for (final candidate in grouped[WindowType.floatingButton]!) {
        if (candidate.controller != buttonWinner?.controller) {
          await _retireWindow(
            candidate.controller,
            type: candidate.type,
            reason: 'duplicate floating button window',
          );
        }
      }
      for (final candidate in stale) {
        await _retireWindow(
          candidate.controller,
          type: candidate.type,
          reason: 'unresponsive secondary window',
        );
      }

      _overlayController = overlayWinner?.controller;
      _buttonController = buttonWinner?.controller;
      _syncWindowStateFlags(
        overlayVisible: overlayWinner?.isVisible ?? false,
        buttonVisible: buttonWinner?.isVisible ?? false,
      );
    } catch (e, st) {
      _log.warning('Failed to reconcile existing secondary windows', e, st);
    } finally {
      _reconcilingWindows = false;
    }
  }

  Future<_DiscoveredWindow?> _probeWindow(
    _ParsedWindowCandidate candidate,
  ) async {
    try {
      final response = await candidate.controller.invokeMethod(
        'getWindowStatus',
      );
      if (response is! String) return null;
      final data = jsonDecode(response) as Map<String, dynamic>;
      if (data['inert'] == true) return null;
      return _DiscoveredWindow(
        controller: candidate.controller,
        type: (data['type'] as String?) ?? candidate.type,
        launchEpochMs:
            (data['launchEpochMs'] as num?)?.toInt() ?? candidate.launchEpochMs,
        isVisible: data['visible'] == true,
      );
    } catch (e) {
      _log.debug(
        'Failed to probe ${candidate.type} window ${candidate.controller.windowId}: $e',
      );
      return null;
    }
  }

  _DiscoveredWindow? _selectPreferredWindow(List<_DiscoveredWindow> windows) {
    if (windows.isEmpty) return null;
    final sorted = [...windows]
      ..sort((a, b) {
        if (a.isVisible != b.isVisible) {
          return a.isVisible ? -1 : 1;
        }
        final launchCompare = b.launchEpochMs.compareTo(a.launchEpochMs);
        if (launchCompare != 0) return launchCompare;
        return b.controller.windowId.compareTo(a.controller.windowId);
      });
    return sorted.first;
  }

  Future<void> _retireWindow(
    WindowController controller, {
    required String type,
    required String reason,
  }) async {
    _log.info('Retiring $type window ${controller.windowId} ($reason)');
    try {
      await controller.invokeMethod('shutdown');
    } catch (_) {}
    try {
      await controller.invokeMethod('hideWindow');
    } catch (_) {}
    try {
      await controller.hide();
    } catch (_) {}
  }

  Future<void> _showSecondaryWindow(
    WindowController controller, {
    required String target,
    bool assertTopmost = false,
    String? arguments,
  }) async {
    // invokeMethod('showWindow') triggers the Flutter engine inside the
    // secondary window to resize + show via window_manager. We intentionally
    // do NOT call controller.show() (DMW native) — that would make the window
    // visible at whatever stale size it has, racing with the engine sizing.
    try {
      await controller.invokeMethod('showWindow', arguments);
    } catch (e) {
      _log.warning('showWindow failed for $target window: $e');
    }
    if (assertTopmost) {
      controller.invokeMethod('assertTopmost').catchError((Object e) {
        _log.warning('assertTopmost failed for $target window: $e');
      });
    }
  }

  Future<void> _hideSecondaryWindow(
    WindowController controller, {
    required String target,
  }) async {
    try {
      await controller.invokeMethod('hideWindow').timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _log.warning('invokeMethod(hideWindow) timed out for $target (3s)');
          return null;
        },
      );
    } catch (e) {
      _log.warning('hideWindow failed for $target window: $e');
    }
    // For the overlay, we do NOT call controller.hide() (DMW native). The
    // overlay uses resize-based visibility (1×1 = hidden, 540×72 = visible)
    // to work around a window_manager bug where transparent frameless windows
    // lose their rendering surface after hide → show on Windows.
    if (target != 'overlay') {
      try {
        await controller.hide();
      } catch (e) {
        _log.warning('Native hide() failed for $target window: $e');
      }
    }
  }

  void _syncWindowStateFlags({
    required bool overlayVisible,
    required bool buttonVisible,
  }) {
    state = state.copyWith(
      overlayVisible: overlayVisible,
      buttonVisible: buttonVisible,
    );
  }

  /// Pushes appearance settings (size, opacity) to the floating button
  /// window via method channel so changes take effect in real-time.
  void _pushButtonSettings(AppSettings settings) {
    final ctrl = _buttonController;
    if (ctrl == null) return;
    final payload = jsonEncode({
      'size': floatingButtonSizeFromString(settings.floatingButtonSize),
      'opacity': settings.floatingButtonOpacity,
      'maxRecordDurationSeconds': settings.maxRecordDuration,
      // Always show the progress ring when a max duration is set —
      // the ring is subtle and useful regardless of overlay mode.
      'showRecordingProgress': settings.maxRecordDuration > 0,
    });
    ctrl.invokeMethod('updateButtonSettings', payload).catchError((Object e) {
      _log.warning('Failed to push button settings', e);
    });
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // -- Floating overlay window ----------------------------------------------

  /// Pre-creates the overlay window (hidden) so it's ready instantly.
  Future<void> _ensureOverlayCreated() async {
    if (!_isDesktop || _creatingOverlay) return;
    if (_overlayController == null) {
      await _reconcileExistingWindows();
    }
    if (_overlayController != null) return;
    _creatingOverlay = true;
    try {
      _overlayController = await _createWindow(WindowType.floatingOverlay);
      if (_overlayController != null) {
        _log.info('Floating overlay pre-created (hidden)');
      } else {
        _log.warning('Floating overlay pre-creation failed');
      }
    } finally {
      _creatingOverlay = false;
    }
  }

  /// Shows the floating overlay. Creates the window if it doesn't exist yet.
  ///
  /// Push recording state BEFORE showing the window so the overlay renders
  /// with the correct content on its first visible frame (avoids transparent
  /// flash while idle state SizedBox.shrink is rendered).
  Future<void> showOverlay() async {
    if (!_isDesktop || _creatingOverlay) return;
    if (_overlayController == null) {
      await _reconcileExistingWindows();
    }
    // Build overlay position args based on start position setting.
    String? posArgs;
    final settings = ref.read(settingsProvider).value;
    if (settings != null) {
      final startPos = settings.overlayStartPositionType;
      switch (startPos) {
        case OverlayStartPosition.lastPosition:
          if (settings.floatingOverlayX >= 0) {
            posArgs = jsonEncode({
              'x': settings.floatingOverlayX,
              'y': settings.floatingOverlayY,
            });
          }
        case OverlayStartPosition.topCenter:
          posArgs = jsonEncode({'align': 'top-center'});
        case OverlayStartPosition.bottomCenter:
          posArgs = jsonEncode({'align': 'bottom-center'});
      }
    }
    if (_overlayController != null) {
      // Window exists — push state first, then show.
      try {
        _pushRecordingStateTo(_overlayController!, ref.read(recordingProvider));
        await _showSecondaryWindow(
          _overlayController!,
          target: 'overlay',
          assertTopmost: true,
          arguments: posArgs,
        );
        _log.info('Floating overlay shown (existing window)');
      } catch (e) {
        _log.warning('Overlay show() failed — recreating', e);
        _overlayController = null;
      }
    }
    // Create if not present (first time or after failed show).
    if (_overlayController == null) {
      _creatingOverlay = true;
      try {
        _overlayController = await _createWindow(WindowType.floatingOverlay);
        if (_overlayController != null) {
          try {
            _pushRecordingStateTo(
              _overlayController!,
              ref.read(recordingProvider),
            );
            await _showSecondaryWindow(
              _overlayController!,
              target: 'overlay',
              assertTopmost: true,
              arguments: posArgs,
            );
            _log.info('Floating overlay shown (newly created)');
          } catch (e) {
            _log.warning('Overlay show() on new window failed', e);
          }
        }
      } finally {
        _creatingOverlay = false;
      }
    }
    if (_overlayController != null) {
      state = state.copyWith(overlayVisible: true);
    } else {
      _log.warning(
        'Floating overlay creation failed — '
        'in-window overlay will be used as fallback',
      );
    }
  }

  /// Re-sends the position to an already-visible overlay window.
  Future<void> _repositionOverlay(
    OverlayStartPosition pos,
    AppSettings settings,
  ) async {
    final ctrl = _overlayController;
    if (ctrl == null) return;

    String? posArgs;
    switch (pos) {
      case OverlayStartPosition.lastPosition:
        if (settings.floatingOverlayX >= 0) {
          posArgs = jsonEncode({
            'x': settings.floatingOverlayX,
            'y': settings.floatingOverlayY,
          });
        }
      case OverlayStartPosition.topCenter:
        posArgs = jsonEncode({'align': 'top-center'});
      case OverlayStartPosition.bottomCenter:
        posArgs = jsonEncode({'align': 'bottom-center'});
    }

    try {
      await _showSecondaryWindow(
        ctrl,
        target: 'overlay',
        assertTopmost: true,
        arguments: posArgs,
      );
      _log.info('Overlay repositioned to $pos');
    } catch (e) {
      _log.warning('Failed to reposition overlay', e);
    }
  }

  /// Hides the overlay window but keeps the controller alive for reuse.
  Future<void> hideOverlay() async {
    final ctrl = _overlayController;
    if (ctrl == null) return;
    state = state.copyWith(overlayVisible: false);
    try {
      await _hideSecondaryWindow(ctrl, target: 'overlay')
          .timeout(const Duration(seconds: 5), onTimeout: () {
        _log.warning('hideOverlay: _hideSecondaryWindow timed out (5s)');
      });
      _log.info('Floating overlay hidden');
    } catch (e) {
      _log.warning('Overlay hide() failed (may already be closed)', e);
      _overlayController = null;
    }
  }

  /// Hides and releases the floating overlay.
  ///
  /// The `desktop_multi_window` package has no API to destroy a secondary
  /// window — only show/hide. We send a 'shutdown' command so the secondary
  /// engine goes inert (stops heartbeat, ignores future calls), then hide the
  /// OS window. The engine stays alive but dormant until the process exits.
  ///
  /// **CRITICAL**: We do NOT call exit(0) in the secondary engine because all
  /// windows share the same OS process — exit(0) would kill everything.
  Future<void> _shutdownOverlay() async {
    final ctrl = _overlayController;
    if (ctrl == null) return;
    _overlayController = null;
    state = state.copyWith(overlayVisible: false);
    _log.info('Shutting down floating overlay window (hide + inert)');
    try {
      await ctrl.invokeMethod('shutdown');
    } catch (e) {
      _log.debug('Overlay shutdown command failed (may already be gone): $e');
    }
    await _hideSecondaryWindow(ctrl, target: 'overlay');
  }

  // -- Floating button window -----------------------------------------------

  Future<void> showButton() async {
    if (!_isDesktop || _creatingButton) return;
    if (_buttonController == null) {
      await _reconcileExistingWindows();
    }
    if (_buttonController != null) {
      // Window already created — just push latest state.
      final settings = ref.read(settingsProvider).value;
      if (settings != null) {
        _pushButtonSettings(settings);
      }
      _pushRecordingStateTo(_buttonController!, ref.read(recordingProvider));
      await _showSecondaryWindow(
        _buttonController!,
        target: 'button',
        assertTopmost: true,
      );
      state = state.copyWith(buttonVisible: true);
      return;
    }
    _creatingButton = true;
    try {
      _buttonController = await _createWindow(WindowType.floatingButton);
      if (_buttonController != null) {
        state = state.copyWith(buttonVisible: true);
        final settings = ref.read(settingsProvider).value;
        if (settings != null) {
          _pushButtonSettings(settings);
        }
        _pushRecordingStateTo(_buttonController!, ref.read(recordingProvider));
      }
    } finally {
      _creatingButton = false;
    }
  }

  Future<void> hideButton() async {
    final ctrl = _buttonController;
    if (ctrl == null) return;
    _buttonController = null;
    state = state.copyWith(buttonVisible: false);
    _log.info('Shutting down floating button (hide + inert)');
    try {
      await ctrl.invokeMethod('shutdown');
    } catch (e) {
      _log.debug('Button shutdown command failed: $e');
    }
    await _hideSecondaryWindow(ctrl, target: 'button');
  }

  // -- Window creation with retry -------------------------------------------

  Future<WindowController?> _createWindow(String type) async {
    try {
      final settings = ref.read(settingsProvider).value;
      final args = jsonEncode({
        'type': type,
        'launchEpochMs': DateTime.now().millisecondsSinceEpoch,
        if (settings != null) ...{
          'size': floatingButtonSizeFromString(settings.floatingButtonSize),
          'opacity': settings.floatingButtonOpacity,
          // Persisted position (-1 = not set → let OS choose).
          'posX': settings.floatingButtonX,
          'posY': settings.floatingButtonY,
          'maxRecordDurationSeconds': settings.maxRecordDuration,
          'showRecordingProgress': settings.maxRecordDuration > 0,
        },
      });
      final controller = await WindowController.create(
        WindowConfiguration(arguments: args, hiddenAtLaunch: true),
      );

      // Wait for the secondary Flutter engine to initialise.
      // The engine runs in a separate process and takes time to start. We
      // verify readiness by probing the method channel for its status. The
      // button screen shows itself via windowManager.show(); the overlay stays
      // hidden until explicitly shown from the main window.
      const maxAttempts = 6;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        await Future<void>.delayed(
          Duration(
            milliseconds: 200 * attempt,
          ), // 200, 400, …, 1200ms (total ~5s)
        );
        try {
          await controller.invokeMethod('getWindowStatus');
          _log.info(
            'Created $type window (id: ${controller.windowId}, '
            'ready on attempt: $attempt)',
          );
          return controller;
        } catch (e) {
          if (attempt == maxAttempts) {
            _log.error(
              'Engine for $type window not ready after $maxAttempts attempts',
              e,
            );
            // Clean up the orphaned OS window to avoid resource leak.
            try {
              await controller.hide();
            } catch (_) {}
            return null;
          }
          _log.debug('$type engine not ready (attempt $attempt), retrying…');
        }
      }
      return null;
    } catch (e, st) {
      _log.error('Failed to create $type window', e, st);
      return null;
    }
  }

  // -- State sync (main → secondary) ---------------------------------------

  String _encodeWithSettings(RecordingState recState) {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return encodeRecordingState(recState);
    final aiMode = settings.postProcessEnabled
        ? settings.postProcessPreset
        : null;
    return encodeRecordingState(
      recState,
      maxRecordDurationSeconds: settings.maxRecordDuration,
      afterAction: settings.afterTranscription,
      aiMode: aiMode,
      isLocalStt: settings.sttProviderType.isLocal,
      hotkeyLabel: formatHotkeyShortcut(
        settings.hotkeyModifiers,
        settings.hotkeyKey,
      ),
      isDark: settings.themeMode == ThemeMode.dark,
    );
  }

  void _pushRecordingState(RecordingState recState) {
    final encoded = _encodeWithSettings(recState);
    // Push to all live controllers regardless of visibility flags.
    // The visibility flags can temporarily go false during window
    // reconciliation — gating on them would permanently block state sync
    // until the next explicit show() call.
    if (_overlayController != null) {
      _pushEncodedTo(_overlayController!, encoded, 'overlay');
    }
    if (_buttonController != null) {
      _pushEncodedTo(_buttonController!, encoded, 'button');
    }
  }

  void _pushRecordingStateTo(
    WindowController controller,
    RecordingState recState,
  ) {
    final target = controller == _overlayController
        ? 'overlay'
        : controller == _buttonController
        ? 'button'
        : 'secondary';
    _pushEncodedTo(controller, _encodeWithSettings(recState), target);
  }

  void _pushEncodedTo(
    WindowController controller,
    String encoded,
    String target,
  ) {
    // Fire-and-forget with timeout — a broken secondary window must never
    // block the main UI thread (the caller is often a synchronous ref.listen).
    controller
        .invokeMethod('updateRecordingState', encoded)
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            _log.warning('$target window invoke timed out (3s)');
            return null;
          },
        )
        .catchError((Object e) {
      // If the channel is gone, the window was closed/destroyed.
      // Null-out the controller so we don't keep spamming a dead window.
      final msg = e.toString();
      if (msg.contains('CHANNEL_UNREGISTERED') ||
          msg.contains('not accessible')) {
        _log.warning('$target window channel dead — removing controller');
        if (target == 'overlay' || target == 'secondary') {
          if (_overlayController == controller) {
            _overlayController = null;
            state = state.copyWith(overlayVisible: false);
          }
        }
        if (target == 'button' || target == 'secondary') {
          if (_buttonController == controller) {
            _buttonController = null;
            state = state.copyWith(buttonVisible: false);
          }
        }
      } else {
        _log.warning('State sync to $target window failed', e);
      }
    });
  }

  // -- Command handler (secondary → main) -----------------------------------

  Future<dynamic> _handleCommand(MethodCall call) async {
    _log.debug('Received command: ${call.method}');
    switch (call.method) {
      case 'ping':
        // Heartbeat response — secondary window verifies main is alive.
        return 'pong';
      case 'toggleRecording':
        ref.read(recordingOrchestratorProvider.notifier).toggleRecording();
      case 'stopRecording':
        ref.read(recordingOrchestratorProvider.notifier).stopRecording();
      case 'cancelRecording':
        ref.read(recordingOrchestratorProvider.notifier).reset();
      case 'showMainWindow':
        await windowManager.show();
        await windowManager.focus();
        // Navigate to the requested page if specified.
        final page = call.arguments as String?;
        if (page != null && page.isNotEmpty) {
          ref.read(activePageProvider.notifier).setPage(page);
        }
      case 'quitApp':
        await _closeAll();
        // Use windowManager.destroy() for graceful shutdown — unlike exit(0),
        // this allows Flutter's normal lifecycle (dispose, DB flush, etc.).
        await windowManager.destroy();
      case 'saveButtonPosition':
        // Persist button position from drag in secondary window.
        final posData = call.arguments;
        if (posData is String) {
          try {
            final pos = jsonDecode(posData) as Map<String, dynamic>;
            final x = (pos['x'] as num?)?.toDouble() ?? -1.0;
            final y = (pos['y'] as num?)?.toDouble() ?? -1.0;
            ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWith(floatingButtonX: x, floatingButtonY: y),
                );
          } catch (e) {
            _log.warning('Failed to parse button position', e);
          }
        }
      case 'saveOverlayPosition':
        // Persist overlay position from drag in secondary window.
        final posData = call.arguments;
        if (posData is String) {
          try {
            final pos = jsonDecode(posData) as Map<String, dynamic>;
            final x = (pos['x'] as num?)?.toDouble() ?? -1.0;
            final y = (pos['y'] as num?)?.toDouble() ?? -1.0;
            ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWith(floatingOverlayX: x, floatingOverlayY: y),
                );
          } catch (e) {
            _log.warning('Failed to parse overlay position', e);
          }
        }
    }
    return null;
  }

  /// Shuts down all secondary windows with a hard timeout.
  /// Called before windowManager.destroy() to give floating windows
  /// time to hide and go inert.
  Future<void> _closeAll() async {
    final overlay = _overlayController;
    final button = _buttonController;
    _overlayController = null;
    _buttonController = null;
    state = state.copyWith(overlayVisible: false, buttonVisible: false);
    _log.info('Shutting down all secondary windows (hide + inert)');

    Future<void> shutdownWindow(WindowController? ctrl, String label) async {
      if (ctrl == null) return;
      try {
        await ctrl.invokeMethod('shutdown').timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
      } catch (_) {}
      try {
        await ctrl.hide().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      } catch (_) {}
    }

    // Shut down both windows in parallel with a hard 2s overall timeout.
    await Future.wait([
      shutdownWindow(overlay, 'overlay'),
      shutdownWindow(button, 'button'),
    ]).timeout(
      const Duration(seconds: 2),
      onTimeout: () => [null, null],
    );

    _log.info('Secondary windows shut down');
  }

  /// Public API for app shutdown — closes all secondary windows with timeout.
  Future<void> shutdownAll() => _closeAll();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final multiWindowProvider =
    NotifierProvider<MultiWindowNotifier, MultiWindowState>(
      MultiWindowNotifier.new,
    );

class _ParsedWindowCandidate {
  const _ParsedWindowCandidate({
    required this.controller,
    required this.type,
    required this.launchEpochMs,
  });

  final WindowController controller;
  final String type;
  final int launchEpochMs;

  static _ParsedWindowCandidate? tryParse(WindowController controller) {
    try {
      final raw = controller.arguments;
      if (raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type != WindowType.floatingOverlay &&
          type != WindowType.floatingButton) {
        return null;
      }
      return _ParsedWindowCandidate(
        controller: controller,
        type: type!,
        launchEpochMs: (data['launchEpochMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class _DiscoveredWindow {
  const _DiscoveredWindow({
    required this.controller,
    required this.type,
    required this.launchEpochMs,
    required this.isVisible,
  });

  final WindowController controller;
  final String type;
  final int launchEpochMs;
  final bool isVisible;
}
