// UIA-HIS-02: a transcript edit that is still open when another entry is
// selected is saved to the entry it was made on, not thrown away.
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

import '../../fixtures/test_helpers.dart';

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
  testWidgets('an unsaved transcript edit is saved to its entry when another '
      'entry is selected (UIA-HIS-02)', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final alpha = HistoryEntriesCompanion.insert(
      id: 'switch-a',
      timestamp: DateTime(2026, 1, 1, 10),
      content: const Value('alpha original'),
      title: const Value('Alpha entry'),
    );
    final beta = HistoryEntriesCompanion.insert(
      id: 'switch-b',
      timestamp: DateTime(2026, 1, 1, 9),
      content: const Value('beta original'),
      title: const Value('Beta entry'),
    );
    await db.insertHistoryEntry(alpha);
    await db.insertHistoryEntry(beta);
    final entries = await db.select(db.historyEntries).get();

    await tester.pumpWidget(_pumpApp(db, entries));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha entry').first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(primaryShortcutModifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(primaryShortcutModifier);
    await tester.pumpAndSettle();

    final editor = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == 'alpha original',
    );
    await tester.enterText(editor, 'alpha corrected');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beta entry').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    final saved = await db.getEntry('switch-a');
    expect(saved!.content, 'alpha corrected');
    final untouched = await db.getEntry('switch-b');
    expect(untouched!.content, 'beta original');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
