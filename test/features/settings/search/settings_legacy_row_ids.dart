import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';

/// The row a legacy section key deep-links to (its anchor row).
String legacyRowId(String section) =>
    kLegacySettingsDeepLinkRowIds[section] ??
    (throw ArgumentError('no row for section "$section"'));

/// Rows that belonged to a pre-WP-23 section (spec §3 table). Search tests
/// written against section keys now expect one of these rows.
const Map<String, List<String>> _legacySectionRows = {
  'interface': [
    'general-app-language',
    'general-autostart',
    'general-autostart-error',
    'general-notifications',
    'general-close-to-tray',
    'general-sponsor-chip',
  ],
  'hotkey': [
    'general-hotkey-dictation',
    'general-hotkey-combo',
    'general-hold-to-record',
    'general-hold-or-tap',
    'general-hotkey-quick-note',
    'general-hotkey-snippet-picker',
    'general-hotkey-smart-mode',
    'general-hotkey-smart-mode-preset',
    'general-hotkey-smart-mode-target',
    'general-hotkey-smart-mode-combination',
    'general-hotkey-selection-edit',
  ],
  'updates': [
    'general-updates-auto',
    'general-updates-check-now',
    'advanced-beta',
    'advanced-beta-rollback-hint',
  ],
  'appearance': [
    'appearance-mode',
    'appearance-backend-utilization',
    'appearance-side-panel',
    'appearance-side-panel-edge',
  ],
  'overlay': [
    'appearance-overlay-start',
    'appearance-overlay-size',
    'appearance-overlay-background',
    'appearance-overlay-wave',
    'appearance-overlay-live-text',
    'appearance-overlay-preview',
  ],
  'floatingButton': ['appearance-floating-button'],
  'audio': [
    'recording-microphone',
    'recording-gain',
    'recording-clipping-hint',
  ],
  'recordingSafety': [
    'recording-dead-mic',
    'recording-auto-stop-silence',
    'recording-max-duration',
  ],
  'sound': ['recording-sound-volume'],
  'stt': [
    'stt-model',
    'speech-provider',
    'speech-parakeet',
    'speech-quality',
    'speech-benchmark',
    'speech-gpu',
    'speech-cuda-pack',
    'speech-deepgram-key',
    'speech-language',
    'speech-punctuation-priming',
    'speech-vad',
    'speech-vocabulary',
  ],
  'afterTranscription': [
    'text-after-dictation-action',
    'text-strip-punctuation',
    'text-numeric-only',
    'text-remove-filler',
    'text-voice-line-breaks',
    'text-auto-paste-blocklist',
    'text-paste-clipboard-after',
  ],
  'smartMode': [
    'text-smart-mode-preset',
    'text-smart-mode-service',
    'text-smart-mode-key',
    'text-smart-mode-target',
    'text-smart-mode-model',
    'text-smart-mode-speed',
  ],
  'privacy': [
    'privacy-error-reporting',
    'privacy-usage-stats',
    'privacy-retain-audio',
    'privacy-history-retention',
    'privacy-history-hide-on-open',
    'privacy-history-pin',
    'privacy-history-auto-lock',
    'privacy-backup-export',
    'privacy-backup-autosave',
    'privacy-backup-status',
    'privacy-backup-import',
  ],
  'history': [
    'privacy-history-retention',
    'privacy-history-hide-on-open',
    'privacy-history-pin',
    'privacy-history-auto-lock',
  ],
  'settingsPortability': [
    'privacy-backup-export',
    'privacy-backup-autosave',
    'privacy-backup-status',
    'privacy-backup-import',
  ],
  'advanced': [
    'advanced-reset-defaults',
    'advanced-factory-reset',
    'advanced-onboarding-again',
    'advanced-feature-spotlights',
    'advanced-review',
    'advanced-ideas',
  ],
  'automationApi': [
    'advanced-automation-api',
    'advanced-automation-token',
    'advanced-automation-status',
    'advanced-automation-port',
    'advanced-automation-docs',
  ],
  'onboardingReview': ['advanced-onboarding-again'],
  'reviewSupport': ['advanced-review'],
};

/// Every row of a pre-WP-23 section.
List<String> legacyRowIds(String section) =>
    _legacySectionRows[section] ??
    (throw ArgumentError('no rows for section "$section"'));

/// Matches an iterable that holds at least one of [rowIds].
Matcher containsAnyOf(Iterable<String> rowIds) => predicate<Iterable<dynamic>>(
  (actual) => actual.any(rowIds.contains),
  'contains one of $rowIds',
);
