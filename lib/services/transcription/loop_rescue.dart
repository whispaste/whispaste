/// Decision for the single targeted second pass over a decode that fell into
/// a repeat loop.
///
/// A loop is detected by [isRepetitionLoop] (unchanged, also the continuity
/// guard). The rescue adds a minimum length so a short genuine stutter never
/// triggers a second decode: clean recordings cost zero extra decodes.
library;

import 'continuity_guard.dart';

/// Fewest words the result must have before a loop triggers the second pass.
/// Below this a repeat is far likelier real speech ("ja ja ja ja ja") than a
/// runaway decoder.
const int kLoopRescueMinWords = 12;

/// Whether the decoded [text] warrants exactly one targeted second decode.
bool shouldRescueLoop(String text) {
  final words = RegExp(r'\S+').allMatches(text).length;
  if (words < kLoopRescueMinWords) return false;
  return isRepetitionLoop(text);
}

/// Picks the text to keep after the second pass: the retry only wins when it
/// is not itself a loop and is not empty; otherwise the first result stays.
String pickRescued({required String first, required String retry}) {
  if (retry.trim().isEmpty || isRepetitionLoop(retry)) return first;
  return retry;
}
