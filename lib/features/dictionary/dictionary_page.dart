/// Dictionary: everything that changes how a dictation reads. Three tabs:
/// terms (hints for the recogniser), replacements (fixed rewrites) and
/// suggestions (learned corrections waiting for a decision).
library;

import 'package:flutter/material.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_tabs.dart';
import 'dictionary_replacements_tab.dart';
import 'dictionary_suggestions_tab.dart';
import 'dictionary_terms_tab.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key, this.extraTermsSections = const []});

  /// Extra cards shown under the terms field. The vocabulary row of ticket
  /// is added here, so this page does not need to know about it.
  final List<Widget> extraTermsSections;

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Each tab lays out its own list with the page inset, so the body has
    // none and the tab strip takes the shared header inset.
    return WpPageShell(
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      header: WpTabs(
        labels: [
          l10n.dictionaryTabTerms,
          l10n.dictionaryTabReplacements,
          l10n.dictionaryTabSuggestions,
        ],
        selectedIndex: _tab,
        onSelected: (i) => setState(() => _tab = i),
        itemKeys: const [
          ValueKey('dictionary-tab-terms'),
          ValueKey('dictionary-tab-replacements'),
          ValueKey('dictionary-tab-suggestions'),
        ],
      ),
      child: switch (_tab) {
        0 => DictionaryTermsTab(extraSections: widget.extraTermsSections),
        1 => const DictionaryReplacementsTab(),
        _ => const DictionarySuggestionsTab(),
      },
    );
  }
}
