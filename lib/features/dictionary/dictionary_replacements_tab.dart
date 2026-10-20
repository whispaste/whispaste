/// Replacements tab: help, a test field that shows the rewrite live, the CSV
/// card, and the replacement list itself (without the learning cards, which
/// the Suggestions tab shows).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/ltr_isolate.dart';
import '../../core/theme/tokens.dart';
import '../../services/replacements/text_replacement_matcher.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_text_field.dart';
import '../replacements/replacements_page.dart';
import 'dictionary_csv_actions.dart';

class DictionaryReplacementsTab extends ConsumerStatefulWidget {
  const DictionaryReplacementsTab({super.key});

  @override
  ConsumerState<DictionaryReplacementsTab> createState() =>
      _DictionaryReplacementsTabState();
}

class _DictionaryReplacementsTabState
    extends ConsumerState<DictionaryReplacementsTab> {
  final _testController = TextEditingController();
  String _testInput = '';

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final items =
        ref.watch(replacementsProvider).value ?? const <Replacement>[];
    final rules = [
      for (final r in items)
        TextReplacementRule(
          triggers: r.triggers,
          replacement: r.replacement,
          matchMode: r.matchMode,
          fuzzyThreshold: r.fuzzyThreshold,
        ),
    ];
    final output = _testInput.trim().isEmpty
        ? ''
        : applyTextReplacements(_testInput, rules);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.lg,
            WpSpacing.md,
            WpSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dictionaryReplacementsHelp,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: WpSpacing.md),
              Text(l10n.dictionaryTestTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: WpSpacing.xs),
              WpTextField(
                key: const ValueKey('dictionary-test-input'),
                controller: _testController,
                variant: WpTextFieldVariant.form,
                hintText: l10n.dictionaryTestInputHint,
                semanticsLabel: l10n.dictionaryTestInputLabel,
                onChanged: (v) => setState(() => _testInput = v),
              ),
              if (_testInput.trim().isNotEmpty) ...[
                const SizedBox(height: WpSpacing.xs),
                Text(
                  key: const ValueKey('dictionary-test-result'),
                  '${l10n.dictionaryTestResultLabel}: '
                  '${output == _testInput ? l10n.dictionaryTestNoChange : output}',
                ),
              ],
              const SizedBox(height: WpSpacing.md),
              _CsvCard(items: items),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        const Expanded(child: ReplacementsPage(showSuggestionCards: false)),
      ],
    );
  }
}

class _CsvCard extends ConsumerWidget {
  const _CsvCard({required this.items});

  final List<Replacement> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dictionaryCsvTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.dictionaryCsvHint(ltrIsolate('|')),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: WpSpacing.xs),
        Wrap(
          spacing: WpSpacing.xs,
          children: [
            WpButton(
              key: const ValueKey('dictionary-csv-import'),
              label: l10n.dictionaryCsvImport,
              variant: WpButtonVariant.secondary,
              onPressed: () => importReplacementsCsv(context, ref),
            ),
            WpButton(
              key: const ValueKey('dictionary-csv-export'),
              label: l10n.dictionaryCsvExport,
              variant: WpButtonVariant.secondary,
              onPressed: items.isEmpty
                  ? null
                  : () => exportReplacementsCsv(context, items),
            ),
          ],
        ),
        // Says why export is off, as visible text (UIA-DIC-08).
        if (items.isEmpty) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(l10n.dictionaryCsvExportEmpty, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
