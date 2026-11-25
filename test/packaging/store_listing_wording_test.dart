import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the store listing texts against wording the product has banned
/// (internal-notes §7, #1940): an unqualified "any app" promise, "pin" for
/// favourites, "template" for snippets, "sidebar" for the side panel,
/// "Premium" as a tier, donation words and code signing as a use of money.
///
/// Covers the Mac App Store listing (`fastlane/metadata`), the Microsoft
/// Store listing (`store/<locale>/`) and the store copy documents
/// (`store/*.md`). Release notes, licence and copyright lines are not listing
/// copy and are skipped, as are the review notes.
const _skippedFiles = {
  'release_notes.txt',
  'release-notes.txt',
  'license-terms.txt',
  'copyright.txt',
  'notes.txt',
};

final _banned = <String, RegExp>{
  'unqualified "any app"': RegExp(
    r'jede[rn]? (windows-)?app\b|\bany (windows )?app\b|every app|'
    r'cualquier (otra )?app|qualquer (outro )?app|qualsiasi app|ogni app|'
    r"toutes? (les )?app|n'importe quelle app|любом приложении|任何应用",
    caseSensitive: false,
  ),
  'pin instead of favourite': RegExp(
    r'anheft|épingl|закрепл|置顶',
    caseSensitive: false,
  ),
  'pin instead of favourite (en)': RegExp(r'\bpin(s|ned|ning)?\b'),
  'template for snippets': RegExp(
    r'vorlage|template|plantilla|шаблон|模板',
    caseSensitive: false,
  ),
  'sidebar for the side panel': RegExp(
    r'seitenleiste|sidebar|侧边栏',
    caseSensitive: false,
  ),
  'Premium as a tier': RegExp(r'premium', caseSensitive: false),
  // Every form internal-notes §7 bans, as whole words, so "donde", "dont" or
  // "don't" stay allowed. Letters are matched with \p{L} because \b only
  // knows ASCII word characters.
  'donation wording': RegExp(
    r'(?<!\p{L})(spende\p{L}*|donat\p{L}*|donaci\p{L}*|donar\p{L}*|'
    r'doa[çc]\p{L}*|doar|donazion\p{L}*|пожертв\p{L}*|'
    r"don(?!['’\p{L}]))(?!\p{L})|捐助|捐款|捐赠",
    caseSensitive: false,
    unicode: true,
  ),
  'code signing as a use of money': RegExp(
    r'code.?sign|zertifikat|certificate',
    caseSensitive: false,
  ),
};

Iterable<File> _listingFiles() sync* {
  for (final root in ['fastlane/metadata', 'store']) {
    for (final entity in Directory(root).listSync(recursive: true)) {
      if (entity is! File) continue;
      final segments = entity.uri.pathSegments;
      final isText = entity.path.endsWith('.txt');
      // store/*.md holds store copy (long description, DMG wording).
      final isStoreDoc =
          root == 'store' &&
          segments.length == 2 &&
          entity.path.endsWith('.md');
      if (!isText && !isStoreDoc) continue;
      if (_skippedFiles.contains(segments.last)) continue;
      yield entity;
    }
  }
}

void main() {
  test('store listings cover both stores', () {
    // `File.path` keeps the platform separator after the listed root
    // (`fastlane/metadata\de-DE\...` on Windows); the URI form is the
    // same on every system.
    final paths = _listingFiles().map((f) => f.uri.path).toList();
    expect(paths.any((p) => p.startsWith('fastlane/metadata/')), isTrue);
    expect(paths.any((p) => p.startsWith('store/')), isTrue);
  });

  test('donation rule catches every language and only whole words', () {
    final rule = _banned['donation wording']!;
    for (final banned in [
      'Spende',
      'spenden',
      'donate',
      'donation',
      'donar',
      'donación',
      'doar',
      'doação',
      'donare',
      'donazione',
      'faire un don',
      'un don de 5 €',
      'пожертвование',
      '捐款',
    ]) {
      expect(rule.hasMatch(banned), isTrue, reason: banned);
    }
    for (final allowed in [
      'donde escribas',
      'dont vous avez besoin',
      "don't",
      'London',
      'abandonar',
      'dono do arquivo',
    ]) {
      expect(rule.hasMatch(allowed), isFalse, reason: allowed);
    }
  });

  test('store listings avoid banned wording', () {
    final hits = <String>[];
    for (final file in _listingFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final rule in _banned.entries) {
          final match = rule.value.firstMatch(lines[i]);
          if (match != null) {
            hits.add('${file.path}:${i + 1}: ${rule.key} "${match[0]}"');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: 'internal-notes §7 bans this wording');
  });
}
