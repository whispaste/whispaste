/// Riverpod wiring of the "Übersicht" page: the stored tip and "new in
/// version" state, the tip usage signals, and the figures. The rules are in
/// `core/overview/overview_logic.dart`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart' show appVersion;
import '../../core/config/selectable_speech_models.dart';
import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show OverlaySettings;
import '../../core/data/analytics_provider.dart';
import '../../core/data/database.dart';
import '../../core/data/history_providers.dart';
import '../../core/data/notes_providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/overview/speech_setup.dart';
import '../../core/recording/recording_state.dart' show SttServerState;
import '../../services/audio_service.dart'
    show audioInputDevicesProvider, inputDeviceToolMissingProvider;
import '../../services/permissions/mic_permission_notifier.dart';
import '../../services/stt/stt_bundle.dart' show localSttBundleProvider;
import '../../services/stt_parakeet/parakeet_engine_notifier.dart'
    show ParakeetEngineState, parakeetEngineProvider;
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
const _kShownBlocks = 'overview_shown_blocks';
const _kBlockOrder = 'overview_block_order';
const _kSideBlocks = 'overview_side_blocks';
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
    this.shownBlocks = const {},
    this.blockOrder = kOverviewDefaultBlockOrder,
    Set<OverviewBlock>? sideBlocks,
    this.milestonesSeen = const {},
    this.askCardDay,
  }) : sideBlocks = sideBlocks ?? kOverviewDefaultSideBlocks;

  /// False until the stored values were read; nothing is decided before.
  final bool loaded;
  final OverviewTipState tips;

  /// The tip shown on this visit (null: none today, or tips closed).
  final OverviewTip? visibleTip;
  final String? closedVersion;
  final String? openedVersion;

  /// Blocks switched off in "Übersicht anpassen" (blocks on by default).
  final Set<OverviewBlock> hiddenBlocks;

  /// Blocks switched on in "Übersicht anpassen" (blocks off by default).
  final Set<OverviewBlock> shownBlocks;

  /// The order of the blocks (#1970), shown or not, so a block switched on
  /// again returns to its place. Stored only once the user moved a card.
  final List<OverviewBlock> blockOrder;

  /// The blocks in the side column of the wide layout (#1970).
  final Set<OverviewBlock> sideBlocks;

  /// Whether order or columns differ from the default layout.
  bool get layoutIsCustom =>
      overviewBlockOrderIsCustom(blockOrder) ||
      overviewSideBlocksAreCustom(sideBlocks);

  /// Whether [block] is on the page.
  bool isBlockShown(OverviewBlock block) =>
      overviewBlockShown(block, hidden: hiddenBlocks, shown: shownBlocks);

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
    Set<OverviewBlock>? shownBlocks,
    List<OverviewBlock>? blockOrder,
    Set<OverviewBlock>? sideBlocks,
    Set<int>? milestonesSeen,
    String? askCardDay,
  }) => OverviewPrefs(
    loaded: loaded ?? this.loaded,
    tips: tips ?? this.tips,
    visibleTip: clearVisible ? null : (visibleTip ?? this.visibleTip),
    closedVersion: closedVersion ?? this.closedVersion,
    openedVersion: openedVersion ?? this.openedVersion,
    hiddenBlocks: hiddenBlocks ?? this.hiddenBlocks,
    shownBlocks: shownBlocks ?? this.shownBlocks,
    blockOrder: blockOrder ?? this.blockOrder,
    sideBlocks: sideBlocks ?? this.sideBlocks,
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

  /// Completes once the stored values were read (or reading failed). Other
  /// pages wait for it before they act on a block switch, e.g. the support
  /// page asking for the project numbers only while "Mitmachen" is shown.
  Future<void> get ready => _loaded.future;

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
        shownBlocks: overviewShownBlocksFromStored(
          await db.readAppSetting(_kShownBlocks),
        ),
        blockOrder: overviewBlockOrderFromStored(
          await db.readAppSetting(_kBlockOrder),
        ),
        sideBlocks: overviewSideBlocksFromStored(
          await db.readAppSetting(_kSideBlocks),
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

  /// Shows or hides one block of the page. A block that is off by default is
  /// kept in the shown set, the others in the hidden set.
  Future<void> setBlockVisible(
    OverviewBlock block, {
    required bool visible,
  }) async {
    if (block.shownByDefault) {
      final hidden = {...state.hiddenBlocks};
      visible ? hidden.remove(block) : hidden.add(block);
      state = state.copyWith(hiddenBlocks: hidden);
      await _write(_kHiddenBlocks, overviewHiddenBlocksToStored(hidden));
    } else {
      final shown = {...state.shownBlocks};
      visible ? shown.add(block) : shown.remove(block);
      state = state.copyWith(shownBlocks: shown);
      await _write(_kShownBlocks, overviewShownBlocksToStored(shown));
    }
  }

  /// Stores a new order of the blocks (#1970), from a drag or the keyboard.
  Future<void> setBlockOrder(List<OverviewBlock> order) async {
    state = state.copyWith(blockOrder: List.unmodifiable(order));
    await _write(_kBlockOrder, overviewBlockOrderToStored(order));
  }

  /// Puts [block] into the side column or the main column of the wide
  /// layout (#1970).
  Future<void> setBlockSide(OverviewBlock block, {required bool side}) async {
    final next = {...state.sideBlocks};
    side ? next.add(block) : next.remove(block);
    state = state.copyWith(sideBlocks: Set.unmodifiable(next));
    await _write(_kSideBlocks, overviewSideBlocksToStored(next));
  }

  /// Back to the default order and columns; the stored values go back to
  /// "default", so a later version may change the default again.
  Future<void> resetBlockOrder() async {
    state = state.copyWith(
      blockOrder: kOverviewDefaultBlockOrder,
      sideBlocks: kOverviewDefaultSideBlocks,
    );
    await _write(_kBlockOrder, '');
    await _write(_kSideBlocks, kOverviewSideBlocksDefault);
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

  /// The rating dialog or an ask card was answered on [now]: no other ask
  /// card follows that day (one shared day rule for all ask cards).
  Future<void> noteAskCardDay(DateTime now) async {
    final day = overviewDayKey(now);
    state = state.copyWith(askCardDay: day);
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
      ref.watch(historyRevisionProvider);
      final db = ref.watch(historyDatabaseProvider);
      final data = await loadAnalyticsData(
        db,
        since: overviewPeriodSince(period, clock.now()),
      );
      // The Übersicht figures have no per-panel error states: a failed
      // query fails the figures as before, instead of showing zeros.
      if (data.failedPanels.isNotEmpty) {
        throw StateError('Analytics figures failed: ${data.failedPanels}');
      }
      return data;
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
  ref.watch(historyRevisionProvider);
  return ref.watch(historyDatabaseProvider).analyticsEntryCount();
});

/// The speech rows of the system card: engine, speech model and microphone.
/// Built only from states the dock and Settings already keep, so a change in
/// Settings shows at once and the card adds no reading of its own (#1567).
final overviewSpeechSetupProvider = Provider.autoDispose<OverviewSpeechSetup>((
  ref,
) {
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final whisper = ref.watch(localSttBundleProvider);
  return overviewSpeechSetup(
    settings: settings,
    models: ref.watch(selectableSpeechModelsProvider),
    whisperState: whisper.serverState,
    whisperModelId: whisper.modelId,
    parakeetState: switch (ref.watch(parakeetEngineProvider).state) {
      ParakeetEngineState.stopped => SttServerState.stopped,
      ParakeetEngineState.starting => SttServerState.starting,
      ParakeetEngineState.ready => SttServerState.ready,
      ParakeetEngineState.error => SttServerState.error,
    },
    micDevices: ref.watch(audioInputDevicesProvider).value,
    micListingUnavailable: ref.watch(inputDeviceToolMissingProvider),
    micDenied:
        ref.watch(micPermissionNotifierProvider).status ==
        MicPermissionStatus.denied,
  );
});
