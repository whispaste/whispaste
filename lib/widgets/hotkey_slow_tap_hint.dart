/// A calm hint that another app's slow keyboard tap may disturb the hotkey
/// (macOS, #915). Shown where the hotkey is set (hotkey settings, onboarding
/// hotkey step), read fresh when the page opens; never a toast on a recording.
/// Nothing is shown when no tap is slow, and off macOS.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../services/hotkey_disturbance.dart';
import 'wp_banner.dart';

class WpHotkeySlowTapHint extends ConsumerWidget {
  /// [idPrefix] names the screen: the testID is `<idPrefix>-slow-tap-hint`.
  const WpHotkeySlowTapHint({super.key, required this.idPrefix});

  final String idPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tap = ref.watch(slowKeyboardTapNowProvider).value;
    if (tap == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final app = tap.name ?? tap.bundleId;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        identifier: '$idPrefix-slow-tap-hint',
        child: WpBanner(
          tone: WpBannerTone.info,
          message: app == null
              ? l10n.hotkeySlowTapHintGeneric
              : l10n.hotkeySlowTapHintNamed(app),
        ),
      ),
    );
  }
}
