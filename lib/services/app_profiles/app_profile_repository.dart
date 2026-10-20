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

  /// Creates [profile], or replaces the stored profile with the same id (a
  /// rename or any other field edit). A new profile goes to the end of the
  /// list; an existing one keeps its position and creation time.
  Future<void> save(AppProfile profile) async {
    final db = ref.read(historyDatabaseProvider);
    final rows = await db.readAppProfiles();
    final existing = rows.where((row) => row.id == profile.id).firstOrNull;
    final now = DateTime.now().toUtc();
    final position = existing?.position ?? _nextPosition(rows);
    await db.saveAppProfile(
      appProfileToCompanion(
        profile,
        position: position,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
      appProfileRulesToCompanions(profile),
    );
    await _reload();
  }

  /// Removes the profile [id] and its rules. A missing id changes nothing.
  Future<void> delete(String id) async {
    await ref.read(historyDatabaseProvider).deleteAppProfile(id);
    await _reload();
  }

  /// Stores [orderedIds] as the new list order. Ids listed here come first in
  /// the given order; profiles not listed keep their relative order after
  /// them, so a stale list never drops a profile.
  Future<void> reorder(List<String> orderedIds) async {
    final db = ref.read(historyDatabaseProvider);
    final rows = await db.readAppProfiles();
    final profiles = appProfilesFromRows(rows, await db.readAppProfileRules());
    final byId = {for (final profile in profiles) profile.id: profile};
    final rowById = {for (final row in rows) row.id: row};
    final listed = orderedIds.where(byId.containsKey).toList();
    final order = [
      ...listed,
      for (final profile in profiles)
        if (!listed.contains(profile.id)) profile.id,
    ];
    final now = DateTime.now().toUtc();
    for (var i = 0; i < order.length; i++) {
      final profile = byId[order[i]]!;
      await db.saveAppProfile(
        appProfileToCompanion(
          profile,
          position: i,
          createdAt: rowById[profile.id]!.createdAt,
          updatedAt: now,
        ),
        appProfileRulesToCompanions(profile),
      );
    }
    await _reload();
  }

  Future<void> _reload() async {
    state = AsyncData(await _read());
  }

  int _nextPosition(List<AppProfileRow> rows) {
    if (rows.isEmpty) return 0;
    return rows.map((row) => row.position).reduce((a, b) => a > b ? a : b) + 1;
  }
}

final appProfilesProvider =
    AsyncNotifierProvider<AppProfilesController, List<AppProfile>>(
      AppProfilesController.new,
    );
