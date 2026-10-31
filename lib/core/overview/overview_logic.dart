/// The "Übersicht" start page: the pure rules.
///
/// Everything here is a function over plain values (the history rows, the
/// readiness flags, the stored tip and "new in version" state, and an
/// injected clock), so the rules are tested without a widget tree or storage.
/// The providers in `overview_state.dart` feed these functions.
library;

import 'package:intl/intl.dart' show DateFormat;

import '../data/analytics_provider.dart' show AnalyticsData;
import '../data/database.dart' show HistoryEntry;
import '../l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Status line: one problem, one action
// ---------------------------------------------------------------------------

/// The one readiness problem the status line names. The order is the order of
/// precedence: audio that can still be lost comes first, then what blocks
/// dictation, and a running download explains a missing model better than the
/// missing model itself does.
enum OverviewStatusIssue {
  recoveryPending,
  modelDownloading,
  modelFailed,
  modelMissing,
  micDenied,
  hotkeyUnbound,
}

/// The problem to show, or null when everything is ready (the line is then
/// not shown at all).
OverviewStatusIssue? overviewStatusIssue({
  required bool recoveryPending,
  required bool modelMissing,
  required bool modelDownloading,
  required bool modelFailed,
  required bool micDenied,
  required bool hotkeyUnbound,
}) {
  if (recoveryPending) return OverviewStatusIssue.recoveryPending;
  if (modelDownloading) return OverviewStatusIssue.modelDownloading;
  if (modelFailed) return OverviewStatusIssue.modelFailed;
  if (modelMissing) return OverviewStatusIssue.modelMissing;
  if (micDenied) return OverviewStatusIssue.micDenied;
  if (hotkeyUnbound) return OverviewStatusIssue.hotkeyUnbound;
  return null;
}

// ---------------------------------------------------------------------------
// Days, weeks and the recent recordings
// ---------------------------------------------------------------------------

/// Monday 00:00 of the week [now] falls into, in local time. The week count
/// restarts on Monday.
DateTime overviewWeekStart(DateTime now) =>
    DateTime(now.year, now.month, now.day - (now.weekday - DateTime.monday));

/// The newest [count] recordings that are neither archived nor in the trash,
/// newest first. Pinned entries do not jump the queue here: "latest" means
/// latest.
List<HistoryEntry> overviewLatestRecordings(
  List<HistoryEntry> entries, {
  int count = 5,
}) {
  final active =
      entries.where((e) => !e.archived && e.deletedAt == null).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return active.take(count).toList();
}

/// The period of the figures: the current week, or everything.
enum OverviewPeriod { week, all }

/// The lower bound of [period] for the analytics query; null means no bound.
DateTime? overviewPeriodSince(OverviewPeriod period, DateTime now) =>
    switch (period) {
      OverviewPeriod.week => overviewWeekStart(now),
      OverviewPeriod.all => null,
    };

// ---------------------------------------------------------------------------
// Discovery tip
// ---------------------------------------------------------------------------

/// The tips of the pool. Each one points at an existing feature, and the
/// order is the order of the rotation when nothing else decides.
enum OverviewTip {
  smartMode('smart_mode'),
  vocabulary('vocabulary'),
  snippets('snippets'),
  notes('notes'),
  overlayLook('overlay_look'),
  recordingMode('recording_mode');

  const OverviewTip(this.id);

  /// Stable storage id. Never rename one: it is persisted.
  final String id;

  /// The page or Settings place the tip's action leads to: a nav page id, or
  /// `settings:<row>` for a Settings row.
  String get target => switch (this) {
    OverviewTip.smartMode => 'smartMode',
    OverviewTip.vocabulary => 'replacements',
    OverviewTip.snippets => 'snippets',
    OverviewTip.notes => 'notes',
    OverviewTip.overlayLook => 'settings:appearance-overlay-preview',
    OverviewTip.recordingMode => 'settings:general-hold-to-record',
  };
}

/// The stored discovery state: the day and tip of the last change, the tips
/// already shown in the current rotation, the tips closed for good, and the
/// switch that turns tips off altogether.
class OverviewTipState {
  const OverviewTipState({
    this.day,
    this.current,
    this.shownInCycle = const {},
    this.dismissed = const {},
    this.off = false,
  });

  /// Local day (yyyy-mm-dd) on which [current] was chosen.
  final String? day;
  final OverviewTip? current;
  final Set<OverviewTip> shownInCycle;
  final Set<OverviewTip> dismissed;
  final bool off;

  OverviewTipState copyWith({
    String? day,
    OverviewTip? current,
    bool clearCurrent = false,
    Set<OverviewTip>? shownInCycle,
    Set<OverviewTip>? dismissed,
    bool? off,
  }) => OverviewTipState(
    day: day ?? this.day,
    current: clearCurrent ? null : (current ?? this.current),
    shownInCycle: shownInCycle ?? this.shownInCycle,
    dismissed: dismissed ?? this.dismissed,
    off: off ?? this.off,
  );

  /// Parses the four stored values. Unknown ids are dropped, so a removed tip
  /// can never break the card.
  factory OverviewTipState.fromStored({
    String? day,
    String? current,
    String? shownInCycle,
    String? dismissed,
    String? off,
  }) => OverviewTipState(
    day: (day == null || day.isEmpty) ? null : day,
    current: _tipById(current),
    shownInCycle: _tipsFromCsv(shownInCycle),
    dismissed: _tipsFromCsv(dismissed),
    off: off == '1',
  );

  String? get storedCurrent => current?.id;
  String get storedShownInCycle => _csvFromTips(shownInCycle);
  String get storedDismissed => _csvFromTips(dismissed);
  String get storedOff => off ? '1' : '0';

  static OverviewTip? _tipById(String? id) {
    if (id == null) return null;
    for (final t in OverviewTip.values) {
      if (t.id == id) return t;
    }
    return null;
  }

  static Set<OverviewTip> _tipsFromCsv(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final ids = raw.split(',').map((s) => s.trim()).toSet();
    return {
      for (final t in OverviewTip.values)
        if (ids.contains(t.id)) t,
    };
  }

  static String _csvFromTips(Set<OverviewTip> tips) => [
    for (final t in OverviewTip.values)
      if (tips.contains(t)) t.id,
  ].join(',');
}

/// The next tip of the rotation, or null when every tip is closed.
///
/// Tips already shown in the current rotation are skipped, so nothing repeats
/// until the pool has run dry; then a new rotation starts. Among the open tips
/// those the user has not used yet ([used], from local signals only) come
/// first, in pool order. Returns the tip together with the rotation to store.
({OverviewTip tip, Set<OverviewTip> shownInCycle})? overviewNextTip({
  required Set<OverviewTip> used,
  required Set<OverviewTip> dismissed,
  required Set<OverviewTip> shownInCycle,
}) {
  final open = [
    for (final t in OverviewTip.values)
      if (!dismissed.contains(t)) t,
  ];
  if (open.isEmpty) return null;
  var candidates = [
    for (final t in open)
      if (!shownInCycle.contains(t)) t,
  ];
  var cycle = shownInCycle;
  if (candidates.isEmpty) {
    // The rotation ran through every open tip: start over.
    candidates = open;
    cycle = {};
  }
  final unused = candidates.where((t) => !used.contains(t)).toList();
  final pick = unused.isNotEmpty ? unused.first : candidates.first;
  return (tip: pick, shownInCycle: {...cycle, pick});
}

/// The tip for a visit on [today] (yyyy-mm-dd), and the state to store.
///
/// The tip changes at most once per calendar day: a second visit on the same
/// day shows the same tip again, and a tip closed today stays closed until
/// tomorrow. Tips that are switched off show nothing.
({OverviewTip? tip, OverviewTipState state}) overviewTipForVisit({
  required OverviewTipState state,
  required String today,
  required Set<OverviewTip> used,
}) {
  if (state.off) return (tip: null, state: state);
  if (state.day == today) {
    final current = state.current;
    final visible = current != null && !state.dismissed.contains(current);
    return (tip: visible ? current : null, state: state);
  }
  final next = overviewNextTip(
    used: used,
    dismissed: state.dismissed,
    shownInCycle: state.shownInCycle,
  );
  if (next == null) {
    return (tip: null, state: state.copyWith(day: today, clearCurrent: true));
  }
  final updated = state.copyWith(
    day: today,
    current: next.tip,
    shownInCycle: next.shownInCycle,
  );
  return (tip: next.tip, state: updated);
}

/// Whether the discovery tip may show at all: after the first steps are done
/// or closed. An install that never got the card (armed false) is never held
/// back by it.
bool overviewTipsEligible({
  required bool firstStepsArmed,
  required bool firstStepsDismissed,
  required bool firstStepsAllDone,
}) => !firstStepsArmed || firstStepsDismissed || firstStepsAllDone;

// ---------------------------------------------------------------------------
// "New in this version"
// ---------------------------------------------------------------------------

/// The app version (`pubspec.yaml`, without build number) whose "new in this
/// version" entries were last reviewed. A test fails as soon as the pubspec
/// version moves past it, so every release bump forces a conscious decision:
/// add entries for the new version, or add none. Either way, set this to the
/// new version.
const kWhatsNewReviewedVersion = '1.4.2';

/// One highlight of a version: a title, one sentence, and the place its
/// "Try it" action leads to (a nav page id or `settings:<row>`).
class WhatsNewItem {
  const WhatsNewItem({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
  });

  /// Stable id, for tests and for the card's keys. Never reuse one.
  final String id;
  final String Function(L10n l10n) title;
  final String Function(L10n l10n) body;
  final String target;
}

/// The highlights per app version. A version without entries is valid: then
/// nothing shows and no dot appears. Only the running version is ever shown,
/// so an existing user gets no catch-up list of older versions.
///
/// The six entries of the retired spotlight are not repeated here: their users
/// already saw them, and they now live on as discovery tips.
final Map<String, List<WhatsNewItem>> kWhatsNewRegistry = {};

/// What the "new in this version" card shows for the running version.
class WhatsNewView {
  const WhatsNewView({required this.items, required this.dot});

  /// Entries of the running version, empty when the card is closed or there
  /// is nothing new.
  final List<WhatsNewItem> items;

  /// The dot on the Übersicht nav entry: shown until the page has been opened
  /// in this version.
  final bool dot;
}

/// The card and dot for [currentVersion]. [closedVersion] is the version whose
/// card the user closed, [openedVersion] the version in which the Übersicht was
/// last opened. Both are null when never stored. [onboardedInVersion] is the
/// version in which the first onboarding finished (empty when unknown): a
/// fresh install of a version has nothing new to catch up on.
WhatsNewView overviewWhatsNewView({
  required String currentVersion,
  required String? closedVersion,
  required String? openedVersion,
  String onboardedInVersion = '',
  Map<String, List<WhatsNewItem>>? registry,
}) {
  final items = (registry ?? kWhatsNewRegistry)[currentVersion] ?? const [];
  if (items.isEmpty ||
      closedVersion == currentVersion ||
      onboardedInVersion == currentVersion) {
    return const WhatsNewView(items: [], dot: false);
  }
  return WhatsNewView(items: items, dot: openedVersion != currentVersion);
}

/// The local calendar day as yyyy-mm-dd, the key of "one tip change per day".
String overviewDayKey(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

/// Ü8: the dictation tempo of the period in words per minute of recording
/// time, or null while it rests on too little to be honest — fewer than three
/// dictations or less than a minute of recording. The card then says "Noch zu
/// wenig Daten" instead of a precise-looking number.
double? overviewWordsPerMinute(AnalyticsData figures) =>
    figures.totalRecordings < 3 || figures.totalDurationSec < 60
    ? null
    : figures.wordsPerMinute;

/// A card of the hint place under the head of the Übersicht.
enum OverviewHint { firstSteps, whatsNew, tip, ask }

/// Ü5: the cards of the hint place, top to bottom. The first steps hold the
/// place alone while they show; after they are done or closed, "new in this
/// version" comes before the discovery tip. The milestone or rate/share
/// card ([overviewAskCard]) only takes the place when none of them shows.
/// Readiness problems are not part of it: the status line above the place
/// names them.
List<OverviewHint> overviewHintPlace({
  required bool firstStepsVisible,
  required bool whatsNewHasItems,
  required bool tipVisible,
  bool askVisible = false,
}) => [
  if (firstStepsVisible)
    OverviewHint.firstSteps
  else if (whatsNewHasItems || tipVisible) ...[
    if (whatsNewHasItems) OverviewHint.whatsNew,
    if (tipVisible) OverviewHint.tip,
  ] else if (askVisible)
    OverviewHint.ask,
];

/// Ü3: the blocks of the Übersicht a user can switch off in "Übersicht
/// anpassen". The discovery tips are switched with [OverviewTipState.off];
/// the head, the status line and the first steps always stay.
enum OverviewBlock {
  figures('figures'),
  recent('recent'),
  dictation('dictation'),
  storage('storage'),
  community('community');

  const OverviewBlock(this.id);

  /// Stored id; never rename one.
  final String id;
}

/// The hidden blocks from their stored comma-separated ids. Unknown ids are
/// dropped, so a block removed in a later version does not linger.
Set<OverviewBlock> overviewHiddenBlocksFromStored(String? raw) {
  final ids = (raw ?? '').split(',').map((e) => e.trim()).toSet();
  return {
    for (final b in OverviewBlock.values)
      if (ids.contains(b.id)) b,
  };
}

/// The stored form of [hidden], in a stable order.
String overviewHiddenBlocksToStored(Set<OverviewBlock> hidden) => [
  for (final b in OverviewBlock.values)
    if (hidden.contains(b)) b.id,
].join(',');

/// Why "Letzte Aufnahmen" has no row to show.
enum OverviewRecentEmpty {
  /// Nothing recorded yet, or the history was cleared: the hotkey invites.
  none,

  /// Every kept recording is archived or in the trash.
  putAway,

  /// Saving recordings is switched off: nothing will appear here.
  notSaved,
}

/// The empty state for [entries] (the whole history), or null when there is
/// a recording to show. Switched-off saving wins: it explains the others.
OverviewRecentEmpty? overviewRecentEmpty(
  List<HistoryEntry> entries, {
  required bool saveHistory,
}) {
  if (!saveHistory) return OverviewRecentEmpty.notSaved;
  if (overviewLatestRecordings(entries, count: 1).isNotEmpty) return null;
  return entries.isEmpty
      ? OverviewRecentEmpty.none
      : OverviewRecentEmpty.putAway;
}

// ---------------------------------------------------------------------------
// Milestone and the rate/share card
// ---------------------------------------------------------------------------

/// Dictation counts that earn a one-time milestone card.
const kOverviewMilestones = [100, 1000];

/// What the last card of this kind sits in the hint place for.
sealed class OverviewAskCard {
  const OverviewAskCard();
}

/// "100 Diktate": shown once per [count].
final class OverviewMilestoneCard extends OverviewAskCard {
  const OverviewMilestoneCard(this.count);
  final int count;

  @override
  bool operator ==(Object other) =>
      other is OverviewMilestoneCard && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

/// Rate in the store of this install, or share the website link.
final class OverviewRateShareCard extends OverviewAskCard {
  const OverviewRateShareCard();

  @override
  bool operator ==(Object other) => other is OverviewRateShareCard;

  @override
  int get hashCode => 0;
}

/// The milestone or rate/share card for a visit on [now], or null.
///
/// Both follow a good moment and never a problem: nothing shows while the
/// status line reports one ([problemShown]). A milestone comes first and
/// only once per count. The rate/share card shows when the review prompt
/// service finds it due ([rateDue]: enough dictations on enough days, its
/// quiet days and "nie wieder" respected). Never two cards on one day.
OverviewAskCard? overviewAskCard({
  required int dictations,
  required Set<int> milestonesSeen,
  required bool rateDue,
  required bool problemShown,
  required DateTime? anyCardShownOn,
  required DateTime now,
}) {
  if (problemShown) return null;
  if (anyCardShownOn != null &&
      overviewDayKey(anyCardShownOn) == overviewDayKey(now)) {
    return null;
  }
  for (final m in kOverviewMilestones.reversed) {
    if (dictations >= m && !milestonesSeen.contains(m)) {
      return OverviewMilestoneCard(m);
    }
    if (dictations >= m) break;
  }
  return rateDue ? const OverviewRateShareCard() : null;
}
