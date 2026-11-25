/// Keeps the registered profile hotkeys in step with the stored profiles and
/// the app hotkeys (ticket 13, part 2). Watch it once, from the app shell.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../hotkey_service.dart';
import '../profile_hotkey_plan.dart';
import 'app_profile.dart';
import 'app_profile_repository.dart';
import '../../core/config/settings_provider.dart';

final _log = AppLogger('ProfileHotkeySync');

/// Favorite languages whose stored hotkey does not work right now (#2137):
/// refused by the plan (combination held by another WhisPaste hotkey or an
/// earlier favorite) or by the OS. The settings row warns under each.
class FavoriteLanguageHotkeyRefusals extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(Set<String> codes) {
    if (setEquals(codes, state)) return;
    state = Set.unmodifiable(codes);
  }
}

final favoriteLanguageHotkeyRefusalsProvider =
    NotifierProvider<FavoriteLanguageHotkeyRefusals, Set<String>>(
      FavoriteLanguageHotkeyRefusals.new,
    );

/// Re-plans and re-syncs the profile hotkeys and the favorite-language
/// hotkeys (#2137) whenever the profile list or the settings change.
/// Unchanged hotkeys are not registered again.
///
/// Order: the languages first, so a removed language key is free before a
/// profile asks for it; then the profiles; then the languages once more when
/// the OS refused one, because a profile that yields to a new language key
/// frees it only in the profile step.
final profileHotkeySyncProvider = Provider<void>((ref) {
  Future<Set<String>> syncLanguages(AppSettings settings) => ref
      .read(hotkeyServiceProvider.notifier)
      .syncFavoriteLanguageHotkeys(
        planFavoriteLanguageHotkeys(settings).entries,
      );

  Future<void> sync() async {
    final profiles = ref.read(appProfilesProvider).value;
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    var languagesRefused = await syncLanguages(settings);
    if (profiles != null) {
      final plan = planProfileHotkeys(
        profiles: profiles,
        reserved: reservedHotkeysOf(settings),
      );
      final refused = await ref
          .read(hotkeyServiceProvider.notifier)
          .syncProfileHotkeys(plan.entries);
      if (refused.isNotEmpty || plan.refusedIds.isNotEmpty) {
        _log.warning(
          'Profile hotkeys refused: ${{...plan.refusedIds, ...refused}}',
        );
      }
    }
    if (languagesRefused.isNotEmpty) {
      languagesRefused = await syncLanguages(settings);
    }
    final planRefused = planFavoriteLanguageHotkeys(settings).refusedCodes;
    ref.read(favoriteLanguageHotkeyRefusalsProvider.notifier).set({
      ...planRefused,
      ...languagesRefused,
    });
    if (languagesRefused.isNotEmpty || planRefused.isNotEmpty) {
      _log.warning(
        'Favorite-language hotkeys refused: '
        '${{...planRefused, ...languagesRefused}}',
      );
    }
  }

  ref.listen<AsyncValue<List<AppProfile>>>(appProfilesProvider, (_, _) {
    unawaited(sync());
  });
  ref.listen(settingsProvider, (_, _) => unawaited(sync()));
  unawaited(sync());
});
