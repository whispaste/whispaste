/// Terms tab: the hint list for the recogniser, with a banner that says what
/// the active speech engine does with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/term_hint_effect.dart';
import '../../widgets/wp_banner.dart';
import 'widgets/dictionary_terms_field.dart';

class DictionaryTermsTab extends ConsumerWidget {
  const DictionaryTermsTab({super.key, this.extraSections = const []});

  final List<Widget> extraSections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();

    final effect = termHintEffectFor(
      provider: settings.sttProviderType,
      engine: settings.onDeviceEngine,
    );
    final effectText = switch (effect) {
      TermHintEffect.promptHint => l10n.dictionaryTermsEffectPrompt,
      TermHintEffect.replacementOnly =>
        l10n.dictionaryTermsEffectReplacementOnly,
    };

    return ListView(
      padding: const EdgeInsets.all(WpSpacing.lg),
      children: [
        WpBanner(tone: WpBannerTone.info, message: effectText),
        const SizedBox(height: WpSpacing.md),
        Text(
          l10n.dictionaryTermsHelp,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: WpSpacing.sm),
        DictionaryTermsField(initialValue: settings.customVocabulary),
        for (final section in extraSections) ...[
          const SizedBox(height: WpSpacing.md),
          section,
        ],
      ],
    );
  }
}
