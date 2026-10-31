// Parity guard for the attention hint on Linux (PAR-046).
//
// Linux under X11 sets the urgency hint on the main window, as Windows flashes
// the taskbar and macOS bounces the Dock. Wayland has no protocol for normal
// clients, so the runner answers false there. The Dart branch, the runner and
// its CMake/app wiring must all exist; a missing link would silently drop the
// hint on Linux.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = File(
    'lib/services/system_attention_service.dart',
  ).readAsStringSync();
  final host = File('linux/runner/attention_host.cc').readAsStringSync();
  final app = File('linux/runner/my_application.cc').readAsStringSync();
  final cmake = File('linux/runner/CMakeLists.txt').readAsStringSync();

  test('Dart asks the runner on Linux and keeps the Wayland reason', () {
    expect(service, contains('Platform.isLinux'));
    expect(service, contains("'com.whispaste.attention'"));
    expect(service, contains('Wayland is deliberately left out'));
  });

  test('the runner serves the same channel and methods as Windows', () {
    expect(host, contains('"com.whispaste.attention"'));
    expect(host, contains('"requestUserAttention"'));
    expect(host, contains('"cancelUserAttentionRequest"'));
  });

  test('the runner sets the hint on X11 only and clears it on focus', () {
    expect(host, contains('GDK_IS_X11_DISPLAY'));
    expect(host, contains('gtk_window_set_urgency_hint(window_, TRUE)'));
    expect(host, contains('"focus-in-event"'));
  });

  test('the host is built and owned by the application', () {
    expect(cmake, contains('"attention_host.cc"'));
    expect(app, contains('#include "attention_host.h"'));
    expect(app, contains('new AttentionHost(main_messenger, window)'));
    expect(app, contains('delete self->attention_host'));
  });
}
