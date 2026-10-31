/// Pure helpers for the language whisper detected during a decode (9.10).
///
/// The native lookups live in `WhisperFfiEngine`; everything here is plain
/// Dart so the mapping and the hint rule can be tested without a dylib.
library;

/// Maps whisper's detected language id to its code (e.g. `de`), or `null`.
///
/// [codeForId] wraps `whisper_lang_str`. A negative id, a missing code or an
/// empty string all mean "unknown", so the hint stays silent.
String? detectedLanguageCode(int id, String? Function(int id) codeForId) {
  if (id < 0) return null;
  final code = codeForId(id)?.trim();
  return (code == null || code.isEmpty) ? null : code;
}

/// Whether the spoken language clearly differs from a fixed setting.
///
/// Never fires on automatic detection, on an unknown detected language, or on
/// very short transcripts, where the detector is guessing and a hint would be
/// noise. [minWords] sets how much speech counts as a clear signal.
bool isLanguageMismatch({
  required String configured,
  required String? detected,
  required int wordCount,
  int minWords = 5,
}) {
  if (configured.isEmpty || configured == 'auto') return false;
  if (detected == null || detected.isEmpty) return false;
  if (wordCount < minWords) return false;
  return detected.toLowerCase() != configured.toLowerCase();
}
