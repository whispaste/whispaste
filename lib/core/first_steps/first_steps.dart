/// The "Erste Schritte" (first steps) card: the pure rules.
///
/// The card lists at most four items. An item is checked off only when the
/// step really happened, as seen in app state or in a recording event, never
/// by a click on the item. Everything here is a pure function over plain
/// values so the rules can be tested without a widget tree or storage.
///
/// Items and their confirmations:
///  - [FirstStepsItem.firstPaste]: a finished dictation whose text went to
///    another app, whether it was pasted or only copied: either the paste
///    outcome (`RecordingState.pasted`) or a recording in the history whose
///    target app is not WhisPaste itself. The history also confirms it for an
///    install that dictated before the card learned this rule.
///  - [FirstStepsItem.findAndCopy]: a recording was copied from the Übersicht
///    or the Aufnahmen page.
///  - [FirstStepsItem.personalize]: a custom vocabulary term exists in the
///    settings (`SttSettings.customVocabulary`). Text replacements are not used
///    here: their table is seeded with sample rows on first load, so a
///    non-empty table proves nothing about the user.
///  - [FirstStepsItem.noteDictation]: a finished dictation into a note.
///
/// The card is armed by the final "Start" action of Onboarding v6 only, so an
/// existing install never sees it (see `OnboardingSettings.firstStepsArmed`).
library;

/// One item of the card. [id] is the stable storage and test identifier;
/// never rename it, because it is persisted in `first_steps_done`.
enum FirstStepsItem {
  firstPaste('first_paste'),
  findAndCopy('copy_recording'),
  personalize('personalize'),
  noteDictation('note_dictation');

  const FirstStepsItem(this.id);

  final String id;
}

/// The ids of the first card (until 2026-10). A card on which all of them were
/// done counts as done in full, so a finished card does not come back with the
/// two steps that replaced the retired ones.
const _legacyCompleteIds = {
  'first_paste',
  'long_dictation',
  'personalize',
  'overlay_look',
};

/// How long the calm success state stays on screen after the last item.
const Duration kFirstStepsCelebration = Duration(seconds: 4);

/// Number of items on the card; the card never grows past this.
const int kFirstStepsItemCount = 4;

/// Parses `OnboardingSettings.firstStepsDone` (comma-separated ids). Unknown
/// ids are dropped, so a removed item can never break the card.
Set<FirstStepsItem> parseFirstStepsDone(String raw) {
  final ids = raw.split(',').map((id) => id.trim()).toSet();
  if (ids.containsAll(_legacyCompleteIds)) return FirstStepsItem.values.toSet();
  return {
    for (final item in FirstStepsItem.values)
      if (ids.contains(item.id)) item,
  };
}

/// Serialises [done] in declaration order, so equal sets always produce the
/// same string and a repeated write is a no-op.
String serializeFirstStepsDone(Set<FirstStepsItem> done) => [
  for (final item in FirstStepsItem.values)
    if (done.contains(item)) item.id,
].join(',');

/// Whether every item is confirmed.
bool firstStepsAllDone(Set<FirstStepsItem> done) =>
    done.length == kFirstStepsItemCount;

/// Whether [targetApp] (the captured bundle id, process or window class,
/// see `HistoryEntry.targetApp`) is WhisPaste itself: `de.whispaste.app` and
/// its variants on macOS and Linux, `whispaste.exe` on Windows.
bool isOwnTargetApp(String targetApp) {
  final id = targetApp.trim().toLowerCase();
  return id == 'whispaste' ||
      id == 'whispaste.exe' ||
      id == 'de.whispaste.app' ||
      id.startsWith('de.whispaste.app.');
}

/// The done set after a dictation finished. An empty transcript confirms
/// nothing: a silent recording is not a step. [toNote] is a dictation into a
/// note; [pasted] the paste outcome of a dictation into another app.
Set<FirstStepsItem> firstStepsAfterDictation({
  required Set<FirstStepsItem> done,
  required bool pasted,
  required bool toNote,
  required String transcript,
}) {
  if (transcript.trim().isEmpty) return done;
  return {
    ...done,
    if (pasted) FirstStepsItem.firstPaste,
    if (toNote) FirstStepsItem.noteDictation,
  };
}

/// The done set after reading the target apps of the saved recordings. Any
/// app other than WhisPaste confirms the first step, also in "copy only" mode
/// where nothing is pasted. Only dictations into another app get a target app.
Set<FirstStepsItem> firstStepsAfterHistory({
  required Set<FirstStepsItem> done,
  required Iterable<String?> targetApps,
}) {
  if (done.contains(FirstStepsItem.firstPaste)) return done;
  final foreign = targetApps.any(
    (app) => app != null && app.trim().isNotEmpty && !isOwnTargetApp(app),
  );
  return foreign ? {...done, FirstStepsItem.firstPaste} : done;
}

/// The done set after a recording was copied from the Übersicht or the
/// Aufnahmen page.
Set<FirstStepsItem> firstStepsAfterCopy(Set<FirstStepsItem> done) => {
  ...done,
  FirstStepsItem.findAndCopy,
};

/// The done set after the custom vocabulary was read. A blank value confirms
/// nothing.
Set<FirstStepsItem> firstStepsAfterVocabulary({
  required Set<FirstStepsItem> done,
  required String customVocabulary,
}) {
  if (customVocabulary.trim().isEmpty) return done;
  return {...done, FirstStepsItem.personalize};
}

/// Whether the card is on screen right now.
///
/// It is never shown while [busy] (a dictation holds the transcriber), never
/// when not [armed] or [dismissed]. Once every item is done the card only
/// shows during the short [celebrating] success state.
bool firstStepsVisible({
  required bool armed,
  required bool dismissed,
  required bool busy,
  required Set<FirstStepsItem> done,
  required bool celebrating,
}) {
  if (!armed || dismissed || busy) return false;
  return !firstStepsAllDone(done) || celebrating;
}

/// Whether "Neu anzeigen" in Settings has anything to bring back. Hidden for
/// installs that never got the card, and once every item is done.
bool firstStepsCanShowAgain({
  required bool armed,
  required Set<FirstStepsItem> done,
}) => armed && !firstStepsAllDone(done);
