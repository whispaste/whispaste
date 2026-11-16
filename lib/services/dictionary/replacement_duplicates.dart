/// Duplicate detection for dictionary entries (matrix 4.5).
///
/// Two triggers count as the same when they normalise to the same words:
/// case-insensitive, and any run of non-letter/non-digit characters counts as
/// one separator. That mirrors how the exact matcher already treats
/// "a-b", "a b" and "A  B" as one phrase (see `_flexibleTriggerPattern` in
/// `text_replacement_matcher.dart`), so a warning here always corresponds to
/// a real collision at dictation time.
library;

/// One entry as seen by the duplicate check: its id and every trigger phrase.
class TriggerOwner {
  const TriggerOwner({required this.id, required this.triggers});

  final String id;
  final List<String> triggers;
}

/// Normalised comparison key of one trigger phrase. Empty when the phrase
/// has no letters or digits at all; such phrases never collide.
String normalizeTriggerKey(String trigger) => trigger
    .toLowerCase()
    .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
    .where((word) => word.isNotEmpty)
    .join(' ');

/// Ids of every entry that shares a normalised trigger with at least one
/// other entry. Each id is returned once, however many collisions it has.
Set<String> duplicateReplacementIds(Iterable<TriggerOwner> entries) {
  final ownersByKey = <String, Set<String>>{};
  for (final entry in entries) {
    for (final trigger in entry.triggers) {
      final key = normalizeTriggerKey(trigger);
      if (key.isEmpty) continue;
      ownersByKey.putIfAbsent(key, () => <String>{}).add(entry.id);
    }
  }
  return {
    for (final owners in ownersByKey.values)
      if (owners.length > 1) ...owners,
  };
}
