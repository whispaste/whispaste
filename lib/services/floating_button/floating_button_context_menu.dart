/// Builds the floating-button right-click context menu.
///
/// Pure (no I/O, no platform channel) so the menu structure — action ids,
/// order, separators and history truncation — is directly unit-testable, and
/// every label is localized via [L10n] (issue 08, bug D5: the labels used to be
/// hard-coded English). The action ids (`__open__`, `__new_recording__`, …) are
/// the stable back-channel contract consumed by `FloatingButtonService`.
library;

import '../../core/l10n/generated/app_localizations.dart';

/// Maximum visible length of a history-entry label before it is ellipsized.
const int _kHistoryLabelMaxLength = 50;

/// Builds the localized context-menu item list for the floating button.
///
/// [entries] are the most-recent history rows (already capped by the caller);
/// each becomes a clickable item whose id is the entry id. The action block,
/// order and separators are identical to the previous hard-coded English menu —
/// only the labels are now localized.
List<Map<String, String>> buildFloatingButtonContextMenu({
  required L10n l10n,
  required List<({String id, String content})> entries,
}) {
  final actionItems = <Map<String, String>>[
    {'id': '__open__', 'label': l10n.buttonContextOpen},
    {
      'id': '__new_recording__',
      'label': '⏺  ${l10n.buttonContextStartRecording}',
    },
    {'id': '__history__', 'label': l10n.buttonContextShowHistory},
    {'id': '__settings__', 'label': l10n.buttonContextSettings},
    {'id': '__sep1__', 'label': '---'},
  ];

  final historyItems = entries.map((e) {
    final label = e.content.length > _kHistoryLabelMaxLength
        ? '${e.content.substring(0, _kHistoryLabelMaxLength - 3)}...'
        : e.content;
    return {'id': e.id, 'label': label};
  }).toList();

  final footerItems = <Map<String, String>>[
    if (historyItems.isNotEmpty) {'id': '__sep2__', 'label': '---'},
    {'id': '__quit__', 'label': l10n.buttonContextQuit},
  ];

  return [...actionItems, ...historyItems, ...footerItems];
}
