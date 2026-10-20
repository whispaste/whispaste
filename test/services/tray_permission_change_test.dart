/// Tray reaction to Auto-Paste permission status transitions.
library;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/tray_service.dart';

void main() {
  group('trayPermissionChangeFor', () {
    test('ready -> missing shows the permission entry', () {
      expect(
        trayPermissionChangeFor(
          PasteCapabilityStatus.ready,
          PasteCapabilityStatus.permissionMissing,
        ),
        TrayPermissionChange.show,
      );
    });

    test('missing -> ready clears it again', () {
      expect(
        trayPermissionChangeFor(
          PasteCapabilityStatus.permissionMissing,
          PasteCapabilityStatus.ready,
        ),
        TrayPermissionChange.clear,
      );
    });

    test('an unchanged status does nothing', () {
      expect(
        trayPermissionChangeFor(
          PasteCapabilityStatus.permissionMissing,
          PasteCapabilityStatus.permissionMissing,
        ),
        TrayPermissionChange.none,
      );
    });

    test('unsupported never touches the tray', () {
      expect(
        trayPermissionChangeFor(
          PasteCapabilityStatus.ready,
          PasteCapabilityStatus.unsupported,
        ),
        TrayPermissionChange.none,
      );
    });
  });

  group('trayPermissionEntryFor (XP-5-06)', () {
    final en = lookupL10n(const Locale('en'));

    test('macOS runs the grant recovery from the tray', () {
      final entry = trayPermissionEntryFor(en, TargetPlatform.macOS);
      expect(entry.label, en.pasteNotificationPermissionBlockedTray);
      expect(entry.key, kTrayPastePermissionActionNeededKey);
    });

    test('Linux names the setup and leads to the Auto-Paste settings', () {
      final entry = trayPermissionEntryFor(en, TargetPlatform.linux);
      expect(entry.label, en.pasteNotificationLinuxUinputTray);
      expect(entry.label, isNot(contains('System Settings')));
      expect(entry.key, kTrayPasteActionNeededKey);
    });
  });
}
