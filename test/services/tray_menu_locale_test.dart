/// Regression test for the tray menu language: the menu used to stay in
/// English until the first recording-state change, because the labels were
/// only localized inside `updateRecordingState(l10n:)`. It also kept the old
/// language after a change in Settings. The menu must follow the locale from
/// start and on every language change, without a recording state change.
library;

import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/permissions/tcc_entry_reset_confirm.dart';
import 'package:whispaste/services/tray_service.dart';

class _LocaleSettingsNotifier extends SettingsNotifier {
  _LocaleSettingsNotifier(this._locale);

  String _locale;

  @override
  Future<AppSettings> build() async =>
      AppSettings(interface_: InterfaceSettings(locale: _locale));

  void setLocale(String code) {
    _locale = code;
    state = AsyncData(AppSettings(interface_: InterfaceSettings(locale: code)));
  }
}

/// Lets the async notifier and the tray's listener run to completion.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tray_manager');
  final de = lookupL10n(const Locale('de'));
  final en = lookupL10n(const Locale('en'));

  late List<List<String>> menus;

  setUp(() {
    menus = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setContextMenu') {
            final arguments = call.arguments as Map<Object?, Object?>;
            final menu = arguments['menu'] as Map<Object?, Object?>;
            final items = menu['items'] as List<Object?>;
            menus.add([
              for (final item in items)
                if (item is Map<Object?, Object?>) item['label'] as String,
            ]);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('tray menu is in the chosen language from start, before any '
      'recording', () async {
    final notifier = _LocaleSettingsNotifier('de');
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle();

    expect(menus, isNotEmpty, reason: 'the tray menu must be built at start');
    expect(menus.last, contains(de.trayStartRecording));
    expect(menus.last, contains(de.traySettings));
    expect(menus.last, isNot(contains(en.traySettings)));
  });

  test('updateLocalizations rebuilds the menu once in the new language, '
      'without a recording state change', () async {
    final notifier = _LocaleSettingsNotifier('de');
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle();
    expect(menus.last, contains(de.traySettings));

    // ServiceBootstrap forwards each locale change to the tray; this is the
    // call it makes, so the tray must rebuild once in the new language.
    final rebuildsBefore = menus.length;
    notifier.setLocale('en');
    await _settle();
    tray.updateLocalizations(l10nForLocaleCode('en'));
    await _settle();

    expect(
      menus.length,
      rebuildsBefore + 1,
      reason: 'one language change must rebuild the menu exactly once',
    );
    expect(menus.last, contains(en.trayStartRecording));
    expect(menus.last, contains(en.traySettings));
    expect(menus.last, isNot(contains(de.traySettings)));
  });
  test('a recording-state update without a language keeps the chosen language '
      '(UIA-SHL-16)', () async {
    final notifier = _LocaleSettingsNotifier('de');
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle();

    tray.updateRecordingState(
      const RecordingState(phase: RecordingPhase.recording),
    );
    await _settle();

    expect(menus.last, contains(de.trayStopRecording));
    expect(menus.last, isNot(contains(en.trayStopRecording)));
  });
}
