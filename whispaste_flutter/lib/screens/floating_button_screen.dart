/// Secondary window content for the floating recording button.
///
/// Runs in a separate Flutter engine created by `desktop_multi_window`.
/// Receives [RecordingState] from the main window via method channel and
/// sends commands (toggle, stop, cancel) back.
library;

import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/theme.dart';
import '../core/recording/recording_state.dart';
import '../core/multi_window/multi_window_types.dart';
import '../widgets/floating_button.dart';

/// Entry point for the floating button secondary window.
///
/// Call this from `main()` when the window arguments indicate
/// [WindowType.floatingButton].
Future<void> runFloatingButtonWindow(WindowController controller) async {
  await windowManager.ensureInitialized();

  // Parse initial settings from arguments passed by the main window.
  int buttonSize = 56;
  double buttonOpacity = 1.0;
  bool buttonLocked = false;
  double posX = -1.0;
  double posY = -1.0;
  try {
    final args = jsonDecode(controller.arguments) as Map<String, dynamic>;
    buttonSize = args['size'] as int? ?? 56;
    buttonOpacity = (args['opacity'] as num?)?.toDouble() ?? 1.0;
    buttonLocked = args['locked'] as bool? ?? false;
    posX = (args['posX'] as num?)?.toDouble() ?? -1.0;
    posY = (args['posY'] as num?)?.toDouble() ?? -1.0;
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
    // Restore persisted position (if any).
    if (posX >= 0 && posY >= 0) {
      await windowManager.setPosition(Offset(posX, posY));
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(_FloatingButtonApp(
    controller: controller,
    buttonSize: buttonSize,
    buttonOpacity: buttonOpacity,
    buttonLocked: buttonLocked,
  ));
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class _FloatingButtonApp extends StatefulWidget {
  const _FloatingButtonApp({
    required this.controller,
    required this.buttonSize,
    required this.buttonOpacity,
    required this.buttonLocked,
  });

  final WindowController controller;
  final int buttonSize;
  final double buttonOpacity;
  final bool buttonLocked;

  @override
  State<_FloatingButtonApp> createState() => _FloatingButtonAppState();
}

class _FloatingButtonAppState extends State<_FloatingButtonApp> {
  RecordingState _recordingState = const RecordingState();
  late int _buttonSize;
  late double _buttonOpacity;
  late bool _buttonLocked;

  @override
  void initState() {
    super.initState();
    _buttonSize = widget.buttonSize;
    _buttonOpacity = widget.buttonOpacity;
    _buttonLocked = widget.buttonLocked;
    // Listen for state pushes from the main window.
    try {
      widget.controller.setWindowMethodHandler(_onMethodCall);
    } catch (e) {
      debugPrint('FloatingButton: failed to register method handler: $e');
    }
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
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
              _buttonLocked = data['locked'] as bool? ?? _buttonLocked;
            });
            // Resize the window to match the new button size.
            final windowSize = (_buttonSize * 1.8).ceilToDouble();
            await windowManager
                .setSize(Size(windowSize, windowSize));
          } catch (e) {
            debugPrint('FloatingButton: failed to parse settings: $e');
          }
        }
    }
    return null;
  }

  void _toggleRecording() {
    commandChannel.invokeMethod('toggleRecording');
  }

  void _showDashboard() {
    commandChannel.invokeMethod('showMainWindow');
  }

  void _hideButton() {
    windowManager.hide();
  }

  void _quitApp() {
    commandChannel.invokeMethod('quitApp');
  }

  /// Initiates a native window drag — the OS handles tracking until release.
  void _startDrag() {
    if (_buttonLocked) return;
    windowManager.startDragging();
  }

  /// Saves the current window position to settings via the main window.
  Future<void> _savePosition() async {
    try {
      final pos = await windowManager.getPosition();
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      darkTheme: wpDarkTheme(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: _DraggableButtonScaffold(
        locked: _buttonLocked,
        onDragStart: _startDrag,
        onDragEnd: _savePosition,
        child: WpFloatingButton(
          size: _buttonSize.toDouble(),
          opacity: _buttonOpacity,
          phase: _recordingState.phase,
          onTap: _toggleRecording,
          onLongPress: _showDashboard,
          enableContextMenu: false,
          locked: _buttonLocked,
          onNavigate: (page) => _showDashboard(),
          onHide: _hideButton,
          onQuit: _quitApp,
        ),
      ),
    );
  }
}

/// Scaffold that wraps the floating button with drag-to-move support.
///
/// Uses [GestureDetector.onPanStart] to initiate native window dragging
/// via [windowManager.startDragging()]. Position is saved on drag end.
class _DraggableButtonScaffold extends StatefulWidget {
  const _DraggableButtonScaffold({
    required this.locked,
    required this.onDragStart,
    required this.onDragEnd,
    required this.child,
  });

  final bool locked;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  State<_DraggableButtonScaffold> createState() =>
      _DraggableButtonScaffoldState();
}

class _DraggableButtonScaffoldState extends State<_DraggableButtonScaffold>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() {
    // Fires when the OS finishes the native drag.
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: widget.locked ? null : (_) => widget.onDragStart(),
        child: Center(child: widget.child),
      ),
    );
  }
}
