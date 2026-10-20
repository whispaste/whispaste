/// Overlay position on the appearance page (UIA-ONB-07): the dropdown offers
/// "Off" like Settings does, shows it while the overlay is off, and a
/// position choice is the visible way to turn the overlay on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/appearance_step.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this.current);

  AppSettings current;

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    current = updater(state.value ?? current);
    state = AsyncData(current);
  }
}

const _prefix = kAppearanceStepOverlayPositionDropdownId;

Future<_FakeSettingsNotifier> _pump(
  WidgetTester tester,
  AppSettings settings,
) async {
  final fake = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const Scaffold(body: SingleChildScrollView(child: AppearanceStep())),
      overrides: [settingsProvider.overrideWith(() => fake)],
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _choose(WidgetTester tester, String value) async {
  await tester.tap(find.byKey(const ValueKey<String>(_prefix)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('$_prefix-item-$value')).last);
  await tester.pumpAndSettle();
}

void main() {
  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('with the overlay off the position reads "Off", and picking a '
      'position turns the overlay on', (tester) async {
    final fake = await _pump(
      tester,
      AppSettings.defaults.copyWith(overlayMode: OverlayMode.off.value),
    );
    final dropdown = find.byKey(const ValueKey<String>(_prefix));
    expect(
      find.descendant(of: dropdown, matching: find.text(l10n.settingsOff)),
      findsOneWidget,
    );

    await _choose(tester, OverlayStartPosition.bottomCenter.value);

    expect(fake.current.effectiveOverlayMode, OverlayMode.floating);
    expect(
      fake.current.overlayStartPositionType,
      OverlayStartPosition.bottomCenter,
    );
  });

  testWidgets('"Off" turns the overlay off without losing the position', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      AppSettings.defaults.copyWith(
        overlayMode: OverlayMode.floating.value,
        overlayStartPosition: OverlayStartPosition.bottomCenter.value,
      ),
    );

    await _choose(tester, OverlayStartPosition.off.value);

    expect(fake.current.effectiveOverlayMode, OverlayMode.off);
    expect(
      fake.current.overlayStartPositionType,
      OverlayStartPosition.bottomCenter,
    );
  });
}
