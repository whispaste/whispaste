/// WP-43a A-N9 / C-N-3: a stored automation port outside the user-selectable
/// range (1024 to 65535) is not loaded, whatever the settings file says.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';

void main() {
  AutomationApiSettings withPort(String port) =>
      AutomationApiSettings.fromMap({'automation_api_custom_port': port});

  test('a privileged port is not loaded', () {
    expect(withPort('80').customPort, isNull);
  });

  test('a port above 65535 is not loaded', () {
    expect(withPort('70000').customPort, isNull);
  });

  test('a port inside the range is loaded', () {
    expect(withPort('8800').customPort, 8800);
    expect(withPort('1024').customPort, 1024);
    expect(withPort('65535').customPort, 65535);
  });
}
