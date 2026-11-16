/// Dictionary: everything that changes how a dictation reads. Three tabs:
/// terms (hints for the recogniser), replacements (fixed rewrites) and
/// suggestions (learned corrections waiting for a decision).
///
/// The difference between terms and replacements is said once, in the two
/// sentences under the tabs; the tabs themselves only explain what is special
/// to them (the suggestions tab: how corrections are noticed).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../replacements/replacements_page.dart'
    show pendingCorrectionCandidatesProvider;
import '../../widgets/page_shell.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_tabs.dart';
import 'dictionary_notice.dart';
import 'dictionary_tab_target.dart';
import 'dictionary_replacements_tab.dart';
import 'dictionary_suggestions_tab.dart';
import 'dictionary_terms_tab.dart';

class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key, this.extraTermsSections = const []});

  /// Extra cards shown under the terms field. The vocabulary row of ticket
  /// is added here, so this page does not need to know about it.
  final List<Widget> extraTermsSections;

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  late DictionaryTab _tab;

  @override
  void initState() {
    super.initState();
    // A jump from the settings search or a banner may have named the tab.
    _tab = ref.read(dictionaryTabTargetProvider) ?? DictionaryTab.terms;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(dictionaryTabTargetProvider.notifier).set(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // The page can already be alive when the jump comes.
    ref.listen(dictionaryTabTargetProvider, (_, next) {
      if (next == null) return;
      setState(() => _tab = next);
      ref.read(dictionaryTabTargetProvider.notifier).set(null);
    });
    final open =
        ref.watch(pendingCorrectionCandidatesProvider).value?.length ?? 0;
    // Each tab lays out its own list with the page inset, so the body has
    // none and the tab strip takes the shared header inset.
    return WpPageShell(
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      header: WpTabs(
        labels: [
          l10n.dictionaryTabTerms,
          l10n.dictionaryTabReplacements,
          open > 0
              ? l10n.dictionaryTabSuggestionsCount(open)
              : l10n.dictionaryTabSuggestions,
        ],
        selectedIndex: _tab.index,
        onSelected: (i) => setState(() => _tab = DictionaryTab.values[i]),
        itemKeys: const [
          ValueKey('dictionary-tab-terms'),
          ValueKey('dictionary-tab-replacements'),
          ValueKey('dictionary-tab-suggestions'),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpPageFrame.inset,
              WpSpacing.md,
              WpPageFrame.inset,
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                key: const ValueKey('dictionary-intro'),
                l10n.dictionaryIntro,
                style: WpTextStyles.rowNote,
              ),
            ),
          ),
          const WpPageNoticeSlot(page: dictionaryNoticePage),
          Expanded(
            child: switch (_tab) {
              DictionaryTab.terms => DictionaryTermsTab(
                extraSections: widget.extraTermsSections,
              ),
              DictionaryTab.replacements => const DictionaryReplacementsTab(),
              DictionaryTab.suggestions => const DictionarySuggestionsTab(),
            },
          ),
        ],
      ),
    );
  }
}
