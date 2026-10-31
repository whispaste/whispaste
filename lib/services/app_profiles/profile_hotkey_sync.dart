/// Keeps the registered profile hotkeys in step with the stored profiles and
/// the app hotkeys (ticket 13, part 2). Watch it once, from the app shell.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../hotkey_service.dart';
import '../profile_hotkey_plan.dart';
import 'app_profile.dart';
import 'app_profile_repository.dart';
import '../../core/config/settings_provider.dart';

final _log = AppLogger('ProfileHotkeySync');

/// Re-plans and re-syncs the profile hotkeys whenever the profile list or the
/// settings change. Unchanged hotkeys are not registered again.
final profileHotkeySyncProvider = Provider<void>((ref) {
  Future<void> sync() async {
    final profiles = ref.read(appProfilesProvider).value;
    final settings = ref.read(settingsProvider).value;
    if (profiles == null || settings == null) return;
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

  ref.listen<AsyncValue<List<AppProfile>>>(appProfilesProvider, (_, _) {
    unawaited(sync());
  });
  ref.listen(settingsProvider, (_, _) => unawaited(sync()));
  unawaited(sync());
});
