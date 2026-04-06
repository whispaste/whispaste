/// Multi-window management for desktop floating overlay and floating button.
///
/// Uses `desktop_multi_window` to create secondary always-on-top Flutter
/// windows. Recording state is pushed from the main window via
/// [WindowController.invokeMethod]; commands flow back via
/// [WindowMethodChannel].
library;

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

    // Auto-show floating button on app start if enabled.
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final settings = next.value;
      if (settings != null &&
          settings.showFloatingButton &&
          !state.buttonVisible) {
        showButton();
      }
      if (settings != null &&
          !settings.showFloatingButton &&
          state.buttonVisible) {
        hideButton();
      }
    });

    ref.onDispose(() {
      commandChannel.setMethodCallHandler(null);
      _closeAll();
    });
    return const MultiWindowState();
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // -- Floating overlay window ----------------------------------------------

  Future<void> showOverlay() async {
    if (!_isDesktop) return;
    if (_overlayController != null) {
      try {
        await _overlayController!.show();
      } catch (_) {
        _overlayController = null;
      }
    }
    _overlayController ??= await _createWindow(WindowType.floatingOverlay);
    if (_overlayController != null) {
      state = state.copyWith(overlayVisible: true);
      _pushRecordingStateTo(
          _overlayController!, ref.read(recordingProvider));
    }
  }

  Future<void> hideOverlay() async {
    if (_overlayController == null) return;
    try {
      await _overlayController!.hide();
    } catch (_) {
      _overlayController = null;
    }
    state = state.copyWith(overlayVisible: false);
  }

  // -- Floating button window -----------------------------------------------

  Future<void> showButton() async {
    if (!_isDesktop) return;
    if (_buttonController != null) {
      try {
        await _buttonController!.show();
      } catch (_) {
        _buttonController = null;
      }
    }
    _buttonController ??= await _createWindow(WindowType.floatingButton);
    if (_buttonController != null) {
      state = state.copyWith(buttonVisible: true);
      _pushRecordingStateTo(
          _buttonController!, ref.read(recordingProvider));
    }
  }

  Future<void> hideButton() async {
    if (_buttonController == null) return;
    try {
      await _buttonController!.hide();
    } catch (_) {
      _buttonController = null;
    }
    state = state.copyWith(buttonVisible: false);
  }

  // -- Window creation ------------------------------------------------------

  Future<WindowController?> _createWindow(String type) async {
    try {
      // Include settings in the creation arguments for the secondary window.
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

      // NOTE: We do NOT call controller.setWindowMethodHandler() here.
      // The handler is set by the secondary window's own Flutter engine
      // in its initState(). Commands from secondary → main use
      // WindowMethodChannel instead.

      // Give the secondary engine time to initialise.
      await Future.delayed(const Duration(milliseconds: 400));
      await controller.show();
      _log.info('Created $type window (id: ${controller.windowId})');
      return controller;
    } catch (e, st) {
      _log.error('Failed to create $type window', e, st);
      return null;
    }
  }

  // -- State sync (main → secondary) ---------------------------------------

  void _pushRecordingState(RecordingState recState) {
    final encoded = encodeRecordingState(recState);
    if (_overlayController != null && state.overlayVisible) {
      _pushEncodedTo(_overlayController!, encoded);
    }
    if (_buttonController != null && state.buttonVisible) {
      _pushEncodedTo(_buttonController!, encoded);
    }
  }

  void _pushRecordingStateTo(
      WindowController controller, RecordingState recState) {
    _pushEncodedTo(controller, encodeRecordingState(recState));
  }

  void _pushEncodedTo(WindowController controller, String encoded) {
    controller.invokeMethod('updateRecordingState', encoded).catchError((_) {
      // Window may have been closed; ignore channel errors.
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
