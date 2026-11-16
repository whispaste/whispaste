/// The Begriffe ("terms") list: the words the speech recogniser is nudged
/// towards, one row per term, with a bar on top that filters the list while
/// you type and adds the typed text on Enter.
///
/// The value is still the one `SttSettings.customVocabulary` string (the
/// engines read it raw), so Settings and the dictionary always show the same
/// terms. Every change is written at once; the string is only touched when
/// the user adds, renames or removes a term (see `role_terms.dart`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/dictionary/entry_validation.dart';
import '../../../services/replacements/correction_learning_service.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_banner.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_page_notice.dart';
import '../../../widgets/wp_row_divider.dart';
import '../../../widgets/wp_search_field.dart';
import '../../../widgets/wp_text_field.dart';
import '../../replacements/replacements_page.dart'
    show Replacement, replacementsProvider;
import '../dictionary_notice.dart';
import '../role_terms.dart';
import '../terms_budget_provider.dart';
import 'role_terms_card.dart';

class DictionaryTermsList extends ConsumerStatefulWidget {
  const DictionaryTermsList({super.key});

  @override
  ConsumerState<DictionaryTermsList> createState() =>
      _DictionaryTermsListState();
}

class _DictionaryTermsListState extends ConsumerState<DictionaryTermsList> {
  final _bar = TextEditingController();
  final _barFocus = FocusNode(debugLabel: 'DictionaryTermsList bar');
  final _right = TextEditingController();
  final _rightFocus = FocusNode(debugLabel: 'DictionaryTermsList right');

  /// "Often misspelled as …": the bar then holds the wrong spelling and a
  /// second field the right one; Enter creates a replacement, not a term.
  bool _misspelled = false;

  @override
  void initState() {
    super.initState();
    _bar.addListener(_onBarChanged);
  }

  @override
  void dispose() {
    _bar.removeListener(_onBarChanged);
    _bar.dispose();
    _barFocus.dispose();
    _right.dispose();
    _rightFocus.dispose();
    super.dispose();
  }

  void _onBarChanged() => setState(() {});

  Future<void> _write(String Function(String stored) change) => ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWith(customVocabulary: change(s.stt.customVocabulary)),
      );

  void _notice(String id, String message) => showWpPageNotice(
    context,
    page: dictionaryNoticePage,
    notice: WpPageNotice(
      id: id,
      message: message,
      tone: WpBannerTone.info,
      autoDismiss: const Duration(seconds: 6),
    ),
  );

  /// The sentence for a refused entry: cause and next step.
  String _problemText(
    DictionaryEntryProblem p,
    String term, {
    bool trigger = false,
  }) {
    final l10n = L10n.of(context);
    return switch (p) {
      DictionaryEntryProblem.tooLong => l10n.dictionaryTermsTooLong,
      DictionaryEntryProblem.onlyPunctuation =>
        l10n.dictionaryTermsOnlyPunctuation,
      DictionaryEntryProblem.duplicate => l10n.dictionaryTermsDuplicate(term),
      DictionaryEntryProblem.triggerConflict =>
        trigger
            ? l10n.dictionaryTermsTriggerClash(term)
            : l10n.dictionaryTermsConflictTrigger(term),
    };
  }

  List<String> _triggers() => [
    for (final r
        in ref.read(replacementsProvider).value ?? const <Replacement>[])
      ...r.triggers,
  ];

  void _add(String stored) {
    if (_misspelled) {
      _addReplacement();
      return;
    }
    final l10n = L10n.of(context);
    final typed = _bar.text.trim();
    if (typed.isEmpty) return;
    // Each typed part is checked on its own; the good ones are added, the
    // others are named with their cause.
    final triggers = _triggers();
    final existing = vocabularyTerms(stored).toList();
    final good = <String>[];
    DictionaryEntryProblem? firstProblem;
    String? firstBad;
    var skipped = 0;
    for (final part in vocabularyTerms(typed)) {
      final problem = checkDictionaryEntry(
        part,
        existing: [...existing, ...good],
        triggers: triggers,
      );
      if (problem == null) {
        good.add(part);
      } else {
        skipped++;
        firstProblem ??= problem;
        firstBad ??= part;
      }
    }
    if (good.isEmpty) {
      // Nothing to add. The bar keeps the text, so the filter shows the rows
      // that are there.
      if (firstProblem != null) {
        _notice('term-problem', _problemText(firstProblem, firstBad!));
      }
      _barFocus.requestFocus();
      return;
    }
    _write((s) => addVocabularyTerms(s, good.join(', ')).vocabulary);
    _bar.clear();
    if (skipped > 0) {
      _notice(
        'term-problem',
        l10n.dictionaryTermsSkipped(
          skipped,
          _problemText(firstProblem!, firstBad!),
        ),
      );
    }
    announce(
      View.of(context),
      good.length == 1
          ? l10n.dictionaryTermsAdded(good.first)
          : l10n.dictionaryTermsAddedMany(good.length),
      Directionality.of(context),
    );
    _barFocus.requestFocus();
  }

  Future<void> _addReplacement() async {
    final l10n = L10n.of(context);
    final wrong = _bar.text.trim();
    final right = _right.text.trim();
    if (wrong.isEmpty) return;
    if (right.isEmpty) {
      _notice('term-problem', l10n.dictionaryTermsRightMissing);
      _rightFocus.requestFocus();
      return;
    }
    final problem = checkDictionaryEntry(
      wrong,
      existing: _triggers(),
      triggers: const [],
    );
    if (problem != null) {
      _notice(
        'term-problem',
        problem == DictionaryEntryProblem.duplicate
            ? l10n.dictionaryTermsTriggerClash(wrong)
            : _problemText(problem, wrong, trigger: true),
      );
      _barFocus.requestFocus();
      return;
    }
    if (wrong.toLowerCase() == right.toLowerCase()) {
      _notice('term-problem', l10n.dictionaryTermsRightSame);
      _rightFocus.requestFocus();
      return;
    }
    // Read before the await: the widget may be gone when it returns.
    final view = View.of(context);
    final direction = Directionality.of(context);
    await ref.read(replacementsProvider.notifier).add([wrong], right);
    if (!mounted) return;
    final message = l10n.dictionaryTermsReplacementAdded(wrong, right);
    _bar.clear();
    _right.clear();
    _notice('replacement-added', message);
    announce(view, message, direction);
    _barFocus.requestFocus();
  }

  void _setMisspelled(bool on) {
    setState(() => _misspelled = on);
    if (!on) _right.clear();
    _barFocus.requestFocus();
  }

  void _delete(int index, String term) {
    final l10n = L10n.of(context);
    // Captured now: the notice and its undo outlive this widget (tab change).
    final container = ProviderScope.containerOf(context, listen: false);
    _write((s) => removeVocabularyTerm(s, index));
    // The list row under the pointer is gone; keep the keyboard in the list.
    _barFocus.requestFocus();
    // No auto-dismiss: the undo stays until closed or the next delete.
    showWpPageNotice(
      context,
      page: dictionaryNoticePage,
      notice: WpPageNotice(
        id: 'term-removed',
        message: l10n.dictionaryTermsRemoved(term),
        tone: WpBannerTone.info,
        action: (_) => WpButton(
          testId: 'dictionary-term-undo',
          label: l10n.undo,
          variant: WpButtonVariant.ghost,
          onPressed: () {
            container
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWith(
                    customVocabulary: insertVocabularyTerm(
                      s.stt.customVocabulary,
                      index,
                      term,
                    ),
                  ),
                );
            container
                .read(wpPageNoticeProvider(dictionaryNoticePage).notifier)
                .dismiss();
          },
        ),
      ),
    );
  }

  Future<void> _edit(int index, String term) async {
    // Read before the dialog: this widget may be gone when it closes.
    final notifier = ref.read(settingsProvider.notifier);
    final renamed = await showWpFormDialog<String>(
      context: context,
      builder: (_, animation) => _EditTermDialog(
        animation: animation,
        term: term,
        findClash: (text) => renameVocabularyTerm(
          ref.read(settingsProvider).value?.stt.customVocabulary ?? '',
          index,
          text,
        ).duplicateOf,
      ),
    );
    if (renamed == null) return;
    await notifier.updateSettings(
      (s) => s.copyWith(
        customVocabulary: renameVocabularyTerm(
          s.stt.customVocabulary,
          index,
          renamed,
        ).vocabulary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final stored = ref.watch(
      settingsProvider.select((s) => s.value?.stt.customVocabulary ?? ''),
    );
    final terms = vocabularyTerms(stored);
    final learned = ref.watch(learnedTermsProvider).value ?? const <String>{};
    final leftOutFrom = ref.watch(termsLeftOutFromProvider).value;
    // While the bar holds a wrong spelling it is no search.
    final query = _misspelled ? '' : _bar.text.trim().toLowerCase();
    final triggerKeys = {for (final t in _triggers()) t.trim().toLowerCase()};
    final shown = [
      for (var i = 0; i < terms.length; i++)
        if (query.isEmpty || terms[i].toLowerCase().contains(query)) i,
    ];

    // Cmd+F on macOS, Ctrl+F elsewhere: the same binding as the other lists.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: defaultTargetPlatform != TargetPlatform.macOS,
          meta: defaultTargetPlatform == TargetPlatform.macOS,
        ): _barFocus.requestFocus,
        // Escape backs out of the add mode, then empties the bar.
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_misspelled) {
            _setMisspelled(false);
          } else if (_bar.text.isNotEmpty) {
            _bar.clear();
          }
        },
      },
      // Vertical only: on the page the list around it owns the side edges.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: WpSearchField(
                    key: const ValueKey('dictionary-terms-bar'),
                    testId: 'dictionary-terms-bar',
                    controller: _bar,
                    focusNode: _barFocus,
                    hintText: _misspelled
                        ? l10n.dictionaryTermsWrongHint
                        : l10n.dictionaryTermsBarHint,
                    semanticsLabel: _misspelled
                        ? l10n.dictionaryTermsWrongLabel
                        : l10n.dictionaryTermsBarLabel,
                    variant: WpSearchFieldVariant.outlined,
                    onSubmitted: (_) =>
                        _misspelled ? _rightFocus.requestFocus() : _add(stored),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                WpIconButton(
                  key: const ValueKey('dictionary-terms-add'),
                  testId: 'dictionary-terms-add',
                  icon: LucideIcons.plus,
                  tooltip: l10n.dictionaryTermsAdd,
                  onPressed: _bar.text.trim().isEmpty
                      ? null
                      : () => _add(stored),
                ),
              ],
            ),
            const SizedBox(height: WpSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: WpFilterChip(
                testId: 'dictionary-terms-misspelled-toggle',
                label: l10n.dictionaryTermsMisspelledToggle,
                isActive: _misspelled,
                onTap: () => _setMisspelled(!_misspelled),
              ),
            ),
            if (_misspelled) ...[
              const SizedBox(height: WpSpacing.sm),
              WpTextField(
                key: const ValueKey('dictionary-terms-right'),
                controller: _right,
                focusNode: _rightFocus,
                variant: WpTextFieldVariant.form,
                hintText: l10n.dictionaryTermsRightHint,
                semanticsLabel: l10n.dictionaryTermsRightLabel,
                onSubmitted: (_) => _addReplacement(),
              ),
            ],
            const SizedBox(height: WpSpacing.sm),
            Semantics(
              identifier: 'dictionary-terms-list',
              container: true,
              label: l10n.dictionaryTabTerms,
              child: Column(
                key: const ValueKey('dictionary-terms-list'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (terms.isEmpty) ...[
                    _Note(
                      id: 'dictionary-terms-empty',
                      text: l10n.dictionaryTermsEmpty,
                    ),
                    // Once, while the list is empty: the packs for the roles
                    // chosen at the start, taken over or hidden for good.
                    _ExampleChips(
                      onPick: (example) {
                        _bar.text = example;
                        _bar.selection = TextSelection.collapsed(
                          offset: example.length,
                        );
                        _barFocus.requestFocus();
                      },
                    ),
                    const RoleTermsCard(),
                  ] else if (shown.isEmpty) ...[
                    _Note(
                      id: 'dictionary-terms-no-match',
                      liveRegion: true,
                      text: l10n.dictionaryTermsNoMatch(_bar.text.trim()),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: WpButton(
                        testId: 'dictionary-terms-create-from-search',
                        label: l10n.dictionaryTermsCreateFromSearch(
                          _bar.text.trim(),
                        ),
                        variant: WpButtonVariant.secondary,
                        size: WpButtonSize.dense,
                        onPressed: () => _add(stored),
                      ),
                    ),
                  ] else
                    for (var n = 0; n < shown.length; n++) ...[
                      if (leftOutFrom != null &&
                          query.isEmpty &&
                          shown[n] == leftOutFrom)
                        _LeftOutDivider(text: l10n.dictionaryTermsLeftOut)
                      else if (n > 0)
                        Divider(height: 1, color: WpColors.borderSubtle),
                      _TermRow(
                        index: shown[n],
                        term: terms[shown[n]],
                        learned: learned.contains(
                          terms[shown[n]].toLowerCase(),
                        ),
                        // Filtered: the divider is hidden too, so no grey
                        // row may stand without its line of text.
                        alsoReplacement: triggerKeys.contains(
                          terms[shown[n]].toLowerCase(),
                        ),
                        leftOut:
                            query.isEmpty &&
                            leftOutFrom != null &&
                            shown[n] >= leftOutFrom,
                        onMoveUp: query.isEmpty && shown[n] > 0
                            ? () {
                                _write(
                                  (s) => moveVocabularyTermUp(s, shown[n]),
                                );
                                // The row is rebuilt under its new index; keep
                                // the keyboard in the list like after a delete.
                                _barFocus.requestFocus();
                              }
                            : null,
                        onEdit: () => _edit(shown[n], terms[shown[n]]),
                        onDelete: () => _delete(shown[n], terms[shown[n]]),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.id, required this.text, this.liveRegion = false});

  final String id;
  final String text;

  /// Read out when it appears (the filter found nothing).
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: id,
      container: true,
      liveRegion: liveRegion,
      child: Padding(
        key: ValueKey(id),
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
        child: Text(
          text,
          style: TextStyle(
            fontSize: WpTypography.small,
            color: WpColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Examples in the empty list: one tap puts the example into the bar, Enter
/// adds it. They only teach what a term looks like; nothing is added alone.
class _ExampleChips extends StatelessWidget {
  const _ExampleChips({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final examples = vocabularyTerms(l10n.dictionaryTermsExamples);
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Wrap(
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.dictionaryTermsExamplesLabel,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textMuted,
            ),
          ),
          for (var i = 0; i < examples.length; i++)
            WpFilterChip(
              testId: 'dictionary-terms-example-$i',
              label: examples[i],
              isActive: false,
              onTap: () => onPick(examples[i]),
            ),
        ],
      ),
    );
  }
}

/// The line between the terms the recognition uses and those it leaves out.
/// Read out as it is, so a screen reader hears where the limit lies.
class _LeftOutDivider extends StatelessWidget {
  const _LeftOutDivider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'dictionary-terms-left-out',
      container: true,
      child: Padding(
        key: const ValueKey('dictionary-terms-left-out'),
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
        child: Row(
          children: [
            const Expanded(child: WpRowDivider()),
            // Flexible, not bare: a Row gives bare children unbounded width,
            // so a long line would overflow at large text scales.
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
            ),
            const Expanded(child: WpRowDivider()),
          ],
        ),
      ),
    );
  }
}

/// One term with its always-visible actions.
class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.index,
    required this.term,
    required this.leftOut,
    required this.alsoReplacement,
    required this.learned,
    required this.onMoveUp,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final String term;

  /// The active recognition does not use this term (it is below the divider).
  final bool leftOut;

  /// The term is also the trigger of a replacement (it works twice).
  final bool alsoReplacement;
  final bool learned;

  /// Null for the first term and while the list is filtered.
  final VoidCallback? onMoveUp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      identifier: 'dictionary-term-row-$index',
      container: true,
      child: Row(
        key: ValueKey('dictionary-term-row-$index'),
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: WpSpacing.sm,
                children: [
                  Text(
                    term,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: leftOut ? WpColors.textMuted : null,
                    ),
                  ),
                  if (learned)
                    Text(
                      l10n.dictionaryTermLearned,
                      key: ValueKey('dictionary-term-learned-$index'),
                      style: TextStyle(
                        fontSize: WpTypography.small,
                        color: WpColors.textMuted,
                      ),
                    ),
                  if (alsoReplacement)
                    Text(
                      key: ValueKey('dictionary-term-also-replacement-$index'),
                      l10n.dictionaryTermsAlsoReplacement,
                      style: TextStyle(
                        fontSize: WpTypography.small,
                        color: WpColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          WpIconButton.ghost(
            key: ValueKey('dictionary-term-move-up-$index'),
            testId: 'dictionary-term-move-up-$index',
            icon: LucideIcons.arrowUp,
            tooltip: l10n.dictionaryTermsMoveUpTooltip(term),
            onPressed: onMoveUp,
          ),
          WpIconButton.ghost(
            key: ValueKey('dictionary-term-edit-$index'),
            testId: 'dictionary-term-edit-$index',
            icon: LucideIcons.pencil,
            tooltip: l10n.dictionaryTermsEditTooltip(term),
            onPressed: onEdit,
          ),
          WpIconButton.ghost(
            key: ValueKey('dictionary-term-delete-$index'),
            testId: 'dictionary-term-delete-$index',
            icon: LucideIcons.trash2,
            tooltip: l10n.dictionaryTermsDeleteTooltip(term),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Small dialog to change one term. Saving a spelling that another term
/// already has stays in the dialog and says so.
class _EditTermDialog extends StatefulWidget {
  const _EditTermDialog({
    required this.animation,
    required this.term,
    required this.findClash,
  });

  final Animation<double> animation;
  final String term;

  /// Index of another term with the typed spelling, or null.
  final int? Function(String text) findClash;

  @override
  State<_EditTermDialog> createState() => _EditTermDialogState();
}

class _EditTermDialogState extends State<_EditTermDialog> {
  late final TextEditingController _ctrl;
  bool _clash = false;
  bool _several = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.term);
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.term.length,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => _ctrl.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    final text = _ctrl.text.trim();
    if (vocabularyTextHoldsSeveral(text)) {
      setState(() => _several = true);
      return;
    }
    if (widget.findClash(text) != null) {
      setState(() => _clash = true);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.dictionaryTermsEditTitle,
      subtitle: l10n.dictionaryTermsEditSubtitle,
      fields: [
        if (_clash || _several) ...[
          Semantics(
            identifier: 'dictionary-term-edit-problem',
            liveRegion: true,
            child: WpBanner(
              key: const ValueKey('dictionary-term-edit-problem'),
              tone: WpBannerTone.error,
              message: _several
                  ? l10n.dictionaryTermsEditOneOnly
                  : l10n.dictionaryTermsDuplicate(_ctrl.text.trim()),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
        ],
        WpTextField(
          key: const ValueKey('dictionary-term-edit-field'),
          controller: _ctrl,
          variant: WpTextFieldVariant.form,
          autofocus: true,
          semanticsLabel: l10n.dictionaryTermsEditTitle,
          onChanged: (_) => setState(() {
            _clash = false;
            _several = false;
          }),
          onSubmitted: (_) => _submit(),
        ),
      ],
      actions: [
        WpDialogAction(
          label: l10n.actionCancel,
          testId: 'dictionary-term-edit-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction(
          label: l10n.actionSave,
          testId: 'dictionary-term-edit-save',
          role: WpDialogActionRole.primary,
          enabled: _valid,
          onPressed: _submit,
        ),
      ],
    );
  }
}
