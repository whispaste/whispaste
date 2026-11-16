// Parity guard for "Transcribe with WhisPaste" in the file manager (#1684).
//
// The entry must appear for exactly the audio types file transcription reads
// (`audioImportExtensions`), on every channel, and must never make WhisPaste
// the default app of a type. The registrations live in platform files that
// cannot read the Dart list, so this test holds them to it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/video_audio_decoder.dart';

String _read(String path) => File(path).readAsStringSync();

/// The Store verb text of one package language (`windows/msix/Strings`).
String? _reswVerb(String dir) => RegExp(
  r'<data name="TranscribeVerb" xml:space="preserve">\s*<value>([^<]+)</value>',
).firstMatch(_read('windows/msix/Strings/$dir/Resources.resw'))?.group(1);

/// The shared-mime-info type a Linux file manager reports per extension.
const _mimeByExtension = {
  'wav': 'audio/x-wav',
  'mp3': 'audio/mpeg',
  'flac': 'audio/flac',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'ogg': 'audio/ogg',
  'opus': 'audio/x-opus+ogg',
};

void main() {
  test('the list is the audio part of what the import reads everywhere', () {
    for (final platform in [
      (mac: true, linux: false, windows: false),
      (mac: false, linux: true, windows: false),
      (mac: false, linux: false, windows: true),
    ]) {
      final supported = supportedImportExtensions(
        isMacOS: platform.mac,
        isLinux: platform.linux,
        isWindows: platform.windows,
      );
      expect(supported, containsAll(audioImportExtensions));
    }
    expect(
      audioImportExtensions.toSet().intersection(videoImportExtensions.toSet()),
      isEmpty,
    );
    expect(_mimeByExtension.keys.toSet(), audioImportExtensions.toSet());
  });

  group('Windows', () {
    test('NSIS adds the verb per audio type and removes it again', () {
      final nsi = _read('installer/whispaste.nsi');
      Set<String> listed(String macro) => RegExp(
        '!insertmacro $macro "([a-z0-9]+)"',
      ).allMatches(nsi).map((m) => m.group(1)!).toSet();
      expect(listed('WriteTranscribeVerb'), audioImportExtensions.toSet());
      expect(listed('DeleteTranscribeVerb'), audioImportExtensions.toSet());
      expect(
        nsi,
        contains(
          r'SystemFileAssociations\.${EXT}\shell\${PRODUCT_VERB}\command" "" '
          '\'"\$INSTDIR\\whispaste.exe" "%1"\'',
        ),
      );
      // Only SystemFileAssociations: never the type's own key, whose
      // default value picks the default app.
      expect(
        RegExp(r'Software\\Classes\\\.').hasMatch(nsi),
        isFalse,
        reason: 'the installer must not write Software\\Classes\\.<ext>',
      );
    });

    test('MSIX associates the same types with the verb', () {
      final script = _read('scripts/build-msix.ps1');
      final list = RegExp(
        r'\$audioExtensions = @\(([^)]*)\)',
      ).firstMatch(script)!.group(1)!;
      final extensions = RegExp(
        "'([a-z0-9]+)'",
      ).allMatches(list).map((m) => m.group(1)!).toSet();
      expect(extensions, audioImportExtensions.toSet());
      expect(
        script,
        contains('<uap3:Verb Id="transcribe" Parameters="&quot;%1&quot;">'),
      );
      expect(
        _read('pubspec.yaml'),
        isNot(contains('file_extension:')),
        reason: 'the association is added once, by build-msix.ps1',
      );
    });

    // #1692: the Store verb reads ms-resource:TranscribeVerb from one .resw
    // per package language. #1701: Explorer does not show that verb (it sits
    // on the package ProgID, which is never the default app), so the Store
    // version is reached through "Open With". The handbook quotes the verb the
    // website installer writes: German in German, English everywhere else
    // (NSIS knows only DE/EN).
    test('MSIX verb text exists for every package language and the handbook '
        'quotes the installer verb', () {
      final script = _read('scripts/build-msix.ps1');
      expect(script, contains(r"$verbText = 'ms-resource:TranscribeVerb'"));
      expect(script, contains(r"$verbText = 'Transcribe with WhisPaste'"));
      final languages = RegExp(r'^\s*languages:\s*(.+)$', multiLine: true)
          .firstMatch(_read('pubspec.yaml'))!
          .group(1)!
          .split(',')
          .map((l) => l.trim().toLowerCase())
          .toSet();
      final dirs = Directory('windows/msix/Strings')
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toList();
      expect(dirs.map((d) => d.toLowerCase()).toSet(), languages);
      for (final dir in dirs) {
        expect(_reswVerb(dir), isNotNull, reason: '$dir has no TranscribeVerb');
        final arb = jsonDecode(
          _read('lib/core/l10n/app_${dir.split('-').first}.arb'),
        );
        final manual = (arb as Map<String, dynamic>)['manualC09S1B4'] as String;
        final verb = _reswVerb(dir == 'de-DE' ? 'de-DE' : 'en-US')!;
        expect(
          RegExp('[“«„]${RegExp.escape(verb)}[”»“]').hasMatch(manual),
          isTrue,
          reason: 'manualC09S1B4 ($dir) must quote the installer verb "$verb"',
        );
        expect(
          manual,
          contains('Microsoft Store'),
          reason: 'manualC09S1B4 ($dir) must name the Store way (Open With)',
        );
      }
      final nsi = _read('installer/whispaste.nsi');
      for (final (lang, dir) in [('ENGLISH', 'en-US'), ('GERMAN', 'de-DE')]) {
        expect(
          nsi,
          contains(
            'LangString VERB_TRANSCRIBE \${LANG_$lang} "${_reswVerb(dir)}"',
          ),
          reason: 'NSIS and Store show the same $dir verb',
        );
      }
    });
  });

  group('macOS', () {
    test(
      'Info.plist claims public.audio only, as Viewer with rank Alternate',
      () {
        // A claim on a concrete type (org.xiph.flac, an extension) outranks
        // QuickTime's public.audio claim and makes WhisPaste the double-click
        // app for FLAC/Ogg/Opus; only public.audio keeps every default.
        final plist = _read('macos/Runner/Info.plist');
        final types = RegExp(
          r'<key>CFBundleDocumentTypes</key>\s*<array>(.*?)</array>\s*</dict>\s*</array>',
          dotAll: true,
        ).firstMatch(plist)!.group(1)!;
        final claimed = RegExp(r'<string>([^<]+)</string>')
            .allMatches(
              RegExp(
                r'<key>LSItemContentTypes</key>\s*<array>(.*)',
                dotAll: true,
              ).firstMatch(types)!.group(1)!,
            )
            .map((m) => m.group(1))
            .toList();
        expect(claimed, ['public.audio']);
        expect(types, isNot(contains('CFBundleTypeExtensions')));
        expect(types, contains('<string>Viewer</string>'));
        expect(types, contains('<string>Alternate</string>'));
        expect(types, isNot(contains('<string>Owner</string>')));
        expect(types, isNot(contains('<string>Default</string>')));
      },
    );

    test('Ogg and Opus files conform to public.audio', () {
      final plist = _read('macos/Runner/Info.plist');
      final imported = plist.substring(
        plist.indexOf('<key>UTImportedTypeDeclarations</key>'),
      );
      expect(imported, contains('<string>public.audio</string>'));
      expect(imported, contains('<string>ogg</string>'));
      expect(imported, contains('<string>opus</string>'));
    });

    test('the delegate forwards opened file URLs to Dart', () {
      final delegate = _read('macos/Runner/AppDelegate.swift');
      expect(delegate, contains('open urls: [URL]'));
      expect(delegate, contains('urls.map(\\.absoluteString)'));
    });
  });

  group('Linux', () {
    for (final path in const [
      // deb and AppImage packaging reuse the Flatpak entry.
      'packaging/flatpak/de.whispaste.app.desktop',
      'packaging/snap/de.whispaste.app.desktop',
    ]) {
      test('$path lists the audio types and passes the files', () {
        final entry = _read(path);
        final mimeLine = RegExp(
          r'^MimeType=(.*)$',
          multiLine: true,
        ).firstMatch(entry)!.group(1)!;
        final mimes = mimeLine.split(';').where((m) => m.isNotEmpty).toSet();
        expect(mimes, containsAll(_mimeByExtension.values));
        expect(mimes.where((m) => m.startsWith('video/')), isEmpty);
        expect(
          RegExp(r'^Exec=\S+ %U$', multiLine: true).hasMatch(entry),
          isTrue,
        );
      });
    }

    test('the self-written entry (AppImage, tarball) matches the packages', () {
      final header = _read('linux/runner/desktop_entry.h');
      final mimes = RegExp(
        r'kOpenWithAudioMimeTypes\[\] =\s*"([^"]*)"',
      ).firstMatch(header)!.group(1)!;
      final flatpak = RegExp(
        r'^MimeType=x-scheme-handler/whispaste;(.*)$',
        multiLine: true,
      ).firstMatch(_read('packaging/flatpak/de.whispaste.app.desktop'))!;
      expect(mimes, flatpak.group(1));
    });
  });
}
