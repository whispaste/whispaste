import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/linux_decoder_hint.dart';

/// On Linux a missing GStreamer AAC decoder gets an install hint that depends
/// on the package format: apt for .deb and tarball, a Flatpak-specific hint
/// without apt, and a Snap-specific hint (PAR-040). The handbook must not
/// promise a decoder that is not verified in the Flatpak or Snap build.
void main() {
  group('linuxDecoderHintFrom', () {
    test('FLATPAK_ID selects the Flatpak hint', () {
      expect(
        linuxDecoderHintFrom({'FLATPAK_ID': 'de.whispaste.app'}),
        LinuxDecoderHint.flatpak,
      );
    });

    test('SNAP or SNAP_NAME selects the Snap hint', () {
      expect(
        linuxDecoderHintFrom({'SNAP': '/snap/whispaste/current'}),
        LinuxDecoderHint.snap,
      );
      expect(
        linuxDecoderHintFrom({'SNAP_NAME': 'whispaste'}),
        LinuxDecoderHint.snap,
      );
    });

    test('no sandbox marker, or an empty FLATPAK_ID, gives the apt hint', () {
      expect(linuxDecoderHintFrom(const {}), LinuxDecoderHint.apt);
      expect(linuxDecoderHintFrom({'FLATPAK_ID': ''}), LinuxDecoderHint.apt);
    });

    test('Flatpak wins when both markers are present', () {
      expect(
        linuxDecoderHintFrom({'FLATPAK_ID': 'x', 'SNAP': '/snap/x'}),
        LinuxDecoderHint.flatpak,
      );
    });
  });

  test(
    'the Flatpak and Snap hints name no apt command in any app language',
    () {
      for (final lang in ['de', 'en', 'es', 'he', 'pt', 'ru']) {
        final arb =
            jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        for (final key in [
          'historyImportFailureDecoderUnavailableFlatpak',
          'historyImportFailureDecoderUnavailableSnap',
        ]) {
          final text = arb[key] as String? ?? '';
          expect(text, isNotEmpty, reason: '$lang $key');
          // Whole word only: "chapter" contains the letters "apt".
          expect(
            text,
            isNot(matches(RegExp(r'\bapt\b'))),
            reason: '$lang $key',
          );
        }
      }
    },
  );

  test(
    'the handbook no longer claims that Flatpak or Snap include the decoder',
    () {
      final en =
          jsonDecode(File('lib/core/l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final de =
          jsonDecode(File('lib/core/l10n/app_de.arb').readAsStringSync())
              as Map<String, dynamic>;
      expect(en['manualC09S1B3'], isNot(contains('include it')));
      expect(de['manualC09S1B3'], isNot(contains('enthalten ihn.')));
    },
  );
}
