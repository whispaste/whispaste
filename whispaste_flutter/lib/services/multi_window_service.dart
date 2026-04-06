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

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import '../features/recording/recording_state.dart';
import 'recording_orchestrator.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Identifies the type of secondary window in its launch arguments.
abstract final class WindowType {
  static const String main = 'main';
  static const String floatingButton = 'floating_button';
  static const String floatingOverlay = 'floating_overlay';
}

// ---------------------------------------------------------------------------
// Encoding helpers
// ---------------------------------------------------------------------------

/// Serialises [RecordingState] to a JSON string for cross-window transfer.
String encodeRecordingState(RecordingState state) => jsonEncode({
      'phase': state.phase.index,
      'elapsedMs': state.elapsed.inMilliseconds,
      'audioLevel': state.audioLevel,
      'transcript': state.transcript,
      'errorMessage': state.errorMessage,
    });

/// Deserialises a JSON string back into a [RecordingState].
RecordingState decodeRecordingState(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  return RecordingState(
    phase: RecordingPhase.values[map['phase'] as int],
    elapsed: Duration(milliseconds: map['elapsedMs'] as int),
    audioLevel: (map['audioLevel'] as num).toDouble(),
    transcript: map['transcript'] as String?,
    errorMessage: map['errorMessage'] as String?,
  );
}

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
    // Push recording state changes to all open secondary windows.
    ref.listen<RecordingState>(recordingProvider, (_, next) {
      _pushRecordingState(next);
    });

    // Auto-show/hide floating overlay when recording starts/stops.
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      final settings = ref.read(settingsProvider).value;
      if (settings == null) return;
      if (settings.overlayMode != 'floating') return;

      if (prev?.phase == RecordingPhase.idle &&
          next.phase == RecordingPhase.recording) {
        showOverlay();
      }
      if (next.phase == RecordingPhase.idle && state.overlayVisible) {
        hideOverlay();
      }
    });

    ref.onDispose(_closeAll);
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
    if (_overlayController == null) {
      _overlayController = await _createWindow(WindowType.floatingOverlay);
    }
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
    if (_buttonController == null) {
      _buttonController = await _createWindow(WindowType.floatingButton);
    }
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
      final args = jsonEncode({'type': type});
      final controller = await WindowController.create(
        WindowConfiguration(arguments: args, hiddenAtLaunch: true),
      );

      // Set up command handler for this window.
      controller.setWindowMethodHandler(_handleCommand);

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
    try {
      controller.invokeMethod('updateRecordingState', encoded);
    } catch (_) {
      // Window may have been closed; ignore.
    }
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
        // Handled by the app — import window_manager there.
        return 'not_implemented';
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
