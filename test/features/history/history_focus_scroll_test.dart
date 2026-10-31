// UIA-HIS-04: the keyboard-focused entry stays on screen, so Enter never acts
// on a row the user cannot see.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/hardware_info_service.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

Widget _pumpApp(HistoryDatabase db, List<HistoryEntry> entries) {
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
      gpuInfoProvider.overrideWith(
        (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
      historyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
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
  );
}

void main() {
  testWidgets('arrowing past the visible rows scrolls the focused entry into '
      'view (UIA-HIS-04)', (tester) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (var i = 0; i < 40; i++) {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'scroll-$i',
          timestamp: DateTime(2026, 1, 1, 12).subtract(Duration(minutes: i)),
          content: Value('text $i'),
          title: Value('Entry ${i.toString().padLeft(2, '0')}'),
        ),
      );
    }
    final entries = await db.select(db.historyEntries).get();

    await tester.pumpWidget(_pumpApp(db, entries));
    await tester.pumpAndSettle();

    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final focused = find.text('Entry 30');
    expect(focused.hitTestable(), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
