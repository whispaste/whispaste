// UIA-HIS-10: a failing database search must surface as an error, not as an
// empty result that the UI reports as "No results".
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart';

class _BrokenSearchDb extends HistoryDatabase {
  _BrokenSearchDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<List<HistoryEntry>> searchEntriesAdvanced({
    String freeText = '',
    List<String> tagNames = const [],
    String? langCode,
    bool includeDeleted = false,
    bool includeArchived = false,
  }) {
    throw StateError('fts broke');
  }
}

void main() {
  test(
    'a failing search reports AsyncError instead of an empty list (UIA-HIS-10)',
    () async {
      final db = _BrokenSearchDb();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      container.read(historySearchProvider.notifier).set('#work');
      final sub = container.listen(filteredHistoryProvider, (_, _) {});
      addTearDown(sub.close);
      // Let the advanced search future settle (it fails immediately).
      for (var i = 0; i < 20 && sub.read().isLoading; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(sub.read(), isA<AsyncError<List<HistoryEntry>>>());
    },
  );
}
