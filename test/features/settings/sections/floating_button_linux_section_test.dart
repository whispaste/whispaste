/// Linux behaviour of the floating-button settings section (PAR-010).
///
/// Covers: the section is visible on Linux; a Wayland session names its limits
/// in the section; an unsupported desktop disables the switch with an
/// explanation; an "on" state that was imported stays switchable off.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/overlay_button_section.dart';
import 'package:whispaste/services/floating_button/floating_button_support.dart';
import 'package:whispaste/services/floating_button/floating_button_support_provider.dart';

import '../../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

const _toggleRow = ValueKey('settings-row-appearance-floating-button');
const _waylandRow = ValueKey('settings-row-appearance-floating-button-wayland');

final _de = lookupL10n(const Locale('de'));

Future<_FakeSettingsNotifier> _pumpLinuxSection(
  WidgetTester tester, {
  required FloatingButtonSupport support,
  required bool showFloatingButton,
}) async {
  final notifier = _FakeSettingsNotifier(
    AppSettings.defaults.copyWithSections(
      overlay: OverlaySettings(showFloatingButton: showFloatingButton),
    ),
  );
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: FloatingButtonSection()),
      locale: const Locale('de'),
      overrides: [
        settingsProvider.overrideWith(() => notifier),
        floatingButtonSupportProvider.overrideWith((ref) async => support),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

// The first switch is the "show floating button" toggle; the look rows below
// it carry further switches.
Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch).first);

// The platform override must be cleared before the test binding checks its
// invariants at the end of the test body, so it is reset in a `finally` here.
void linuxTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  linuxTest('the section is shown on Linux', (tester) async {
    expect(FloatingButtonSection.isSupportedPlatform, isTrue);

    await _pumpLinuxSection(
      tester,
      support: FloatingButtonSupport.full,
      showFloatingButton: false,
    );

    expect(find.byKey(_toggleRow), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });

  linuxTest('a Wayland session names its limits in the section', (
    tester,
  ) async {
    await _pumpLinuxSection(
      tester,
      support: const FloatingButtonSupport(
        available: true,
        limits: {
          FloatingButtonLimit.alwaysOnTop,
          FloatingButtonLimit.freePositioning,
        },
      ),
      showFloatingButton: false,
    );

    expect(find.byKey(_waylandRow), findsOneWidget);
    expect(find.text(_de.settingsFloatingButtonWaylandTitle), findsOneWidget);
    expect(find.text(_de.settingsFloatingButtonWaylandLimit), findsOneWidget);
    // The switch still works on Wayland: the limit is a hint, not a block.
    expect(_switch(tester).onChanged, isNotNull);
  });

  linuxTest('no limit note on X11', (tester) async {
    await _pumpLinuxSection(
      tester,
      support: FloatingButtonSupport.full,
      showFloatingButton: false,
    );

    expect(find.byKey(_waylandRow), findsNothing);
  });

  linuxTest(
    'unsupported desktop: switch disabled with an explanation when off',
    (tester) async {
      await _pumpLinuxSection(
        tester,
        support: FloatingButtonSupport.unavailable,
        showFloatingButton: false,
      );

      expect(_switch(tester).onChanged, isNull);
      expect(find.text(_de.settingsFloatingButtonUnavailable), findsOneWidget);
    },
  );

  linuxTest(
    'unsupported desktop: an imported "on" state can still be turned off',
    (tester) async {
      final notifier = await _pumpLinuxSection(
        tester,
        support: FloatingButtonSupport.unavailable,
        showFloatingButton: true,
      );

      expect(_switch(tester).value, isTrue);
      expect(_switch(tester).onChanged, isNotNull);
      expect(find.text(_de.settingsFloatingButtonUnavailable), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.overlay.showFloatingButton, isFalse);
    },
  );

  linuxTest('supported Linux: an imported "on" state turns off', (
    tester,
  ) async {
    final notifier = await _pumpLinuxSection(
      tester,
      support: FloatingButtonSupport.full,
      showFloatingButton: true,
    );

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(notifier.state.value!.overlay.showFloatingButton, isFalse);
  });
}
