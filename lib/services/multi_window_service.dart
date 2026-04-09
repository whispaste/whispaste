/// Multi-window management for the desktop floating button.
///
/// Uses `desktop_multi_window` to create a secondary always-on-top Flutter
/// window for the floating recording button. Recording state is pushed from
/// the main window via [WindowController.invokeMethod]; commands flow back
/// via [WindowMethodChannel].
///
/// NOTE: The floating OVERLAY window was removed in favor of an in-app
/// overlay (RecordingOverlay widget). The secondary overlay engine caused
/// ANGLE/DirectX GPU crashes (Flutter #152299, plugin #352). Only the
/// floating button still uses a secondary engine — it will be replaced
/// by a native Win32 overlay in a future phase.
///
/// Robustness guarantees:
/// - Creation guard prevents concurrent window creation.
/// - Readiness probe (up to 6 attempts) verifies engine before use.
/// - Logged errors on channel failures (no silent catches).
/// - Shutdown sends 'shutdown' command → secondary hides + goes inert.
///   We NEVER call exit(0) from secondary windows because all engines
///   share the same OS process — exit(0) would kill the whole app.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

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
    this.buttonVisible = false,
  });

  final bool buttonVisible;

  MultiWindowState copyWith({bool? buttonVisible}) =>
      MultiWindowState(
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
  static WindowController? _buttonController;

  // Guard against concurrent creation of the button window.
  static bool _creatingButton = false;
  static bool _reconcilingWindows = false;

  Timer? _buttonDebounce;

  // ── State push throttling ──
  // During recording, audioLevel updates fire ~10/sec. Each triggers a
  // method channel call to the button window. On Windows, these calls go
  // through SendMessage (synchronous) — if the secondary engine is slow,
  // the main Win32 message loop blocks, causing a UI freeze.
  // We throttle audio-level-only pushes to at most once per 150ms (~7fps)
  // while still pushing every phase transition immediately.
  DateTime _lastStatePushTime = DateTime.fromMillisecondsSinceEpoch(0);
  RecordingPhase? _lastPushedPhase;
  static const _minStatePushInterval = Duration(milliseconds: 150);
  Timer? _coalescedPushTimer;

  @override
  MultiWindowState build() {
    // Register the main window's command handler for secondary -> main calls.
    commandChannel.setMethodCallHandler(_handleCommand);

    // Push recording state to the floating button window.
    ref.listen<RecordingState>(recordingProvider, (prev, next) {
      _pushRecordingState(next);
    });

    // React to settings changes: show/hide floating button.
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final settings = next.value;
      if (settings == null) return;

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
    });

    ref.onDispose(() {
      _buttonDebounce?.cancel();
      _coalescedPushTimer?.cancel();
      commandChannel.setMethodCallHandler(null);
    });

    // Recover state from surviving secondary windows (hot reload scenario).
    final initialState = MultiWindowState(
      buttonVisible: _buttonController != null,
    );

    // Always reconcile with the actual OS windows after build returns. Static
    // refs survive hot reload, but they are not enough to dedupe orphaned
    // secondary engines or recover hidden windows reliably.
    Future.microtask(() async {
      try {
        await _restoreExistingWindows().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _log.warning('Window restoration timed out (10s)');
            _reconcilingWindows = false;
          },
        );
      } catch (e) {
        _log.warning('Window restoration failed: $e');
        _reconcilingWindows = false;
      }
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
    if (!settings.onboardingCompleted) return;

    if (settings.showFloatingButton && !state.buttonVisible) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!state.buttonVisible) showButton();
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
        _pushRecordingStateTo(_buttonController!, ref.read(recordingProvider));
        if (!state.buttonVisible) {
          await _showSecondaryWindow(_buttonController!, target: 'button');
          state = state.copyWith(buttonVisible: true);
        }
      }
    } else if (_buttonController != null) {
      await hideButton();
    }
  }

  Future<void> _reconcileExistingWindows() async {
    if (!_isDesktop || _reconcilingWindows) return;
    _reconcilingWindows = true;
    try {
      final controllers = await WindowController.getAll();
      final buttonCandidates = <_DiscoveredWindow>[];
      final stale = <_ParsedWindowCandidate>[];

      for (final controller in controllers) {
        final parsed = _ParsedWindowCandidate.tryParse(controller);
        if (parsed == null) continue;
        // Retire any surviving overlay windows from previous sessions.
        if (parsed.type == WindowType.floatingOverlay) {
          _log.info('Retiring orphaned overlay window ${controller.windowId}');
          await _retireWindow(
            controller,
            type: parsed.type,
            reason: 'overlay windows removed — using in-app overlay',
          );
          continue;
        }
        final probe = await _probeWindow(parsed);
        if (probe == null) {
          stale.add(parsed);
          continue;
        }
        buttonCandidates.add(probe);
      }

      final buttonWinner = _selectPreferredWindow(buttonCandidates);

      for (final candidate in buttonCandidates) {
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

      _buttonController = buttonWinner?.controller;
      state = state.copyWith(
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
      ).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _log.warning(
            'Probe timed out for ${candidate.type} '
            'window ${candidate.controller.windowId}',
          );
          return null;
        },
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
      await controller.invokeMethod('shutdown').timeout(
        const Duration(seconds: 1),
        onTimeout: () => null,
      );
    } catch (_) {}
    try {
      await controller.invokeMethod('hideWindow').timeout(
        const Duration(seconds: 1),
        onTimeout: () => null,
      );
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
    try {
      await controller.hide();
    } catch (e) {
      _log.warning('Native hide() failed for $target window: $e');
    }
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
    final isPhaseChange = recState.phase != _lastPushedPhase;

    // Phase transitions are always pushed immediately.
    // Audio-level-only updates during recording are throttled to prevent
    // flooding the native message channel (~10/sec → ~7/sec max).
    if (!isPhaseChange && recState.phase == RecordingPhase.recording) {
      final now = DateTime.now();
      if (now.difference(_lastStatePushTime) < _minStatePushInterval) {
        _coalescedPushTimer ??= Timer(_minStatePushInterval, () {
          _coalescedPushTimer = null;
          if (_buttonController != null) {
            _doPush(ref.read(recordingProvider));
          }
        });
        return;
      }
    }

    _coalescedPushTimer?.cancel();
    _coalescedPushTimer = null;
    _doPush(recState);
  }

  void _doPush(RecordingState recState) {
    _lastStatePushTime = DateTime.now();
    _lastPushedPhase = recState.phase;
    if (_buttonController != null) {
      final encoded = _encodeWithSettings(recState);
      _pushEncodedTo(_buttonController!, encoded, 'button');
    }
  }

  void _pushRecordingStateTo(
    WindowController controller,
    RecordingState recState,
  ) {
    final target = controller == _buttonController ? 'button' : 'secondary';
    _pushEncodedTo(controller, _encodeWithSettings(recState), target);
  }

  void _pushEncodedTo(
    WindowController controller,
    String encoded,
    String target,
  ) {
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
      final msg = e.toString();
      if (e is PlatformException ||
          msg.contains('CHANNEL_UNREGISTERED') ||
          msg.contains('not accessible')) {
        _log.warning('$target window channel dead — removing controller');
        if (_buttonController == controller) {
          _buttonController = null;
          state = state.copyWith(buttonVisible: false);
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
    }
    return null;
  }

  /// Shuts down the floating button window with a hard timeout.
  /// Called before windowManager.destroy() to give the button window
  /// time to hide and go inert.
  Future<void> _closeAll() async {
    final button = _buttonController;
    _buttonController = null;
    state = state.copyWith(buttonVisible: false);
    _log.info('Shutting down floating button window');

    if (button != null) {
      try {
        await button.invokeMethod('shutdown').timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
      } catch (_) {}
      try {
        await button.hide().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      } catch (_) {}
    }

    _log.info('Floating button shut down');
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
