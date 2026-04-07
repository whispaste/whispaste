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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/settings_enums.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/multi_window/multi_window_types.dart';
export '../core/multi_window/multi_window_types.dart';
import '../core/recording/recording_state.dart';
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

  // Debounce timer for settings-driven button show/hide.
  Timer? _buttonDebounce;
  // Timer for auto-dismissing the floating overlay after completion.
  Timer? _overlayDismissTimer;

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
          showOverlay();
        }
        // Auto-hide overlay a few seconds after completion so the done pill
        // is readable. The pill holds for 3s, then we hide the window.
        if (next.phase == RecordingPhase.idle && state.overlayVisible) {
          _overlayDismissTimer?.cancel();
          _overlayDismissTimer = Timer(const Duration(seconds: 4), () {
            if (state.overlayVisible) hideOverlay();
          });
        }
      }
    });

    // React to settings changes: show/hide button + overlay, push updates.
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final settings = next.value;
      if (settings == null) return;

      _buttonDebounce?.cancel();
      _buttonDebounce = Timer(const Duration(milliseconds: 300), () {
        // ── Floating button show/hide ──
        if (settings.showFloatingButton && !state.buttonVisible) {
          showButton();
        }
        if (!settings.showFloatingButton && state.buttonVisible) {
          hideButton();
        }
        if (state.buttonVisible && _buttonController != null) {
          _pushButtonSettings(settings);
        }

        // ── Floating overlay mode changes ──
        final prevMode = prev?.value?.overlayModeType;
        if (prevMode != settings.overlayModeType) {
          if (settings.overlayModeType == OverlayMode.floating) {
            // Pre-create the overlay window so it's ready instantly.
            _ensureOverlayCreated();
          } else {
            // Switched away from floating — destroy the overlay window.
            destroyOverlay();
          }
        }
      });
    });

    ref.onDispose(() {
      _buttonDebounce?.cancel();
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

    // If no windows survived, apply initial settings to show them.
    // Scheduled as microtask because `state` is not set until build() returns.
    if (!initialState.buttonVisible && !initialState.overlayVisible) {
      Future.microtask(_applyInitialSettings);
    } else {
      _log.info('Reconnected to surviving secondary windows '
          '(button=${initialState.buttonVisible}, '
          'overlay=${initialState.overlayVisible})');
    }

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

  /// Pushes appearance settings (size, opacity, locked) to the floating button
  /// window via method channel so changes take effect in real-time.
  void _pushButtonSettings(AppSettings settings) {
    final ctrl = _buttonController;
    if (ctrl == null) return;
    final payload = jsonEncode({
      'size': floatingButtonSizeFromString(settings.floatingButtonSize),
      'opacity': settings.floatingButtonOpacity,
      'locked': settings.floatingButtonLocked,
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
    if (!_isDesktop || _creatingOverlay || _overlayController != null) return;
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
  Future<void> showOverlay() async {
    if (!_isDesktop || _creatingOverlay) return;
    if (_overlayController != null) {
      // Window exists — show and push latest state.
      try {
        await _overlayController!.show();
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
      } finally {
        _creatingOverlay = false;
      }
    }
    if (_overlayController != null) {
      state = state.copyWith(overlayVisible: true);
      _pushRecordingStateTo(_overlayController!, ref.read(recordingProvider));
    } else {
      _log.warning('Floating overlay creation failed — '
          'in-window overlay will be used as fallback');
    }
  }

  /// Hides the overlay window but keeps the controller alive for reuse.
  Future<void> hideOverlay() async {
    final ctrl = _overlayController;
    if (ctrl == null) return;
    state = state.copyWith(overlayVisible: false);
    try {
      await ctrl.hide();
    } catch (e) {
      _log.warning('Overlay hide() failed (may already be closed)', e);
      _overlayController = null;
    }
  }

  /// Destroys the overlay window completely (when mode changes away from
  /// floating mode). Unlike [hideOverlay], this releases the controller.
  Future<void> destroyOverlay() async {
    final ctrl = _overlayController;
    if (ctrl == null) return;
    _overlayController = null;
    state = state.copyWith(overlayVisible: false);
    try {
      await ctrl.hide();
    } catch (e) {
      _log.warning('Overlay destroy: hide() failed', e);
    }
  }

  // -- Floating button window -----------------------------------------------

  Future<void> showButton() async {
    if (!_isDesktop || _creatingButton) return;
    if (_buttonController != null) {
      // Window already created — just push latest state.
      _pushRecordingStateTo(
          _buttonController!, ref.read(recordingProvider));
      state = state.copyWith(buttonVisible: true);
      return;
    }
    _creatingButton = true;
    try {
      _buttonController = await _createWindow(WindowType.floatingButton);
      if (_buttonController != null) {
        state = state.copyWith(buttonVisible: true);
        _pushRecordingStateTo(
            _buttonController!, ref.read(recordingProvider));
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
    try {
      await ctrl.hide();
    } catch (e) {
      _log.warning('Button hide() failed (may already be closed)', e);
    }
  }

  // -- Window creation with retry -------------------------------------------

  Future<WindowController?> _createWindow(String type) async {
    try {
      final settings = ref.read(settingsProvider).value;
      final args = jsonEncode({
        'type': type,
        if (settings != null) ...{
          'size': floatingButtonSizeFromString(
              settings.floatingButtonSize),
          'opacity': settings.floatingButtonOpacity,
          'locked': settings.floatingButtonLocked,
          // Persisted position (-1 = not set → let OS choose).
          'posX': settings.floatingButtonX,
          'posY': settings.floatingButtonY,
        },
      });
      final controller = await WindowController.create(
        WindowConfiguration(arguments: args, hiddenAtLaunch: true),
      );

      // Wait for the secondary Flutter engine to initialise.
      // The engine runs in a separate process and takes time to start. We
      // verify readiness by probing the method channel. The button screen
      // shows itself via windowManager.show(); the overlay stays hidden
      // until explicitly shown via controller.show() from showOverlay().
      const maxAttempts = 6;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 * attempt), // 200, 400, …, 1200ms (total ~5s)
        );
        try {
          await controller.invokeMethod(
            'updateRecordingState',
            encodeRecordingState(const RecordingState()),
          );
          _log.info(
              'Created $type window (id: ${controller.windowId}, '
              'ready on attempt: $attempt)');
          return controller;
        } catch (e) {
          if (attempt == maxAttempts) {
            _log.error(
                'Engine for $type window not ready after $maxAttempts attempts',
                e);
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

  void _pushRecordingState(RecordingState recState) {
    final encoded = encodeRecordingState(recState);
    if (_overlayController != null && state.overlayVisible) {
      _pushEncodedTo(_overlayController!, encoded, 'overlay');
    }
    if (_buttonController != null && state.buttonVisible) {
      _pushEncodedTo(_buttonController!, encoded, 'button');
    }
  }

  void _pushRecordingStateTo(
      WindowController controller, RecordingState recState) {
    final target = controller == _overlayController
        ? 'overlay'
        : controller == _buttonController
            ? 'button'
            : 'secondary';
    _pushEncodedTo(controller, encodeRecordingState(recState), target);
  }

  void _pushEncodedTo(
      WindowController controller, String encoded, String target) {
    controller
        .invokeMethod('updateRecordingState', encoded)
        .catchError((Object e) {
      // If the channel is gone, the window was closed/destroyed.
      // Null-out the controller so we don't keep spamming a dead window.
      final msg = e.toString();
      if (msg.contains('CHANNEL_UNREGISTERED') ||
          msg.contains('not accessible')) {
        _log.warning('$target window channel dead — removing controller');
        if (target == 'overlay' || target == 'secondary') {
          if (_overlayController == controller) _overlayController = null;
        }
        if (target == 'button' || target == 'secondary') {
          if (_buttonController == controller) _buttonController = null;
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
      case 'quitApp':
        _closeAll();
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
            ref.read(settingsProvider.notifier).updateSettings(
              (s) => s.copyWith(floatingButtonX: x, floatingButtonY: y),
            );
          } catch (e) {
            _log.warning('Failed to parse button position', e);
          }
        }
    }
    return null;
  }

  void _closeAll() {
    final overlay = _overlayController;
    final button = _buttonController;
    _overlayController = null;
    _buttonController = null;
    state = state.copyWith(overlayVisible: false, buttonVisible: false);
    overlay?.hide().catchError((_) {});
    button?.hide().catchError((_) {});
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final multiWindowProvider =
    NotifierProvider<MultiWindowNotifier, MultiWindowState>(
  MultiWindowNotifier.new,
);
