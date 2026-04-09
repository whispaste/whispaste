/// Secondary window content for the floating recording button.
///
/// Runs in a separate Flutter engine created by `desktop_multi_window`.
/// Receives [RecordingState] from the main window via method channel and
/// sends commands (toggle, stop, cancel) back.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/theme.dart';
import '../core/recording/recording_state.dart';
import '../core/multi_window/multi_window_types.dart';
import '../core/multi_window/window_heartbeat.dart';
import '../widgets/floating_button.dart';

/// Entry point for the floating button secondary window.
///
/// Call this from `main()` when the window arguments indicate
/// [WindowType.floatingButton].
Future<void> runFloatingButtonWindow(WindowController controller) async {
  // Wrap the entire secondary engine in an error zone so unhandled exceptions
  // are logged instead of silently crashing the process.
  FlutterError.onError = (details) {
    debugPrint('FloatingButton FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
  };

  await windowManager.ensureInitialized();

  // Parse initial settings from arguments passed by the main window.
  int buttonSize = 56;
  double buttonOpacity = 1.0;
  double posX = -1.0;
  double posY = -1.0;
  int launchEpochMs = 0;
  int maxRecordDurationSeconds = 0;
  bool showRecordingProgress = false;
  try {
    final args = jsonDecode(controller.arguments) as Map<String, dynamic>;
    buttonSize = args['size'] as int? ?? 56;
    buttonOpacity = (args['opacity'] as num?)?.toDouble() ?? 1.0;
    posX = (args['posX'] as num?)?.toDouble() ?? -1.0;
    posY = (args['posY'] as num?)?.toDouble() ?? -1.0;
    launchEpochMs = (args['launchEpochMs'] as num?)?.toInt() ?? 0;
    maxRecordDurationSeconds =
        (args['maxRecordDurationSeconds'] as num?)?.toInt() ?? 0;
    showRecordingProgress = args['showRecordingProgress'] == true;
  } catch (e) {
    debugPrint('FloatingButton: failed to parse arguments: $e');
  }

  // Extra space for pulse ring.
  final windowSize = (buttonSize * 1.8).ceilToDouble();

  final options = WindowOptions(
    size: Size(windowSize, windowSize),
    center: posX < 0 || posY < 0, // center only if no persisted position
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    if (Platform.isWindows) {
      await windowManager.setHasShadow(false);
    }
    // Restore persisted position (if any), validating screen bounds.
    if (posX >= 0 && posY >= 0) {
      if (await _isPositionOnScreen(posX, posY, windowSize, windowSize)) {
        await windowManager.setPosition(Offset(posX, posY));
      } else {
        debugPrint(
          'FloatingButton: saved position ($posX, $posY) is off-screen, '
          'resetting',
        );
        await windowManager.setAlignment(Alignment.centerRight);
      }
    }
    await windowManager.show();
    await windowManager.setSkipTaskbar(true);
    await windowManager.focus();
  });

  runApp(
    _FloatingButtonApp(
      controller: controller,
      buttonSize: buttonSize,
      buttonOpacity: buttonOpacity,
      launchEpochMs: launchEpochMs,
      maxRecordDurationSeconds: maxRecordDurationSeconds,
      showRecordingProgress: showRecordingProgress,
    ),
  );
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class _FloatingButtonApp extends StatefulWidget {
  const _FloatingButtonApp({
    required this.controller,
    required this.buttonSize,
    required this.buttonOpacity,
    required this.launchEpochMs,
    required this.maxRecordDurationSeconds,
    required this.showRecordingProgress,
  });

  final WindowController controller;
  final int buttonSize;
  final double buttonOpacity;
  final int launchEpochMs;
  final int maxRecordDurationSeconds;
  final bool showRecordingProgress;

  @override
  State<_FloatingButtonApp> createState() => _FloatingButtonAppState();
}

class _FloatingButtonAppState extends State<_FloatingButtonApp>
    with WindowHeartbeat, WindowListener {
  RecordingState _recordingState = const RecordingState();
  late int _buttonSize;
  late double _buttonOpacity;
  late int _maxRecordDurationSeconds;
  late bool _showRecordingProgress;

  /// When true, this window has been shut down and ignores all method calls.
  bool _inert = false;

  /// Periodically re-asserts always-on-top so the button isn't buried by other
  /// topmost windows (e.g. game overlays, fullscreen apps).
  Timer? _topmostTimer;

  /// Debounce timer for saving window position after drag.
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _buttonSize = widget.buttonSize;
    _buttonOpacity = widget.buttonOpacity;
    _maxRecordDurationSeconds = widget.maxRecordDurationSeconds;
    _showRecordingProgress = widget.showRecordingProgress;
    // Listen for state pushes from the main window.
    try {
      widget.controller.setWindowMethodHandler(_onMethodCall);
    } catch (e) {
      debugPrint('FloatingButton: failed to register method handler: $e');
    }
    windowManager.addListener(this);
    startHeartbeat();
    _topmostTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_inert) windowManager.setAlwaysOnTop(true).catchError((_) {});
    });
  }

  @override
  void dispose() {
    _topmostTimer?.cancel();
    _saveDebounce?.cancel();
    windowManager.removeListener(this);
    stopHeartbeat();
    super.dispose();
  }

  @override
  void onWindowMoved() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _savePosition);
  }

  @override
  void onWindowBlur() {
    // Auto-dismiss the context menu when the window loses focus (e.g. user
    // clicks outside the floating button window). Without this, the menu stays
    // open because clicks outside the OS window boundary never reach Flutter.
    if (_menuOpen) {
      final nav = _navKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
      }
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (_inert) return null; // Window has been shut down — ignore everything.
    switch (call.method) {
      case 'updateRecordingState':
        if (call.arguments is String) {
          setState(() {
            _recordingState = decodeRecordingState(call.arguments as String);
          });
        }
      case 'updateButtonSettings':
        if (call.arguments is String) {
          try {
            final data =
                jsonDecode(call.arguments as String) as Map<String, dynamic>;
            setState(() {
              _buttonSize = data['size'] as int? ?? _buttonSize;
              _buttonOpacity =
                  (data['opacity'] as num?)?.toDouble() ?? _buttonOpacity;
              _maxRecordDurationSeconds =
                  (data['maxRecordDurationSeconds'] as num?)?.toInt() ??
                  _maxRecordDurationSeconds;
              _showRecordingProgress =
                  data['showRecordingProgress'] as bool? ??
                  _showRecordingProgress;
            });
            // Resize the window to match the new button size.
            final windowSize = (_buttonSize * 1.8).ceilToDouble();
            await windowManager.setSize(Size(windowSize, windowSize));
          } catch (e) {
            debugPrint('FloatingButton: failed to parse settings: $e');
          }
        }
      case 'showWindow':
        try {
          await windowManager.show();
          await windowManager.setAlwaysOnTop(true);
        } catch (e) {
          debugPrint('FloatingButton: showWindow failed: $e');
        }
      case 'assertTopmost':
        try {
          await windowManager.setAlwaysOnTop(true);
        } catch (_) {}
      case 'hideWindow':
        try {
          await windowManager.hide();
        } catch (e) {
          debugPrint('FloatingButton: hideWindow failed: $e');
        }
      case 'getWindowStatus':
        return jsonEncode({
          'type': WindowType.floatingButton,
          'visible': await windowManager.isVisible(),
          'inert': _inert,
          'launchEpochMs': widget.launchEpochMs,
        });
      case 'shutdown':
        // IMPORTANT: Do NOT call exit(0) here! All windows share the same OS
        // process — exit(0) would kill the ENTIRE application including the
        // main window. Instead, go inert: stop heartbeat, hide, ignore future
        // method calls.
        debugPrint('FloatingButton: received shutdown — going inert');
        stopHeartbeat();
        _inert = true;
        try {
          await windowManager.hide();
        } catch (_) {}
    }
    return null;
  }

  void _toggleRecording() {
    commandChannel.invokeMethod('toggleRecording');
  }

  void _hideButton() {
    windowManager.hide();
  }

  void _quitApp() {
    commandChannel.invokeMethod('quitApp');
  }

  /// GlobalKey for the navigator context — needed for `showMenu` after window
  /// resize so Flutter's overlay has room for the popup.
  final _navKey = GlobalKey<NavigatorState>();

  /// Whether the context menu is currently open (prevents re-entrant calls).
  bool _menuOpen = false;

  /// Saved button window position/size before expanding for context menu.
  Offset? _preMenuPosition;
  Size? _preMenuSize;

  /// Opens the context menu: expands the window, shows the popup, dispatches
  /// the action, and shrinks back. This entire flow is sequential to avoid
  /// the race condition where the menu renders in the unexpanded window.
  Future<void> _openContextMenu(Offset globalPosition) async {
    if (_menuOpen || _inert) return;
    _menuOpen = true;
    try {
      await _expandForMenu();
      // Small delay so the window manager completes the resize before
      // Flutter paints the overlay.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      final ctx = _navKey.currentContext;
      if (ctx == null) {
        _menuOpen = false;
        await _shrinkAfterMenu();
        return;
      }
      // Position menu at the top-left of the expanded window.
      // ignore: use_build_context_synchronously — ctx is from a GlobalKey,
      // freshly obtained and null-checked after the await; not the State's own
      // context.
      final action = await WpFloatingButton.showButtonContextMenu(
        ctx, // ignore: use_build_context_synchronously
        const Offset(8, 8),
      );
      _buttonWidget?.handleMenuAction(action);
    } finally {
      _menuOpen = false;
      await _shrinkAfterMenu();
    }
  }

  /// Reference to the current button widget for dispatching menu actions.
  WpFloatingButton? _buttonWidget;

  /// Expand the window to accommodate a popup menu above the button.
  Future<void> _expandForMenu() async {
    try {
      final pos = await windowManager.getPosition();
      final curSize = await windowManager.getSize();
      _preMenuPosition = pos;
      _preMenuSize = curSize;

      const menuW = 220.0;
      const menuH = 240.0;
      final btnWindow = curSize.width; // current square window size
      final newW = menuW.clamp(btnWindow, 400.0);
      final newH = menuH + btnWindow;

      // Move window up by menuH so the button (at bottom) stays in place.
      // Also center the wider window horizontally around the button center.
      final newY = (pos.dy - menuH).clamp(0.0, double.infinity);
      final newX = pos.dx - (newW - btnWindow) / 2;

      // Resize first, then reposition — keeps the button visually anchored
      // during the transition (size change alone just extends upward/rightward,
      // the subsequent position adjustment aligns it properly).
      await windowManager.setSize(Size(newW, newH));
      await windowManager.setPosition(Offset(newX, newY));
      await windowManager.setAlwaysOnTop(true);
    } catch (e) {
      debugPrint('FloatingButton: expandForMenu failed: $e');
    }
  }

  /// Shrink back to button size after the menu closes.
  Future<void> _shrinkAfterMenu() async {
    try {
      final origPos = _preMenuPosition;
      final origSize = _preMenuSize;
      _preMenuPosition = null;
      _preMenuSize = null;

      if (origPos != null && origSize != null) {
        // Move back to original position first, then resize — the button
        // visually returns to its position before the shrink collapses the
        // menu area, avoiding the "jump down then shrink" artefact.
        await windowManager.setPosition(origPos);
        await windowManager.setSize(origSize);
      } else {
        // Fallback: use current position + offset.
        final pos = await windowManager.getPosition();
        final btnWindow = (_buttonSize * 1.8).ceilToDouble();
        const menuH = 240.0;
        final newY = pos.dy + menuH;
        await windowManager.setPosition(Offset(pos.dx, newY));
        await windowManager.setSize(Size(btnWindow, btnWindow));
      }

      await windowManager.setAlwaysOnTop(true);
    } catch (e) {
      debugPrint('FloatingButton: shrinkAfterMenu failed: $e');
    }
  }

  /// Initiates a native window drag — the OS handles tracking until release.
  void _startDrag() {
    windowManager.startDragging();
  }

  /// Saves the current window position to settings via the main window.
  /// Skips save if the position is off-screen (e.g. mid-drag to an
  /// unreachable area).
  Future<void> _savePosition() async {
    try {
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      if (!await _isPositionOnScreen(
        pos.dx,
        pos.dy,
        size.width,
        size.height,
      )) {
        debugPrint(
          'FloatingButton: position (${pos.dx}, ${pos.dy}) is off-screen, '
          'not saving',
        );
        return;
      }
      commandChannel.invokeMethod(
        'saveButtonPosition',
        jsonEncode({'x': pos.dx, 'y': pos.dy}),
      );
    } catch (e) {
      debugPrint('FloatingButton: failed to save position: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = WpFloatingButton(
      size: _buttonSize.toDouble(),
      opacity: _buttonOpacity,
      phase: _recordingState.phase,
      elapsed: _recordingState.elapsed,
      maxRecordDurationSeconds: _maxRecordDurationSeconds,
      showRecordingProgress: _showRecordingProgress,
      onTap: _toggleRecording,
      onDragStart: _startDrag,
      onDragEnd: _savePosition,
      onContextMenuRequest: _openContextMenu,
      onNavigate: (page) {
        commandChannel.invokeMethod('showMainWindow', page);
      },
      onHide: _hideButton,
      onQuit: _quitApp,
    );
    _buttonWidget = button;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: wpDarkTheme(),
      darkTheme: wpDarkTheme(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: _ButtonScaffold(child: button),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-monitor bounds check
// ---------------------------------------------------------------------------

/// Returns `true` when a window at ([x], [y]) with the given dimensions
/// overlaps at least one connected display. Uses [screenRetriever] to
/// enumerate all monitors with their logical positions and sizes.
///
/// If the display list cannot be retrieved the check is skipped and the
/// position is assumed valid.
Future<bool> _isPositionOnScreen(
  double x,
  double y,
  double windowWidth,
  double windowHeight,
) async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) return true; // Can't validate — assume OK.

    for (final display in displays) {
      final pos = display.visiblePosition;
      final size = display.visibleSize;
      if (pos == null || size == null) continue;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      // At least part of the window is visible on this display.
      if (x < rect.right &&
          x + windowWidth > rect.left &&
          y < rect.bottom &&
          y + windowHeight > rect.top) {
        return true;
      }
    }
    return false;
  } catch (e) {
    debugPrint('FloatingButton: screen bounds check failed: $e');
    return true; // Can't validate — assume OK.
  }
}

/// Simple transparent scaffold that hosts the floating button.
class _ButtonScaffold extends StatelessWidget {
  const _ButtonScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // bottomCenter keeps the button visually pinned when the window
      // expands upward for the context menu.
      body: Align(alignment: Alignment.bottomCenter, child: child),
    );
  }
}
