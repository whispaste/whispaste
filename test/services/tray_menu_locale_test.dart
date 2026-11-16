/// Regression test for the tray menu language: the menu used to stay in
/// English until the first recording-state change, because the labels were
/// only localized inside `updateRecordingState(l10n:)`. It also kept the old
/// language after a change in Settings. The menu must follow the locale from
/// start and on every language change, without a recording state change.
library;

import 'dart:ui' show Locale;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/tcc_entry_reset_confirm.dart';
import 'package:whispaste/services/support/support_state.dart';
import 'package:whispaste/services/tray_service.dart';
import '../test_helpers/test_deadline.dart';

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

/// Download state without the disk scan of the real notifier.
class _NoDownloads extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

/// Everything the tray menu reads that would otherwise load from disk or a
/// store: an in-memory history database, no download scan, no store query.
/// Without disk I/O a late rebuild can only come from microtasks and
/// zero-delay timers, which [_settle] drains without a fixed wait (#1491).
List<Override> _noDiskIo(_LocaleSettingsNotifier notifier) => [
  settingsProvider.overrideWith(() => notifier),
  historyDatabaseProvider.overrideWith((ref) {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    ref.onDispose(db.close);
    return db;
  }),
  modelDownloadProvider.overrideWith(_NoDownloads.new),
  supportStoreTipAvailableProvider.overrideWith((ref) async => false),
];

/// Lets the async notifier, the tray's listeners and the channel round trips
/// of pending menu rebuilds finish: returns once [count] has stayed unchanged
/// for a number of event-loop turns. A rebuild that lands late would
/// otherwise be counted as a second one.
Future<void> _settle(int Function() count) async {
  var last = count();
  var quietTicks = 0;
  final deadline = TestDeadline(const Duration(seconds: 5));
  while (quietTicks < 20 && !deadline.expired) {
    await pumpEventQueue(times: 1);
    final now = count();
    quietTicks = now == last ? quietTicks + 1 : 0;
    last = now;
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
    final container = ProviderContainer(overrides: _noDiskIo(notifier));
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle(() => menus.length);

    expect(menus, isNotEmpty, reason: 'the tray menu must be built at start');
    expect(menus.last, anyElement(startsWith(de.trayStartRecording)));
    expect(menus.last, anyElement(startsWith(de.traySettings)));
    expect(menus.last, isNot(anyElement(startsWith(en.traySettings))));
  });

  test('updateLocalizations rebuilds the menu once in the new language, '
      'without a recording state change', () async {
    final notifier = _LocaleSettingsNotifier('de');
    final container = ProviderContainer(overrides: _noDiskIo(notifier));
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle(() => menus.length);
    expect(menus.last, anyElement(startsWith(de.traySettings)));

    // ServiceBootstrap forwards each locale change to the tray; this is the
    // call it makes, so the tray must rebuild once in the new language.
    final rebuildsBefore = menus.length;
    notifier.setLocale('en');
    await _settle(() => menus.length);
    tray.updateLocalizations(l10nForLocaleCode('en'));
    await _settle(() => menus.length);

    expect(
      menus.length,
      rebuildsBefore + 1,
      reason: 'one language change must rebuild the menu exactly once',
    );
    expect(menus.last, anyElement(startsWith(en.trayStartRecording)));
    expect(menus.last, anyElement(startsWith(en.traySettings)));
    expect(menus.last, isNot(anyElement(startsWith(de.traySettings))));
  });
  test('a recording-state update without a language keeps the chosen language '
      '(UIA-SHL-16)', () async {
    final notifier = _LocaleSettingsNotifier('de');
    final container = ProviderContainer(overrides: _noDiskIo(notifier));
    addTearDown(container.dispose);

    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle(() => menus.length);

    tray.updateRecordingState(
      const RecordingState(phase: RecordingPhase.recording),
    );
    await _settle(() => menus.length);

    expect(menus.last, anyElement(startsWith(de.trayStopRecording)));
    expect(menus.last, isNot(anyElement(startsWith(en.trayStopRecording))));
  });
}
