/// One-time offer of the macOS Input Monitoring permission for a key
/// combination (#807). Without that permission the app cannot read whether
/// the combination's key is still down, so a lost release (#791) leaves a
/// hold-to-talk recording running until the next press. The offer comes only
/// after that happened once, explains itself before the system prompt, and is
/// never repeated: a decline or an ignored card stays final.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import 'hotkey_observer_health.dart';
import 'modifier_key_monitor.dart';

/// The host that reports and requests the Input Monitoring permission.
/// Overridden in tests.
final inputMonitoringMonitorProvider = Provider<ModifierKeyMonitor>(
  (ref) => ModifierKeyMonitor(),
);

/// Holds the offer's due flag. The UI takes it, shows the explanation and
/// calls [consume], which records the offer for good.
class InputMonitoringOfferNotifier extends Notifier<bool> {
  bool _checking = false;

  @override
  bool build() => false;

  /// A key combination's release got lost on macOS: a new press came while
  /// the previous one still counted as held. Offers the permission when it is
  /// missing, the offer was never made and [holdModeOn] (only a hold can hang
  /// a recording this way). A request that does not qualify uses nothing up.
  Future<void> releaseLost({required bool holdModeOn}) async {
    if (!holdModeOn || state || _checking) return;
    if (_offered()) return;
    _checking = true;
    try {
      final health = await ref.read(inputMonitoringMonitorProvider).health();
      // Only a clear "not granted" counts; an unknown answer is no reason to
      // bother the user.
      if (health != ObserverHealth.permissionRevoked || _offered()) return;
      state = true;
    } finally {
      _checking = false;
    }
  }

  /// The UI has shown the offer. Records it, so it never comes again.
  Future<void> consume() async {
    state = false;
    if (_offered()) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(inputMonitoringOffered: true),
          ),
        );
  }

  /// The offer could not be shown now (onboarding is on screen). Nothing is
  /// recorded, so the next lost release offers it again.
  void postpone() => state = false;

  /// The user accepted the explanation: shows the system prompt.
  Future<bool> accept() =>
      ref.read(inputMonitoringMonitorProvider).requestAccess();

  bool _offered() =>
      ref.read(settingsProvider).value?.onboarding.inputMonitoringOffered ??
      true;
}

final inputMonitoringOfferProvider =
    NotifierProvider<InputMonitoringOfferNotifier, bool>(
      InputMonitoringOfferNotifier.new,
    );
