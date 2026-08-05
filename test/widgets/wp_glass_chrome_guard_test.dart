/// Guard: the painted glass chrome never reaches for an OS blur.
///
/// [WpGlassChrome] fakes glass with a plain [CustomPainter] (gradient fill +
/// Fresnel rim). That is an architecture decision, not an optimisation — the
/// product promises the widest possible hardware reach, and a compositor blur
/// is the one effect that would quietly break it on weak GPUs. This test keeps
/// the promise enforced rather than merely documented.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Sources that make up the glass chrome component.
const _componentSources = ['lib/widgets/wp_glass_chrome.dart'];

const _forbiddenApis = ['BackdropFilter', 'ImageFilter.blur'];

void main() {
  final repoRoot = _findRepoRoot();

  for (final source in _componentSources) {
    test('$source uses no OS blur API', () {
      final file = File(p.join(repoRoot, source));
      expect(file.existsSync(), isTrue, reason: '$source must exist');

      final text = file.readAsStringSync();
      for (final api in _forbiddenApis) {
        expect(
          text.contains(api),
          isFalse,
          reason:
              '$source must not use $api — the glass is painted, not blurred.',
        );
      }
    });
  }
}

/// Walks up from the current directory until it finds the package root.
String _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
