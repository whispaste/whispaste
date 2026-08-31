/// Pure identifier-extraction and dedup logic for the vocabulary-import
/// feature (PRD.md "Import-Scan-Mechanismus"). Deliberately dependency-free
/// (no `dart:io`, no DB) — testable with in-memory file contents, per
/// PRD.md "Testing Decisions".
library;

/// Source file extensions the scanner reads — a maintained constant, not an
/// exhaustive language list (PRD.md).
const List<String> vocabularyImportSourceExtensions = [
  '.dart',
  '.ts',
  '.tsx',
  '.js',
  '.jsx',
  '.py',
  '.java',
  '.kt',
  '.swift',
  '.go',
  '.rs',
  '.rb',
  '.php',
  '.c',
  '.cpp',
  '.h',
  '.cs',
];

/// Directory names the scanner never descends into — version control,
/// dependency, and build-output trees. None of these hold *your* vocabulary:
/// they are third-party or generated code, and in a real project can dwarf
/// the actual source by orders of magnitude (a repo's `.git` and
/// `node_modules` alone commonly outnumber its own source files 10:1+),
/// turning what should be an instant scan into a multi-minute read of
/// megabytes of vendored JS/TS with no source-language filter of its own.
const List<String> vocabularyImportIgnoredDirNames = [
  '.git',
  '.dart_tool',
  '.hg',
  '.svn',
  'node_modules',
  'build',
  'dist',
  '.next',
  'Pods',
  '.build',
];

/// Language-agnostic declaration patterns: `class X`, `def X`, `function X`,
/// `fn X`, `const X =`, `let X =`, `var X`. Deliberately no per-language
/// parser (PRD.md "kein Parser pro Sprache").
final List<RegExp> _declarationPatterns = [
  RegExp(r'\bclass\s+([A-Za-z_][A-Za-z0-9_]*)'),
  RegExp(r'\bdef\s+([A-Za-z_][A-Za-z0-9_]*)'),
  RegExp(r'\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)'),
  RegExp(r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)'),
  RegExp(r'\bconst\s+([A-Za-z_][A-Za-z0-9_]*)\s*='),
  RegExp(r'\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*='),
  RegExp(r'\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\b'),
];

/// A call expression `X(...)` — a weaker signal than a declaration (also
/// matches control-flow keywords like `if (...)`, hence still gated by
/// [_looksLikeMultiSegmentIdentifier] before being kept).
final RegExp _callPattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\(');

/// Fallback heuristic: any standalone camelCase/PascalCase/snake_case token
/// of at least 2 segments — catches identifiers no declaration/call pattern
/// above recognized (PRD.md: "bekannte Grenze, kein Bug" — documented false
/// positives are acceptable here).
final RegExp _tokenPattern = RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\b');

/// Tokens longer than this are almost never real identifiers -- a real
/// class/function/variable name reads as a word or two, not a paragraph.
/// Anything past this length is far more likely a base64/minified/generated
/// blob that happened to satisfy the shape checks below (post-mortem: a
/// pre-fix scan of vendored build output imported thousands of such blobs
/// as "vocabulary", see `.scratch/vocabulary-fuzzy-replacements/`).
const int _maxIdentifierLength = 50;

bool _looksLikeMultiSegmentIdentifier(String token) {
  if (token.length > _maxIdentifierLength) return false;
  if (token.contains('_')) {
    final parts = token.split('_').where((p) => p.isNotEmpty);
    return parts.length >= 2;
  }
  // camelCase/PascalCase: an uppercase letter that is not the very first
  // character (so the whole token is not just a single capitalized word) --
  // but also require a lowercase letter somewhere, so a pure-uppercase token
  // (e.g. an acronym-shaped fragment pulled out of unrelated text) is never
  // mistaken for camelCase merely because every one of its letters is
  // "uppercase not at position 0". A short all-caps token like that is
  // exactly the shape that causes real damage downstream: as a fuzzy
  // replacement trigger it sits dangerously close (edit distance 1) to
  // ordinary short words, silently corrupting unrelated dictation.
  if (token == token.toUpperCase()) return false;
  final firstUpperInside = RegExp('(?<=.)[A-Z]');
  return firstUpperInside.hasMatch(token);
}

/// Extracts probable identifiers from [filesByPath] (path -> file content).
/// Pure and CPU-only — designed to run inside [compute]/an isolate (see
/// `VocabularyImportService`), so it must not touch the filesystem itself.
Set<String> extractIdentifiers(Map<String, String> filesByPath) {
  final found = <String>{};
  for (final content in filesByPath.values) {
    for (final pattern in _declarationPatterns) {
      for (final match in pattern.allMatches(content)) {
        final name = match.group(1);
        if (name != null &&
            name.isNotEmpty &&
            name.length <= _maxIdentifierLength) {
          found.add(name);
        }
      }
    }
    for (final match in _callPattern.allMatches(content)) {
      final name = match.group(1);
      if (name != null && _looksLikeMultiSegmentIdentifier(name)) {
        found.add(name);
      }
    }
    for (final match in _tokenPattern.allMatches(content)) {
      final name = match.group(0)!;
      if (_looksLikeMultiSegmentIdentifier(name)) found.add(name);
    }
  }
  return found;
}

/// Result of comparing freshly extracted [candidates] against the
/// [existingTriggers] already present in the replacements table.
class VocabularyImportDiff {
  const VocabularyImportDiff({required this.toInsert, required this.skipped});

  /// New identifiers to insert as fuzzy replacement entries.
  final List<String> toInsert;

  /// Count of candidates that already exist as a trigger (case-sensitive
  /// exact match, PRD.md User Story 13) and were therefore skipped.
  final int skipped;
}

/// Case-sensitive exact-string dedup against every existing trigger,
/// regardless of that existing entry's `origin` (manual or imported) —
/// PRD.md User Story 13.
VocabularyImportDiff computeImportDiff(
  Set<String> candidates,
  Set<String> existingTriggers,
) {
  final toInsert = <String>[];
  var skipped = 0;
  for (final candidate in candidates) {
    if (existingTriggers.contains(candidate)) {
      skipped++;
    } else {
      toInsert.add(candidate);
    }
  }
  toInsert.sort();
  return VocabularyImportDiff(toInsert: toInsert, skipped: skipped);
}
