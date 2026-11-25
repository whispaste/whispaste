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
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/dictionary/entry_validation.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_collection_page.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_notice_bar.dart';
import '../../../widgets/wp_search_field.dart';
import '../../../widgets/wp_text_field.dart';
import '../../replacements/replacements_page.dart'
    show Replacement, replacementsProvider;
import '../role_terms.dart';
import '../term_store.dart';
import 'role_terms_card.dart';

class DictionaryTermsList extends ConsumerStatefulWidget {
  const DictionaryTermsList({
    super.key,
    this.layoutBuilder,
    this.onQueryChanged,
    this.toolbarActions = const [],
  });

  final Widget Function(Widget toolbar, Widget rows)? layoutBuilder;
  final ValueChanged<String>? onQueryChanged;
  final List<Widget> toolbarActions;

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

  void _onBarChanged() {
    setState(() {});
    widget.onQueryChanged?.call(_misspelled ? '' : _bar.text.trim());
  }

  /// A refused entry or a done change: both close themselves, so they stand
  /// in the notice bar at the bottom and never push the list (#1903).
  void _notice(String id, String message) =>
      showWpConfirmation(context, id: 'dictionary-$id', message: message);

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

  void _add() {
    if (_misspelled) {
      _addReplacement();
      return;
    }
    final l10n = L10n.of(context);
    final typed = _bar.text.trim();
    if (typed.isEmpty) return;
    // Each typed part is checked on its own; the good ones are added, the
    // others are named with their cause.
    // A term is a term entry "term → term" (#1969): checked against the
    // triggers, the one list there is.
    final existing = _triggers();
    final good = <String>[];
    DictionaryEntryProblem? firstProblem;
    String? firstBad;
    var skipped = 0;
    for (final part in vocabularyTerms(typed)) {
      final problem = checkDictionaryEntry(
        part,
        existing: [...existing, ...good],
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
    addDictionaryTerms(ProviderScope.containerOf(context), good);
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
    widget.onQueryChanged?.call(on ? '' : _bar.text.trim());
    _barFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // While the bar holds a wrong spelling it is no search.
    final query = _misspelled ? '' : _bar.text.trim().toLowerCase();
    final replacements = ref.watch(replacementsProvider).value;
    final empty = replacements != null && replacements.isEmpty;
    final noMatch =
        query.isNotEmpty &&
        replacements != null &&
        !replacements.any(
          (r) =>
              r.replacement.toLowerCase().contains(query) ||
              r.triggers.any((t) => t.toLowerCase().contains(query)),
        );

    // The page family's head (#1969): the same row, gaps and order as Notes
    // and Snippets. Before, the actions were laid flush after the field.
    final toolbar = Column(
      children: [
        WpCollectionToolbar(
          screenId: 'dictionary',
          framed: false,
          search: WpSearchField(
            key: const ValueKey('dictionary-terms-bar'),
            testId: 'dictionary-terms-bar',
            controller: _bar,
            focusNode: _barFocus,
            autofocus: widget.layoutBuilder != null,
            hintText: _misspelled
                ? l10n.dictionaryTermsWrongHint
                : l10n.dictionaryTermsBarHint,
            semanticsLabel: _misspelled
                ? l10n.dictionaryTermsWrongLabel
                : l10n.dictionaryTermsBarLabel,
            variant: WpSearchFieldVariant.outlined,
            onSubmitted: (_) =>
                _misspelled ? _rightFocus.requestFocus() : _add(),
          ),
          // Only for something typed (#1969): with an empty bar there is
          // nothing that could be misspelled.
          searchActions: [
            if (_misspelled || _bar.text.trim().isNotEmpty)
              WpFilterChip(
                key: const ValueKey('dictionary-terms-misspelled-toggle'),
                testId: 'dictionary-terms-misspelled-toggle',
                label: l10n.dictionaryTermsMisspelledToggle,
                isActive: _misspelled,
                onTap: () => _setMisspelled(!_misspelled),
              ),
          ],
          tools: widget.toolbarActions,
          primaryAction: WpIconButton(
            key: const ValueKey('dictionary-terms-add'),
            testId: 'dictionary-terms-add',
            icon: LucideIcons.plus,
            tooltip: l10n.dictionaryTermsAdd,
            onPressed: _bar.text.trim().isEmpty ? null : () => _add(),
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
      ],
    );
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
      child: _layout(
        toolbar,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                identifier: 'dictionary-terms-list',
                container: true,
                label: l10n.dictionaryTabTerms,
                child: Column(
                  key: const ValueKey('dictionary-terms-list'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (empty && query.isEmpty) ...[
                      _Note(
                        id: 'dictionary-terms-empty',
                        text: l10n.dictionaryTermsEmpty,
                      ),
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
                    ] else if (noMatch) ...[
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
                          onPressed: _add,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layout(Widget toolbar, Widget rows) =>
      widget.layoutBuilder?.call(toolbar, rows) ??
      Column(children: [toolbar, rows]);
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
