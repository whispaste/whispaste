/// Voice action parser — classifies raw voice transcription into structured
/// actions: add a note, add a tag, or correct the entry's transcript.
///
/// Stateless utility — no Riverpod state, no side effects. Pure input → output.
library;

/// The kind of action detected from a voice transcription.
enum VoiceActionType { note, tag, correction }

/// Result of parsing a voice transcription into an actionable intent.
class VoiceActionResult {
  const VoiceActionResult({
    required this.type,
    required this.payload,
  });

  /// What to do with [payload].
  final VoiceActionType type;

  /// The extracted text — tag name, correction text, or note content.
  final String payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceActionResult &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          payload == other.payload;

  @override
  int get hashCode => Object.hash(type, payload);

  @override
  String toString() => 'VoiceActionResult($type, "$payload")';
}

/// Parses raw transcription text into a [VoiceActionResult].
///
/// Detection rules (case-insensitive, leading/trailing whitespace trimmed):
///
/// 1. **Tag**: starts with `tag as ` or `tag:` → extracts the tag name.
/// 2. **Correction**: starts with `correct:` or `korrektur:` → extracts
///    replacement text.
/// 3. **Note**: everything else → treated as a plain voice note.
///
/// Returns `null` when [text] is empty or whitespace-only.
VoiceActionResult? parseVoiceAction(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  final lower = trimmed.toLowerCase();

  // ── Tag detection ───────────────────────────────────────────────────────
  if (lower.startsWith('tag as ')) {
    final tagName = trimmed.substring('tag as '.length).trim();
    if (tagName.isNotEmpty) {
      return VoiceActionResult(type: VoiceActionType.tag, payload: tagName);
    }
  }
  if (lower.startsWith('tag:')) {
    final tagName = trimmed.substring('tag:'.length).trim();
    if (tagName.isNotEmpty) {
      return VoiceActionResult(type: VoiceActionType.tag, payload: tagName);
    }
  }

  // ── Correction detection ────────────────────────────────────────────────
  if (lower.startsWith('correct:')) {
    final replacement = trimmed.substring('correct:'.length).trim();
    if (replacement.isNotEmpty) {
      return VoiceActionResult(
        type: VoiceActionType.correction,
        payload: replacement,
      );
    }
  }
  if (lower.startsWith('korrektur:')) {
    final replacement = trimmed.substring('korrektur:'.length).trim();
    if (replacement.isNotEmpty) {
      return VoiceActionResult(
        type: VoiceActionType.correction,
        payload: replacement,
      );
    }
  }

  // ── Default: note ───────────────────────────────────────────────────────
  return VoiceActionResult(type: VoiceActionType.note, payload: trimmed);
}
