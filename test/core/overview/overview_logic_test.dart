import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/analytics_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/overview/overview_logic.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';

Note _note({
  required String id,
  required DateTime updatedAt,
  String content = 'text',
  String? title,
  bool pinned = false,
  DateTime? deletedAt,
}) => Note(
  id: id,
  content: content,
  title: title,
  pinned: pinned,
  isQuickNote: false,
  archived: false,
  deletedAt: deletedAt,
  createdAt: DateTime(2026),
  updatedAt: updatedAt,
);

HistoryEntry _entry({
  required String id,
  required DateTime timestamp,
  String content = 'text',
  bool archived = false,
  DateTime? deletedAt,
}) => HistoryEntry(
  id: id,
  content: content,
  title: '',
  timestamp: timestamp,
  durationSec: 1,
  processingDurationSec: 0,
  language: 'de',
  languageHint: '',
  tags: '',
  pinned: false,
  source: 'dictation',
  model: 'whisper',
  isLocal: true,
  costUsd: 0,
  archived: archived,
  titleEdited: false,
  deletedAt: deletedAt,
  colorSlot: 0,
);

// 2026-10-30 is a Friday; its week starts on Monday 2026-10-26.
final _now = DateTime(2026, 10, 30, 12);

void main() {
  group('milestone and support card', () {
    final now = DateTime(2026, 10, 30, 10);
    OverviewAskCard? ask({
      int dictations = 25,
      Set<int> seen = const {},
      bool problem = false,
      DateTime? anyShownOn,
    }) => overviewAskCard(
      dictations: dictations,
      milestonesSeen: seen,
      problemShown: problem,
      anyCardShownOn: anyShownOn,
      now: now,
    );

    test('a milestone comes only once per count', () {
      expect(ask(), isNull);
      expect(ask(dictations: 120), const OverviewMilestoneCard(100));
      expect(ask(dictations: 120, seen: {100}), isNull);
      expect(
        ask(dictations: 1500, seen: {100}),
        const OverviewMilestoneCard(1000),
      );
      // Past 1,000 the 100 that was never shown no longer comes.
      expect(ask(dictations: 1500, seen: {1000}), isNull);
    });

    test('nothing while a problem shows or after a card today', () {
      expect(ask(dictations: 120, problem: true), isNull);
      expect(
        ask(dictations: 120, anyShownOn: DateTime(2026, 10, 30, 8)),
        isNull,
      );
      expect(
        ask(dictations: 120, anyShownOn: DateTime(2026, 10, 29, 8)),
        isNotNull,
      );
    });

    OverviewAskCard? support({
      int dictations = 25,
      Set<int> seen = const {},
      bool problem = false,
      DateTime? anyShownOn,
      bool recurring = false,
      bool running = false,
    }) => overviewAskCard(
      dictations: dictations,
      milestonesSeen: seen,
      problemShown: problem,
      anyCardShownOn: anyShownOn,
      now: now,
      supportDue: true,
      supportRecurring: recurring,
      dictationRunning: running,
    );

    test('support comes after the milestone', () {
      expect(support(), const OverviewSupportCard(recurring: false));
      expect(
        support(recurring: true),
        const OverviewSupportCard(recurring: true),
      );
      expect(support(dictations: 120), const OverviewMilestoneCard(100));
    });

    test('support shares the day rule and the problem rule', () {
      expect(support(anyShownOn: DateTime(2026, 10, 30, 8)), isNull);
      expect(support(anyShownOn: DateTime(2026, 10, 29, 8)), isNotNull);
      expect(support(problem: true), isNull);
    });

    test('support never shows during a dictation', () {
      expect(support(running: true), isNull);
    });
  });

  group('customised blocks', () {
    test('round-trip in a stable order and drop unknown ids', () {
      final hidden = overviewHiddenBlocksFromStored('recent, gone,figures');
      expect(hidden, {OverviewBlock.figures, OverviewBlock.recent});
      expect(overviewHiddenBlocksToStored(hidden), 'figures,recent');
      expect(overviewHiddenBlocksFromStored(null), isEmpty);
      expect(overviewHiddenBlocksToStored({}), '');
    });

    test('the dictation and storage blocks are shown until switched off', () {
      // Nothing stored yet: both new blocks are on for every user.
      final hidden = overviewHiddenBlocksFromStored(null);
      expect(hidden.contains(OverviewBlock.dictation), isFalse);
      expect(hidden.contains(OverviewBlock.storage), isFalse);
      final off = overviewHiddenBlocksFromStored('storage');
      expect(overviewHiddenBlocksToStored(off), 'storage');
    });
  });

  group('hint place', () {
    test('the milestone or rate card never shows beside another hint', () {
      List<OverviewHint> place({
        bool first = false,
        bool news = false,
        bool tip = false,
      }) => overviewHintPlace(
        firstStepsVisible: first,
        whatsNewHasItems: news,
        tipVisible: tip,
        askVisible: true,
      );
      expect(place(), [OverviewHint.ask]);
      expect(place(first: true), [OverviewHint.firstSteps]);
      expect(place(news: true), [OverviewHint.whatsNew]);
      expect(place(tip: true), [OverviewHint.tip]);
    });

    test('the first steps hold the place alone', () {
      expect(
        overviewHintPlace(
          firstStepsVisible: true,
          whatsNewHasItems: true,
          tipVisible: true,
        ),
        [OverviewHint.firstSteps],
      );
    });

    test('afterwards what is new comes before the tip', () {
      expect(
        overviewHintPlace(
          firstStepsVisible: false,
          whatsNewHasItems: true,
          tipVisible: true,
        ),
        [OverviewHint.whatsNew, OverviewHint.tip],
      );
      expect(
        overviewHintPlace(
          firstStepsVisible: false,
          whatsNewHasItems: false,
          tipVisible: false,
        ),
        isEmpty,
      );
    });
  });

  group('tempo', () {
    AnalyticsData figures(int recordings, int seconds) => AnalyticsData(
      totalRecordings: recordings,
      totalDurationMinutes: seconds ~/ 60,
      totalWords: 120,
      totalDurationSec: seconds.toDouble(),
      timeSavedMinutes: 0,
      dailyActivity: const [0, 0, 0, 0, 0, 0, 0],
      modelUsage: const [],
      durationBuckets: const [0, 0, 0, 0, 0],
      localSavingsUsd: 0,
      cloudCostUsd: 0,
    );

    test('needs three dictations and a minute of recording', () {
      expect(overviewWordsPerMinute(figures(2, 600)), isNull);
      expect(overviewWordsPerMinute(figures(3, 59)), isNull);
      expect(overviewWordsPerMinute(figures(3, 60)), 120);
    });

    test('Statistik uses the same rule: one short dictation shows no tempo '
        '(#1845)', () {
      expect(figures(1, 1).wordsPerMinute, isNull);
      expect(figures(3, 60).wordsPerMinute, 120);
    });
  });

  group('overviewStatusIssue', () {
    OverviewStatusIssue? issue({
      bool missing = false,
      bool downloading = false,
      bool failed = false,
      bool mic = false,
      bool hotkey = false,
      bool recovery = false,
    }) => overviewStatusIssue(
      recoveryPending: recovery,
      modelMissing: missing,
      modelDownloading: downloading,
      modelFailed: failed,
      micDenied: mic,
      hotkeyUnbound: hotkey,
    );

    test('shows nothing when everything is ready', () {
      expect(issue(), isNull);
    });

    test('a recording to recover outranks every readiness problem', () {
      expect(
        issue(recovery: true, missing: true, downloading: true, mic: true),
        OverviewStatusIssue.recoveryPending,
      );
    });

    test('a running download outranks a failed or missing model', () {
      expect(
        issue(missing: true, downloading: true, failed: true),
        OverviewStatusIssue.modelDownloading,
      );
    });

    test('a failed model outranks a missing one', () {
      expect(
        issue(missing: true, failed: true),
        OverviewStatusIssue.modelFailed,
      );
    });

    test('model problems outrank microphone, which outranks the hotkey', () {
      expect(
        issue(missing: true, mic: true, hotkey: true),
        OverviewStatusIssue.modelMissing,
      );
      expect(issue(mic: true, hotkey: true), OverviewStatusIssue.micDenied);
      expect(issue(hotkey: true), OverviewStatusIssue.hotkeyUnbound);
    });
  });

  group('week and recordings', () {
    test('the week starts on Monday at local midnight', () {
      expect(overviewWeekStart(_now), DateTime(2026, 10, 26));
      expect(
        overviewWeekStart(DateTime(2026, 11, 1, 9)),
        DateTime(2026, 10, 26),
      );
    });

    test('the empty state of the recent recordings', () {
      final kept = _entry(id: 'a', timestamp: DateTime(2026, 10, 28, 9));
      expect(overviewRecentEmpty([kept], saveHistory: true), isNull);
      expect(
        overviewRecentEmpty([], saveHistory: true),
        OverviewRecentEmpty.none,
      );
      expect(
        overviewRecentEmpty([kept.copyWith(archived: true)], saveHistory: true),
        OverviewRecentEmpty.putAway,
      );
      expect(
        overviewRecentEmpty([kept], saveHistory: false),
        OverviewRecentEmpty.notSaved,
      );
    });

    test(
      'latest recordings are newest first, five at most, no archive or trash',
      () {
        final entries = [
          for (var i = 0; i < 7; i++)
            _entry(id: 'e$i', timestamp: DateTime(2026, 10, 20 + i)),
          _entry(
            id: 'archived',
            timestamp: DateTime(2026, 10, 29),
            archived: true,
          ),
          _entry(
            id: 'trashed',
            timestamp: DateTime(2026, 10, 29),
            deletedAt: DateTime(2026, 10, 29),
          ),
        ];
        final latest = overviewLatestRecordings(entries);
        expect(latest.map((e) => e.id), ['e6', 'e5', 'e4', 'e3', 'e2']);
      },
    );

    test('the latest notes: three, edited last first, pinned not first, '
        'trashed and blank ones left out, ties by id', () {
      final notes = [
        _note(id: 'old', updatedAt: DateTime(2026, 10, 1), pinned: true),
        _note(id: 'b', updatedAt: DateTime(2026, 10, 20)),
        _note(id: 'a', updatedAt: DateTime(2026, 10, 20)),
        _note(id: 'new', updatedAt: DateTime(2026, 10, 25)),
        _note(
          id: 'titled',
          updatedAt: DateTime(2026, 10, 24),
          content: '',
          title: 'T',
        ),
        _note(id: 'blank', updatedAt: DateTime(2026, 10, 29), content: '  '),
        _note(
          id: 'trashed',
          updatedAt: DateTime(2026, 10, 29),
          deletedAt: DateTime(2026, 10, 29),
        ),
      ];
      expect(overviewLatestNotes(notes).map((n) => n.id), [
        'new',
        'titled',
        'a',
      ]);
      expect(overviewLatestNotes(const []), isEmpty);
    });

    test('the day of a row: today, yesterday across a month, earlier', () {
      final now = DateTime(2026, 11, 1, 9);
      expect(
        overviewDayOf(DateTime(2026, 11, 1, 0, 1), now),
        OverviewDay.today,
      );
      expect(
        overviewDayOf(DateTime(2026, 10, 31, 23, 59), now),
        OverviewDay.yesterday,
      );
      expect(
        overviewDayOf(DateTime(2026, 10, 30, 12), now),
        OverviewDay.earlier,
      );
    });

    test('the period bound is the week start, or none for all time', () {
      expect(
        overviewPeriodSince(OverviewPeriod.week, _now),
        DateTime(2026, 10, 26),
      );
      expect(overviewPeriodSince(OverviewPeriod.all, _now), isNull);
    });
  });

  group('discovery tips', () {
    test('prefers a tip the user has not used yet', () {
      final next = overviewNextTip(
        used: {OverviewTip.smartMode, OverviewTip.vocabulary},
        dismissed: {},
        shownInCycle: {},
      );
      expect(next!.tip, OverviewTip.snippets);
      expect(next.shownInCycle, {OverviewTip.snippets});
    });

    test('skips dismissed tips and returns null when none is left', () {
      final all = OverviewTip.values.toSet();
      expect(
        overviewNextTip(used: {}, dismissed: all, shownInCycle: {}),
        isNull,
      );
      final next = overviewNextTip(
        used: {},
        dismissed: {OverviewTip.smartMode},
        shownInCycle: {},
      );
      expect(next!.tip, isNot(OverviewTip.smartMode));
    });

    test('restarts the cycle once every open tip has been shown', () {
      final open = OverviewTip.values.toSet();
      final next = overviewNextTip(used: {}, dismissed: {}, shownInCycle: open);
      expect(next, isNotNull);
      expect(next!.shownInCycle, {next.tip});
    });

    test(
      'changes at most one tip per day and keeps it for the rest of the day',
      () {
        const start = OverviewTipState();
        final first = overviewTipForVisit(
          state: start,
          today: '2026-10-30',
          used: {},
        );
        expect(first.tip, isNotNull);

        final again = overviewTipForVisit(
          state: first.state,
          today: '2026-10-30',
          used: {},
        );
        expect(again.tip, first.tip);

        final nextDay = overviewTipForVisit(
          state: again.state,
          today: '2026-10-31',
          used: {},
        );
        expect(nextDay.tip, isNot(first.tip));
      },
    );

    test('a dismissed tip stays hidden for the rest of the day', () {
      final first = overviewTipForVisit(
        state: const OverviewTipState(),
        today: '2026-10-30',
        used: {},
      );
      final dismissed = first.state.copyWith(dismissed: {first.tip!});
      final later = overviewTipForVisit(
        state: dismissed,
        today: '2026-10-30',
        used: {},
      );
      expect(later.tip, isNull);
    });

    test('turning tips off shows nothing on any day', () {
      final off = overviewTipForVisit(
        state: const OverviewTipState(off: true),
        today: '2026-10-30',
        used: {},
      );
      expect(off.tip, isNull);
    });

    test('stored state survives a round trip through the settings strings', () {
      const state = OverviewTipState(
        day: '2026-10-30',
        current: OverviewTip.notes,
        shownInCycle: {OverviewTip.notes, OverviewTip.snippets},
        dismissed: {OverviewTip.smartMode},
      );
      final restored = OverviewTipState.fromStored(
        day: state.day,
        current: state.storedCurrent,
        shownInCycle: state.storedShownInCycle,
        dismissed: state.storedDismissed,
        off: state.storedOff,
      );
      expect(restored.current, OverviewTip.notes);
      expect(restored.shownInCycle, state.shownInCycle);
      expect(restored.dismissed, state.dismissed);
      expect(restored.off, isFalse);
    });

    test('tips wait until the first steps are done or closed', () {
      expect(
        overviewTipsEligible(
          firstStepsArmed: true,
          firstStepsDismissed: false,
          firstStepsAllDone: false,
        ),
        isFalse,
      );
      expect(
        overviewTipsEligible(
          firstStepsArmed: true,
          firstStepsDismissed: true,
          firstStepsAllDone: false,
        ),
        isTrue,
      );
      expect(
        overviewTipsEligible(
          firstStepsArmed: false,
          firstStepsDismissed: false,
          firstStepsAllDone: false,
        ),
        isTrue,
      );
    });
  });

  group('what is new', () {
    const item = WhatsNewItem(
      id: 'x',
      title: _titleOf,
      body: _bodyOf,
      target: 'history',
    );

    test('shows nothing without entries for the running version', () {
      final view = overviewWhatsNewView(
        currentVersion: '9.9.9',
        closedVersion: null,
        openedVersion: null,
        registry: const {
          '1.0.0': [item],
        },
      );
      expect(view.items, isEmpty);
      expect(view.dot, isFalse);
    });

    test('the dot stays until the page was opened, the card until closed', () {
      final registry = {
        '2.0.0': [item],
      };
      final fresh = overviewWhatsNewView(
        currentVersion: '2.0.0',
        closedVersion: null,
        openedVersion: null,
        registry: registry,
      );
      expect(fresh.items, [item]);
      expect(fresh.dot, isTrue);

      final opened = overviewWhatsNewView(
        currentVersion: '2.0.0',
        closedVersion: null,
        openedVersion: '2.0.0',
        registry: registry,
      );
      expect(opened.dot, isFalse);
      expect(opened.items, [item]);

      final closed = overviewWhatsNewView(
        currentVersion: '2.0.0',
        closedVersion: '2.0.0',
        openedVersion: '2.0.0',
        registry: registry,
      );
      expect(closed.items, isEmpty);
    });

    test('a fresh install of a version has nothing new to catch up on', () {
      final registry = {
        '2.0.0': [item],
      };
      final onboardedNow = overviewWhatsNewView(
        currentVersion: '2.0.0',
        closedVersion: null,
        openedVersion: null,
        onboardedInVersion: '2.0.0',
        registry: registry,
      );
      expect(onboardedNow.items, isEmpty);
      expect(onboardedNow.dot, isFalse);

      // An install that finished the onboarding earlier, or before the
      // version was recorded, sees the card as before.
      for (final earlier in ['1.9.0', '']) {
        final update = overviewWhatsNewView(
          currentVersion: '2.0.0',
          closedVersion: null,
          openedVersion: null,
          onboardedInVersion: earlier,
          registry: registry,
        );
        expect(update.items, [item]);
        expect(update.dot, isTrue);
      }
    });

    test('a patch shows the entries of its minor release, and what was '
        'closed or onboarded there stays done (1.5.1)', () {
      final registry = {
        '2.0.0': [item],
      };
      final updatedFromOlder = overviewWhatsNewView(
        currentVersion: '2.0.1',
        closedVersion: '1.9.0',
        openedVersion: '1.9.0',
        onboardedInVersion: '1.9.0',
        registry: registry,
      );
      expect(updatedFromOlder.items, [item]);
      expect(updatedFromOlder.dot, isTrue);

      for (final (closed, opened, onboarded) in [
        ('2.0.0', '2.0.0', '1.9.0'), // closed in 2.0.0
        (null, null, '2.0.0'), // fresh 2.0.0 install
      ]) {
        final view = overviewWhatsNewView(
          currentVersion: '2.0.1',
          closedVersion: closed,
          openedVersion: opened,
          onboardedInVersion: onboarded,
          registry: registry,
        );
        expect(view.items, isEmpty, reason: '$closed/$onboarded');
        expect(view.dot, isFalse);
      }

      final opened = overviewWhatsNewView(
        currentVersion: '2.0.1',
        closedVersion: null,
        openedVersion: '2.0.0',
        registry: registry,
      );
      expect(opened.items, [item]);
      expect(opened.dot, isFalse);

      // Another minor, or a version string that is not x.y.z, gets nothing.
      for (final v in ['2.1.1', '2.0.1-beta']) {
        expect(
          overviewWhatsNewView(
            currentVersion: v,
            closedVersion: null,
            openedVersion: null,
            registry: registry,
          ).items,
          isEmpty,
          reason: v,
        );
      }
      expect(whatsNewKey('1.5.1', kWhatsNewRegistry), '1.5.0');
    });

    test('every version has 2 to 5 entries with own ids, real targets and '
        'text in every app language (#1576)', () async {
      expect(kWhatsNewRegistry.keys, containsAll(['1.5.0', '1.5.5']));
      final settingsRows = {for (final e in kSettingsSearchTable) e.rowId};
      const pages = {
        'overview',
        'snippets',
        'notes',
        'history',
        'smartMode',
        'replacements',
      };
      final allIds = <String>[];
      for (final MapEntry(key: version, value: items)
          in kWhatsNewRegistry.entries) {
        expect(items.length, inInclusiveRange(2, 5), reason: version);
        allIds.addAll(items.map((i) => i.id));
        for (final item in items) {
          final row = item.target.startsWith('settings:')
              ? item.target.substring('settings:'.length)
              : null;
          expect(
            pages.contains(item.target) ||
                item.target == kOverviewCustomizeTarget ||
                (row != null && settingsRows.contains(row)),
            isTrue,
            reason: '${item.id} -> ${item.target}',
          );
        }
        for (final locale in L10n.supportedLocales) {
          final l10n = await L10n.delegate.load(locale);
          for (final item in items) {
            expect(item.title(l10n).trim(), isNotEmpty, reason: '$locale');
            expect(item.body(l10n).trim(), isNotEmpty, reason: '$locale');
          }
        }
      }
      // Ids are never reused, across versions too.
      expect(allIds.toSet(), hasLength(allIds.length));
    });

    test('the reviewed version matches the app version in pubspec.yaml', () {
      // Bump this together with the pubspec version, after reviewing the
      // "New in this version" entries for it.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*([0-9.]+)',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(match, isNotNull);
      expect(kWhatsNewReviewedVersion, match!.group(1));
    });
  });
}

String _titleOf(dynamic _) => 'title';
String _bodyOf(dynamic _) => 'body';
