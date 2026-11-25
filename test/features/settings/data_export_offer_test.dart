// Regular offer to export recordings and dictionary (#1023): the rule, the
// files it writes and the dialog with its testIDs.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/settings/data_export_offer.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/nudge_gate_open.dart';
import '../../test_helpers/pump_until.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

AppSettings _settings({required bool onboarded}) =>
    AppSettings.defaults.copyWithSections(
      onboarding: OnboardingSettings.defaults.copyWith(
        onboardingCompleted: onboarded,
      ),
    );

HistoryDatabase _memoryDb() => HistoryDatabase.forTesting(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

Future<void> _seed(HistoryDatabase db, DateTime now) async {
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'active',
      timestamp: now,
      content: const Value('first dictation'),
    ),
  );
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'archived',
      timestamp: now,
      content: const Value('archived dictation'),
      archived: const Value(true),
    ),
  );
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'trashed',
      timestamp: now,
      content: const Value('trashed dictation'),
      deletedAt: Value(now),
    ),
  );
  await db.writeReplacements([
    ReplacementWrite(
      id: 'r1',
      triggers: const ['kubernetis'],
      replacement: 'Kubernetes',
      createdAt: now,
    ),
  ]);
}

void main() {
  final now = DateTime.utc(2026, 11, 23, 12);

  group('decideDataExportOffer', () {
    test('nothing to lose, nothing to ask', () {
      expect(
        decideDataExportOffer(now: now, hasData: false),
        DataExportOfferStep.wait,
      );
    });

    test('the first check only starts the clock', () {
      expect(
        decideDataExportOffer(now: now, hasData: true),
        DataExportOfferStep.startClock,
      );
    });

    test('asks once the interval since the last offer or export passed', () {
      final recent = now.subtract(const Duration(days: 3));
      final old = now.subtract(kDataExportOfferInterval);
      expect(
        decideDataExportOffer(now: now, hasData: true, offeredAt: recent),
        DataExportOfferStep.wait,
      );
      expect(
        decideDataExportOffer(now: now, hasData: true, offeredAt: old),
        DataExportOfferStep.offer,
      );
      // An export restarts the interval, whichever is later counts.
      expect(
        decideDataExportOffer(
          now: now,
          hasData: true,
          offeredAt: old,
          exportedAt: recent,
        ),
        DataExportOfferStep.wait,
      );
      expect(
        decideDataExportOffer(now: now, hasData: true, exportedAt: old),
        DataExportOfferStep.offer,
      );
    });
  });

  test('the export writes recordings and dictionary, not the trash', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    await _seed(db, now);
    final dir = Directory.systemTemp.createTempSync('wp_data_export_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final result = await exportRecordingsAndDictionary(db, dir.path, now: now);

    expect(result.recordings, 2);
    expect(result.dictionaryEntries, 1);
    final names = dataExportFileNames(now);
    final json = File(p.join(dir.path, names.recordings)).readAsStringSync();
    expect(json, contains('first dictation'));
    expect(json, contains('archived dictation'));
    expect(json, isNot(contains('trashed dictation')));
    expect(() => jsonDecode(json), returnsNormally);
    final csv = File(p.join(dir.path, names.dictionary)).readAsStringSync();
    expect(csv, contains('kubernetis'));
    expect(csv, contains('Kubernetes'));
  });

  group('the offer dialog', () {
    Future<HistoryDatabase> pump(
      WidgetTester tester, {
      required bool onboarded,
      String? offeredAt,
      Future<String?> Function()? pickFolder,
    }) async {
      final db = _memoryDb();
      await tester.runAsync(() async {
        await _seed(db, now);
        if (offeredAt != null) {
          await db.writeAppSetting(dataExportOfferedAtKey, offeredAt);
        }
      });
      await tester.pumpWidget(
        makeTestable(
          const DataExportOfferWatcher(),
          db: db,
          locale: const Locale('en'),
          noticeBar: true,
          overrides: [
            nudgeGateOpenOverride(),
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(_settings(onboarded: onboarded)),
            ),
            dataExportClockProvider.overrideWithValue(() => now),
            dataExportFolderPickerProvider.overrideWithValue(
              pickFolder ?? () async => null,
            ),
          ],
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      return db;
    }

    final due = now
        .subtract(kDataExportOfferInterval)
        .toUtc()
        .toIso8601String();

    // Disposes the watcher, which cancels its periodic re-check.
    Future<void> unmount(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox.shrink());

    Finder byId(String id) => find.bySemanticsIdentifier(id);

    testWidgets('is due: offers export and "Later" records the offer', (
      tester,
    ) async {
      final db = await pump(tester, onboarded: true, offeredAt: due);

      expect(byId('data-export-offer-body'), findsOneWidget);
      await tester.tap(byId('data-export-offer-later'));
      await tester.pumpAndSettle();

      expect(byId('data-export-offer-body'), findsNothing);
      final stamped = await tester.runAsync(
        () => db.readAppSetting(dataExportOfferedAtKey),
      );
      expect(DateTime.parse(stamped!), now);
      expect(
        await tester.runAsync(() => db.readAppSetting(dataExportDoneAtKey)),
        isNull,
      );
      await unmount(tester);
    });

    testWidgets('"Export" writes the files into the chosen folder', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('wp_data_export_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = await pump(
        tester,
        onboarded: true,
        offeredAt: due,
        pickFolder: () async => dir.path,
      );

      await tester.tap(byId('data-export-offer-export'));
      final names = dataExportFileNames(now);
      // The dialog says "done" only after the files and the done mark.
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('data-export-offer-done'))
            .evaluate()
            .isNotEmpty,
        what: 'the export done state',
      );

      expect(File(p.join(dir.path, names.recordings)).existsSync(), isTrue);
      expect(File(p.join(dir.path, names.dictionary)).existsSync(), isTrue);
      expect(
        await tester.runAsync(() => db.readAppSetting(dataExportDoneAtKey)),
        isNotNull,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('data-export-offer-done')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 30));
      await unmount(tester);
    });

    testWidgets('a first check starts the clock without asking', (
      tester,
    ) async {
      final db = await pump(tester, onboarded: true);

      expect(byId('data-export-offer-body'), findsNothing);
      expect(
        await tester.runAsync(() => db.readAppSetting(dataExportOfferedAtKey)),
        isNotNull,
      );
      await unmount(tester);
    });

    testWidgets('never during the onboarding', (tester) async {
      final db = await pump(tester, onboarded: false, offeredAt: due);

      expect(byId('data-export-offer-body'), findsNothing);
      expect(
        await tester.runAsync(() => db.readAppSetting(dataExportOfferedAtKey)),
        due,
      );
      await unmount(tester);
    });
  });
}
