// Flatpak/Snap autostart (#97): format choice, portal answer, refusal.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/desktop_paste/linux_package_format.dart';
import 'package:whispaste/services/linux_autostart.dart';
import 'package:whispaste/services/linux_portal_autostart.dart';

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('wp-portal'));
  tearDown(() => home.deleteSync(recursive: true));

  Map<String, String> env() => {'HOME': home.path};

  group('portal backend', () {
    test('enable sends autostart=true and remembers the grant', () async {
      final calls = <(bool, List<String>)>[];
      final b = FlatpakPortalAutostartBackend(
        env: env(),
        call:
            ({
              required autostart,
              required commandline,
              required reason,
            }) async {
              calls.add((autostart, commandline));
              return BackgroundPortalResult(response: 0, autostart: autostart);
            },
      );
      expect(await b.isEnabled(), isFalse);
      await b.enable();
      // Records compare lists by identity, so check the parts.
      expect(calls.single.$1, isTrue);
      expect(calls.single.$2, ['whispaste', '--autostart']);
      expect(await b.isEnabled(), isTrue);
      await b.disable();
      expect(calls.last.$1, isFalse);
      expect(await b.isEnabled(), isFalse);
    });

    test('a denied request throws and leaves the switch off', () async {
      final b = FlatpakPortalAutostartBackend(
        env: env(),
        call:
            ({
              required autostart,
              required commandline,
              required reason,
            }) async => const BackgroundPortalResult(response: 1),
      );
      await expectLater(b.enable(), throwsA(isA<AutostartPortalException>()));
      expect(await b.isEnabled(), isFalse);
    });

    test('a grant that contradicts the request is a refusal', () {
      expect(
        () => checkBackgroundResult(
          const BackgroundPortalResult(response: 0, autostart: false),
          wantEnabled: true,
        ),
        throwsA(isA<AutostartPortalException>()),
      );
      expect(
        () => checkBackgroundResult(
          const BackgroundPortalResult(response: 2),
          wantEnabled: true,
        ),
        throwsA(isA<AutostartPortalException>()),
      );
    });

    test('a failed disable keeps the marker', () async {
      var fail = false;
      final b = FlatpakPortalAutostartBackend(
        env: env(),
        call:
            ({
              required autostart,
              required commandline,
              required reason,
            }) async => BackgroundPortalResult(response: fail ? 2 : 0),
      );
      await b.enable();
      fail = true;
      await expectLater(b.disable(), throwsA(isA<AutostartPortalException>()));
      expect(await b.isEnabled(), isTrue);
    });
  });

  group('format choice', () {
    test('Flatpak uses the portal, the others the entry file', () {
      expect(
        linuxAutostartBackendFor(
          format: LinuxPackageFormat.flatpak,
          env: env(),
        ),
        isA<FlatpakPortalAutostartBackend>(),
      );
      for (final f in [
        LinuxPackageFormat.native,
        LinuxPackageFormat.appimage,
        LinuxPackageFormat.snap,
      ]) {
        expect(
          linuxAutostartBackendFor(format: f, env: env()),
          isA<LinuxAutostartBackend>(),
        );
      }
    });

    test('Snap writes the stable launcher, not the revision path', () async {
      await LinuxAutostartBackend(
        env: env(),
        resolvedExecutable: '/snap/whispaste/42/bin/whispaste',
        format: LinuxPackageFormat.snap,
        // A local build names the entry after the dev application ID.
        localBuild: false,
      ).enable();
      final text = File(
        p.join(home.path, '.config', 'autostart', 'de.whispaste.app.desktop'),
      ).readAsStringSync();
      expect(text, contains('Exec="/snap/bin/whispaste" --autostart\n'));
      expect(text, isNot(contains('/snap/whispaste/42')));
    });
  });
}
