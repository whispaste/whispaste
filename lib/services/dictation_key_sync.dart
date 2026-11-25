/// Keeps the registered extra dictation keys (#2055) in step with the
/// settings. Watch it once, from the service bootstrap.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'dictation_key_plan.dart';
import 'hotkey_service.dart';
import 'profile_hotkey_plan.dart' show hotkeysBeforeDictationKeysOf;

final _log = AppLogger('DictationKeySync');

/// The plan for the current settings: which extra keys register and which
/// the app itself refuses (no modifier, unknown language, a combination
/// another hotkey holds). Settings reads it for the notices at each key.
final dictationKeyPlanProvider = Provider<DictationKeyPlan>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  return planDictationKeys(
    keys: settings.hotkey.extraDictationKeys,
    reserved: hotkeysBeforeDictationKeysOf(settings),
  );
});

/// Re-syncs the registered extra keys whenever the settings change.
/// Unchanged keys are not registered again; without extra keys nothing is
/// registered at all.
final dictationKeySyncProvider = Provider<void>((ref) {
  var running = Future<void>.value();
  Future<void> sync() async {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    final plan = ref.read(dictationKeyPlanProvider);
    final refused = await ref
        .read(hotkeyServiceProvider.notifier)
        .syncDictationKeys(plan.entries);
    if (refused.isNotEmpty || plan.refusedIds.isNotEmpty) {
      _log.warning(
        'Dictation keys refused: ${{...plan.refusedIds, ...refused}}',
      );
    }
  }

  // One sync at a time, in order: two quick settings writes must not
  // register the same key twice.
  void schedule() {
    running = running.then((_) => sync()).catchError((Object e) {
      _log.warning('Dictation key sync failed: $e');
    });
  }

  ref.listen(settingsProvider, (_, _) => schedule());
  schedule();
});
