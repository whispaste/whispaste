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

  // Parse initial size from settings passed in arguments (default 56).
  int buttonSize = 56;
  double buttonOpacity = 1.0;
  try {
    final args = jsonDecode(controller.arguments) as Map<String, dynamic>;
    buttonSize = args['size'] as int? ?? 56;
    buttonOpacity = (args['opacity'] as num?)?.toDouble() ?? 1.0;
  } catch (_) {}

  // Extra space for pulse ring.
  final windowSize = (buttonSize * 1.8).ceilToDouble();

  final options = WindowOptions(
    size: Size(windowSize, windowSize),
    center: false,
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
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(_FloatingButtonApp(
    controller: controller,
    buttonSize: buttonSize,
    buttonOpacity: buttonOpacity,
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
  });

  final WindowController controller;
  final int buttonSize;
  final double buttonOpacity;

  @override
  State<_FloatingButtonApp> createState() => _FloatingButtonAppState();
}

class _FloatingButtonAppState extends State<_FloatingButtonApp> {
  RecordingState _recordingState = const RecordingState();

  @override
  void initState() {
    super.initState();
    // Listen for state pushes from the main window.
    widget.controller.setWindowMethodHandler(_onMethodCall);
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'updateRecordingState':
        final encoded = call.arguments as String;
        setState(() {
          _recordingState = decodeRecordingState(encoded);
        });
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      darkTheme: wpDarkTheme(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: WpFloatingButton(
            size: widget.buttonSize.toDouble(),
            opacity: widget.buttonOpacity,
            phase: _recordingState.phase,
            onTap: _toggleRecording,
            onLongPress: () {}, // handled by onNavigate/onHide/onQuit
            onNavigate: (page) => _showDashboard(),
            onHide: _hideButton,
            onQuit: _quitApp,
          ),
        ),
      ),
    );
  }
}
