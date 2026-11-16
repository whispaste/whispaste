import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';

LinuxPackageFormat detect({
  Map<String, String> env = const {},
  String executable = '/usr/lib/whispaste/whispaste',
  bool flatpakInfoPresent = false,
  bool appImageFilePresent = false,
}) => linuxPackageFormatFrom(
  env: env,
  executable: executable,
  flatpakInfoPresent: flatpakInfoPresent,
  appImageFilePresent: appImageFilePresent,
);

void main() {
  group('linuxPackageFormatFrom', () {
    test('/.flatpak-info marks a Flatpak build', () {
      expect(
        detect(
          flatpakInfoPresent: true,
          executable: '/app/whispaste/whispaste',
        ),
        LinuxPackageFormat.flatpak,
      );
    });

    test('FLATPAK_ID alone does not mark a Flatpak build', () {
      expect(
        detect(env: {'FLATPAK_ID': 'de.whispaste.app'}),
        LinuxPackageFormat.native,
      );
    });

    test('an executable under SNAP marks a Snap build', () {
      expect(
        detect(
          env: {'SNAP': '/snap/whispaste/42'},
          executable: '/snap/whispaste/42/whispaste',
        ),
        LinuxPackageFormat.snap,
      );
    });

    test('a native binary started from a Snap app is not Snap', () {
      expect(
        detect(
          env: {'SNAP': '/snap/whispaste/42'},
          executable: '/usr/lib/whispaste/whispaste',
        ),
        LinuxPackageFormat.native,
      );
    });

    test('a native binary started from a Flatpak app is not Flatpak', () {
      expect(
        detect(
          env: {'FLATPAK_ID': 'de.whispaste.app'},
          executable: '/usr/lib/whispaste/whispaste',
        ),
        LinuxPackageFormat.native,
      );
    });

    test('APPIMAGE with an existing file and APPDIR marks an AppImage', () {
      expect(
        detect(
          env: {
            'APPIMAGE': '/home/u/WhisPaste.AppImage',
            'APPDIR': '/tmp/.mount_WhisPa',
          },
          executable: '/tmp/.mount_WhisPa/usr/bin/whispaste',
          appImageFilePresent: true,
        ),
        LinuxPackageFormat.appimage,
      );
    });

    test('a trailing slash on APPDIR still matches the executable', () {
      expect(
        detect(
          env: {
            'APPIMAGE': '/home/u/WhisPaste.AppImage',
            'APPDIR': '/tmp/.mount_WhisPa/',
          },
          executable: '/tmp/.mount_WhisPa/usr/bin/whispaste',
          appImageFilePresent: true,
        ),
        LinuxPackageFormat.appimage,
      );
    });

    test('a native binary started from an AppImage app is not AppImage', () {
      expect(
        detect(
          env: {
            'APPIMAGE': '/home/u/WhisPaste.AppImage',
            'APPDIR': '/tmp/.mount_WhisPa',
          },
          executable: '/usr/lib/whispaste/whispaste',
          appImageFilePresent: true,
        ),
        LinuxPackageFormat.native,
      );
    });

    test('APPIMAGE without an existing file is not AppImage', () {
      expect(
        detect(
          env: {
            'APPIMAGE': '/home/u/WhisPaste.AppImage',
            'APPDIR': '/tmp/.mount_WhisPa',
          },
        ),
        LinuxPackageFormat.native,
      );
    });

    test('APPIMAGE without APPDIR is not AppImage', () {
      expect(
        detect(
          env: {'APPIMAGE': '/home/u/WhisPaste.AppImage'},
          appImageFilePresent: true,
        ),
        LinuxPackageFormat.native,
      );
    });

    test('no marker means a native install (.deb or manual build)', () {
      expect(detect(), LinuxPackageFormat.native);
      expect(
        detect(env: {'HOME': '/home/u', 'PATH': '/usr/bin'}),
        LinuxPackageFormat.native,
      );
    });

    test('an empty SNAP value counts as unset', () {
      expect(
        detect(env: {'SNAP': '', 'APPIMAGE': '', 'APPDIR': ''}),
        LinuxPackageFormat.native,
      );
    });

    test('Flatpak wins when several facts are set', () {
      expect(
        detect(
          env: {
            'SNAP': '/snap/whispaste/42',
            'APPIMAGE': '/x.AppImage',
            'APPDIR': '/tmp/.mount',
          },
          executable: '/snap/whispaste/42/whispaste',
          flatpakInfoPresent: true,
          appImageFilePresent: true,
        ),
        LinuxPackageFormat.flatpak,
      );
    });
  });
}
