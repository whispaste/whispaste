/// The paste key named in onboarding and failure copy follows the platform:
/// ⌘V on macOS, the Ctrl chord (localized "Strg" in German) elsewhere.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

Future<L10n> _pumpLocale(WidgetTester tester, Locale locale) async {
  late L10n l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Builder(
        builder: (context) {
          l10n = L10n.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return l10n;
}

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('macOS names ⌘V in the onboarding copy', (tester) async {
    final l10n = await _pumpLocale(tester, const Locale('en'));
    await _onPlatform(TargetPlatform.macOS, () async {
      final label = pasteShortcutLabel(l10n: l10n);

      expect(label, '⌘V');
      expect(
        l10n.onboardingReadyStep3CopyOnly(label),
        'Text is in your clipboard, press ⌘V to paste',
      );
    });
  });

  testWidgets('Windows names Ctrl+V in English copy, Strg+V in German', (
    tester,
  ) async {
    final en = await _pumpLocale(tester, const Locale('en'));
    await _onPlatform(TargetPlatform.windows, () async {
      final label = pasteShortcutLabel(l10n: en);
      expect(label, 'Ctrl+V');
      expect(
        en.onboardingReadyStep3CopyOnly(label),
        'Text is in your clipboard, press Ctrl+V to paste',
      );
    });

    final de = await _pumpLocale(tester, const Locale('de'));
    await _onPlatform(TargetPlatform.windows, () async {
      expect(pasteShortcutLabel(l10n: de), 'Strg+V');
    });
  });

  testWidgets('Linux uses the same Ctrl chord, never the macOS glyph', (
    tester,
  ) async {
    final l10n = await _pumpLocale(tester, const Locale('en'));
    await _onPlatform(TargetPlatform.linux, () async {
      final label = pasteShortcutLabel(l10n: l10n);

      expect(label, 'Ctrl+V');
      expect(l10n.pasteFailureGeneric(label), isNot(contains('⌘')));
      expect(l10n.onboardingReadyStep3CopyOnly(label), isNot(contains('⌘')));
    });
  });
}
