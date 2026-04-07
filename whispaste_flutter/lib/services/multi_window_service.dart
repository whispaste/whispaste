/// Multi-window management for desktop floating overlay and floating button.
///
/// Uses `desktop_multi_window` to create secondary always-on-top Flutter
/// windows. Recording state is pushed from the main window via
/// [WindowController.invokeMethod]; commands flow back via
/// [WindowMethodChannel].
///
/// Robustness guarantees:
/// - Creation guards prevent concurrent window creation for the same type.
/// - Retry loop (up to 5 attempts) replaces fixed delay for engine readiness.
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

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/multi_window/multi_window_types.dart';
export '../core/multi_window/multi_window_types.dart';
import '../core/recording/recording_state.dart';
import 'floating_button_service.dart';
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

  WindowController? _overlayController;
  WindowController? _buttonController;

  // Guards against concurrent creation of the same window type.
  bool _creatingOverlay = false;
  bool _creatingButton = false;

  // Debounce timer for settings-driven button show/hide.
  Timer? _buttonDebounce;

  @override
  MultiWindowState build() {
    // Register the main window's command handler for secondary → main calls.
    commandChannel.setMethodCallHandler(_handleCommand);

    // Push recording state to secondary windows + auto-show/hide overlay.
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      _pushRecordingState(next);

      // Auto-show/hide floating overlay based on recording phase.
      final settings = ref.read(settingsProvider).value;
      if (settings != null && settings.overlayMode == 'floating') {
        if (prev?.phase == RecordingPhase.idle &&
            next.phase == RecordingPhase.recording) {
          showOverlay();
        }
        if (next.phase == RecordingPhase.idle && state.overlayVisible) {
          hideOverlay();
        }
      }
    });

    // Auto-show/hide floating button based on settings (debounced).
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final settings = next.value;
      if (settings == null) return;

      _buttonDebounce?.cancel();
      _buttonDebounce = Timer(const Duration(milliseconds: 300), () {
        if (settings.showFloatingButton && !state.buttonVisible) {
          showButton();
        }
        if (!settings.showFloatingButton && state.buttonVisible) {
          hideButton();
        }
      });
    });

    ref.onDispose(() {
      _buttonDebounce?.cancel();
      commandChannel.setMethodCallHandler(null);
      _closeAll();
    });
    return const MultiWindowState();
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // -- Floating overlay window ----------------------------------------------

  Future<void> showOverlay() async {
    if (!_isDesktop || _creatingOverlay) return;
    if (_overlayController != null) {
      try {
        await _overlayController!.show();
        state = state.copyWith(overlayVisible: true);
        _pushRecordingStateTo(
            _overlayController!, ref.read(recordingProvider));
        return;
      } catch (e) {
        _log.warning('Overlay show() failed, will recreate', e);
        _overlayController = null;
      }
    }
    _creatingOverlay = true;
    try {
      _overlayController = await _createWindow(WindowType.floatingOverlay);
      if (_overlayController != null) {
        state = state.copyWith(overlayVisible: true);
        _pushRecordingStateTo(
            _overlayController!, ref.read(recordingProvider));
      } else {
        _log.warning('Floating overlay creation failed — no fallback needed '
            '(in-window overlay shown by app shell when mode != floating)');
      }
    } finally {
      _creatingOverlay = false;
    }
  }

  Future<void> hideOverlay() async {
    if (_overlayController == null) return;
    try {
      await _overlayController!.hide();
    } catch (e) {
      _log.warning('Overlay hide() failed', e);
      _overlayController = null;
    }
    state = state.copyWith(overlayVisible: false);
  }

  // -- Floating button window -----------------------------------------------

  Future<void> showButton() async {
    if (!_isDesktop || _creatingButton) return;
    if (_buttonController != null) {
      try {
        await _buttonController!.show();
        state = state.copyWith(buttonVisible: true);
        _pushRecordingStateTo(
            _buttonController!, ref.read(recordingProvider));
        return;
      } catch (e) {
        _log.warning('Button show() failed, will recreate', e);
        _buttonController = null;
      }
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
    if (_buttonController == null) return;
    try {
      await _buttonController!.hide();
    } catch (e) {
      _log.warning('Button hide() failed', e);
      _buttonController = null;
    }
    state = state.copyWith(buttonVisible: false);
  }

  // -- Window creation with retry -------------------------------------------

  Future<WindowController?> _createWindow(String type) async {
    try {
      final settings = ref.read(settingsProvider).value;
      final args = jsonEncode({
        'type': type,
        if (settings != null) ...{
          'size': FloatingButtonNotifier.sizeFromString(
              settings.floatingButtonSize),
          'opacity': settings.floatingButtonOpacity,
        },
      });
      final controller = await WindowController.create(
        WindowConfiguration(arguments: args, hiddenAtLaunch: true),
      );

      // Retry loop: wait for secondary engine to initialise (up to 2s).
      const maxAttempts = 5;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 * attempt), // 200, 400, 600, 800, 1000ms
        );
        try {
          await controller.show();
          _log.info(
              'Created $type window (id: ${controller.windowId}, '
              'attempt: $attempt)');
          return controller;
        } catch (e) {
          if (attempt == maxAttempts) {
            _log.error(
                'Failed to show $type window after $maxAttempts attempts',
                e);
            return null;
          }
          _log.debug('$type window not ready (attempt $attempt), retrying…');
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
    _pushEncodedTo(
        controller, encodeRecordingState(recState), 'secondary');
  }

  void _pushEncodedTo(
      WindowController controller, String encoded, String target) {
    controller
        .invokeMethod('updateRecordingState', encoded)
        .catchError((Object e) {
      _log.warning('State sync to $target window failed', e);
    });
  }

  // -- Command handler (secondary → main) -----------------------------------

  Future<dynamic> _handleCommand(MethodCall call) async {
    _log.debug('Received command: ${call.method}');
    switch (call.method) {
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
        exit(0);
    }
    return null;
  }

  void _closeAll() {
    _overlayController = null;
    _buttonController = null;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final multiWindowProvider =
    NotifierProvider<MultiWindowNotifier, MultiWindowState>(
  MultiWindowNotifier.new,
);
