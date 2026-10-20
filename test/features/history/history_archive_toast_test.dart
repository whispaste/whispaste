// UIA-HIS-25: archiving a single entry confirms the move and offers undo.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  testWidgets(
    'archiving one entry shows a confirmation with undo (UIA-HIS-25)',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final l10n = await L10n.delegate.load(const Locale('en'));
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'arch-1',
          timestamp: DateTime(2026, 1, 1, 12),
          content: const Value('archive me'),
          title: const Value('Archive me'),
        ),
      );

      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          locale: const Locale('en'),
          db: db,
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive me').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.ellipsisVertical));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.historyArchive).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.historyArchived), findsWidgets);
      expect(find.text(l10n.historyUndo), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    },
  );
}
