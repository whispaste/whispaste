import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Protects the renderer choice from #445: Impeller on Metal corrupts the glyph
// atlas when another GPU job delays an upload. BUILD.md, "Renderer", names the
// criterion for lifting it; this test goes together with the setting.
void main() {
  test('the macOS app renders with Skia', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();

    expect(plist, matches(RegExp(r'<key>FLTEnableImpeller</key>\s*<false/>')));
  });
}
