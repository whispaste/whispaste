library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';

import 'screenshot_devices.dart';

final _screenshots = <_WelcomeShot>[
  const _WelcomeShot(
    name: '05_onboarding_welcome_dark_en',
    settings: AppSettings(themeMode: ThemeMode.dark, locale: 'en'),
  ),
  const _WelcomeShot(
    name: '06_onboarding_welcome_light_de',
    settings: AppSettings(themeMode: ThemeMode.light, locale: 'de'),
  ),
];

const _devices = [WpScreenshotDevices.windowsStore];

void main() {
  ScreenshotDevice.screenshotsFolder = 'goldens/';

  group('Onboarding welcome screenshots', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    for (final screen in _screenshots) {
      for (final goldenDevice in _devices) {
        testGoldens(goldenDevice.name, (tester) async {
          final device = goldenDevice.device;
          final app = _buildScreenshotApp(
            device: device,
            settings: screen.settings,
          );

          await tester.pumpWidget(app);
          await tester.loadAssets();
          await tester.pumpFrames(app, const Duration(seconds: 1));
          await tester.expectScreenshot(device, screen.name);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        });
      }
    }
  });
}

Widget _buildScreenshotApp({
  required ScreenshotDevice device,
  required AppSettings settings,
}) {
  return ScreenshotApp(
    device: device,
    theme: wpLightTheme(),
    darkTheme: wpDarkTheme(),
    themeMode: settings.themeMode == ThemeMode.light
        ? ThemeMode.light
        : ThemeMode.dark,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: Locale(settings.locale),
    home: ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _MockSettingsNotifier(settings)),
      ],
      child: const Scaffold(body: OnboardingOverlay()),
    ),
  );
}

class _WelcomeShot {
  const _WelcomeShot({required this.name, required this.settings});

  final String name;
  final AppSettings settings;
}

class _MockSettingsNotifier extends SettingsNotifier {
  _MockSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}
