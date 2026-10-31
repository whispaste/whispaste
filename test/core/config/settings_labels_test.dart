import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';

/// Runs [body] with the platform pinned. Flutter requires the override to be
/// cleared inside the test body, so it cannot be left to `addTearDown`.
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
  Future<L10n> pumpLocale(WidgetTester tester, Locale locale) async {
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

  group('settings_labels', () {
    testWidgets('localizes modifier and special key labels in German', (
      tester,
    ) async {
      final l10n = await pumpLocale(tester, const Locale('de'));

      expect(
        formatHotkeyShortcut('ctrl+shift', 'enter', l10n: l10n, isMacOS: false),
        'Strg+Umschalt+Eingabe',
      );
      expect(hotkeyKeyLabel('delete', l10n: l10n), 'Entf');
      expect(hotkeyKeyLabel('space', l10n: l10n), 'Leertaste');
    });

    testWidgets('recorder hint examples follow the platform modifier names', (
      tester,
    ) async {
      final l10n = await pumpLocale(tester, const Locale('de'));

      final windows = hotkeyRecorderExamples(l10n: l10n, isMacOS: false);
      expect(windows.first, 'Alt+Leertaste');
      expect(windows.join(' '), contains('Strg+'));
      expect(windows.join(' '), isNot(contains('Ctrl')));

      final mac = hotkeyRecorderExamples(l10n: l10n, isMacOS: true);
      expect(mac.join(' '), isNot(contains('Ctrl')));
      expect(mac.join(' '), isNot(contains('Strg')));
      expect(mac, hasLength(3));
    });

    testWidgets('altgr token renders as the AltGr label (#39)', (tester) async {
      final l10n = await pumpLocale(tester, const Locale('de'));

      expect(hotkeyModifierLabels('altgr', l10n: l10n, isMacOS: false), [
        'AltGr',
      ]);
      expect(hotkeyModifierLabels('shift+altgr', l10n: l10n, isMacOS: false), [
        'Umschalt',
        'AltGr',
      ]);
    });
  });

  group('pushToTalkUnavailableMessage', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(locale);

      test('Linux points to the --toggle CLI trigger '
          '(${locale.languageCode})', () {
        final message = pushToTalkUnavailableMessage(
          l10n,
          operatingSystem: 'linux',
        );
        expect(message, l10n.pushToTalkUnavailableLinuxTooltip);
        expect(message, contains('whispaste --toggle'));
      });

      test('other platforms keep the generic hint '
          '(${locale.languageCode})', () {
        expect(
          pushToTalkUnavailableMessage(l10n, operatingSystem: 'windows'),
          l10n.pushToTalkUnavailableTooltip,
        );
      });
    }
  });

  group('doubleTapFallbackNotice', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(locale);

      test('macOS names the missing Input Monitoring permission '
          '(${locale.languageCode})', () {
        expect(
          doubleTapFallbackNotice(l10n, isMacOS: true),
          l10n.settingsDoubleTapFallbackNoticeMac,
        );
      });

      test('Windows and Linux name their own reason '
          '(${locale.languageCode})', () {
        expect(
          doubleTapFallbackNotice(l10n, isMacOS: false, isWindows: true),
          l10n.settingsDoubleTapFallbackNoticeWindows,
        );
        expect(
          doubleTapFallbackNotice(
            l10n,
            isMacOS: false,
            isWindows: false,
            isLinux: true,
          ),
          l10n.settingsDoubleTapFallbackNoticeLinux,
        );
      });

      test('other systems keep the generic wording '
          '(${locale.languageCode})', () {
        expect(
          doubleTapFallbackNotice(
            l10n,
            isMacOS: false,
            isWindows: false,
            isLinux: false,
          ),
          l10n.settingsDoubleTapFallbackNotice,
        );
      });
    }

    test(
      'the macOS wording differs from the generic one in every language',
      () {
        for (final locale in L10n.supportedLocales) {
          final l10n = lookupL10n(locale);
          expect(
            l10n.settingsDoubleTapFallbackNoticeMac,
            isNot(l10n.settingsDoubleTapFallbackNotice),
            reason: locale.languageCode,
          );
        }
      },
    );
  });

  group('onboardingDoubleTapFallbackHint', () {
    for (final locale in L10n.supportedLocales) {
      final l10n = lookupL10n(locale);

      test('macOS names the missing permission, elsewhere the generic hint '
          '(${locale.languageCode})', () {
        expect(
          onboardingDoubleTapFallbackHint(l10n, isMacOS: true),
          l10n.onboardingTriggerDoubleTapFallbackHintMac,
        );
        expect(
          onboardingDoubleTapFallbackHint(
            l10n,
            isMacOS: false,
            isWindows: false,
            isLinux: false,
          ),
          l10n.onboardingTriggerDoubleTapFallbackHint,
        );
        expect(
          l10n.onboardingTriggerDoubleTapFallbackHintMac,
          isNot(l10n.onboardingTriggerDoubleTapFallbackHint),
        );
      });
    }
  });

  group('one hotkey format per platform (all hotkey displays)', () {
    // Settings, Snippets, onboarding, dock and tooltips all go through
    // formatHotkeyShortcut / hotkeyDisplayParts, so pinning the platform
    // here pins every display.
    for (final (platform, expected, parts) in const [
      (TargetPlatform.macOS, '⌃⇧ E', ['⌃', '⇧', 'E']),
      (TargetPlatform.windows, 'Strg+Umschalt+E', ['Strg', 'Umschalt', 'E']),
      (TargetPlatform.linux, 'Strg+Umschalt+E', ['Strg', 'Umschalt', 'E']),
    ]) {
      testWidgets('${platform.name}: shortcut and keycap parts', (
        tester,
      ) async {
        final l10n = await pumpLocale(tester, const Locale('de'));
        await _onPlatform(platform, () async {
          expect(formatHotkeyShortcut('ctrl+shift', 'e', l10n: l10n), expected);
          expect(hotkeyDisplayParts('ctrl+shift', 'e', l10n: l10n), parts);
        });
      });
    }
  });

  group('speech group value (engine · model, NAM-02)', () {
    test('a local Whisper model reads as family · tier, never the raw ID', () {
      const settings = AppSettings(
        stt: SttSettings(
          provider: 'On Device',
          engine: 'whisper',
          model: 'whisper-small',
        ),
      );
      expect(sttEngineModelLabel(settings, L10nDe()), 'Whisper · Schnell');
      expect(sttEngineModelLabel(settings, L10nEn()), 'Whisper · Fast');
    });

    test('local Parakeet reads as its engine name', () {
      const settings = AppSettings(
        stt: SttSettings(provider: 'On Device', engine: 'parakeet'),
      );
      expect(sttEngineModelLabel(settings, L10nDe()), 'Parakeet');
    });

    test('a cloud provider reads as its name', () {
      const settings = AppSettings(stt: SttSettings(provider: 'OpenAI'));
      expect(sttEngineModelLabel(settings, L10nEn()), 'OpenAI');
    });
  });

  group('dock language value (XP-5-14)', () {
    final l10n = lookupL10n(const Locale('de'));

    test('auto-detection reads as a short translated label', () {
      const settings = AppSettings(stt: SttSettings(language: 'auto'));
      expect(sttLanguageDockLabel(settings, l10n), 'Automatisch');
    });

    test('the legacy stored "Auto-detect" never shows raw', () {
      const settings = AppSettings(stt: SttSettings(language: 'Auto-detect'));
      expect(sttLanguageDockLabel(settings, l10n), 'Automatisch');
    });

    test('a chosen language reads as its name in the app language', () {
      const settings = AppSettings(stt: SttSettings(language: 'fr'));
      expect(
        sttLanguageDockLabel(
          settings,
          l10n,
          nameOf: (code) => code == 'fr' ? 'Französisch' : null,
        ),
        'Französisch',
      );
    });

    test('without localized names the catalog name is used', () {
      const settings = AppSettings(stt: SttSettings(language: 'English'));
      expect(sttLanguageDockLabel(settings, l10n), 'English');
    });

    test('Parakeet always detects the language itself', () {
      const settings = AppSettings(
        stt: SttSettings(
          provider: 'On Device',
          engine: 'parakeet',
          language: 'de',
        ),
      );
      expect(sttLanguageDockLabel(settings, l10n), 'Automatisch');
    });
  });
}
