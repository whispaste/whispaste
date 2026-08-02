/// Dateibasierter Settings-Export/-Import — Custom Vocabulary,
/// Text-Replacements und Hotkey-Konfiguration (PRD `experience-perf-polish`,
/// Cluster 5 „Portabilität & Fehler-Feedback"). Deliberately excludes
/// dictation History and Audio (privacy/scope) — see the PRD for rationale.
///
/// Reuses [HotkeySettings.toMap]/[HotkeySettings.fromMap] for the hotkey
/// sub-object so the exported JSON schema mirrors the existing flat-string
/// persistence format already used by the SQLite-backed settings storage,
/// instead of inventing a second serialization scheme.
library;

import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';

import '../core/config/settings_sections.dart' show HotkeySettings;
import '../features/replacements/replacements_page.dart' show Replacement;

// ---------------------------------------------------------------------------
// Bundle
// ---------------------------------------------------------------------------

/// The three portable settings areas bundled into a single export file.
class SettingsExportBundle {
  const SettingsExportBundle({
    required this.customVocabulary,
    required this.hotkey,
    required this.replacements,
  });

  final String customVocabulary;
  final HotkeySettings hotkey;
  final List<Replacement> replacements;
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

  static const int formatVersion = 1;

  /// Serialises [bundle] to a pretty-printed JSON string.
  String encode(SettingsExportBundle bundle) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'format_version': formatVersion,
      'custom_vocabulary': bundle.customVocabulary,
      'hotkey': bundle.hotkey.toMap(),
      'replacements': [
        for (final r in bundle.replacements)
          {'triggers': r.triggers, 'replacement': r.replacement},
      ],
    });
  }

  /// Parses JSON produced by [encode] back into a [SettingsExportBundle].
  /// Throws [SettingsImportFormatException] for malformed or structurally
  /// invalid content.
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

    final hotkeyRaw = raw['hotkey'];
    if (hotkeyRaw is! Map) {
      throw const SettingsImportFormatException('Missing "hotkey" object');
    }
    final replacementsRaw = raw['replacements'];
    if (replacementsRaw is! List) {
      throw const SettingsImportFormatException('Missing "replacements" list');
    }

    final hotkeyMap = <String, String>{
      for (final entry in hotkeyRaw.entries) '${entry.key}': '${entry.value}',
    };

    return SettingsExportBundle(
      customVocabulary: raw['custom_vocabulary'] as String? ?? '',
      hotkey: HotkeySettings.fromMap(hotkeyMap),
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
