/// Ticket 21 — the window-activation sequence is one shared helper behind a
/// provider, so the quick-note path and the tray use the same code and both
/// are testable without a real window (no `windowManager` mocking anywhere).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/services/window_activation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the provider hands out the real sequence by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(windowActivatorProvider), same(activateWindow));
  });

  test('TrayService shows the window through the shared activator', () async {
    var activations = 0;
    final container = ProviderContainer(
      overrides: [
        windowActivatorProvider.overrideWithValue(() async => activations++),
      ],
    );
    addTearDown(container.dispose);

    final tray = container.read(trayServiceProvider.notifier);

    // Left-click on the tray icon — the entry point that used to inline the
    // macOS-aware show/focus sequence.
    tray.onTrayIconMouseDown();
    await Future<void>.delayed(Duration.zero);

    expect(activations, 1);
  });
}
