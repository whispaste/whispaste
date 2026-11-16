/// Start screen for an encrypted history whose data key needs consent (#1427,
/// redesigned in #1461).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/data_key_access.dart';
import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/brand_wordmark.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_hero_button.dart';
import '../onboarding/app_language_select.dart';
import '../settings/data_key/data_key_flows.dart';
import 'startup_screen_frame.dart';

/// Shown instead of the shell when the history file is encrypted but its key
/// could not be read quietly, for example after the app was replaced by a
/// build with another code signature (macOS keychain ACL).
///
/// The shell must not start then: without the database it has no settings
/// and would show the onboarding as if this were a new installation.
///
/// The screen is a calm pause, not an error: it says that the data is
/// protected, why the system asks once, and that nothing is lost, then offers
/// one decision. The language is the user's own even here, from the locale
/// mirror (#1461), and can be changed on the spot.
///
/// "Allow access" is the deliberate tap that may open the system prompt
/// ([DataKeyAccessNotifier.request]). Once the key is ready, the database is
/// opened again, so history, settings, language and model come back without a
/// restart. Without a recorded key (no marker) the button is not offered: the
/// store would then create a new key, and this screen never does that.
///
/// Once the key is known to be lost or unreadable, or none is recorded, the
/// screen also offers the restore dialog of Settings → Privacy (recovery code
/// or backup file), which is otherwise out of reach behind this gate. It
/// leaves out "Create new key" there; a restored key reopens the database
/// like a granted one.
class DataKeyLockedScreen extends ConsumerStatefulWidget {
  const DataKeyLockedScreen({super.key});

  @override
  ConsumerState<DataKeyLockedScreen> createState() =>
      _DataKeyLockedScreenState();
}

class _DataKeyLockedScreenState extends ConsumerState<DataKeyLockedScreen> {
  DataKeyAccessStatus? _outcome;
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final status = await ref.read(dataKeyAccessProvider.notifier).request();
    if (!mounted) return;
    if (status == DataKeyAccessStatus.ready ||
        status == DataKeyAccessStatus.fileFallback) {
      _reopenDatabase();
      return;
    }
    setState(() {
      _busy = false;
      _outcome = status;
    });
  }

  /// Opens the restore dialog (recovery code or backup file). The dialog
  /// offers no "Create new key" here; a restored key reopens the database
  /// just like a granted one.
  Future<void> _restore() async {
    setState(() => _busy = true);
    final restored = await ref.read(dataKeyLockedRestoreFlowProvider)(context);
    if (!mounted) return;
    if (restored) {
      _reopenDatabase();
      return;
    }
    setState(() => _busy = false);
  }

  /// The key is ready: the gate probes the database again and the shell
  /// starts without a restart.
  void _reopenDatabase() {
    // The app keeps the language this screen showed, also one picked here
    // in an earlier run, instead of the older value in the database.
    ref.read(startupLocaleChoiceProvider.notifier).keepShown();
    ref.invalidate(historyDatabaseProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // A key must have been recorded before; otherwise asking the store could
    // create a fresh key next to the encrypted file.
    final keyRecorded =
        ref.read(dataKeyAccessProvider) != DataKeyAccessStatus.notRequested ||
        _outcome != null;
    final outcome = _outcome;
    // A backup helps once the key is known to be gone or unreadable, or when
    // none is recorded (copied data folder). Before the first tap the system
    // most likely only waits for consent, so "Allow access" stays the one
    // offer then; after a refusal or a locked keyring, retrying is the way.
    final offersRestore =
        !keyRecorded ||
        outcome == DataKeyAccessStatus.lost ||
        outcome == DataKeyAccessStatus.failed;
    final status = switch (outcome) {
      null => keyRecorded ? null : l10n.dataKeyLockedUnavailable,
      DataKeyAccessStatus.declined => l10n.dataKeyLockedDeclined,
      DataKeyAccessStatus.keyringLocked => l10n.dataKeyStatusLocked,
      _ => l10n.dataKeyLockedUnavailable,
    };
    return StartupScreenFrame(
      key: const ValueKey('data-key-locked-screen'),
      title: l10n.dataKeyLockedTitle,
      leading: const WpBrandWordmark(height: 32),
      children: [
        WpCard(
          key: const ValueKey('data-key-locked-points'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Point(
                icon: LucideIcons.shieldCheck,
                text: l10n.dataKeyLockedPointProtected,
              ),
              const SizedBox(height: WpSpacing.md),
              _Point(
                icon: LucideIcons.keyRound,
                text: defaultTargetPlatform == TargetPlatform.macOS
                    ? l10n.dataKeyLockedPointWhyMac
                    : l10n.dataKeyLockedPointWhy,
              ),
              const SizedBox(height: WpSpacing.md),
              _Point(
                icon: LucideIcons.circleCheck,
                text: l10n.dataKeyLockedPointSafe,
              ),
            ],
          ),
        ),
        // Read out after each attempt: focus stays on the button, so a screen
        // reader would otherwise announce only its label. A refusal is a
        // calm notice, not an error: the data is untouched either way.
        Semantics(
          liveRegion: true,
          child: status == null
              ? const SizedBox(height: WpSpacing.xl)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: WpSpacing.lg),
                  child: WpBanner(
                    key: const ValueKey('data-key-locked-status'),
                    tone: outcome == DataKeyAccessStatus.declined
                        ? WpBannerTone.info
                        : WpBannerTone.warning,
                    message: status,
                  ),
                ),
        ),
        if (keyRecorded) ...[
          SizedBox(
            width: double.infinity,
            child: WpHeroButton(
              key: const ValueKey('data-key-locked-allow'),
              testId: 'data-key-locked-allow',
              label: outcome == null
                  ? l10n.dataKeyLockedAllow
                  : l10n.actionRetry,
              autofocus: true,
              onPressed: _busy ? null : _allow,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        if (offersRestore) ...[
          SizedBox(
            width: double.infinity,
            child: WpButton(
              key: const ValueKey('data-key-locked-restore'),
              testId: 'data-key-locked-restore',
              label: l10n.dataKeyLockedRestore,
              icon: LucideIcons.keyRound,
              variant: WpButtonVariant.secondary,
              expanded: true,
              autofocus: !keyRecorded,
              onPressed: _busy ? null : () => unawaited(_restore()),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        Align(
          alignment: AlignmentDirectional.center,
          child: WpButton(
            key: const ValueKey('data-key-locked-quit'),
            testId: 'data-key-locked-quit',
            label: l10n.databaseTooNewQuit,
            // Without a recorded key the restore button above is offered, so
            // there is always an action before quitting.
            variant: WpButtonVariant.ghost,
            onPressed: () => quitFromStartupScreen(context),
          ),
        ),
        const SizedBox(height: WpSpacing.xl),
        Divider(height: 1, color: WpColors.borderSubtle),
        const SizedBox(height: WpSpacing.lg),
        AppLanguageSelect(
          testId: 'data-key-locked-language',
          locale: ref.watch(localeProvider).languageCode,
          onChanged: (code) =>
              ref.read(startupLocaleChoiceProvider.notifier).choose(code),
        ),
      ],
    );
  }
}

/// One reassurance line: a quiet accent glyph and a sentence.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: WpIconSize.md, color: WpColors.accent),
        ),
        const SizedBox(width: WpSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: WpTypography.body,
              height: 1.5,
              color: WpColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
