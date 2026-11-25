/// Consent flow in front of the data key (#1071).
///
/// [DataKeyStore.obtain] may open a system prompt (macOS keychain, a locked
/// Linux keyring; Windows keeps the key in a DPAPI file and never asks, see
/// #1130). That prompt must never come
/// out of nowhere: the app first explains what the key protects, that it
/// stays on the device and what declining means, and only a deliberate tap
/// ([DataKeyAccessNotifier.request]) lets the prompt appear.
///
/// - New installations see the explanation as a card on the last onboarding
///   page.
/// - Existing users who finished onboarding earlier get the same explanation
///   once as a dialog (`DataKeyExplanationWatcher`).
/// - Settings → Privacy always shows the status and the way to allow again.
///
/// Code that needs the key (#1020, #1021) goes through
/// [dataKeyAccessProvider] and never calls [DataKeyStore.obtain] before
/// [OnboardingSettings.dataKeyExplained] is set.
library;

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/automation_api/automation_api_token_store.dart'
    show automationApiTokenKey, automationWriteTokenKey;
import '../../services/feedback_consent_store.dart' show kSecureConsentStateKey;
import 'data_key_store.dart';
import 'keychain_migration.dart';
import 'secure_access_gate.dart';
import 'secure_key_store.dart';
import 'settings_provider.dart';

export 'data_key_store.dart' show dataKeyStoreProvider;

/// Every secure-storage entry the old-keychain move looks at (#1163).
final legacyMigrationKeys = <String>[
  dataKeyStorageName,
  ...allSecureKeys,
  automationApiTokenKey,
  automationWriteTokenKey,
  kSecureConsentStateKey,
];

/// The old-keychain move of this build, or null where there is nothing to
/// move (no macOS access group: the login keychain is the only keychain).
final keychainMigrationProvider = FutureProvider<KeychainMigration?>((
  ref,
) async {
  if (!Platform.isMacOS) return null;
  final storages = await resolveDefaultSecureStorages();
  final legacy = storages.legacy;
  final quiet = platformQuietReader();
  if (legacy == null || quiet == null) return null;
  final store = ref.read(dataKeyStoreProvider);
  return KeychainMigration(
    legacy: legacy,
    primary: storages.primary,
    quietReader: quiet,
    // Reads after consent and deletes go through the same file-keychain
    // query as the quiet reader, never the plugin storage (#1674).
    oldKeychain: platformOldKeychain(),
    keys: legacyMigrationKeys,
    // The old data key only moves when it is the one the marker fingerprints.
    repairKeys: {dataKeyStorageName},
    verify: (key, value) =>
        key != dataKeyStorageName || store.matchesMarker(value),
  );
});

/// What is left of the old-keychain move.
class LegacyKeychainState {
  const LegacyKeychainState({this.pending = const [], this.declined = false});

  /// Entries still in the old keychain that need the system dialog.
  final List<String> pending;

  /// The last attempt was declined, cancelled or failed.
  final bool declined;

  bool get hasPending => pending.isNotEmpty;
}

/// Runs the old-keychain move (#1163). [scan] is quiet and safe at every
/// start; [migrate] may show the one system dialog and belongs behind the
/// announcement.
class LegacyKeychainNotifier extends Notifier<LegacyKeychainState> {
  @override
  LegacyKeychainState build() => const LegacyKeychainState();

  /// Moves what reads quietly and records what still needs the dialog.
  Future<void> scan() async {
    final migration = await ref.read(keychainMigrationProvider.future);
    if (migration == null) return;
    final result = await migration.scan();
    state = LegacyKeychainState(
      pending: result.pending,
      declined: state.declined && result.pending.isNotEmpty,
    );
    if (result.pending.isEmpty && result.movedQuietly.isNotEmpty) {
      // What was held back is readable now.
      secureAccessGate.retryHeldBack('old keychain moved quietly');
    }
  }

  /// Moves everything, with one system dialog. Call only after the
  /// announcement. [openGate]: after a full move, let the held-back secrets be
  /// read now (the data-key request opens the gate itself).
  Future<KeychainMigrationOutcome> migrate({bool openGate = true}) async {
    final migration = await ref.read(keychainMigrationProvider.future);
    if (migration == null) return KeychainMigrationOutcome.done;
    final scanned = await migration.scan();
    final outcome = await migration.migratePending(scanned.pending);
    state = LegacyKeychainState(
      pending: outcome == KeychainMigrationOutcome.done
          ? const []
          : scanned.pending,
      declined: outcome != KeychainMigrationOutcome.done,
    );
    if (openGate && outcome == KeychainMigrationOutcome.done) {
      // Nothing in the old keychain can prompt any more.
      if (secureAccessGate.promptsAllowed) {
        secureAccessGate.retryHeldBack('old keychain moved');
      } else {
        secureAccessGate.allowPrompts('old keychain moved');
      }
    }
    return outcome;
  }
}

final legacyKeychainProvider =
    NotifierProvider<LegacyKeychainNotifier, LegacyKeychainState>(
      LegacyKeychainNotifier.new,
    );

/// What the user sees about the data key.
enum DataKeyAccessStatus {
  /// No key yet, the system was never asked.
  notRequested,

  /// The system prompt is open (or the store is being asked).
  requesting,

  /// The key is in the system key store.
  ready,

  /// The key is in an owner-only file (Linux without Secret Service).
  fileFallback,

  /// Declined or cancelled. Nothing was replaced.
  declined,

  /// The system or the store failed technically (not a "no" from the user).
  /// Nothing was replaced; trying again is offered.
  failed,

  /// The Linux keyring is locked or does not answer.
  keyringLocked,

  /// A key was created earlier but is missing or different now.
  lost,
}

/// Maps a store result to the status shown to the user.
DataKeyAccessStatus dataKeyAccessStatusOf(DataKeyResult result) =>
    switch (result) {
      DataKeyReady(usesFileFallback: true) => DataKeyAccessStatus.fileFallback,
      DataKeyReady() => DataKeyAccessStatus.ready,
      DataKeyLost() => DataKeyAccessStatus.lost,
      DataKeyUnavailable(
        reason: DataKeyUnavailableReason.keyringLocked ||
            DataKeyUnavailableReason.keyringUnreachable,
      ) =>
        DataKeyAccessStatus.keyringLocked,
      DataKeyUnavailable() => DataKeyAccessStatus.failed,
    };

/// Status known without asking any secret store: only the marker counts.
DataKeyAccessStatus dataKeyStatusFromMarker(DataKeyBackend? backend) =>
    switch (backend) {
      null => DataKeyAccessStatus.notRequested,
      DataKeyBackend.systemKeyStore => DataKeyAccessStatus.ready,
      DataKeyBackend.file => DataKeyAccessStatus.fileFallback,
    };

/// Whether a status still offers the "allow" action.
bool dataKeyStatusOffersAllow(DataKeyAccessStatus status) => switch (status) {
  DataKeyAccessStatus.notRequested ||
  DataKeyAccessStatus.declined ||
  DataKeyAccessStatus.failed ||
  DataKeyAccessStatus.keyringLocked => true,
  _ => false,
};

/// Whether an existing user gets the one-time explanation dialog: onboarding
/// was finished earlier, the key was never explained and never created, and
/// no onboarding surface is on screen (which explains it itself).
bool shouldExplainDataKeyToExistingUser({
  required bool onboardingCompleted,
  required bool dataKeyExplained,
  required bool keyRecorded,
  required bool onboardingSurfaceActive,
}) =>
    onboardingCompleted &&
    !dataKeyExplained &&
    !keyRecorded &&
    !onboardingSurfaceActive;

/// Holds the data-key status and the one way to ask the system for the key.
class DataKeyAccessNotifier extends Notifier<DataKeyAccessStatus> {
  @override
  DataKeyAccessStatus build() =>
      dataKeyStatusFromMarker(ref.read(dataKeyStoreProvider).recordedBackend());

  /// Marks the key as explained and asks the store for it. Call only from a
  /// deliberate tap after the explanation: this may open the system prompt.
  ///
  /// The tap is also the user's go-ahead for the key store as a whole: it
  /// opens [secureAccessGate], so secrets held back at start are read now,
  /// together (#1161).
  Future<DataKeyAccessStatus> request() async {
    state = DataKeyAccessStatus.requesting;
    await markExplained();
    // The old login-keychain entries move first, with the one dialog the
    // explanation announced (#1163). Declined: nothing changes, the gate
    // stays closed and "Try again" offers the move again.
    final moved = await withSecureTrigger(
      'old keychain move',
      () => ref.read(legacyKeychainProvider.notifier).migrate(openGate: false),
    );
    // Only a "no" from the user stops here. A technical failure of the move
    // does not block the key: [DataKeyStore.obtain] reads it itself, also from
    // the old keychain, and a key that cannot be read ends as unavailable.
    if (moved == KeychainMigrationOutcome.declined) {
      state = DataKeyAccessStatus.declined;
      return state;
    }
    final wasOpen = secureAccessGate.promptsAllowed;
    secureAccessGate.allowPrompts('data key allowed');
    final result = await withSecureTrigger(
      'data key request',
      () => ref.read(dataKeyStoreProvider).obtain(),
    );
    final status =
        moved == KeychainMigrationOutcome.failed &&
            result is! DataKeyReady &&
            result is! DataKeyLost
        ? DataKeyAccessStatus.failed
        : dataKeyAccessStatusOf(result);
    // Retry after an unlock: the gate stayed open, so listeners that found the
    // key store locked earlier would never run again (#1217).
    if (wasOpen && result is DataKeyReady) {
      secureAccessGate.retryHeldBack('data key retry');
    }
    state = status;
    return status;
  }

  /// The key for code that needs it (recordings). Never opens a prompt of
  /// its own before the explanation: until [request] ran, the store reads
  /// quietly. A key that turns out unreadable (for example written under
  /// another signature) shows up as a status that offers "Try again", so
  /// the way to the prompt always leads through the explanation in
  /// Settings → Privacy.
  Future<DataKeyResult> obtainForUse(String trigger) async {
    final result = await withSecureTrigger(
      trigger,
      () => ref.read(dataKeyStoreProvider).obtain(),
    );
    final status = dataKeyAccessStatusOf(result);
    if (state != DataKeyAccessStatus.requesting && state != status) {
      state = status;
    }
    return result;
  }

  /// The key for a backup as recovery code or file (#1166), or null when it
  /// is not available right now. Only meant for a key that already exists
  /// (status ready or fileFallback); the status follows what the store says.
  Future<DataKey?> keyForBackup() async {
    final result = await withSecureTrigger(
      'data key backup',
      () => ref.read(dataKeyStoreProvider).obtain(),
    );
    state = dataKeyAccessStatusOf(result);
    return result is DataKeyReady ? result.key : null;
  }

  /// Restores the key from a recovery code or backup file (#1167). Counts as
  /// the deliberate tap of [request]: the dialog explained beforehand that
  /// the system may ask for permission (#1155).
  Future<DataKeyRestoreResult> restore(List<int> bytes) async {
    final before = state;
    state = DataKeyAccessStatus.requesting;
    await markExplained();
    final result = await ref.read(dataKeyStoreProvider).restore(bytes);
    state = switch (result) {
      DataKeyRestored(:final ready) => dataKeyAccessStatusOf(ready),
      DataKeyRestoreFailed(failure: DataKeyRestoreFailure.keyringLocked) =>
        DataKeyAccessStatus.keyringLocked,
      DataKeyRestoreFailed() => before,
    };
    return result;
  }

  /// Leaves the lost key behind and creates a new one (#1167). Call only
  /// after the warning was confirmed.
  Future<DataKeyAccessStatus> replaceLostKey() async {
    state = DataKeyAccessStatus.requesting;
    final result = await ref.read(dataKeyStoreProvider).replaceLostKey();
    final status = dataKeyAccessStatusOf(result);
    state = status;
    return status;
  }

  /// Records that the explanation was shown (device-local, never exported).
  Future<void> markExplained() async {
    final settings = ref.read(settingsProvider).value;
    if (settings?.onboarding.dataKeyExplained ?? false) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(dataKeyExplained: true),
          ),
        );
  }
}

final dataKeyAccessProvider =
    NotifierProvider<DataKeyAccessNotifier, DataKeyAccessStatus>(
      DataKeyAccessNotifier.new,
    );

/// When the data key was last backed up (#1166), or null when it never was.
/// Read from the marker; re-read whenever the access status changes, so a
/// newly created key shows as not backed up.
class DataKeyBackupNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.watch(dataKeyAccessProvider);
    return ref.read(dataKeyStoreProvider).recordedBackupAt();
  }

  /// Records a finished backup of [key]. False when the key is no longer the
  /// current one or the marker could not be written.
  Future<bool> record(DataKey key) async {
    final at = DateTime.now();
    final ok = await ref.read(dataKeyStoreProvider).recordBackup(key, at);
    if (ok) state = at;
    return ok;
  }
}

final dataKeyBackupProvider =
    NotifierProvider<DataKeyBackupNotifier, DateTime?>(
      DataKeyBackupNotifier.new,
    );
