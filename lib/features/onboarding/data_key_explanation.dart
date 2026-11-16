/// The data-key explanation in front of the system prompt (#1071).
///
/// - [OnboardingDataKeyRow]: the row on the closing onboarding page for new
///   installations. Seeing it counts as explained.
/// - [DataKeyExplanationWatcher]: shows existing users the same explanation
///   once as a dialog, through the nudge gate, before anything asks the
///   system for the key.
/// - [dataKeyStatusText] / [dataKeyActionLabel]: shared with Settings →
///   Privacy, where the status and the way to allow again always live.
///
/// The system prompt only ever follows a tap on "Create key".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/data_key_access.dart';
import '../../core/config/keychain_migration.dart';
import '../../core/config/secure_key_store.dart' show withSecureTrigger;
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../core/theme/tokens.dart';
import '../../services/nudge_gate.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import '../settings/settings_widgets.dart';

/// What the user reads about the key in [status].
String dataKeyStatusText(L10n l10n, DataKeyAccessStatus status) =>
    switch (status) {
      DataKeyAccessStatus.notRequested => l10n.dataKeyStatusNotRequested,
      DataKeyAccessStatus.requesting => l10n.dataKeyStatusRequesting,
      DataKeyAccessStatus.ready => l10n.dataKeyStatusReady,
      DataKeyAccessStatus.fileFallback => l10n.dataKeyFileFallbackHint,
      DataKeyAccessStatus.declined => l10n.dataKeyStatusDeclined,
      DataKeyAccessStatus.failed => l10n.dataKeyStatusFailed,
      DataKeyAccessStatus.keyringLocked => l10n.dataKeyStatusLocked,
      DataKeyAccessStatus.lost => l10n.dataKeyStatusLost,
    };

/// Label of the allow action: first time "Create key", afterwards "Try again".
String dataKeyActionLabel(L10n l10n, DataKeyAccessStatus status) =>
    status == DataKeyAccessStatus.notRequested ||
        status == DataKeyAccessStatus.requesting
    ? l10n.dataKeyAllow
    : l10n.dataKeyRetry;

/// The allow button, or nothing once the key is settled.
Widget dataKeyAllowButton({
  required WidgetRef ref,
  required L10n l10n,
  required DataKeyAccessStatus status,
  required String testId,
}) {
  final requesting = status == DataKeyAccessStatus.requesting;
  if (!requesting && !dataKeyStatusOffersAllow(status)) {
    return const SizedBox.shrink();
  }
  return WpButton(
    testId: testId,
    label: dataKeyActionLabel(l10n, status),
    variant: WpButtonVariant.secondary,
    isLoading: requesting,
    onPressed: requesting
        ? null
        : () => unawaited(ref.read(dataKeyAccessProvider.notifier).request()),
  );
}

/// Data-key row on the closing onboarding page. Being on screen is the
/// explanation, so it marks the key as explained; the prompt still waits for
/// the button.
class OnboardingDataKeyRow extends ConsumerStatefulWidget {
  const OnboardingDataKeyRow({super.key});

  @override
  ConsumerState<OnboardingDataKeyRow> createState() =>
      _OnboardingDataKeyRowState();
}

class _OnboardingDataKeyRowState extends ConsumerState<OnboardingDataKeyRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(dataKeyAccessProvider.notifier).markExplained());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final status = ref.watch(dataKeyAccessProvider);
    return SettingRow(
      testId: 'onboarding-privacy-data-key-row',
      icon: LucideIcons.keyRound,
      iconSize: WpIconSize.md,
      label: l10n.dataKeyTitle,
      subtitle: status == DataKeyAccessStatus.notRequested
          ? '${l10n.dataKeyExplainBody} ${l10n.dataKeyExplainPrompt}'
          : dataKeyStatusText(l10n, status),
      trailing: dataKeyAllowButton(
        ref: ref,
        l10n: l10n,
        status: status,
        testId: 'onboarding-privacy-data-key-allow',
      ),
    );
  }
}

/// Shows existing users the data-key explanation once (see
/// [shouldExplainDataKeyToExistingUser]). Renders no UI of its own.
class DataKeyExplanationWatcher extends ConsumerStatefulWidget {
  const DataKeyExplanationWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DataKeyExplanationWatcher> createState() =>
      _DataKeyExplanationWatcherState();
}

class _DataKeyExplanationWatcherState
    extends ConsumerState<DataKeyExplanationWatcher> {
  bool _running = false;

  bool _eligible() {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return false;
    return shouldExplainDataKeyToExistingUser(
      onboardingCompleted: settings.onboarding.onboardingCompleted,
      dataKeyExplained: settings.onboarding.dataKeyExplained,
      keyRecorded:
          ref.read(dataKeyAccessProvider) != DataKeyAccessStatus.notRequested,
      onboardingSurfaceActive: onboardingSurfaceActive(
        onboardingCompleted: settings.onboarding.onboardingCompleted,
        manuallyOpen: ref.read(onboardingManuallyOpenProvider),
        revisionRunning: ref.read(onboardingRevisionRunProvider),
      ),
    );
  }

  Future<void> _run() async {
    _running = true;
    try {
      // R-11: no dictation running and the app idle before a dialog opens.
      await ref.read(nudgeGateProvider).whenAllowed();
      if (!mounted || !_eligible()) return;
      // Old keychain entries that would need a dialog are announced together
      // with the key explanation (#1163).
      await ref.read(legacyKeychainProvider.notifier).scan();
      if (!mounted || !_eligible()) return;
      final allow = await _explain();
      if (!mounted) return;
      final notifier = ref.read(dataKeyAccessProvider.notifier);
      await notifier.markExplained();
      if (allow != true || !mounted) return;
      final status = await notifier.request();
      if (!mounted || status == DataKeyAccessStatus.ready) return;
      await _showOutcome(status);
    } finally {
      _running = false;
    }
  }

  Future<bool?> _explain() {
    final l10n = L10n.of(context);
    return showWpDialog<bool>(
      context: context,
      title: l10n.dataKeyExplainTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            identifier: 'data-key-explanation-body',
            child: Text(l10n.dataKeyExplainBody),
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(l10n.dataKeyExplainPrompt),
          if (ref.read(legacyKeychainProvider).hasPending) ...[
            const SizedBox(height: WpSpacing.sm),
            Text(l10n.keychainMigrationBody),
          ],
        ],
      ),
      actions: [
        WpDialogAction<bool>(
          label: l10n.dataKeyLater,
          testId: 'data-key-explanation-later',
          role: WpDialogActionRole.cancel,
          value: false,
        ),
        WpDialogAction<bool>(
          label: l10n.dataKeyAllow,
          testId: 'data-key-explanation-allow',
          role: WpDialogActionRole.primary,
          value: true,
        ),
      ],
    );
  }

  /// Calm follow-up when the key is not in the system store: what happened
  /// and that Settings → Privacy offers the way back. Nothing was replaced.
  Future<void> _showOutcome(DataKeyAccessStatus status) {
    final l10n = L10n.of(context);
    return showWpDialog<void>(
      context: context,
      title: l10n.dataKeyTitle,
      content: Semantics(
        identifier: 'data-key-outcome-status',
        child: Text(dataKeyStatusText(l10n, status)),
      ),
      actions: [
        WpDialogAction<void>(
          label: l10n.dataKeyClose,
          testId: 'data-key-outcome-close',
          role: WpDialogActionRole.primary,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider);
    if (!_running && _eligible()) {
      _running = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_run());
      });
    }
    return widget.child;
  }
}

/// Announces the one-time move of the old keychain entries (#1163) to users
/// who already saw the data-key explanation, and offers it again later from
/// Settings → Privacy. Renders no UI of its own.
class KeychainMigrationWatcher extends ConsumerStatefulWidget {
  const KeychainMigrationWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeychainMigrationWatcher> createState() =>
      _KeychainMigrationWatcherState();
}

class _KeychainMigrationWatcherState
    extends ConsumerState<KeychainMigrationWatcher> {
  bool _started = false;

  bool _ready() {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return false;
    final onboarding = settings.onboarding;
    return onboarding.onboardingCompleted &&
        onboarding.dataKeyExplained &&
        !onboardingSurfaceActive(
          onboardingCompleted: onboarding.onboardingCompleted,
          manuallyOpen: ref.read(onboardingManuallyOpenProvider),
          revisionRunning: ref.read(onboardingRevisionRunProvider),
        );
  }

  /// Once per launch: move what reads quietly, announce the rest. Whoever
  /// has not seen the data-key explanation gets the same text there.
  Future<void> _run() async {
    await ref.read(nudgeGateProvider).whenAllowed();
    if (!mounted || !_ready()) return;
    await ref.read(legacyKeychainProvider.notifier).scan();
    if (!mounted || !ref.read(legacyKeychainProvider).hasPending) return;
    final l10n = L10n.of(context);
    final agree = await showWpDialog<bool>(
      context: context,
      title: l10n.keychainMigrationTitle,
      content: Semantics(
        identifier: 'keychain-migration-body',
        child: Text(l10n.keychainMigrationBody),
      ),
      actions: [
        WpDialogAction<bool>(
          label: l10n.dataKeyLater,
          testId: 'keychain-migration-later',
          role: WpDialogActionRole.cancel,
          value: false,
        ),
        WpDialogAction<bool>(
          label: l10n.keychainMigrationAllow,
          testId: 'keychain-migration-allow',
          role: WpDialogActionRole.primary,
          value: true,
        ),
      ],
    );
    if (agree != true || !mounted) return;
    await runKeychainMigration(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider);
    if (!_started && _ready()) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_run());
      });
    }
    return widget.child;
  }
}

/// Runs the confirmed move and, when it did not complete, says what is
/// missing and that it can be started again. The user's tap is the go-ahead,
/// so this is the only place that lets the system dialog appear.
Future<void> runKeychainMigration(BuildContext context, WidgetRef ref) async {
  final outcome = await withSecureTrigger(
    'old keychain move',
    ref.read(legacyKeychainProvider.notifier).migrate,
  );
  if (outcome == KeychainMigrationOutcome.done || !context.mounted) return;
  final l10n = L10n.of(context);
  await showWpDialog<void>(
    context: context,
    title: l10n.keychainMigrationTitle,
    content: Semantics(
      identifier: 'keychain-migration-outcome',
      child: Text(l10n.keychainMigrationDeclined),
    ),
    actions: [
      WpDialogAction<void>(
        label: l10n.dataKeyClose,
        testId: 'keychain-migration-outcome-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
}
