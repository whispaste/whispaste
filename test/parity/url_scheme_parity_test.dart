// Parity guard for the whispaste:// URL scheme (newsletter return path).
//
// The confirmation page links back into the app; that only works where the
// channel registered the scheme and hands the URL to Dart. Every desktop
// channel is checked against the one source, `kAppUrlScheme`, so a channel
// that drops its registration fails here instead of in a user's browser.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_link.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const scheme = kAppUrlScheme;
  const mime = 'x-scheme-handler/$scheme;';
  const classesKey = r'Software\Classes\' + scheme;

  group('macOS (direct and Mac App Store)', () {
    test('Info.plist declares the scheme', () {
      final plist = _read('macos/Runner/Info.plist');
      expect(plist, contains('<key>CFBundleURLSchemes</key>'));
      expect(plist, contains('<string>$scheme</string>'));
    });

    test('the delegate forwards opened URLs, cold start included', () {
      final delegate = _read('macos/Runner/AppDelegate.swift');
      expect(delegate, contains('open urls: [URL]'));
      expect(delegate, contains('"openUrls"'));
      expect(delegate, contains('"takeOpenUrls"'));
    });
  });

  group('Windows', () {
    test('MSIX activates the protocol', () {
      expect(_read('pubspec.yaml'), contains('protocol_activation: $scheme'));
    });

    test('NSIS (and winget) writes the key and the uninstaller drops it', () {
      final nsi = _read('installer/whispaste.nsi');
      expect(nsi, contains('WriteRegStr HKCU "$classesKey" "URL Protocol"'));
      expect(
        nsi,
        contains(
          r'shell\open\command" "" '
          "'\"\$INSTDIR",
        ),
      );
      expect(nsi, contains('DeleteRegKey HKCU "$classesKey"'));
    });

    test('Scoop registers on install and removes on uninstall', () {
      final manifest = _read('packaging/scoop/whispaste.json');
      final escaped = classesKey.replaceAll(r'\', r'\\');
      final install = RegExp(r'"post_install"[^\]]*').stringMatch(manifest);
      final uninstall = RegExp(r'"uninstaller"[^}]*').stringMatch(manifest);
      expect(install, contains(escaped));
      expect(install, contains('URL Protocol'));
      expect(uninstall, contains(escaped));
    });

    test('the runner heals the key outside MSIX', () {
      final runner = _read('windows/runner/url_scheme_registration.cpp');
      expect(
        runner,
        contains(
          r'L"Software\\Classes\\' + scheme + r'\\shell\\open\\command"',
        ),
      );
      expect(runner, contains('GetCurrentPackageFullName'));
      expect(
        _read('windows/runner/main.cpp'),
        contains('EnsureUrlSchemeRegistered()'),
      );
    });
  });

  group('Linux', () {
    for (final path in const [
      // deb and AppImage packaging reuse the Flatpak entry.
      'packaging/flatpak/de.whispaste.app.desktop',
      'packaging/snap/de.whispaste.app.desktop',
    ]) {
      test('$path handles the scheme and passes the URL', () {
        final entry = _read(path);
        expect(entry, contains('MimeType=$mime'));
        expect(
          // %U: links and, for "Open With" (#1684), several files.
          RegExp(r'^Exec=\S+ %U$', multiLine: true).hasMatch(entry),
          isTrue,
        );
      });
    }

    test('the self-written entry (AppImage, tarball) does too', () {
      final entry = _read('linux/runner/desktop_entry.h');
      expect(entry, contains('"x-scheme-handler/$scheme"'));
      expect(entry, contains(' %U'));
    });
  });
}
