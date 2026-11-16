/// Overlay cards for hotkey situations that need a next step (#454): a
/// hold-mode press too short to watch, and the language hotkey without
/// favorites. Each card names the cause and offers the fix as its button.
library;

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../input_monitoring_offer.dart';
import '../window_activation.dart';
import 'dictation_notice.dart';

/// Reads a provider; both `WidgetRef.read` and `ProviderContainer.read` fit.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Short press in hold mode: offers "Tap or hold", which lets a short press
/// start and end the recording.
DictationNotice shortPressHintNotice(L10n l10n, ProviderRead read) =>
    DictationNotice(
      id: 'short-press-hint',
      cause: l10n.shortPressHintMessage,
      autoDismiss: const Duration(seconds: 10),
      actions: [
        DictationNoticeAction(
          id: 'enable-tap-or-hold',
          label: l10n.shortPressHintAction,
          // The card closes on the press; the pill says it worked (#827, I7).
          confirmation: l10n.settingsEnabled,
          onPressed: () => unawaited(
            read(settingsProvider.notifier).updateSettings(
              (s) => s.copyWithSections(
                audioInput: s.audioInput.copyWith(holdOrTap: true),
              ),
            ),
          ),
        ),
        // The alternative to the switch: stop asking, kept in the settings.
        DictationNoticeAction(
          id: 'hide-short-press-hint',
          label: l10n.shortPressHintHide,
          onPressed: () => unawaited(
            read(settingsProvider.notifier).updateSettings(
              (s) => s.copyWithSections(
                audioInput: s.audioInput.copyWith(shortPressHintHidden: true),
              ),
            ),
          ),
        ),
      ],
    );

/// Input Monitoring offer for a key combination (#807): explains why, then
/// the button shows the macOS system prompt. Shown once; closing or ignoring
/// the card is a decline.
DictationNotice inputMonitoringOfferNotice(L10n l10n, ProviderRead read) =>
    DictationNotice(
      id: 'input-monitoring-offer',
      cause: l10n.inputMonitoringOfferMessage,
      autoDismiss: const Duration(seconds: 15),
      actions: [
        DictationNoticeAction(
          id: 'allow-input-monitoring',
          label: l10n.inputMonitoringOfferAction,
          onPressed: () =>
              unawaited(read(inputMonitoringOfferProvider.notifier).accept()),
        ),
      ],
    );

/// Language hotkey without favorites: opens Settings at the language row,
/// with the language dialog (where the stars are) on top.
/// The card sits on the overlay and the window is usually hidden while
/// dictating in another app, so the button brings it forward.
DictationNotice noFavoriteLanguagesNotice(L10n l10n, ProviderRead read) =>
    DictationNotice(
      id: 'language-cycle-no-favorites',
      cause: l10n.languageCycleNoFavoritesToast,
      autoDismiss: kDictationHintTime,
      actions: [
        DictationNoticeAction(
          id: 'open-settings',
          label: l10n.languageCycleOpenSettings,
          onPressed: () {
            read(settingsScrollTargetProvider.notifier).set('speech-language');
            // Favorites are set by star in the language dialog (#1610), so
            // open it right away, as "More languages…" does.
            read(settingsLanguageDialogRequestProvider.notifier).request();
            read(activePageProvider.notifier).setPage('settings');
            unawaited(read(windowActivatorProvider)());
          },
        ),
      ],
    );
