import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/theme/appearance.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';

void main() {
  group('AppearanceMode persistence', () {
    test('defaults to navy', () {
      expect(InterfaceSettings.defaults.appearance, AppearanceMode.navy);
      expect(AppSettings.defaults.interface_.appearance, AppearanceMode.navy);
    });

    test('a missing appearance key loads as the navy default', () {
      expect(InterfaceSettings.fromMap({}).appearance, AppearanceMode.navy);
      expect(AppearanceMode.fromValue(null), AppearanceMode.navy);
    });

    test('an explicitly stored light stays light', () {
      expect(
        InterfaceSettings.fromMap({'appearance': 'light'}).appearance,
        AppearanceMode.light,
      );
      expect(
        InterfaceSettings.fromMap({'appearance': 'dark'}).appearance,
        AppearanceMode.dark,
      );
    });

    test('round-trips through the settings map', () {
      for (final mode in AppearanceMode.values) {
        final map = InterfaceSettings.defaults
            .copyWith(appearance: mode)
            .toMap();
        expect(map['appearance'], mode.value);
        expect(InterfaceSettings.fromMap(map).appearance, mode);
      }
    });

    test('ignores the retired theme_mode key and unknown values', () {
      expect(
        InterfaceSettings.fromMap({'theme_mode': 'dark'}).appearance,
        AppearanceMode.navy,
      );
      expect(
        InterfaceSettings.fromMap({'appearance': 'sepia'}).appearance,
        AppearanceMode.navy,
      );
    });
  });

  group('colorsForAppearance', () {
    test('fixed modes ignore the platform brightness', () {
      for (final platform in Brightness.values) {
        expect(
          colorsForAppearance(AppearanceMode.light, platform),
          same(wpLightColors),
        );
        expect(
          colorsForAppearance(AppearanceMode.dark, platform),
          same(wpDarkColors),
        );
        expect(
          colorsForAppearance(AppearanceMode.navy, platform),
          same(wpNavyColors),
        );
      }
    });

    test('system follows the platform between light and dark', () {
      expect(
        colorsForAppearance(AppearanceMode.system, Brightness.light),
        same(wpLightColors),
      );
      expect(
        colorsForAppearance(AppearanceMode.system, Brightness.dark),
        same(wpDarkColors),
      );
    });

    test('brand paints light content inside a navy frame', () {
      expect(wpNavyColors.brightness, Brightness.light);
      expect(wpNavyColors.surface, wpLightColors.surface);
      expect(wpNavyColors.frame, same(wpDarkColors));
      expect(wpLightColors.frame, same(wpLightColors));
      expect(wpDarkColors.frame, same(wpDarkColors));
    });
  });

  test('WpColors reads the activated set', () {
    addTearDown(() => WpColors.activate(wpLightColors));
    WpColors.activate(wpDarkColors);
    expect(WpColors.background, wpDarkColors.background);
    expect(WpColors.current, same(wpDarkColors));
    WpColors.activate(wpNavyColors);
    expect(WpColors.frame.background, wpDarkColors.background);
    expect(WpColors.background, wpLightColors.background);
  });

  group('navy is the renamed brand mode (ticket)', () {
    test('stores as navy and loads a legacy brand value as navy', () {
      expect(AppearanceMode.navy.value, 'navy');
      expect(AppearanceMode.fromValue('brand'), AppearanceMode.navy);
      expect(
        InterfaceSettings.fromMap({'appearance': 'brand'}).appearance,
        AppearanceMode.navy,
      );
    });

    test(
      'navy uses the amber primary record fill, light and dark stay cyan',
      () {
        expect(wpNavyColors.primaryRecordFill, WpPalette.amber400);
        expect(wpLightColors.primaryRecordFill, wpLightColors.action);
        expect(wpDarkColors.primaryRecordFill, wpDarkColors.action);
        expect(wpLightColors.primaryRecordFill, WpPalette.cyan300);
      },
    );
  });

  group('effectiveColorsFor (onboarding stage)', () {
    test('the stage is the navy stage whatever the appearance is', () {
      for (final mode in AppearanceMode.values) {
        for (final platform in Brightness.values) {
          expect(
            effectiveColorsFor(
              onboardingStage: true,
              mode: mode,
              platform: platform,
            ),
            same(wpDarkColors),
            reason: '$mode on $platform',
          );
        }
      }
    });

    test('off the stage the user appearance applies unchanged', () {
      for (final mode in AppearanceMode.values) {
        for (final platform in Brightness.values) {
          expect(
            effectiveColorsFor(
              onboardingStage: false,
              mode: mode,
              platform: platform,
            ),
            same(colorsForAppearance(mode, platform)),
            reason: '$mode on $platform',
          );
        }
      }
    });

    test('the stage palette is dark, so its text tokens are light', () {
      expect(wpDarkColors.brightness, Brightness.dark);
      expect(wpDarkColors.textPrimary.computeLuminance(), greaterThan(0.8));
      expect(wpDarkColors.frame.background, same(wpDarkColors.background));
    });
  });
}
