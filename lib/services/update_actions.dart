/// Shared "check / present update" routing, used by every update-check
/// surface (About page, Settings, status bar) so they behave identically.
///
/// Before this existed, each surface re-implemented its own tap routing.
/// The About page's copy had a bug (PRD Bug 2): on Sparkle platforms
/// (macOS/Windows) it only ever called [presentSparkleUpdate] when
/// `updateState.phase == UpdatePhase.available` — a phase that, before the
/// Bug 1 fix (`auto_updater_service.dart`'s `registerSparkleListener`), the
/// native path could never reach on its own. Every other tap silently fell
/// through to [UpdateNotifier.checkForUpdate] (the GitHub-API mechanism),
/// which is channel-blind and pre-release-blind — so "Check now" on a
/// Sparkle platform effectively never found a beta.
library;

import 'package:flutter/material.dart' show IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/generated/app_localizations.dart';
import 'auto_updater_service.dart';
import 'deploy_channel_service.dart';
import 'update_channel_service.dart';
import 'update_service.dart';

/// Runs the correct "check for update" / "present update" / "install"
/// action for the current [updateState], routed identically regardless of
/// which UI surface triggered it.
///
/// - [UpdatePhase.available]: Sparkle platforms open the native dialog;
///   Linux/portable open the release notes URL.
/// - [UpdatePhase.readyToInstall]: installs the already-downloaded update
///   (Linux/portable installer flow only — Sparkle platforms swap in-place
///   before ever reaching this phase).
/// - Anything else (idle/checking/upToDate/error): triggers a fresh check —
///   the native Sparkle foreground check on Sparkle platforms (so beta
///   releases are actually found), or the GitHub-API check elsewhere.
void triggerUpdateAction({
  required WidgetRef ref,
  required UpdateState updateState,
  required DeployChannel channel,
}) {
  final notifier = ref.read(updateProvider.notifier);

  if (updateState.phase == UpdatePhase.available) {
    if (shouldUseAutoUpdater(channel)) {
      presentSparkleUpdate(
        ref.read(updateChannelProvider).value ?? UpdateChannel.stable,
      );
    } else {
      final url = updateState.releaseNotesUrl;
      if (url != null) launchUrl(Uri.parse(url));
    }
    return;
  }

  if (updateState.phase == UpdatePhase.readyToInstall) {
    notifier.installUpdate();
    return;
  }

  if (shouldUseAutoUpdater(channel)) {
    presentSparkleUpdate(
      ref.read(updateChannelProvider).value ?? UpdateChannel.stable,
    );
  } else {
    notifier.checkForUpdate();
  }
}

/// Resolves the icon + label every update-check surface shows for
/// [phase], so the About page, Settings, and status bar never drift out of
/// sync with each other (PRD Bug 5's parity requirement).
(IconData, String) resolveUpdateActionDisplay({
  required UpdatePhase phase,
  required DeployChannel channel,
  required UpdateState state,
  required L10n l10n,
}) {
  return switch (phase) {
    UpdatePhase.idle => (LucideIcons.refreshCw, l10n.updateCheckNow),
    UpdatePhase.checking => (LucideIcons.refreshCw, l10n.updateCheckNow),
    UpdatePhase.available =>
      channel == DeployChannel.portable
          ? (LucideIcons.externalLink, l10n.updateViewRelease)
          : (
              LucideIcons.download,
              l10n.updateAvailable(state.latestVersion ?? ''),
            ),
    UpdatePhase.downloading => (
      LucideIcons.download,
      l10n.updateDownloading((state.progressPercent * 100).round()),
    ),
    UpdatePhase.readyToInstall => (
      LucideIcons.packageCheck,
      l10n.updateInstall,
    ),
    UpdatePhase.upToDate => (LucideIcons.circleCheck, l10n.updateUpToDate),
    UpdatePhase.error => (LucideIcons.triangleAlert, l10n.updateError),
  };
}
