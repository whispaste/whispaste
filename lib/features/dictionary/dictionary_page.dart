/// One dictionary workflow; storage and commands stay with their owners.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/term_hint_effect.dart';
import '../../services/replacements/correction_candidate_detector.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/searchable_list_page.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_page_notice.dart';
import '../replacements/replacements_page.dart';
import 'contact_import_page.dart';
import 'correction_learning_log.dart';
import 'dictionary_notice.dart';
import 'dictionary_tab_target.dart';
import 'dictionary_replacements_tab.dart';
import 'dictionary_suggestions_tab.dart';
import 'term_import_page.dart';
import 'widgets/dictionary_terms_list.dart';

class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key, this.extraTermsSections = const []});
  final List<Widget> extraTermsSections;

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  String _query = '';
  bool _logOpen = false;
  final _replacements = GlobalKey();
  final _suggestions = GlobalKey();
  final _log = GlobalKey();

  void _jump(DictionaryTab target) {
    final key = switch (target) {
      DictionaryTab.replacements => _replacements,
      DictionaryTab.suggestions => _suggestions,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = key.currentContext;
      if (context != null) Scrollable.ensureVisible(context);
      ref.read(dictionaryTabTargetProvider.notifier).set(null);
    });
  }

  @override
  void initState() {
    super.initState();
    final target = ref.read(dictionaryTabTargetProvider);
    if (target != null) _jump(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value;
    ref.listen(dictionaryTabTargetProvider, (_, target) {
      if (target != null) _jump(target);
    });
    final open =
        ref.watch(pendingCorrectionCandidatesProvider).value?.length ?? 0;
    final learning = settings?.behavior.correctionLearningEnabled ?? true;
    final noHints =
        settings != null &&
        termHintEffectFor(
              provider: settings.sttProviderType,
              engine: settings.onDeviceEngine,
            ) ==
            TermHintEffect.replacementOnly;

    return DictionaryReplacementsTab(
      query: _query,
      dictionaryBuilder:
          (
            replacementRows,
            actions,
            addReplacement,
            sortControl,
          ) => DictionaryTermsList(
            onQueryChanged: (value) => setState(() => _query = value),
            toolbarActions: [
              sortControl,
              Builder(
                builder: (buttonContext) => WpIconButton(
                  key: const ValueKey('dictionary-more'),
                  testId: 'dictionary-more',
                  icon: LucideIcons.ellipsis,
                  tooltip: l10n.dockOverflow,
                  onPressed: () => showWpListMenu(buttonContext, [
                    WpListMenuAction(
                      itemKey: const ValueKey('dictionary-add-replacement'),
                      label: l10n.replacementsAdd,
                      icon: LucideIcons.replace,
                      onSelected: addReplacement,
                    ),
                    WpListMenuAction(
                      itemKey: const ValueKey('dictionary-terms-import'),
                      label: l10n.dictionaryTermImport,
                      icon: LucideIcons.fileUp,
                      onSelected: () => openTermImport(context),
                    ),
                    WpListMenuAction(
                      itemKey: const ValueKey('dictionary-contacts-import'),
                      label: l10n.dictionaryContactsMenu,
                      icon: LucideIcons.contact,
                      onSelected: () => openContactImport(context),
                    ),
                    ...actions,
                    WpListMenuAction(
                      itemKey: const ValueKey('dictionary-learning-toggle'),
                      label: l10n.correctionLearningToggleLabel,
                      hint: l10n.dictionarySuggestionsHint(
                        correctionCandidateThreshold,
                      ),
                      icon: LucideIcons.sparkles,
                      checked: learning,
                      onSelected: () => ref
                          .read(settingsProvider.notifier)
                          .updateSettings(
                            (s) => s.copyWithSections(
                              behavior: s.behavior.copyWith(
                                correctionLearningEnabled: !learning,
                              ),
                            ),
                          ),
                    ),
                    if (noHints)
                      WpListMenuAction(
                        itemKey: const ValueKey(
                          'dictionary-terms-similarity-toggle',
                        ),
                        label: l10n.dictionaryTermsSimilarityLabel,
                        hint: l10n.dictionaryTermsSimilarityHint,
                        icon: LucideIcons.spellCheck,
                        checked: settings.behavior.termSimilarityEnabled,
                        onSelected: () => ref
                            .read(settingsProvider.notifier)
                            .updateSettings(
                              (s) => s.copyWithSections(
                                behavior: s.behavior.copyWith(
                                  termSimilarityEnabled:
                                      !s.behavior.termSimilarityEnabled,
                                ),
                              ),
                            ),
                      ),
                  ]),
                ),
              ),
            ],
            layoutBuilder: (toolbar, termRows) => WpPageShell(
              scrollable: false,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.dictionaryIntro,
                    key: const ValueKey('dictionary-intro'),
                  ),
                  const SizedBox(height: WpSpacing.sm),
                  toolbar,
                  Wrap(
                    spacing: WpSpacing.sm,
                    children: [
                      WpButton(
                        testId: 'dictionary-log-open',
                        label: l10n.dictionaryLogTitle,
                        variant: WpButtonVariant.ghost,
                        onPressed: () {
                          // A rising edge opens the section; after the user
                          // closed it, drop the flag for one frame first.
                          final again = _logOpen;
                          setState(() => _logOpen = !again);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            if (again) setState(() => _logOpen = true);
                            final logContext = _log.currentContext;
                            if (logContext != null) {
                              Scrollable.ensureVisible(logContext);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const WpPageNoticeSlot(page: dictionaryNoticePage),
                ],
              ),
              child: Semantics(
                identifier: 'dictionary-list',
                child: SingleChildScrollView(
                  key: const ValueKey('dictionary-list'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heading(
                        _suggestions,
                        open > 0
                            ? l10n.dictionaryTabSuggestionsCount(open)
                            : l10n.dictionaryTabSuggestions,
                      ),
                      DictionarySuggestionsTab(embedded: true, query: _query),
                      // One list (#1969): the replacements, without a
                      // heading of their own; terms follow from them.
                      KeyedSubtree(key: _replacements, child: termRows),
                      if (settings?.textReplacementsEnabled == false)
                        Text(l10n.replacementsToggleDisabled),
                      replacementRows,
                      ...widget.extraTermsSections,
                      KeyedSubtree(
                        key: _log,
                        child: CorrectionLearningLog(
                          // Opens in place, animated; no remount (#1969).
                          initiallyExpanded: _logOpen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _heading(Key key, String label) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}
