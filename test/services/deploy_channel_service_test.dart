/// Tests for [detectDeployChannel] — real `Platform`/`kIsMasBuild` values
/// (no injection seam exists for either), so only the branch reachable in a
/// normal `flutter test` run is exercised: this suite runs on macOS without
/// the `WHISPASTE_MAS` dart-define, so `kIsMasBuild` is `false` at compile
/// time and the MAS branch cannot be toggled at runtime (same limitation
/// documented in `mas_ondevice_provider_gating_test.dart`).
library;

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/build_config.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

void main() {
  group('detectDeployChannel', () {
    test(
      'returns portable on a non-MAS macOS build',
      () {
        expect(kIsMasBuild, isFalse);
        expect(detectDeployChannel(), DeployChannel.portable);
      },
      skip: Platform.isMacOS ? false : 'macOS-only branch',
    );

    test('deployChannelOverride short-circuits real detection', () {
      deployChannelOverride = DeployChannel.store;
      addTearDown(() => deployChannelOverride = null);

      expect(detectDeployChannel(), DeployChannel.store);
    });
  });

  group('isExternallyManaged', () {
    test('true for store', () {
      expect(isExternallyManaged(DeployChannel.store), isTrue);
    });
    test('true for packageManaged', () {
      expect(isExternallyManaged(DeployChannel.packageManaged), isTrue);
    });
    test('false for installer', () {
      expect(isExternallyManaged(DeployChannel.installer), isFalse);
    });
    test('false for portable', () {
      expect(isExternallyManaged(DeployChannel.portable), isFalse);
    });
  });

  group('linuxChannelFromEnv — pure decision function', () {
    test('SNAP present → packageManaged', () {
      expect(
        linuxChannelFromEnv({
          'SNAP': '/snap/whispaste/x1',
        }, flatpakInfoExists: false),
        DeployChannel.packageManaged,
      );
    });

    test('SNAP_NAME present → packageManaged', () {
      expect(
        linuxChannelFromEnv({
          'SNAP_NAME': 'whispaste',
        }, flatpakInfoExists: false),
        DeployChannel.packageManaged,
      );
    });

    test('FLATPAK_ID present → packageManaged', () {
      expect(
        linuxChannelFromEnv({
          'FLATPAK_ID': 'de.whispaste.WhisPaste',
        }, flatpakInfoExists: false),
        DeployChannel.packageManaged,
      );
    });

    test('/.flatpak-info present (no FLATPAK_ID env) → packageManaged', () {
      expect(
        linuxChannelFromEnv(const {}, flatpakInfoExists: true),
        DeployChannel.packageManaged,
      );
    });

    test('APPIMAGE present → portable (not package-manager updated)', () {
      expect(
        linuxChannelFromEnv({
          'APPIMAGE': '/home/user/Downloads/WhisPaste.AppImage',
        }, flatpakInfoExists: false),
        DeployChannel.portable,
      );
    });

    test('no markers (.deb / tarball / dev run) → portable', () {
      expect(
        linuxChannelFromEnv(const {}, flatpakInfoExists: false),
        DeployChannel.portable,
      );
    });

    test('SNAP takes precedence over an incidental APPIMAGE var', () {
      expect(
        linuxChannelFromEnv({
          'SNAP': '/snap/whispaste/x1',
          'APPIMAGE': '/some/path',
        }, flatpakInfoExists: false),
        DeployChannel.packageManaged,
      );
    });
  });

  group('hasHomebrewCaskEntry — pure decision function', () {
    test('true when /opt/homebrew/Caskroom/whispaste exists', () {
      expect(
        hasHomebrewCaskEntry(
          dirExists: (path) => path == '/opt/homebrew/Caskroom/whispaste',
        ),
        isTrue,
      );
    });

    test('true when /usr/local/Caskroom/whispaste exists (Intel Homebrew)', () {
      expect(
        hasHomebrewCaskEntry(
          dirExists: (path) => path == '/usr/local/Caskroom/whispaste',
        ),
        isTrue,
      );
    });

    test('false when neither Caskroom path exists', () {
      expect(hasHomebrewCaskEntry(dirExists: (path) => false), isFalse);
    });
  });

  group('isScoopExecutablePath — pure decision function', () {
    test('true for a per-user Scoop install path', () {
      expect(
        isScoopExecutablePath(
          r'C:\Users\silvio\scoop\apps\whispaste\current\whispaste.exe',
        ),
        isTrue,
      );
    });

    test('true for a global Scoop install path', () {
      expect(
        isScoopExecutablePath(
          r'C:\ProgramData\scoop\apps\whispaste\1.2.51\whispaste.exe',
        ),
        isTrue,
      );
    });

    test('true regardless of path separator style', () {
      expect(
        isScoopExecutablePath(
          'C:/Users/silvio/scoop/apps/whispaste/current/whispaste.exe',
        ),
        isTrue,
      );
    });

    test('false for an NSIS-installed path', () {
      expect(
        isScoopExecutablePath(r'C:\Program Files\WhisPaste\whispaste.exe'),
        isFalse,
      );
    });

    test('false for an unrelated scoop app', () {
      expect(
        isScoopExecutablePath(
          r'C:\Users\silvio\scoop\apps\other-app\current\other-app.exe',
        ),
        isFalse,
      );
    });
  });
}
