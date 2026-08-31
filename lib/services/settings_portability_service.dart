/// Dateibasierter Settings-Export/-Import — der vollständige portable
/// Einstellungszustand (`AppSettings.toStorageMap()` abzüglich
/// [settingsPortabilityDenyList]), plus Text-Replacements und Snippets, die
/// nicht aus `AppSettings` stammen. PRD `settings-portability-vollumfang`
/// (Ticket 01); Vorläufer: PRD `experience-perf-polish` Cluster 5
/// „Portabilität & Fehler-Feedback" (v1, vier hartkodierte Felder).
///
/// Deliberately excludes History and Audio (privacy/scope) and API
/// keys (`openai_api_key`/`deepgram_api_key` — always written empty by
/// `CloudProviderSettings.toMap()`, and additionally deny-listed here for
/// readability) — see the PRD for rationale.
///
/// Format v2's root object still carries a top-level `hotkey` object and
/// `custom_vocabulary` string (both derived from `settings`, never a second
/// source) purely so the already-published v1 decoder — which throws without
/// them — can still import a v2 file. `settings` always wins on read.
library;

import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';

import '../core/config/settings_provider.dart' show AppSettings;
import '../core/config/settings_sections.dart' show HotkeySettings;
import '../features/replacements/replacements_page.dart' show Replacement;
import '../features/snippets/snippets_page.dart' show SnippetItem;

// ---------------------------------------------------------------------------
// Deny list
// ---------------------------------------------------------------------------

/// Storage keys excluded from the export file in both directions: excluded
/// from `settings` on [SettingsPortabilityService.encode], and filtered out
/// of an imported file's map again before merging (so a hand-edited or
/// foreign-version file cannot smuggle them back in).
///
/// Key-genau, nicht sektionsweise — z. B. ist `microphone` der einzige
/// ausgeschlossene Key aus `AudioInputSettings`; `push_to_talk` und
/// `input_gain` derselben Sektion bleiben portabel.
///
/// Neue Einträge gehören an diese eine Stelle.
const Set<String> settingsPortabilityDenyList = {
  // BenchmarkSettings — hardwaregebunden, auf dem Zielrechner falsch.
  'tier_benchmark_rtf',
  'benchmark_hardware_id',
  'benchmark_timestamp',
  // WindowPositionSettings — monitorgebunden.
  'floating_button_x',
  'floating_button_y',
  'floating_overlay_x',
  'floating_overlay_y',
  'window_x',
  'window_y',
  'window_width',
  'window_height',
  'window_maximized',
  // OnboardingSettings — Fortschritt/Zustand, keine Präferenz.
  'onboarding_completed',
  'onboarding_current_step',
  // Added post-PRD (`onboarding_flow_version`, commit f0599fd9): tracks
  // which onboarding step-sequence version a saved position indexes into,
  // same category as `onboarding_current_step` above — progress/migration
  // state, not a preference.
  'onboarding_flow_version',
  // Added for the onboarding revision registry (`.scratch/
  // onboarding-revisions/issues/01`): last content revision this
  // installation was shown/grandfathered to. Progress/migration state
  // exactly like the two keys above, not a preference — and doubly wrong
  // to import, since a foreign install's revision history has nothing to
  // do with what this one has already seen.
  'onboarding_content_version',
  // Feature-spotlight registry (`.scratch/feature-spotlight/issues/01`):
  // ids of hints this installation has already been shown. Same category as
  // `onboarding_content_version` above — progress/seen-state, not a
  // preference — and just as wrong to import: a foreign install's spotlight
  // history has nothing to do with what this one has already seen.
  'seen_feature_spotlight_ids',
  'auto_paste_off_hint_dismissed',
  // Smart Mode post-usage discovery hint (ticket 08 of
  // `.scratch/smart-mode-v2/`): same category as the two seen-state keys
  // above — whether this installation already showed the one-time hint,
  // not a preference to carry to another machine.
  'smart_mode_usage_hint_shown',
  // AudioInputSettings — gerätegebundener Mikrofonname.
  'microphone',
  // AppSettings.toStorageMap() — reines Persistenz-Artefakt, von
  // fromStorageMap nie gelesen; hat neben format_version nichts verloren.
  'schema_version',
  // CloudProviderSettings — Klarheit/Verteidigung in der Tiefe. Der
  // tragende Schutz ist die API-Key-Rückinjektion beim Import, siehe
  // `mergeImportedSettings`; diese beiden Keys hier helfen dabei nicht (ein
  // *fehlender* Key läse ohnehin als '' über CloudProviderSettings.fromMap).
  'openai_api_key',
  'deepgram_api_key',
  // SettingsPortabilityPathSettings (Ticket 03) — describe *where* the
  // export file lives on this machine, not *what* is exported. Bookmark
  // blobs are additionally security-scoped tokens bound to this machine and
  // this app's code signature; they are meaningless on the target machine.
  'settings_export_path',
  'settings_import_path',
  'settings_export_bookmark',
  'settings_import_bookmark',
  // SettingsAutosaveSettings (Ticket 26) — same category as the four keys
  // above, one machine's backup *plumbing* rather than any part of the
  // configuration being backed up: a rotation folder that does not exist on
  // the target machine, a bookmark bound to this machine and code
  // signature, and two timestamps describing runs that happened here.
  //
  // Deny-listing also carries the feature's loop guard: the autosave
  // trigger compares this same filtered map, so writing the timestamps back
  // after a run is invisible to it and cannot schedule the next run. Moving
  // any of these five keys off this list re-arms that loop.
  'settings_autosave_enabled',
  'settings_autosave_folder',
  'settings_autosave_bookmark',
  'settings_autosave_last_success',
  'settings_autosave_last_error',
};

/// Every storage key that is neither deny-listed nor a genuinely new
/// section-less key must be explicitly acknowledged as portable here — the
/// anti-obsolescence test in `settings_portability_service_test.dart` fails
/// otherwise. Not consulted at runtime (an unknown new key travels
/// automatically, by design); this is purely the maintainer checkpoint.
///
/// Derived by dumping `AppSettings.defaults.toStorageMap().keys` and sorting
/// every key into this list or [settingsPortabilityDenyList] — not
/// reconstructed from reading section classes by eye.
const Set<String> settingsPortabilityPortableKeysForTest = {
  'after_transcription',
  'auto_paste_blocklist',
  'auto_paste_delay',
  'auto_stop_silence',
  'check_updates',
  'close_to_tray',
  'cloud_stt_provider',
  'custom_vocabulary',
  'dead_mic_timeout',
  'duration_warning_sound',
  // Consent flags — bewusst portabel, siehe Implementation Decisions im
  // Eltern-PRD ("Telemetrie-Schalter reisen bewusst mit").
  'error_reporting',
  'error_sound',
  'gpu_acceleration',
  'history_auto_trash_days',
  'history_max_entries',
  'hotkey_enabled',
  'hotkey_key',
  'hotkey_key_display',
  'hotkey_modifiers',
  'input_gain',
  'launch_at_startup',
  'locale',
  'max_record_duration',
  'overlay_mode',
  'overlay_size',
  'overlay_start_position',
  'overlay_style',
  'push_to_talk',
  // Ticket 20: second, independently configurable hotkey — same portability
  // rationale as the existing 'hotkey_*' keys above.
  'quick_note_hotkey_enabled',
  'quick_note_hotkey_key',
  'quick_note_hotkey_key_display',
  'quick_note_hotkey_modifiers',
  'record_start_sound',
  'record_stop_sound',
  // PrivacySettings — a behavior preference, not the audio data itself
  // (which the export deliberately excludes, same as History's entries vs.
  // its own portable 'history_*' preferences above).
  'retain_recent_audio',
  'share_usage_stats',
  // Clipboard quick-paste side panel toggle — a display preference like the
  // other 'show_*' keys below it.
  'side_panel_enabled',
  // Ticket: status-bar CPU/GPU backend-utilization chip — a display
  // preference like the other 'show_*' keys around it.
  'show_backend_utilization',
  'show_floating_button',
  'show_notifications',
  'show_overlay',
  // Ticket 26: third, independently configurable hotkey (opens the
  // Snippet-Picker panel) — same portability rationale as 'hotkey_*'/
  // 'quick_note_hotkey_*' above.
  'snippet_picker_hotkey_enabled',
  'snippet_picker_hotkey_key',
  'snippet_picker_hotkey_key_display',
  'snippet_picker_hotkey_modifiers',
  'snippet_picker_trigger',
  // Ticket 01 of `.scratch/smart-mode-v2/` — standard preset is a genuine
  // user preference, portable like any other section field.
  'smart_mode_standard_preset',
  // Ticket 03 of `.scratch/smart-mode-v2/` — same rationale as the preset
  // above.
  'smart_mode_target_language',
  // Ticket 06 of `.scratch/smart-mode-v2/` — local/cloud engine choice, same
  // rationale as the preset above. The OpenAI API key itself lives in secure
  // storage (shared with Cloud STT) and is never portable, by design.
  'smart_mode_provider',
  // Ticket 04 of `.scratch/smart-mode-v2/`: fourth, independently
  // configurable hotkey (bound to one preset) — same portability rationale
  // as 'hotkey_*'/'quick_note_hotkey_*'/'snippet_picker_hotkey_*' above.
  'smart_mode_hotkey_enabled',
  'smart_mode_hotkey_key',
  'smart_mode_hotkey_key_display',
  'smart_mode_hotkey_modifiers',
  'smart_mode_hotkey_preset',
  'sound_volume',
  'start_minimized',
  'stt_engine',
  'stt_idle_timeout_minutes',
  'stt_language',
  'stt_model',
  'stt_numeric_only_mode',
  'stt_provider',
  'stt_punctuation_priming',
  'stt_strip_punctuation',
  'stt_vad_enabled',
  'text_replacements_enabled',
  // No 'theme_mode' since 2026-08-11. It left this list with the light theme:
  // `toStorageMap()` no longer emits the key, and the assertion that every
  // emitted key is accounted for here cuts both ways — a portable key with
  // nothing to carry fails it just as loudly as an unlisted one. An older
  // export file that still contains the key stays importable; the merge path
  // does not consult this list, so the stale entry is ignored rather than
  // rejected.
  'transcription_complete_sound',
};

// ---------------------------------------------------------------------------
// Bundle
// ---------------------------------------------------------------------------

/// The portable settings bundled into a single export file.
///
/// [settings] is the flat storage-key map — the same shape
/// `AppSettings.toStorageMap()`/`fromStorageMap()` already use for SQLite
/// persistence, already filtered against [settingsPortabilityDenyList].
/// [replacements] and [snippets] stay separate lists because they do not
/// come from `AppSettings` (they live in `replacementsProvider` /
/// `snippetsProvider`) and must not be folded into the settings map.
///
/// [snippets] is deliberately nullable — unlike [replacements] it must not
/// become a required section, so an export file produced by a version of the
/// app that predates the Snippets feature still imports without exception.
/// `null` means "section absent from the file" (leave the user's existing
/// snippets untouched on import); an empty list means "section present, user
/// genuinely has zero snippets" (clear them on import). Collapsing those two
/// into one empty-list default would silently delete snippets on every
/// import of an older export.
class SettingsExportBundle {
  const SettingsExportBundle({
    required this.settings,
    required this.replacements,
    this.snippets,
  });

  final Map<String, String> settings;
  final List<Replacement> replacements;
  final List<SnippetItem>? snippets;
}

/// Builds the bundle every export writes, from live app state.
///
/// Shared by the manual export (`SettingsPortabilityController.gather`, wired
/// in `settings_portability_section.dart`) and the automatic one
/// (`SettingsAutosaveRunner.gather`, wired in `app.dart`) so the two can
/// never come to differ in *what* they consider portable — a file the user
/// exported by hand and one the automation wrote a second later must be the
/// same file.
///
/// The settings map is filtered against [settingsPortabilityDenyList] here
/// *and* again in [SettingsPortabilityService.encode], the file-writing
/// boundary, which cannot assume its caller filtered — deliberate, not
/// accidental duplication. It matters for the machine-bound keys (window
/// geometry, onboarding progress, microphone, autosave configuration) that
/// carry real values at this point; the two API-key entries are moot either
/// way, since `CloudProviderSettings.toMap()` always writes them as ''
/// regardless of filtering (secure storage is the real API-key guard — see
/// [mergeImportedSettings]).
SettingsExportBundle buildSettingsExportBundle({
  required AppSettings settings,
  required List<Replacement> replacements,
  required List<SnippetItem> snippets,
}) => SettingsExportBundle(
  settings: <String, String>{
    for (final entry in settings.toStorageMap().entries)
      if (!settingsPortabilityDenyList.contains(entry.key))
        entry.key: entry.value,
  },
  replacements: replacements,
  snippets: snippets,
);

// ---------------------------------------------------------------------------
// Merge seam
// ---------------------------------------------------------------------------

/// Merges an imported settings map onto [current] and returns the
/// [AppSettings] to hand to a single `updateSettings` call. Carries
/// filtering, merge-not-replace semantics, and API-key re-injection as one
/// testable unit — kept out of the settings widget so the
/// security-relevant API-key behaviour is unit-testable without a widget
/// test.
///
/// - [imported] is filtered against [settingsPortabilityDenyList] first, so
///   a hand-edited or foreign-version file cannot smuggle window geometry,
///   onboarding progress, or the microphone selection back in even though
///   [SettingsPortabilityService.encode] already omits them.
/// - The result is `{...current.toStorageMap(), ...filtered imported}` run
///   through `AppSettings.fromStorageMap` — a key the file doesn't mention
///   keeps its current value (not the factory default); a key the file
///   knows and this build doesn't is silently dropped by `fromStorageMap`.
/// - The in-memory API keys from [current] are written back onto the merged
///   result before returning. Without this, `_syncApiKeysToSecureStorage`
///   (`settings_provider.dart`) sees the merged settings' empty
///   `openai_api_key`/`deepgram_api_key` (both are always written empty by
///   `CloudProviderSettings.toMap`, deny-listed or not) against the
///   previously non-empty keychain value and deletes it.
AppSettings mergeImportedSettings(
  AppSettings current,
  Map<String, String> imported,
) {
  final filteredImported = <String, String>{
    for (final entry in imported.entries)
      if (!settingsPortabilityDenyList.contains(entry.key))
        entry.key: entry.value,
  };
  final merged = AppSettings.fromStorageMap({
    ...current.toStorageMap(),
    ...filteredImported,
  });
  return merged.copyWithSections(
    cloudProvider: merged.cloudProvider.copyWith(
      openAiApiKey: current.cloudProvider.openAiApiKey,
      deepgramApiKey: current.cloudProvider.deepgramApiKey,
    ),
  );
}

/// Thrown by [SettingsPortabilityService.decode] / `importFromFile` when the
/// file content is not valid WhisPaste settings-export JSON.
class SettingsImportFormatException implements Exception {
  const SettingsImportFormatException(this.message);

  final String message;

  @override
  String toString() => 'SettingsImportFormatException: $message';
}

/// Thrown by `importFromFile` when no file exists at the given path.
///
/// A dedicated type (rather than relying on the underlying [FileSystem]
/// backend's not-found exception, which differs between `LocalFileSystem`
/// and `MemoryFileSystem`) so callers can show a friendly, consistent
/// message regardless of backend.
class SettingsImportFileNotFoundException implements Exception {
  const SettingsImportFileNotFoundException(this.path);

  final String path;

  @override
  String toString() => 'SettingsImportFileNotFoundException: $path';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Encodes/decodes [SettingsExportBundle] as JSON and reads/writes it via an
/// injectable [FileSystem] (production: [LocalFileSystem]; tests: a
/// `MemoryFileSystem`) — mirrors the seam used by `FactoryResetCoordinator`.
class SettingsPortabilityService {
  const SettingsPortabilityService({FileSystem? fileSystem})
    : _fileSystem = fileSystem ?? const LocalFileSystem();

  final FileSystem _fileSystem;

  static const int formatVersion = 2;

  /// Serialises [bundle] to a pretty-printed JSON string.
  ///
  /// Filters [bundle.settings] against [settingsPortabilityDenyList] before
  /// writing — regardless of whether the caller already filtered (both
  /// `gather` call sites and the merge seam do). The deny list must hold at
  /// the file-writing boundary itself, not merely as a caller convention:
  /// "the export file never contains these keys in the first place" is the
  /// guarantee, not "callers are expected to filter first".
  String encode(SettingsExportBundle bundle) {
    const encoder = JsonEncoder.withIndent('  ');
    final filteredSettings = <String, String>{
      for (final entry in bundle.settings.entries)
        if (!settingsPortabilityDenyList.contains(entry.key))
          entry.key: entry.value,
    };
    final hotkeyDuplicate = HotkeySettings.fromMap(filteredSettings).toMap();
    return encoder.convert({
      'format_version': formatVersion,
      'settings': filteredSettings,
      'replacements': [
        for (final r in bundle.replacements)
          {'triggers': r.triggers, 'replacement': r.replacement},
      ],
      if (bundle.snippets case final snippets?)
        'snippets': [
          for (final s in snippets)
            {
              'title': s.title,
              'body': s.body,
              'kind': s.kind,
              'fields': s.fields,
            },
        ],
      // v1-compat duplicates — see library doc. Derived from `settings`,
      // never a second source.
      'custom_vocabulary': filteredSettings['custom_vocabulary'] ?? '',
      'hotkey': hotkeyDuplicate,
    });
  }

  /// Parses JSON produced by [encode] back into a [SettingsExportBundle].
  /// Reads both v1 (no `settings` object; `custom_vocabulary` + `hotkey` at
  /// the root) and v2 files. A `format_version` higher than [formatVersion]
  /// is read best-effort, never rejected. Throws
  /// [SettingsImportFormatException] for malformed or structurally invalid
  /// content.
  SettingsExportBundle decode(String jsonString) {
    final Object? raw;
    try {
      raw = jsonDecode(jsonString);
    } on FormatException catch (e) {
      throw SettingsImportFormatException('Invalid JSON: ${e.message}');
    }

    if (raw is! Map<String, dynamic>) {
      throw const SettingsImportFormatException(
        'Export file root is not a JSON object',
      );
    }

    final settingsRaw = raw['settings'];
    final hotkeyRaw = raw['hotkey'];
    // The top-level "hotkey" object is only *mandatory* for a v1 file (one
    // with no "settings" object) — it is v1's only vehicle for the hotkey
    // keys. A v2 file already carries them in "settings"; requiring the
    // v1-compat duplicate there too would reject a well-formed v2 file that
    // omits it (e.g. a future producer that drops the duplicate once v1
    // builds are no longer in the wild), contradicting "a file this build
    // doesn't fully recognise is read best-effort, never rejected".
    if (settingsRaw is! Map && hotkeyRaw is! Map) {
      throw const SettingsImportFormatException('Missing "hotkey" object');
    }
    final replacementsRaw = raw['replacements'];
    if (replacementsRaw is! List) {
      throw const SettingsImportFormatException('Missing "replacements" list');
    }

    // v1 lift: `custom_vocabulary` is literally the storage key
    // `SttSettings.toMap()` writes, and the `hotkey` object's entries are
    // exactly `HotkeySettings.toMap()`'s storage keys — so both v1 fields
    // hoist directly into the flat map with no translation. On a v2 file,
    // `settings` (read after, so it wins) already carries both.
    final settings = <String, String>{
      if (hotkeyRaw is Map)
        for (final entry in hotkeyRaw.entries) '${entry.key}': '${entry.value}',
      if (raw['custom_vocabulary'] case final String customVocabulary)
        'custom_vocabulary': customVocabulary,
      if (settingsRaw is Map)
        for (final entry in settingsRaw.entries)
          '${entry.key}': '${entry.value}',
    };
    for (final key in settingsPortabilityDenyList) {
      settings.remove(key);
    }

    // Unlike "hotkey"/"replacements", "snippets" is an optional section: an
    // export predating the Snippets feature has no such key at all, and
    // that must decode to `null` (not `[]`) so the caller can tell "section
    // absent" apart from "section present, empty" and skip overwriting the
    // user's existing snippets. `raw['snippets']` already reads as `null`
    // for a missing key, so the `is List` check below collapses both
    // "absent" and "malformed" into `null` and only a real JSON list
    // (including `[]`) decodes to a list.
    final snippetsRaw = raw['snippets'];

    return SettingsExportBundle(
      settings: settings,
      replacements: [
        for (final entry in replacementsRaw)
          if (entry is Map)
            if (_decodeTriggers(entry) case final triggers
                when triggers.isNotEmpty)
              Replacement(
                // IDs are DB-assigned on import (a fresh install may already
                // have colliding IDs) — not part of the portable identity.
                id: '',
                triggers: triggers,
                replacement: '${entry['replacement'] ?? ''}',
              ),
      ],
      snippets: snippetsRaw is List
          ? [
              for (final entry in snippetsRaw)
                if (entry is Map)
                  if ('${entry['title'] ?? ''}' case final title
                      when title.isNotEmpty)
                    SnippetItem(
                      // IDs are DB-assigned on import — see the replacements
                      // case above for the same rationale.
                      id: '',
                      title: title,
                      body: '${entry['body'] ?? ''}',
                      // Older export files (pre-interactive-snippets) have
                      // neither key — default to a plain static snippet.
                      kind: '${entry['kind'] ?? 'static'}',
                      fields: switch (entry['fields']) {
                        final List fields => [for (final f in fields) '$f'],
                        _ => const [],
                      },
                    ),
            ]
          : null,
    );
  }

  /// Reads a replacement entry's trigger phrases. Prefers the current
  /// `"triggers"` list; falls back to the pre-multi-trigger `"trigger"`
  /// string so an export produced by the currently-published version still
  /// imports without exception. Empty strings are dropped either way — an
  /// empty trigger would match everywhere once fed into the replacement
  /// regex.
  List<String> _decodeTriggers(Map entry) {
    final triggersRaw = entry['triggers'];
    if (triggersRaw is List) {
      return triggersRaw.map((t) => '$t').where((t) => t.isNotEmpty).toList();
    }
    final legacyTrigger = '${entry['trigger'] ?? ''}';
    return legacyTrigger.isEmpty ? const [] : [legacyTrigger];
  }

  /// Writes [bundle] as JSON to [path], overwriting any existing file.
  /// Creates the parent directory if it does not exist yet.
  Future<void> exportToFile(String path, SettingsExportBundle bundle) async {
    final file = _fileSystem.file(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(encode(bundle));
  }

  /// Reads and decodes the export file at [path].
  ///
  /// Throws [SettingsImportFileNotFoundException] when no file exists at
  /// [path], or [SettingsImportFormatException] when its content is
  /// malformed.
  Future<SettingsExportBundle> importFromFile(String path) async {
    final file = _fileSystem.file(path);
    if (!await file.exists()) {
      throw SettingsImportFileNotFoundException(path);
    }
    final content = await file.readAsString();
    return decode(content);
  }
}
