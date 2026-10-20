// Snippet-picker window size guard (PAR-017, ADR 0024 shadow inset).
//
// The Dart body draws its shadow inside a transparent margin of
// kSnippetPickerShadowInset on each side. The native shells on macOS, Windows
// and Linux must size their window to the same card plus that margin, or the
// shadow is clipped on one platform only. The check reads the size literals
// in each shell source.
//
// Static check: it proves the sizes match, not that the shadow renders.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/snippet_picker_render_entrypoint.dart';

const _cardWidth = 360;
const _cardHeight = 420;

/// Each shell source and the regex that captures its width and height.
final _shells = <String, _SizeLiterals>{
  'macos': _SizeLiterals(
    file: 'macos/Runner/SnippetPickerHost.swift',
    width: RegExp(r'contentSize = NSSize\(width: (\d+), height: (\d+)\)'),
  ),
  'windows': _SizeLiterals(
    file: 'windows/runner/snippet_picker_host.cpp',
    width: RegExp(r'kLogicalWidth = (\d+);[\s\S]*?kLogicalHeight = (\d+);'),
  ),
  'linux': _SizeLiterals(
    file: 'linux/runner/snippet_picker_window.h',
    width: RegExp(
      r'kSnippetPickerWidth = (\d+);[\s\S]*?kSnippetPickerHeight = (\d+);',
    ),
  ),
};

class _SizeLiterals {
  const _SizeLiterals({required this.file, required this.width});
  final String file;
  final RegExp width;
}

void main() {
  final inset = kSnippetPickerShadowInset.round();
  final expectedWidth = _cardWidth + 2 * inset;
  final expectedHeight = _cardHeight + 2 * inset;

  for (final entry in _shells.entries) {
    test('${entry.key} picker window = card + shadow inset on each side', () {
      final source = File(entry.value.file).readAsStringSync();
      final match = entry.value.width.firstMatch(source);
      expect(
        match,
        isNotNull,
        reason: 'size literals not found in ${entry.value.file}',
      );
      expect(
        int.parse(match!.group(1)!),
        expectedWidth,
        reason: entry.value.file,
      );
      expect(
        int.parse(match.group(2)!),
        expectedHeight,
        reason: entry.value.file,
      );
    });
  }

  test('macOS panel draws no native shadow (the Dart body draws it)', () {
    final source = File(
      'macos/Runner/SnippetPickerPanel.swift',
    ).readAsStringSync();
    expect(source, contains('hasShadow = false'));
    expect(source, isNot(contains('hasShadow = true')));
  });
}
