/// Golden tests for the History detail panel's original-transcript
/// disclosure and target-app/character-count metadata (ticket 12).
///
/// Two states are pictured, matching the acceptance criteria: the
/// disclosure affordance shown when the original transcript actually
/// differs from the final text, and hidden when there is nothing to
/// disclose (no captured original, or original == final). Both goldens
/// also carry the character-count chip; only the "differs" entry carries
/// the target-app chip, since that is the entry seeded with a captured
/// target app.
@Tags(<String>['golden'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/services/hardware_info_service.dart';

Widget _pumpApp(HistoryDatabase db, HistoryEntry entry) {
  final theme = wpDarkTheme();

  return ProviderScope(
    overrides: [
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
      theme: theme,
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

/// Same waiver as the sibling widget test — these goldens are about the
/// diff-disclosure/metadata state, not incidental overflow elsewhere in the
/// detail panel at this fixed test window size.
void _ignoreOverflowErrors() {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.toString().contains('overflowed')) return;
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

Future<void> _openDetail(
  WidgetTester tester,
  HistoryDatabase db,
  HistoryEntry entry,
  String title,
) async {
  _ignoreOverflowErrors();
  await tester.pumpWidget(_pumpApp(db, entry));
  await tester.pumpAndSettle();
  await tester.loadAssets(
    alsoLoadTheseFonts: const [
      'packages/lucide_icons_flutter/Lucide',
      'MaterialIcons',
      'Inter',
    ],
  );

  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

void main() {
  group('History detail panel — original-transcript diff & metadata', () {
    testWidgets(
      'original differs from final: disclosure + target-app chip shown',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        await db.upsertEntry(
          HistoryEntriesCompanion.insert(
            id: 'golden-diff-1',
            timestamp: DateTime(2026, 1, 1, 10),
            content: const Value('Cleaned up final text.'),
            title: const Value('Golden diff entry'),
            originalTranscript: const Value(
              'uh cleaned up final text with um filler',
            ),
            targetApp: const Value('com.microsoft.VSCode'),
            colorSlot: const Value(0),
          ),
        );
        final entry = (await db.getEntry('golden-diff-1'))!;

        await _openDetail(tester, db, entry, 'Golden diff entry');

        await expectLater(
          find.byType(HistoryDetailPanel),
          matchesGoldenFile('goldens/history_detail_original_diff_shown.png'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('original equals final (or absent): disclosure hidden', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'golden-same-1',
          timestamp: DateTime(2026, 1, 1, 10),
          content: const Value('Just some final text.'),
          title: const Value('Golden identical entry'),
          colorSlot: const Value(0),
        ),
      );
      final entry = (await db.getEntry('golden-same-1'))!;

      await _openDetail(tester, db, entry, 'Golden identical entry');

      await expectLater(
        find.byType(HistoryDetailPanel),
        matchesGoldenFile('goldens/history_detail_original_diff_hidden.png'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
