import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Initialize window_manager for custom chrome
  // TODO: Initialize Go FFI bridge
  // TODO: Initialize system tray

  runApp(
    const ProviderScope(
      child: WhisPasteApp(),
    ),
  );
}
