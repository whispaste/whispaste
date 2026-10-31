import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_identity/app_category.dart';

void main() {
  group('appCategoryFor', () {
    test('maps the identifier of each platform', () {
      // macOS bundle id, Windows exe name, Linux app_id and WM_CLASS.
      expect(appCategoryFor('com.googlecode.iterm2'), AppCategory.terminal);
      expect(appCategoryFor('WindowsTerminal'), AppCategory.terminal);
      expect(appCategoryFor('org.gnome.Terminal'), AppCategory.terminal);
      expect(appCategoryFor('gnome-terminal-server'), AppCategory.terminal);
    });

    test('a prefix entry covers every channel of an app', () {
      expect(appCategoryFor('dev.warp.Warp-Stable'), AppCategory.terminal);
      expect(appCategoryFor('dev.warp.Warp-Preview'), AppCategory.terminal);
      expect(appCategoryFor('com.microsoft.VSCodeInsiders'), AppCategory.code);
    });

    test('case and a trailing .exe do not matter', () {
      expect(appCategoryFor('OUTLOOK.EXE'), AppCategory.mail);
      expect(appCategoryFor('  Slack '), AppCategory.chat);
    });

    test('prefix entries match whole bundle families', () {
      expect(appCategoryFor('com.apple.iWork.Numbers'), AppCategory.office);
      expect(appCategoryFor('com.apple.Safari'), AppCategory.browser);
    });

    test('Firefox on X11 reports Navigator as its WM_CLASS name', () {
      expect(appCategoryFor('Navigator'), AppCategory.browser);
    });

    test('unlisted and empty identifiers are unknown', () {
      expect(appCategoryFor('com.example.Unlisted'), AppCategory.unknown);
      expect(appCategoryFor(''), AppCategory.unknown);
      // An exact name is not a prefix: `code` must not swallow `codeblocks`.
      expect(appCategoryFor('codeblocks'), AppCategory.unknown);
    });
  });
}
