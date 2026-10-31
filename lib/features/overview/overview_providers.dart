/// Riverpod wiring of the "Übersicht" page: the stored tip and "new in
/// version" state, the tip usage signals, and the figures. The rules are in
/// `core/overview/overview_logic.dart`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart' show appVersion;
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OverlaySettings;
import '../../core/data/analytics_provider.dart';
import '../../core/data/database.dart';
import '../../core/data/history_providers.dart';
import '../../core/data/notes_providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/overview/overview_logic.dart';
import '../snippets/snippets_page.dart' show SnippetItem, snippetsProvider;

final _log = AppLogger('Overview');

const _kTipDay = 'overview_tip_day';
const _kTipCurrent = 'overview_tip_current';
const _kTipCycle = 'overview_tip_cycle';
const _kTipDismissed = 'overview_tip_dismissed';
const _kTipOff = 'overview_tip_off';
const _kWhatsNewClosed = 'overview_whats_new_closed';
const _kWhatsNewOpened = 'overview_whats_new_opened';
const _kHiddenBlocks = 'overview_hidden_blocks';
const _kMilestonesSeen = 'overview_milestones_seen';
const _kAskCardDay = 'overview_ask_card_day';

/// The stored discovery and "new in version" state, as the page needs it.
class OverviewPrefs {
  const OverviewPrefs({
    this.loaded = false,
    this.tips = const OverviewTipState(),
    this.visibleTip,
    this.closedVersion,
    this.openedVersion,
    this.hiddenBlocks = const {},
    this.milestonesSeen = const {},
    this.askCardDay,
  });

  /// False until the stored values were read; nothing is decided before.
  final bool loaded;
  final OverviewTipState tips;

  /// The tip shown on this visit (null: none today, or tips closed).
  final OverviewTip? visibleTip;
  final String? closedVersion;
  final String? openedVersion;

  /// Blocks switched off in "Übersicht anpassen".
  final Set<OverviewBlock> hiddenBlocks;

  /// Milestone counts whose card was closed; each shows once.
  final Set<int> milestonesSeen;

  /// The local day ([overviewDayKey]) a milestone card was closed: no
  /// second card on that day.
  final String? askCardDay;

  OverviewPrefs copyWith({
    bool? loaded,
    OverviewTipState? tips,
    OverviewTip? visibleTip,
    bool clearVisible = false,
    String? closedVersion,
    String? openedVersion,
    Set<OverviewBlock>? hiddenBlocks,
    Set<int>? milestonesSeen,
    String? askCardDay,
  }) => OverviewPrefs(
    loaded: loaded ?? this.loaded,
    tips: tips ?? this.tips,
    visibleTip: clearVisible ? null : (visibleTip ?? this.visibleTip),
    closedVersion: closedVersion ?? this.closedVersion,
    openedVersion: openedVersion ?? this.openedVersion,
    hiddenBlocks: hiddenBlocks ?? this.hiddenBlocks,
    milestonesSeen: milestonesSeen ?? this.milestonesSeen,
    askCardDay: askCardDay ?? this.askCardDay,
  );
}

/// Reads and writes the overview state in the `app_settings` table, best
/// effort: losing one remembered tip is not worth an error.
class OverviewPrefsNotifier extends Notifier<OverviewPrefs> {
  final Completer<void> _loaded = Completer<void>();

  @override
  OverviewPrefs build() {
    unawaited(_load());
    return const OverviewPrefs();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(historyDatabaseProvider);
      final tips = OverviewTipState.fromStored(
        day: await db.readAppSetting(_kTipDay),
        current: await db.readAppSetting(_kTipCurrent),
        shownInCycle: await db.readAppSetting(_kTipCycle),
        dismissed: await db.readAppSetting(_kTipDismissed),
        off: await db.readAppSetting(_kTipOff),
      );
      state = OverviewPrefs(
        loaded: true,
        tips: tips,
        closedVersion: await db.readAppSetting(_kWhatsNewClosed),
        openedVersion: await db.readAppSetting(_kWhatsNewOpened),
        hiddenBlocks: overviewHiddenBlocksFromStored(
          await db.readAppSetting(_kHiddenBlocks),
        ),
        milestonesSeen: {
          for (final id
              in (await db.readAppSetting(_kMilestonesSeen) ?? '').split(','))
            ?int.tryParse(id.trim()),
        },
        askCardDay: await db.readAppSetting(_kAskCardDay),
      );
    } on Object catch (e) {
      _log.debug('Overview state not loaded (non-fatal): $e');
      state = const OverviewPrefs(loaded: true);
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  /// Chooses the tip for this visit. Waits for the stored state first, so a
  /// visit right after start-up still follows yesterday's choice.
  Future<void> chooseTipForVisit({
    required DateTime now,
    required Set<OverviewTip> used,
  }) async {
    await _loaded.future;
    final result = overviewTipForVisit(
      state: state.tips,
      today: overviewDayKey(now),
      used: used,
    );
    state = state.copyWith(
      tips: result.state,
      visibleTip: result.tip,
      clearVisible: result.tip == null,
    );
    await _writeTips(result.state);
  }

  Future<void> dismissTip(OverviewTip tip) async {
    final tips = state.tips.copyWith(dismissed: {...state.tips.dismissed, tip});
    state = state.copyWith(tips: tips, clearVisible: true);
    await _writeTips(tips);
  }

  Future<void> turnTipsOff() async {
    final tips = state.tips.copyWith(off: true);
    state = state.copyWith(tips: tips, clearVisible: true);
    await _writeTips(tips);
  }

  /// Switches the discovery tips on or off from "Übersicht anpassen". On
  /// again, the next visit picks a tip as usual.
  Future<void> setTipsOn({required bool on}) async {
    final tips = state.tips.copyWith(off: !on);
    state = state.copyWith(tips: tips, clearVisible: !on);
    await _writeTips(tips);
  }

  /// Shows or hides one block of the page.
  Future<void> setBlockVisible(
    OverviewBlock block, {
    required bool visible,
  }) async {
    final hidden = {...state.hiddenBlocks};
    visible ? hidden.remove(block) : hidden.add(block);
    state = state.copyWith(hiddenBlocks: hidden);
    await _write(_kHiddenBlocks, overviewHiddenBlocksToStored(hidden));
  }

  /// The Übersicht was opened in [version]: the nav dot goes away.
  Future<void> markOpened(String version) async {
    if (state.openedVersion == version) return;
    state = state.copyWith(openedVersion: version);
    await _write(_kWhatsNewOpened, version);
  }

  /// The milestone card for [count] was closed on [now]: it never comes
  /// again, and no other card follows that day.
  Future<void> closeMilestone(int count, {required DateTime now}) async {
    final seen = {...state.milestonesSeen, count};
    final day = overviewDayKey(now);
    state = state.copyWith(milestonesSeen: seen, askCardDay: day);
    await _write(_kMilestonesSeen, (seen.toList()..sort()).join(','));
    await _write(_kAskCardDay, day);
  }

  /// The "new in this version" card was closed in [version].
  Future<void> closeWhatsNew(String version) async {
    state = state.copyWith(closedVersion: version);
    await _write(_kWhatsNewClosed, version);
  }

  Future<void> _writeTips(OverviewTipState t) async {
    await _write(_kTipDay, t.day ?? '');
    await _write(_kTipCurrent, t.storedCurrent ?? '');
    await _write(_kTipCycle, t.storedShownInCycle);
    await _write(_kTipDismissed, t.storedDismissed);
    await _write(_kTipOff, t.storedOff);
  }

  Future<void> _write(String key, String value) async {
    try {
      await ref.read(historyDatabaseProvider).writeAppSetting(key, value);
    } on Object catch (e) {
      _log.debug('Overview state not saved (non-fatal): $e');
    }
  }
}

final overviewPrefsProvider =
    NotifierProvider<OverviewPrefsNotifier, OverviewPrefs>(
      OverviewPrefsNotifier.new,
    );

/// The version the running app reports, as the "new in version" rules see it.
String overviewCurrentVersion() => appVersion;

/// The "new in this version" card and dot for the running version.
final overviewWhatsNewProvider = Provider<WhatsNewView>((ref) {
  final prefs = ref.watch(overviewPrefsProvider);
  return overviewWhatsNewView(
    currentVersion: overviewCurrentVersion(),
    closedVersion: prefs.closedVersion,
    openedVersion: prefs.openedVersion,
    onboardedInVersion:
        ref.watch(settingsProvider).value?.onboarding.completedInVersion ?? '',
  );
});

/// Whether the nav entry shows its "new in this version" dot.
final overviewNavDotProvider = Provider<bool>(
  (ref) => ref.watch(overviewWhatsNewProvider).dot,
);

/// The tips whose use the app can see locally. Nothing leaves the device.
/// A tip whose feature is already in use is not offered first.
final overviewTipUsageProvider = Provider<Set<OverviewTip>>((ref) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final snippets = ref.watch(snippetsProvider).value ?? const <SnippetItem>[];
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  return {
    if (settings.smartMode.standardPreset != 'off') OverviewTip.smartMode,
    if (settings.stt.customVocabulary.trim().isNotEmpty) OverviewTip.vocabulary,
    if (snippets.isNotEmpty) OverviewTip.snippets,
    if (notes.isNotEmpty) OverviewTip.notes,
    if (_overlayLookChanged(settings.overlay)) OverviewTip.overlayLook,
  };
});

/// Whether one of the overlay look settings differs from the default, which
/// shows the user already found out the overlay can be made their own.
bool _overlayLookChanged(OverlaySettings o) {
  const d = OverlaySettings.defaults;
  return o.overlaySize != d.overlaySize ||
      o.overlayBackground != d.overlayBackground ||
      o.overlayWave != d.overlayWave ||
      o.overlayForm != d.overlayForm ||
      o.overlayWaveStyle != d.overlayWaveStyle ||
      o.overlayWaveFluid != d.overlayWaveFluid;
}

/// The figures of the page for [period], from the same loader as the
/// Statistik page. Recomputed whenever the recordings change.
final overviewFiguresProvider = FutureProvider.autoDispose
    .family<AnalyticsData, OverviewPeriod>((ref, period) async {
      ref.watch(historyEntriesProvider);
      final db = ref.watch(historyDatabaseProvider);
      return loadAnalyticsData(
        db,
        since: overviewPeriodSince(period, clock.now()),
      );
    });

/// The figures period the user picked on the page (week by default).
class OverviewPeriodNotifier extends Notifier<OverviewPeriod> {
  @override
  OverviewPeriod build() => OverviewPeriod.week;

  void set(OverviewPeriod period) => state = period;
}

final overviewPeriodProvider =
    NotifierProvider<OverviewPeriodNotifier, OverviewPeriod>(
      OverviewPeriodNotifier.new,
    );

/// All dictations in the daily aggregates, for the milestone card.
/// Recomputed whenever the recordings change.
final overviewDictationTotalProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  ref.watch(historyEntriesProvider);
  return ref.watch(historyDatabaseProvider).analyticsEntryCount();
});
