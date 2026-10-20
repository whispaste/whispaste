/// Search synonyms in every app language (the ARB `settingsSearchKeywords*`
/// keys).
///
/// [kSettingsSearchTable] carries curated synonyms in DE and EN. For every
/// other app language these lists add the UI language's own words, one comma-separated ARB value per
/// pre-WP-23 settings section. Each list sits on the section's anchor row
/// from [kLegacySettingsDeepLinkRowIds] and on the rows in
/// [kSharedSectionRowIds], so a search in any language lands where it landed
/// before the row model.
library;

import 'settings_search_entry.dart';

/// Legacy section key → its localized synonym list.
final Map<String, SettingsSearchLabel> _sectionKeywords = {
  'interface': (l) => l.settingsSearchKeywordsInterface,
  'hotkey': (l) => l.settingsSearchKeywordsHotkey,
  'updates': (l) => l.settingsSearchKeywordsUpdates,
  'overlay': (l) => l.settingsSearchKeywordsOverlay,
  'floatingButton': (l) => l.settingsSearchKeywordsFloatingButton,
  'audio': (l) => l.settingsSearchKeywordsAudio,
  'recordingSafety': (l) => l.settingsSearchKeywordsRecordingSafety,
  'sound': (l) => l.settingsSearchKeywordsSound,
  'stt': (l) => l.settingsSearchKeywordsStt,
  'afterTranscription': (l) => l.settingsSearchKeywordsAfterTranscription,
  'smartMode': (l) => l.settingsSearchKeywordsSmartMode,
  'privacy': (l) => l.settingsSearchKeywordsPrivacy,
  'history': (l) => l.settingsSearchKeywordsHistory,
  'settingsPortability': (l) => l.settingsSearchKeywordsSettingsPortability,
  'advanced': (l) => l.settingsSearchKeywordsAdvanced,
  'automationApi': (l) => l.settingsSearchKeywordsAutomationApi,
  'onboardingReview': (l) => l.settingsSearchKeywordsOnboardingReview,
  'reviewSupport': (l) => l.settingsSearchKeywordsReviewSupport,
};

/// Row id → localized synonym list, derived from the legacy anchors.
final Map<String, SettingsSearchLabel> kLocalizedSettingsKeywords = {
  for (final MapEntry(:key, :value) in _sectionKeywords.entries)
    kLegacySettingsDeepLinkRowIds[key]!: value,
};

/// Section key → further rows of that section that share its synonym list.
/// The ARB lists name terms of these rows that the anchor row does not own.
const Map<String, List<String>> kSharedSectionRowIds = {
  'afterTranscription': [
    'text-auto-paste-blocklist',
    'text-paste-clipboard-after',
  ],
  'recordingSafety': ['recording-max-duration'],
};

/// Rows that carry their own localized synonym list, for rows that are not
/// section anchors (the overlay background and wave rows).
final Map<String, SettingsSearchLabel> kLocalizedRowKeywords = {
  'appearance-overlay-background': (l) =>
      l.settingsSearchKeywordsOverlayBackground,
  'appearance-overlay-wave': (l) => l.settingsSearchKeywordsOverlayWave,
};

/// Every row that carries a localized synonym list: anchors, shared rows and
/// the rows with their own list.
final Map<String, SettingsSearchLabel> _rowKeywords = {
  ...kLocalizedSettingsKeywords,
  for (final MapEntry(:key, :value) in kSharedSectionRowIds.entries)
    for (final rowId in value) rowId: _sectionKeywords[key]!,
  ...kLocalizedRowKeywords,
};

/// Languages whose synonyms already live in [kSettingsSearchTable]; their
/// broader pre-WP-23 lists would only add noise to the curated rows.
const Set<String> _tableLanguages = {'de', 'en'};

/// The synonyms for [rowId] in [locale]; empty when the row has none or the
/// table already covers the language.
List<String> localizedSettingsKeywords(String rowId, String locale) {
  final keywords = _rowKeywords[rowId];
  final language = locale.split(RegExp('[-_]')).first;
  if (keywords == null || _tableLanguages.contains(language)) return const [];
  return [
    for (final word in keywords(settingsL10nFor(locale)).split(','))
      if (word.trim().isNotEmpty) word.trim(),
  ];
}
