/// The "Übersicht" start page: the pure rules.
///
/// Everything here is a function over plain values (the history rows, the
/// readiness flags, the stored tip and "new in version" state, and an
/// injected clock), so the rules are tested without a widget tree or storage.
/// The providers in `overview_state.dart` feed these functions.
library;

import 'package:intl/intl.dart' show DateFormat;

import '../data/analytics_provider.dart' show AnalyticsData;
import '../data/database.dart' show HistoryEntry, Note;
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

/// The [count] notes edited last, newest first (#630). Like the recordings,
/// pinned notes do not jump the queue; trashed notes and notes without any
/// text (one just created and not yet written) are left out. Equal edit times
/// fall back to the id, so the order never depends on the input order.
List<Note> overviewLatestNotes(List<Note> notes, {int count = 3}) {
  final live =
      notes
          .where(
            (n) =>
                n.deletedAt == null &&
                ((n.title?.trim().isNotEmpty ?? false) ||
                    n.content.trim().isNotEmpty),
          )
          .toList()
        ..sort((a, b) {
          final byTime = b.updatedAt.compareTo(a.updatedAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
  return live.take(count).toList();
}

/// Which day [t] falls on as seen from [now], for the time column of the
/// Übersicht rows: today shows the time, yesterday and earlier the day.
enum OverviewDay { today, yesterday, earlier }

/// The [OverviewDay] of [t] relative to [now], in local calendar days.
OverviewDay overviewDayOf(DateTime t, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return OverviewDay.today;
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return OverviewDay.yesterday;
  }
  return OverviewDay.earlier;
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
/// 1.5.0: four entries, picked from the CHANGELOG in #1576.
/// 1.5.1: no own entries; a patch shows its minor's entries (see
/// [whatsNewKey]), so a 1.4 user who updates straight to 1.5.1 (the first 1.5
/// in the Mac App Store) still meets the 1.5 highlights.
/// 1.5.2: no own entries, bug fixes only; shows the 1.5 entries like 1.5.1.
const kWhatsNewReviewedVersion = '1.5.2';

/// One highlight of a version: a title, one sentence, and the place its
/// "Try it" action leads to (a nav page id, `settings:<row>` or
/// [kOverviewCustomizeTarget]).
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
final Map<String, List<WhatsNewItem>> kWhatsNewRegistry = {
  // #1576: the four changes a 1.4 user meets first. The illustration style
  // (#172) is not in 1.5.0 and gets no entry.
  '1.5.0': [
    WhatsNewItem(
      id: 'v150-overview-cards',
      title: (l) => l.overviewWhatsNew150CardsTitle,
      body: (l) => l.overviewWhatsNew150CardsBody,
      target: kOverviewCustomizeTarget,
    ),
    WhatsNewItem(
      id: 'v150-editor',
      title: (l) => l.overviewWhatsNew150EditorTitle,
      body: (l) => l.overviewWhatsNew150EditorBody,
      target: 'notes',
    ),
    WhatsNewItem(
      id: 'v150-smart-mode-presets',
      title: (l) => l.overviewWhatsNew150SmartTitle,
      body: (l) => l.overviewWhatsNew150SmartBody,
      target: 'smartMode',
    ),
    WhatsNewItem(
      id: 'v150-insert-snippets',
      title: (l) => l.overviewWhatsNew150SnippetsTitle,
      body: (l) => l.overviewWhatsNew150SnippetsBody,
      target: 'snippets',
    ),
  ],
};

/// The "Try it" target that opens the "Customise overview" menu of the
/// Übersicht instead of a page, so a new card is one click away.
const kOverviewCustomizeTarget = 'overview:customize';

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
  final reg = registry ?? kWhatsNewRegistry;
  final key = whatsNewKey(currentVersion, reg);
  final items = reg[key] ?? const [];
  // Stored versions count for the same entries: closing the card in 1.5.0
  // keeps it closed in 1.5.1, and a fresh 1.5.0 install has nothing to catch
  // up on in 1.5.1 either.
  bool same(String? v) => v != null && whatsNewKey(v, reg) == key;
  if (items.isEmpty || same(closedVersion) || same(onboardedInVersion)) {
    return const WhatsNewView(items: [], dot: false);
  }
  return WhatsNewView(items: items, dot: !same(openedVersion));
}

/// The registry key whose entries [version] shows: its own entries when it
/// has any, else those of its minor release (`1.5.1` → `1.5.0`), so a patch
/// does not hide the highlights of the version it fixes. Any other version
/// keeps its own key (and shows nothing without entries).
String whatsNewKey(String version, Map<String, List<WhatsNewItem>> registry) {
  if (registry.containsKey(version)) return version;
  final m = RegExp(r'^(\d+)\.(\d+)\.\d+$').firstMatch(version);
  if (m == null) return version;
  final minor = '${m.group(1)}.${m.group(2)}.0';
  return registry.containsKey(minor) ? minor : version;
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

/// Ü3: the blocks of the Übersicht a user can switch on or off in "Übersicht
/// anpassen". The discovery tips are switched with [OverviewTipState.off];
/// the head, the status line and the first steps always stay.
///
/// Most blocks are on by default and stored as hidden when switched off. A
/// block that is off by default ([shownByDefault] false) is stored as shown
/// when switched on, so an existing install keeps its page unchanged.
enum OverviewBlock {
  figures('figures'),
  recent('recent'),
  notes('notes'),
  dictation('dictation'),
  storage('storage'),
  community('community'),
  system('system', shownByDefault: false),
  news('news', shownByDefault: false),

  /// The weather card (#1569): off by default, asks a weather service only
  /// once a place is chosen.
  weather('weather', shownByDefault: false);

  const OverviewBlock(this.id, {this.shownByDefault = true});

  /// Stored id; never rename one.
  final String id;

  /// Whether the block is on until the user switches it off.
  final bool shownByDefault;
}

/// Whether [block] is on the page, given the stored hidden and shown sets.
bool overviewBlockShown(
  OverviewBlock block, {
  required Set<OverviewBlock> hidden,
  required Set<OverviewBlock> shown,
}) => block.shownByDefault ? !hidden.contains(block) : shown.contains(block);

/// The blocks from their stored comma-separated ids. Unknown ids are dropped,
/// so a block removed in a later version does not linger.
Set<OverviewBlock> _overviewBlocksFromStored(String? raw) {
  final ids = (raw ?? '').split(',').map((e) => e.trim()).toSet();
  return {
    for (final b in OverviewBlock.values)
      if (ids.contains(b.id)) b,
  };
}

/// The stored form of [blocks], in a stable order.
String _overviewBlocksToStored(Set<OverviewBlock> blocks) => [
  for (final b in OverviewBlock.values)
    if (blocks.contains(b)) b.id,
].join(',');

/// The hidden blocks from their stored comma-separated ids.
Set<OverviewBlock> overviewHiddenBlocksFromStored(String? raw) =>
    _overviewBlocksFromStored(raw);

/// The stored form of [hidden], in a stable order.
String overviewHiddenBlocksToStored(Set<OverviewBlock> hidden) =>
    _overviewBlocksToStored(hidden);

/// The blocks switched on although they are off by default, from their stored
/// ids.
Set<OverviewBlock> overviewShownBlocksFromStored(String? raw) =>
    _overviewBlocksFromStored(raw);

/// The stored form of [shown], in a stable order.
String overviewShownBlocksToStored(Set<OverviewBlock> shown) =>
    _overviewBlocksToStored(shown);

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
// Milestone, rate/share and support card
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

/// The quiet ask to support WhisPaste; [recurring] is the one-time follow-up
/// after a sponsoring link was opened.
final class OverviewSupportCard extends OverviewAskCard {
  const OverviewSupportCard({required this.recurring});
  final bool recurring;

  @override
  bool operator ==(Object other) =>
      other is OverviewSupportCard && other.recurring == recurring;

  @override
  int get hashCode => recurring.hashCode;
}

/// The milestone, rate/share or support card for a visit on [now], or null.
///
/// All follow a good moment and never a problem: nothing shows while the
/// status line reports one ([problemShown]). Order: milestone > rate/share >
/// support. A milestone shows only once per count. The rate/share card shows
/// when the review prompt service finds it due ([rateDue]), the support card
/// when the support prompt service does ([supportDue]) and no dictation is
/// running ([dictationRunning]). Never two cards on one day: once any card
/// was answered on [now]'s day ([anyCardShownOn]), the place stays quiet.
OverviewAskCard? overviewAskCard({
  required int dictations,
  required Set<int> milestonesSeen,
  required bool rateDue,
  required bool problemShown,
  required DateTime? anyCardShownOn,
  required DateTime now,
  bool supportDue = false,
  bool supportRecurring = false,
  bool dictationRunning = false,
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
  if (rateDue) return const OverviewRateShareCard();
  if (supportDue && !dictationRunning) {
    return OverviewSupportCard(recurring: supportRecurring);
  }
  return null;
}
