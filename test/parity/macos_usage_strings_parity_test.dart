// Guard: macOS permission reasons (microphone, Apple Events) exist for every
// app language. The App language set comes from lib/core/l10n/app_*.arb; the
// English text lives in Base.lproj. One Xcode target serves the direct build
// and the Mac App Store scheme, so the registration is checked once.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _keys = ['NSMicrophoneUsageDescription', 'NSAppleEventsUsageDescription'];

List<String> _appLanguages() =>
    Directory('lib/core/l10n')
        .listSync()
        .map((e) => RegExp(r'app_([a-z]+)\.arb$').firstMatch(e.path)?.group(1))
        .whereType<String>()
        .toList()
      ..sort();

void main() {
  final languages = _appLanguages();

  test('every app language has both usage descriptions', () {
    expect(languages, isNotEmpty);
    for (final lang in languages) {
      final dir = lang == 'en' ? 'Base' : lang;
      final file = File('macos/Runner/$dir.lproj/InfoPlist.strings');
      expect(file.existsSync(), isTrue, reason: '$dir.lproj/InfoPlist.strings');
      final text = file.readAsStringSync();
      for (final key in _keys) {
        expect(
          RegExp('"$key"\\s*=\\s*"[^"]+";').hasMatch(text),
          isTrue,
          reason: '$lang lacks $key',
        );
      }
    }
  });

  test('Info.plist lists every app language in CFBundleLocalizations', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    final block = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist)?.group(1);
    expect(block, isNotNull);
    final listed = RegExp(
      r'<string>([^<]+)</string>',
    ).allMatches(block!).map((m) => m.group(1)).toSet();
    expect(listed, containsAll(languages));
  });

  test('the Xcode project ships InfoPlist.strings as a localized resource', () {
    final pbx = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    // Only the Resources-phase entry counts: the PBXBuildFile declaration
    // carries the same phrase, so a plain contains() misses a dropped entry.
    expect(
      RegExp(
        r'^\s+[0-9A-F]+ /\* InfoPlist\.strings in Resources \*/,$',
        multiLine: true,
      ).hasMatch(pbx),
      isTrue,
      reason: 'InfoPlist.strings missing from the Resources build phase',
    );
    for (final lang in languages.where((l) => l != 'en')) {
      expect(pbx, contains('path = $lang.lproj/InfoPlist.strings'));
    }
    expect(pbx, contains('path = Base.lproj/InfoPlist.strings'));
  });
}
