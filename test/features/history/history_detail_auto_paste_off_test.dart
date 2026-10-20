/// The detail overflow menu offers "Turn off auto-paste in this app" for a
/// recording whose target app is known and not yet on the block list.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/hardware_info_service.dart';

late L10n l10n;

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

AppSettings _settingsWithBlocklist(String blocklist) =>
    AppSettings.defaults.copyWithSections(
      behavior: AppSettings.defaults.behavior.copyWith(
        autoPasteBlocklist: blocklist,
      ),
    );

Future<void> _pumpDetail(
  WidgetTester tester, {
  required HistoryDatabase db,
  required HistoryEntry entry,
  required _FakeSettingsNotifier settings,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => settings),
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        gpuInfoProvider.overrideWith(
          (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
        ),
        historyEntriesProvider.overrideWith((ref) => Stream.value([entry])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: wpDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(size: Size(1800, 900)),
          child: Scaffold(body: HistoryPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Target entry').first);
  await tester.pumpAndSettle();
}

/// Lets toasts and other timers finish, then tears the page down. Riverpod
/// disposes the drift stream providers during that teardown, and drift then
/// starts a zero-duration timer to close each stream (framework-owned, not
/// app code; verified with a zone probe). Short pumps after the close flush it
/// before the test ends.
Future<void> _disposeDetail(WidgetTester tester, HistoryDatabase db) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
  await db.close();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

Future<HistoryEntry> _insertEntry(HistoryDatabase db, String? targetApp) async {
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'target-entry',
      timestamp: DateTime(2026, 10, 1, 10),
      content: const Value('Some dictated text.'),
      title: const Value('Target entry'),
      targetApp: Value(targetApp),
    ),
  );
  return (await db.getEntry('target-entry'))!;
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('a known, unlisted target app is offered and gets blocked', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final entry = await _insertEntry(db, 'notepad');
    final settings = _FakeSettingsNotifier(_settingsWithBlocklist(''));

    await _pumpDetail(tester, db: db, entry: entry, settings: settings);
    await tester.tap(find.byKey(const ValueKey('history-detail-menu')));
    await tester.pumpAndSettle();

    final item = find.byKey(
      const ValueKey('history-detail-menu-auto-paste-off'),
    );
    expect(item, findsOneWidget);
    expect(find.text(l10n.historyAutoPasteOffForApp), findsOneWidget);

    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(settings.state.value!.behavior.autoPasteBlocklist, 'notepad');
    await _disposeDetail(tester, db);
  });

  testWidgets('no target app means no auto-paste item', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final entry = await _insertEntry(db, null);
    final settings = _FakeSettingsNotifier(_settingsWithBlocklist(''));

    await _pumpDetail(tester, db: db, entry: entry, settings: settings);
    await tester.tap(find.byKey(const ValueKey('history-detail-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('history-detail-menu-auto-paste-off')),
      findsNothing,
    );
    await _disposeDetail(tester, db);
  });

  testWidgets('an app that is already blocked is not offered again', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final entry = await _insertEntry(db, 'Notepad.exe');
    final settings = _FakeSettingsNotifier(_settingsWithBlocklist('notepad'));

    await _pumpDetail(tester, db: db, entry: entry, settings: settings);
    await tester.tap(find.byKey(const ValueKey('history-detail-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('history-detail-menu-auto-paste-off')),
      findsNothing,
    );
    await _disposeDetail(tester, db);
  });
}
