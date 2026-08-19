@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';

final _screenshots = <_WelcomeShot>[
  const _WelcomeShot(
    name: '05_onboarding_welcome_dark_en',
    settings: AppSettings(interface_: InterfaceSettings(locale: 'en')),
  ),
  // Was `06_onboarding_welcome_light_de` — the German shot happened to be the
  // light one, so removing the light theme would otherwise have taken the
  // only non-English capture of this screen with it. The locale is the point
  // of the second shot; the theme never was.
  const _WelcomeShot(
    name: '06_onboarding_welcome_dark_de',
    settings: AppSettings(interface_: InterfaceSettings(locale: 'de')),
  ),
  // Beats 1 and 2 (0-based) were never captured — only the first beat's
  // asset was ever exercised by this golden. Cover the other two real clips
  // too, same locale as the primary shot to isolate the beat as the only
  // variable.
  const _WelcomeShot(
    name: '07_onboarding_welcome_dark_beat2',
    settings: AppSettings(interface_: InterfaceSettings(locale: 'en')),
    beatIndex: 1,
  ),
  const _WelcomeShot(
    name: '08_onboarding_welcome_dark_beat3',
    settings: AppSettings(interface_: InterfaceSettings(locale: 'en')),
    beatIndex: 2,
  ),
];

const _devices = [
  ScreenshotDevice(
    platform: TargetPlatform.windows,
    resolution: Size(1366, 768),
    pixelRatio: 1,
    goldenSubFolder: 'onboardingWelcomeScreenshots/',
    frameBuilder: ScreenshotFrame.noFrame,
  ),
];

void main() {
  ScreenshotDevice.screenshotsFolder = 'goldens/';

  group('Onboarding welcome screenshots', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    for (final screen in _screenshots) {
      for (final device in _devices) {
        testGoldens('windowsStore', (tester) async {
          final app = _buildScreenshotApp(
            device: device,
            settings: screen.settings,
          );

          await tester.pumpWidget(app);
          await tester.loadAssets();
          if (screen.beatIndex != 0) {
            await tester.tap(
              find.byKey(onboardingBeatTileKey(screen.beatIndex)),
            );
            await tester.pump();
            await tester.loadAssets();
          }
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
    theme: wpDarkTheme(),
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
  const _WelcomeShot({
    required this.name,
    required this.settings,
    this.beatIndex = 0,
  });

  final String name;
  final AppSettings settings;
  final int beatIndex;
}

class _MockSettingsNotifier extends SettingsNotifier {
  _MockSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}
