import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards App Store Connect's length limits for everything `mas_release`
/// uploads from `fastlane/metadata` (#1734).
///
/// App Store Connect rejects an over-long field only when deliver PATCHes it,
/// which happens after the build: the v1.5.0 run stopped at the review notes
/// (4548 characters) before the binary was uploaded. The same overflow had
/// been trimmed once before, so this check keeps it from coming back.
///
/// Limits: characters, except keywords, which App Store Connect counts in
/// UTF-8 bytes. deliver strips surrounding whitespace before uploading.
const _charLimits = {
  'name.txt': 30,
  'subtitle.txt': 30,
  'promotional_text.txt': 170,
  'description.txt': 4000,
  'release_notes.txt': 4000,
  'notes.txt': 4000,
};
const _keywordByteLimit = 100;

void main() {
  final files = Directory('fastlane/metadata')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.txt'))
      .toList();

  test('metadata folder holds the review notes and localized listings', () {
    final names = files.map((f) => f.uri.pathSegments.last).toSet();
    expect(names, containsAll(['notes.txt', 'description.txt']));
    expect(names, contains('keywords.txt'));
  });

  test('every field stays within App Store Connect limits', () {
    final tooLong = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final text = file.readAsStringSync().trim();
      if (name == 'keywords.txt') {
        final bytes = utf8.encode(text).length;
        if (bytes > _keywordByteLimit) {
          tooLong.add('${file.path}: $bytes bytes > $_keywordByteLimit');
        }
        continue;
      }
      final limit = _charLimits[name];
      if (limit == null) continue;
      final chars = text.runes.length;
      if (chars > limit) {
        tooLong.add('${file.path}: $chars characters > $limit');
      }
    }
    expect(tooLong, isEmpty, reason: 'App Store Connect would reject these');
  });
}
