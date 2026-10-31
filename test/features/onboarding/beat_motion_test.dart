/// Guards for the onboarding still images (ticket 13, decision 7b).
///
/// Every onboarding page shows a static still; no animated WebP is shipped.
/// These tests pin the delivery contract without goldens: which files exist,
/// that each is a still at the panel canvas, and the bundle size.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';

/// Beats that have a page: 2 (speech model) and 4 (access). Stills only.
const List<int> _kUsedBeats = [2, 4];

/// Every shipped theme: hell (light), dunkel (dark), marine (navy default).
const List<String> _kThemes = ['hell', 'dunkel', 'marine'];
final List<(String, int)> _kVariants = [
  for (final theme in _kThemes)
    for (final beat in _kUsedBeats) (theme, beat - 1),
];
const int _kMaxBundleBytes = 2 * 1024 * 1024;
const int _kCanvasWidth = 920;
const int _kCanvasHeight = 576;

/// What the guard reads from a WebP file header.
class _WebpInfo {
  const _WebpInfo({
    required this.width,
    required this.height,
    required this.animated,
    required this.frames,
    required this.durationMs,
  });

  final int width;
  final int height;
  final bool animated;
  final int frames;
  final int durationMs;
}

String _ascii(Uint8List b, int offset, int length) =>
    String.fromCharCodes(b.sublist(offset, offset + length));

int _le16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _le24(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);

int _le32(Uint8List b, int o) => _le24(b, o) | (b[o + 3] << 24);

/// Parses the RIFF/WEBP container: a simple lossy still (`VP8 `) or an
/// extended file (`VP8X`), animated when its ANMF frames are present.
_WebpInfo _parseWebp(Uint8List b) {
  expect(_ascii(b, 0, 4), 'RIFF', reason: 'not a RIFF file');
  expect(_ascii(b, 8, 4), 'WEBP', reason: 'not a WebP file');

  switch (_ascii(b, 12, 4)) {
    case 'VP8 ':
      // Frame header at 20: 3-byte frame tag, start code 9d 01 2a, then
      // 14-bit width and height.
      return _WebpInfo(
        width: _le16(b, 26) & 0x3fff,
        height: _le16(b, 28) & 0x3fff,
        animated: false,
        frames: 1,
        durationMs: 0,
      );
    case 'VP8X':
      final animated = (b[20] & 0x02) != 0;
      var frames = 0;
      var durationMs = 0;
      var p = 30;
      while (p + 8 <= b.length) {
        final tag = _ascii(b, p, 4);
        final size = _le32(b, p + 4);
        if (tag == 'ANMF') {
          // ANMF payload: X, Y, W, H (3 bytes each), duration (3 bytes), flags.
          durationMs += _le24(b, p + 8 + 12);
          frames++;
        }
        p += 8 + size + (size & 1);
      }
      return _WebpInfo(
        width: _le24(b, 24) + 1,
        height: _le24(b, 27) + 1,
        animated: animated,
        frames: frames,
        durationMs: durationMs,
      );
    default:
      fail('unexpected WebP chunk ${_ascii(b, 12, 4)}');
  }
}

Uint8List _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsBytesSync();
}

void main() {
  group('onboarding still assets', () {
    test('every used beat has a still of 920x576 in every theme', () {
      for (final (theme, i) in _kVariants) {
        final still = _parseWebp(
          _read(onboardingBeatAssetPath(index: i, theme: theme)),
        );
        expect(still.animated, isFalse, reason: 'beat ${i + 1} still');
        expect(
          (still.width, still.height),
          (_kCanvasWidth, _kCanvasHeight),
          reason: 'beat ${i + 1} still canvas',
        );
      }
    });

    test('the shipped files are exactly the used stills, within 2 MB', () {
      final files = Directory('assets/onboarding')
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                p.basename(f.path).startsWith('beat_') &&
                f.path.endsWith('.webp'),
          )
          .toList();
      expect(files.map((f) => p.basename(f.path)).toSet(), {
        for (final (theme, i) in _kVariants)
          p.basename(onboardingBeatAssetPath(index: i, theme: theme)),
      }, reason: 'only the stills of the pages are shipped');

      var total = 0;
      for (final (theme, i) in _kVariants) {
        total += _read(onboardingBeatAssetPath(index: i, theme: theme)).length;
      }
      expect(total, lessThanOrEqualTo(_kMaxBundleBytes));
    });
  });

  group('welcome beat widget', () {
    test('has no platform branch: the loops are identical everywhere', () {
      final source = File(
        'lib/features/onboarding/steps/welcome_step.dart',
      ).readAsStringSync();

      for (final forbidden in [
        'defaultTargetPlatform',
        'TargetPlatform.',
        'Platform.is',
        'dart:io',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              'welcome_step.dart must not branch on the platform '
              '($forbidden)',
        );
      }
    });
  });
}
