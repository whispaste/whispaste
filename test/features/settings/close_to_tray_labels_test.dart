/// The close-to-tray switch speaks of the menu bar on macOS (#1920): the Mac
/// has no tray or notification area.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/close_to_tray_labels.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS names the menu bar, in every language', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    for (final locale in L10n.supportedLocales) {
      final l10n = await L10n.delegate.load(locale);
      expect(closeToTrayTitle(l10n), l10n.settingsCloseToMenuBar);
      expect(closeToTraySubtitle(l10n), l10n.settingsCloseToMenuBarSubtitle);
      expect(
        closeToTrayTitle(l10n),
        isNot(l10n.settingsCloseToTray),
        reason: '$locale',
      );
    }
    final de = await L10n.delegate.load(const Locale('de'));
    expect(closeToTrayTitle(de), isNot(contains('Infobereich')));
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test('${platform.name} keeps the tray wording', () async {
      debugDefaultTargetPlatformOverride = platform;
      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(closeToTrayTitle(l10n), l10n.settingsCloseToTray);
      expect(closeToTraySubtitle(l10n), l10n.settingsCloseToTraySubtitle);
    });
  }
}
