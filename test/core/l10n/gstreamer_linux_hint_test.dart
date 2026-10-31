import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// M4A/AAC import on Linux needs the GStreamer libav plugin (PAR-038). The
/// install hint in the import failure and in the handbook must name that
/// package in every app language, and every Linux package must ship it:
/// the .deb as a Recommends, the Snap as a staged package.
const _gstPackage = 'gstreamer1.0-libav';

void main() {
  test(
    'the Linux import hint names the GStreamer package in all six languages',
    () {
      for (final lang in ['de', 'en', 'es', 'he', 'pt', 'ru']) {
        final arb =
            jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        for (final key in [
          'historyImportFailureDecoderUnavailableLinux',
          'manualC09S1B3',
        ]) {
          expect(
            (arb[key] as String?) ?? '',
            contains(key == 'manualC09S1B3' ? 'GStreamer' : _gstPackage),
            reason: '$lang $key',
          );
        }
        expect(
          arb['manualC09S1Cmd'],
          'sudo apt install $_gstPackage',
          reason: '$lang manualC09S1Cmd',
        );
      }
    },
  );

  test('the .deb recommends the GStreamer plugins', () {
    final control = File('packaging/deb/control.template').readAsStringSync();
    final recommends = control
        .split('\n')
        .firstWhere((l) => l.startsWith('Recommends:'));
    expect(recommends, contains(_gstPackage));
    expect(recommends, contains('gstreamer1.0-plugins-base'));
    expect(recommends, contains('gstreamer1.0-plugins-good'));
  });

  test('the Snap stages the GStreamer plugins', () {
    final snap = File('packaging/snap/snapcraft.yaml').readAsStringSync();
    expect(snap, contains('      - $_gstPackage\n'));
    expect(snap, contains('      - gstreamer1.0-plugins-base\n'));
    expect(snap, contains('      - gstreamer1.0-plugins-good\n'));
  });
}
