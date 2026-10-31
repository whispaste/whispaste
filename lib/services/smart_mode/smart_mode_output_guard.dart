/// Output guard for Smart Mode generations.
///
/// A small local model sometimes keeps generating after the real text is
/// finished (a repeated paragraph, an invented continuation). The pipeline's
/// timeout bounds the time, not the damage: the runaway text would still be
/// pasted. This pure check flags such output so the caller can fall back to
/// the raw transcript, the same way it does for timeouts and engine errors.
library;

/// Minimum output length before a length comparison is made at all. Short
/// answers can be longer than their input without looping.
const int kSmartModeLoopMinOutputChars = 200;

/// Output longer than this multiple of the input counts as a loop.
const double kSmartModeLoopMaxRatio = 1.5;

/// Whether [output] looks like a runaway generation for [input].
///
/// Returns true only when [output] is at least
/// [kSmartModeLoopMinOutputChars] long and more than
/// [kSmartModeLoopMaxRatio] times the length of [input]. Callers must not
/// apply this to translations, whose target language can legitimately be
/// much longer than the source.
bool smartModeOutputLooksLooped({
  required String input,
  required String output,
}) {
  if (output.length < kSmartModeLoopMinOutputChars) return false;
  return output.length > input.length * kSmartModeLoopMaxRatio;
}
