/// The stored app profiles, as one live list (ticket 13, part 2).
///
/// The tray, the overlay, the hotkeys and the Settings section all read this
/// provider, so a save, rename, delete or reorder shows everywhere at once
/// without a restart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import 'app_profile.dart';
import 'app_profile_storage.dart';

/// The profiles in stored order. Writes are added with the Settings section.
class AppProfilesController extends AsyncNotifier<List<AppProfile>> {
  @override
  Future<List<AppProfile>> build() => _read();

  Future<List<AppProfile>> _read() async {
    final db = ref.watch(historyDatabaseProvider);
    return appProfilesFromRows(
      await db.readAppProfiles(),
      await db.readAppProfileRules(),
    );
  }
}

final appProfilesProvider =
    AsyncNotifierProvider<AppProfilesController, List<AppProfile>>(
      AppProfilesController.new,
    );
