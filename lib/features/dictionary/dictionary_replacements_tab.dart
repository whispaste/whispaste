/// Replacements tab: the replacement list itself, with its secondary actions
/// (try-it test, CSV import/export) behind the toolbar's overflow button.
///
/// The list is the only thing above the fold on purpose (WP-81): explanation
/// and rows scroll together, search and Add stay fixed, and nothing else takes
/// vertical space until it is asked for. The learning cards live on the
/// Suggestions tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/ltr_isolate.dart';
import '../../core/theme/tokens.dart';
import '../../services/replacements/text_replacement_matcher.dart';
import '../../widgets/dialog.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/wp_text_field.dart';
import '../replacements/replacements_page.dart';
import 'dictionary_csv_actions.dart';

class DictionaryReplacementsTab extends ConsumerWidget {
  const DictionaryReplacementsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final items =
        ref.watch(replacementsProvider).value ?? const <Replacement>[];
    return ReplacementsPage(
      showSuggestionCards: false,
      leadingMenuActions: [
        WpListMenuAction(
          itemKey: const ValueKey('dictionary-test-open'),
          label: l10n.dictionaryTestTitle,
          hint: l10n.dictionaryTestInputHint,
          icon: LucideIcons.flaskConical,
          onSelected: () => _openTestDialog(context),
        ),
        WpListMenuAction(
          itemKey: const ValueKey('dictionary-csv-import'),
          label: l10n.dictionaryCsvImport,
          hint: l10n.dictionaryCsvHint(ltrIsolate('|')),
          icon: LucideIcons.fileUp,
          onSelected: () => importReplacementsCsv(context, ref),
        ),
        WpListMenuAction(
          itemKey: const ValueKey('dictionary-csv-export'),
          label: l10n.dictionaryCsvExport,
          icon: LucideIcons.fileDown,
          // A disabled row says why: the empty list is the reason.
          hint: items.isEmpty ? l10n.dictionaryCsvExportEmpty : null,
          enabled: items.isNotEmpty,
          onSelected: () => exportReplacementsCsv(context, items),
        ),
      ],
    );
  }
}

Future<void> _openTestDialog(BuildContext context) {
  return showWpFormDialog<void>(
    context: context,
    builder: (_, a) => _TestReplacementDialog(animation: a),
  );
}

/// "Try it": a sentence in, the rewrite out, live. It was a card above the
/// list; as a dialog it costs the list nothing while the user adds or finds
/// replacements. Its subtitle carries the tab's explanation, which therefore
/// no longer takes a line above the rows.
class _TestReplacementDialog extends ConsumerStatefulWidget {
  const _TestReplacementDialog({required this.animation});

  final Animation<double> animation;

  @override
  ConsumerState<_TestReplacementDialog> createState() =>
      _TestReplacementDialogState();
}

class _TestReplacementDialogState
    extends ConsumerState<_TestReplacementDialog> {
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

    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.dictionaryTestTitle,
      subtitle: l10n.dictionaryReplacementsHelp,
      fields: [
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
            style: theme.textTheme.bodyMedium,
          ),
        ],
        // Says why export is off, as visible text (UIA-DIC-08).
        if (items.isEmpty) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(l10n.dictionaryCsvExportEmpty, style: theme.textTheme.bodySmall),
        ],
      ],
      actions: [
        WpDialogAction(
          label: l10n.actionClose,
          testId: 'dictionary-test-close',
          role: WpDialogActionRole.cancel,
        ),
      ],
    );
  }
}
