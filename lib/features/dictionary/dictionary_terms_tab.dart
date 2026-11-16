/// Terms tab: the hint list for the recogniser. It only speaks up when the
/// active speech engine takes no hints, because then a term changes nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/term_hint_effect.dart';
import '../../widgets/page_shell.dart' show WpPageFrame;
import '../../widgets/wp_banner.dart';
import '../settings/settings_widgets.dart' show SettingRow, settingsToggle;
import '../../widgets/wp_button.dart';
import 'dictionary_tab_target.dart';
import 'widgets/dictionary_terms_list.dart';
import 'term_import_page.dart';

class DictionaryTermsTab extends ConsumerWidget {
  const DictionaryTermsTab({super.key, this.extraSections = const []});

  final List<Widget> extraSections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // The term list does not depend on the settings: while they load, or
    // when loading them failed, the list still shows (#1635) and only the
    // engine hint below waits for them.
    final settings = ref.watch(settingsProvider).value;
    final effect = settings == null
        ? null
        : termHintEffectFor(
            provider: settings.sttProviderType,
            engine: settings.onDeviceEngine,
          );

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: WpPageFrame.inset,
        vertical: WpSpacing.lg,
      ),
      children: [
        if (settings != null && effect == TermHintEffect.replacementOnly) ...[
          WpBanner(
            key: const ValueKey('dictionary-terms-no-hints'),
            tone: WpBannerTone.info,
            message: l10n.dictionaryTermsEffectReplacementOnly,
            action: WpButton(
              testId: 'dictionary-terms-as-replacement',
              label: l10n.dictionaryTermsAsReplacement,
              variant: WpButtonVariant.secondary,
              size: WpButtonSize.dense,
              onPressed: () {
                ref
                    .read(dictionaryNewReplacementRequestProvider.notifier)
                    .set(true);
                ref
                    .read(dictionaryTabTargetProvider.notifier)
                    .set(DictionaryTab.replacements);
              },
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          SettingRow(
            icon: LucideIcons.spellCheck,
            label: l10n.dictionaryTermsSimilarityLabel,
            subtitle: l10n.dictionaryTermsSimilarityHint,
            switchNamesRow: true,
            trailing: settingsToggle(
              label: l10n.dictionaryTermsSimilarityLabel,
              value: settings.behavior.termSimilarityEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      behavior: s.behavior.copyWith(termSimilarityEnabled: v),
                    ),
                  ),
              key: const ValueKey('dictionary-terms-similarity-toggle'),
              testId: 'dictionary-terms-similarity-toggle',
            ),
          ),
          const SizedBox(height: WpSpacing.md),
        ],
        const TermTransferActions(),
        const DictionaryTermsList(),
        for (final section in extraSections) ...[
          const SizedBox(height: WpSpacing.md),
          section,
        ],
      ],
    );
  }
}
