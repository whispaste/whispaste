// UIA-SHL-02: closing the window without a working tray icon must not hide
// the app out of sight; the decision reports the missing tray.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart';
import 'package:whispaste/core/config/settings_provider.dart';

void main() {
  test('closing to tray is refused while the tray is not initialized '
      '(UIA-SHL-02)', () {
    final settings = AppSettings.defaults.copyWith(
      closeToTray: true,
      onboardingCompleted: true,
    );
    expect(shouldHideToTrayOnClose(settings), isTrue);
    expect(shouldHideToTrayOnClose(settings, trayReady: false), isFalse);
  });

  test('an initialized tray icon without a tray host does not count as a '
      'way back (Linux without a status-notifier watcher)', () {
    expect(trayUsableForClose(initialized: true, hostMissing: false), isTrue);
    expect(trayUsableForClose(initialized: true, hostMissing: true), isFalse);
    expect(trayUsableForClose(initialized: false, hostMissing: false), isFalse);
  });
}
