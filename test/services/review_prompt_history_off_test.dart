/// Rating count while "Aufnahmen speichern" is off (history-off feature).
///
/// With history off no entry is written, so the count must come from a
/// content-free counter of dictations whose paste was confirmed. Entries that
/// exist keep counting as before.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/review_prompt_service.dart';

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        deployChannelProvider.overrideWithValue(DeployChannel.portable),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('history-free dictations count toward the rating threshold', () async {
    final notifier = container.read(reviewPromptProvider.notifier);
    for (var i = 0; i < 3; i++) {
      await notifier.countHistoryFreeDictation();
    }

    final prefs = await SharedPreferences.getInstance();
    expect(await countEligibleRecordings(prefs, db), 3);
  });

  test('the history-free count adds to the entries that exist', () async {
    await db.upsertEntry(
      HistoryEntriesCompanion.insert(
        id: 'entry-1',
        timestamp: DateTime(2026, 10, 1),
      ),
    );
    await container
        .read(reviewPromptProvider.notifier)
        .countHistoryFreeDictation();

    final prefs = await SharedPreferences.getInstance();
    expect(await countEligibleRecordings(prefs, db), 2);
  });
}
