/// Review step of the vocabulary-import flow (PRD.md
/// `.scratch/vocabulary-fuzzy-replacements/PRD.md`): a scan can turn up
/// thousands of candidate identifiers, so nothing is written to the database
/// until the user has actually picked which ones should become replacements.
///
/// A dedicated full-page route rather than a dialog: the app's dialog shell
/// scrolls its body inside a `SingleChildScrollView`, which has no bounded
/// height for a nested `ListView.builder` to virtualize against -- it would
/// build every row up front. A real project scan has been observed to return
/// on the order of ten thousand candidates, so virtualization is not
/// optional here.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_row_checkbox.dart';
import '../../widgets/wp_text_field.dart';

/// Pushed via `Navigator.push`; pops with the list of terms the user selected
/// to import, or `null` if they cancelled without importing anything.
class VocabularyImportReviewPage extends StatefulWidget {
  const VocabularyImportReviewPage({super.key, required this.candidates});

  /// Sorted, already deduplicated against existing triggers (the scan's
  /// output) -- every entry here is a legitimate new-identifier candidate.
  final List<String> candidates;

  @override
  State<VocabularyImportReviewPage> createState() =>
      _VocabularyImportReviewPageState();
}

class _VocabularyImportReviewPageState
    extends State<VocabularyImportReviewPage> {
  final _searchCtrl = TextEditingController();
  final _selected = <String>{};
  String _query = '';
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.candidates;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyFilter(String query) {
    setState(() {
      _query = query;
      final lower = query.trim().toLowerCase();

      if (lower.isEmpty) {
        _filtered = widget.candidates;
      } else {
        // Precompile RegExp to avoid allocating thousands of lowercased strings
        // via `String.toLowerCase()` on each keystroke for large candidate lists,
        // which can cause severe GC spikes.
        final regex = RegExp(RegExp.escape(lower), caseSensitive: false);
        _filtered = widget.candidates.where((c) => regex.hasMatch(c)).toList();
      }
    });
  }

  void _toggle(String term) {
    setState(() {
      if (!_selected.remove(term)) _selected.add(term);
    });
  }

  void _selectAllFiltered() {
    setState(() => _selected.addAll(_filtered));
  }

  void _deselectAll() {
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: WpColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xl,
            vertical: WpSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    icon: const Icon(
                      LucideIcons.arrowLeft,
                      color: WpColors.textPrimary,
                    ),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.replacementsImportReviewTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          l10n.replacementsImportReviewSubtitle(
                            widget.candidates.length,
                          ),
                          style: const TextStyle(
                            color: WpColors.textMuted,
                            fontSize: WpTypography.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WpSpacing.lg),
              WpTextField(
                controller: _searchCtrl,
                variant: WpTextFieldVariant.form,
                hintText: l10n.replacementsImportReviewSearchHint,
                onChanged: _applyFilter,
              ),
              const SizedBox(height: WpSpacing.sm),
              Row(
                children: [
                  // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                  WpButton(
                    label: l10n.replacementsImportReviewSelectAllFiltered,
                    variant: WpButtonVariant.ghost,
                    size: WpButtonSize.dense,
                    onPressed: _filtered.isEmpty ? null : _selectAllFiltered,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                  WpButton(
                    label: l10n.replacementsImportReviewDeselectAll,
                    variant: WpButtonVariant.ghost,
                    size: WpButtonSize.dense,
                    onPressed: _selected.isEmpty ? null : _deselectAll,
                  ),
                  const Spacer(),
                  Text(
                    l10n.replacementsImportReviewSelectedCount(
                      _selected.length,
                      widget.candidates.length,
                    ),
                    style: const TextStyle(color: WpColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: WpSpacing.sm),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WpColors.cardFill,
                    borderRadius: WpRadius.borderMd,
                    border: Border.all(color: WpColors.borderSubtle),
                  ),
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? l10n.replacementsImportNothingFound
                                : l10n.replacementsImportReviewNoMatches,
                            style: const TextStyle(color: WpColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            vertical: WpSpacing.xxs,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final term = _filtered[index];
                            final checked = _selected.contains(term);
                            return InkWell(
                              onTap: () => _toggle(term),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: WpSpacing.sm,
                                  vertical: WpSpacing.xxs,
                                ),
                                child: Row(
                                  children: [
                                    WpRowCheckbox(
                                      value: checked,
                                      onChanged: () => _toggle(term),
                                    ),
                                    const SizedBox(width: WpSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        term,
                                        style: const TextStyle(
                                          color: WpColors.textPrimary,
                                          fontFamily: 'monospace',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: WpSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                  WpButton(
                    label: MaterialLocalizations.of(context).cancelButtonLabel,
                    variant: WpButtonVariant.ghost,
                    tone: WpButtonTone.neutral,
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
                  WpButton(
                    label: l10n.replacementsImportReviewImportButton(
                      _selected.length,
                    ),
                    variant: WpButtonVariant.primary,
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selected.toList()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
