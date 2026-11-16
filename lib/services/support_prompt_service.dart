/// Support prompt service — decides when the quiet support card shows in the
/// hint place of the Übersicht, after the user has had substantial positive
/// experience with the app. It is never a dialog and never takes the focus.
///
/// Mechanically analogous to [ReviewPromptNotifier] (`review_prompt_service.dart`)
/// but with entirely independent persisted state — its own SharedPreferences
/// keys and its own thresholds. The two asks are never coupled through shared
/// counters; they are only coordinated in *timing* (see [checkAndMaybePrompt]
/// and the shared day rule of the hint place). The one shared input is the
/// history itself: dictations whose paste failed are excluded from both
/// thresholds (see [countEligibleRecordings]).
///
/// "Später" and the main action buy a 90-day pause; "Nicht mehr fragen" is
/// permanent. Opening a sponsoring link buys a 9-month quiet period, after
/// which exactly one recurring-sponsoring follow-up card is offered.
/// Regardless of path, a hard cap of [_impressionCap] card rounds per install
/// is enforced — see internal-notes §6.8.
///
/// Uses SharedPreferences to persist prompt history across sessions.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import 'deploy_channel_service.dart';
import 'review_prompt_service.dart';
import 'shared_prefs_safe_read.dart';
import 'support/support_capabilities.dart';
import 'support/support_state.dart';
import 'telemetry_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Which card copy/variant is due to be shown.
enum SupportPromptKind {
  /// The regular support ask.
  initial,

  /// The one-time, distinct follow-up offering to turn a prior link click
  /// into recurring monthly sponsoring. Only reachable after [initial] was
  /// resolved via a link click and the post-link quiet period has elapsed.
  recurringFollowUp,
}

/// Snapshot of the support prompt service state.
class SupportPromptState {
  const SupportPromptState({
    this.shouldShowPrompt = false,
    this.kind = SupportPromptKind.initial,
  });

  final bool shouldShowPrompt;
  final SupportPromptKind kind;

  SupportPromptState copyWith({
    bool? shouldShowPrompt,
    SupportPromptKind? kind,
  }) => SupportPromptState(
    shouldShowPrompt: shouldShowPrompt ?? this.shouldShowPrompt,
    kind: kind ?? this.kind,
  );
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

/// Total number of card rounds (any variant) shown so far.
const _keyImpressionCount = 'support_prompt_impression_count';

/// Timestamp of the last "Später" or main action — starts a [_snoozeDays]
/// pause.
const _keySnoozeMs = 'support_prompt_snooze_ms';

/// Timestamp of the last sponsoring-link click — starts a
/// [_postLinkQuietDays] quiet period before the recurring follow-up.
const _keyPostLinkMs = 'support_prompt_post_link_ms';

/// Whether a sponsoring link has ever been opened — gates whether the next
/// eligible show is the recurring follow-up rather than the initial ask.
const _keyLinkClicked = 'support_prompt_link_clicked';

/// Whether the one-time recurring follow-up has already been shown — once
/// `true`, the card never shows again regardless of the cap.
const _keyFollowUpShown = 'support_prompt_followup_shown';

/// "Nicht mehr fragen": permanent. No update, cap or quiet period lifts it.
const _keyNever = 'support_prompt_never';

/// Whether a card round is on screen and not yet answered. A round counts
/// once against [_impressionCap], however often the Übersicht is reopened
/// before the user answers it.
const _keyRoundOpen = 'support_prompt_round_open';

/// Hard cap on card rounds (any variant) per install. Independent of
/// resolution path — see internal-notes §6.8.
const _impressionCap = 3;

/// Pause after "Später" or the main action.
const _snoozeDays = 90;

/// Quiet period after a sponsoring-link click, before the one-time recurring
/// follow-up becomes eligible. ~9 months at 30 days/month, matching this
/// codebase's existing day-based cooldown convention.
const _postLinkQuietDays = 270;

/// Hypothese: minimum successfully pasted dictations before the support card
/// may show. Twice the review threshold, so the two asks read as distinct
/// moments; failed pastes do not count ([countEligibleRecordings]).
const _minRecordings = 40;

/// Hypothese: minimum distinct dictation days — a habit, not one busy week.
const _minDictationDays = 5;

/// Hypothese: minimum days between the first dictation and the first card.
const _minDaysInUse = 14;

/// Read-only coordination keys — these are [ReviewPromptNotifier]'s own
/// persisted key *names*, duplicated here (not imported, since they are
/// library-private in `review_prompt_service.dart`) purely so this service
/// can check — never write — whether the review prompt was recently shown
/// or snoozed. This is a one-directional, read-only mutual-exclusion check;
/// it does not create any shared counter or mutable state between the two
/// services.
const _reviewKeyLastShownMs = 'review_prompt_last_shown';
const _reviewKeyLastSnoozeMs = 'review_prompt_last_snooze';

/// Coordination window (days). If the review prompt was shown or snoozed
/// within this many days, the support card stays silent this check —
/// ensuring the two asks never land in close temporal proximity. Matches
/// the order of magnitude of the review prompt's own cooldowns (30/60 days).
const _coordinationWindowDays = 30;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages when the support card shows in the hint place of the Übersicht.
///
/// [checkAndMaybePrompt] runs after a successful paste and on every visit of
/// the Übersicht. While [SupportPromptState.shouldShowPrompt] is `true` the
/// hint place may show the card (the Übersicht decides the order); the card
/// calls [markPresented] once it is on screen and one of [dismiss]
/// ("Später"), [never] or [opened] (main action) when answered.
class SupportPromptNotifier extends Notifier<SupportPromptState> {
  static final _log = AppLogger('SupportPrompt');

  @override
  SupportPromptState build() => const SupportPromptState();

  /// Checks whether conditions are met and, if so, sets
  /// [SupportPromptState.shouldShowPrompt] to `true` with the appropriate
  /// [SupportPromptState.kind].
  ///
  /// Conditions (in order):
  /// 1. Not "Nicht mehr fragen"; no verified, pending or declared support;
  ///    the sponsor chip is not hidden. An opened checkout is no payment.
  /// 2. This build has a usable payment route ([_offersPaymentRoute]).
  /// 3. The cap ([_impressionCap]) is not reached, unless a round is still
  ///    open (it already counted), and the one-time follow-up is not used up.
  /// 4. Usage: [supportPromptUsageMet].
  /// 5. The review prompt is not pending in this session, and was not
  ///    shown/snoozed within [_coordinationWindowDays] days.
  /// 6. Depending on whether a sponsoring link was ever clicked: either the
  ///    post-link quiet period ([_postLinkQuietDays]) has elapsed (→ the
  ///    recurring follow-up), or no pause ([_snoozeDays]) is active (→ the
  ///    initial ask).
  Future<void> checkAndMaybePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (readBoolPrefSafe(prefs, _keyNever) == true) return;

      // Verified and self-declared supporters are never asked again.
      final status = await loadSupportStatus(
        prefs: prefs,
        bridge: ref.read(supportStoreBridgeProvider),
      );
      // A user who hid the sponsor chip is not asked again either (R-12).
      if (status.suppressesPrompts || status.chipHidden) return;
      // A pending store purchase is a payment on its way: no ask meanwhile.
      if (readSupportPurchasePending(prefs)) return;
      if (!await _offersPaymentRoute()) return;

      final roundOpen = readBoolPrefSafe(prefs, _keyRoundOpen) == true;
      final impressions = readIntPrefSafe(prefs, _keyImpressionCount) ?? 0;
      if (!roundOpen && impressions >= _impressionCap) return;

      // The recurring follow-up is one-time; once shown, nothing is left to
      // offer regardless of remaining impression budget.
      if (readBoolPrefSafe(prefs, _keyFollowUpShown) == true) return;

      final db = ref.read(historyDatabaseProvider);
      // Failed-paste dictations do not count here either (growth review GR-012).
      final count = await countEligibleRecordings(prefs, db);
      final now = clock.now();
      if (!supportPromptUsageMet(
        recordings: count,
        dictationDays: await db.analyticsActiveDays(),
        firstDictationDay: await db.analyticsFirstActiveDay(),
        now: now,
      )) {
        return;
      }

      // In-session guard: if the review prompt is currently pending display,
      // never offer the support card alongside it.
      if (ref.read(reviewPromptProvider).shouldShowPrompt) return;

      // Cross-session guard: skip if the review prompt was shown or snoozed
      // recently, so the two asks stay spaced apart in time.
      // Safe read: this key can be a bundle-ID-migrated String (see
      // shared_prefs_safe_read.dart) — confirmed crashing in production as
      // Sentry FLUTTER_WHISPASTE-BP before this fix.
      final reviewLastShownMs =
          readIntPrefSafe(prefs, _reviewKeyLastShownMs) ?? 0;
      if (_isWithinDays(reviewLastShownMs, _coordinationWindowDays, now)) {
        return;
      }
      final reviewLastSnoozeMs =
          readIntPrefSafe(prefs, _reviewKeyLastSnoozeMs) ?? 0;
      if (_isWithinDays(reviewLastSnoozeMs, _coordinationWindowDays, now)) {
        return;
      }

      final kind = _kindAfterLinkHistory(prefs, now);
      if (kind == null) return;
      _log.info('card due: $kind (recordings=$count)');
      state = state.copyWith(shouldShowPrompt: true, kind: kind);
    } on Exception catch (e) {
      _log.error('check failed: $e', e);
    }
  }

  /// The card kind due after the link and pause history, or null when the
  /// card stays silent. A coffee click shares the quiet period but never
  /// leads to the recurring follow-up (GR-021).
  SupportPromptKind? _kindAfterLinkHistory(
    SharedPreferences prefs,
    DateTime now,
  ) {
    final postLinkMs = readIntPrefSafe(prefs, _keyPostLinkMs) ?? 0;
    final inQuietPeriod = _isWithinDays(postLinkMs, _postLinkQuietDays, now);
    if (readBoolPrefSafe(prefs, _keyLinkClicked) == true) {
      if (postLinkMs == 0 || inQuietPeriod) return null;
      return SupportPromptKind.recurringFollowUp;
    }
    if (inQuietPeriod) return null;
    final snoozeMs = readIntPrefSafe(prefs, _keySnoozeMs) ?? 0;
    if (_isWithinDays(snoozeMs, _snoozeDays, now)) return null;
    return SupportPromptKind.initial;
  }

  /// Whether [ms] (epoch milliseconds, 0 = never) lies less than [days] full
  /// days before [now].
  static bool _isWithinDays(int ms, int days, DateTime now) =>
      ms > 0 &&
      now.difference(DateTime.fromMillisecondsSinceEpoch(ms)).inDays < days;

  /// Call when the card is on screen. The first call of a round counts one
  /// round against [_impressionCap] and sends `card_shown`; showing the same
  /// unanswered card again on a later visit counts nothing.
  Future<void> markPresented() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (readBoolPrefSafe(prefs, _keyRoundOpen) == true) return;
      final impressions =
          (readIntPrefSafe(prefs, _keyImpressionCount) ?? 0) + 1;
      await prefs.setInt(_keyImpressionCount, impressions);
      await prefs.setBool(_keyRoundOpen, true);
      _track(SupportTelemetryEvent.cardShown);
    } on Exception catch (e) {
      _log.error('markPresented failed: $e', e);
    }
  }

  /// "Später": a 90-day pause, not a permanent flag. For the recurring
  /// follow-up nothing is left to offer afterward, so it marks the follow-up
  /// as shown.
  Future<void> dismiss() async {
    _track(SupportTelemetryEvent.cardLater);
    await _pause('dismiss');
  }

  /// Main action "Unterstützen": the card leaves for Help › Unterstützen and
  /// pauses like "Später". Opening the page is no payment; a sponsoring link
  /// opened there records itself ([markLinkOpened]).
  Future<void> opened() async {
    _track(SupportTelemetryEvent.cardOpen);
    await _pause('opened');
  }

  /// "Nicht mehr fragen": permanent, survives restart and update.
  Future<void> never() async {
    _track(SupportTelemetryEvent.cardNever);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyNever, true);
      await prefs.remove(_keyRoundOpen);
    } on Exception catch (e) {
      _log.error('never failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  Future<void> _pause(String action) async {
    final kind = state.kind;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (kind == SupportPromptKind.recurringFollowUp) {
        await prefs.setBool(_keyFollowUpShown, true);
      } else {
        await prefs.setInt(_keySnoozeMs, clock.now().millisecondsSinceEpoch);
      }
      await prefs.remove(_keyRoundOpen);
    } on Exception catch (e) {
      _log.error('$action failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  /// Card telemetry: the event plus the card kind, nothing else.
  void _track(SupportTelemetryEvent event) {
    try {
      recordSupportEvent(
        ref.read(telemetryProvider),
        event,
        name: state.kind.name,
      );
    } on Object catch (e) {
      _log.debug('telemetry skipped: $e');
    }
  }

  /// Records that a sponsoring link (GitHub Sponsors/Ko-fi) opened in the
  /// browser. Call only after the launch succeeded.
  ///
  /// For the initial ask, this starts the [_postLinkQuietDays] quiet period
  /// after which the one-time recurring follow-up becomes eligible. For the
  /// recurring follow-up itself, there is nothing left to offer afterward, so
  /// it marks the follow-up as shown. A browser click never counts as a
  /// payment.
  Future<void> markLinkOpened() async {
    final kind = state.kind;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (kind == SupportPromptKind.recurringFollowUp) {
        await prefs.setBool(_keyFollowUpShown, true);
      } else {
        await prefs.setBool(_keyLinkClicked, true);
        await prefs.setInt(_keyPostLinkMs, clock.now().millisecondsSinceEpoch);
      }
    } on Exception catch (e) {
      _log.error('markLinkOpened failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  /// Records a click on a coffee page (Ko-fi, Buy Me a Coffee) that opened in
  /// the browser (GR-021). The quiet period starts as for any sponsoring link,
  /// but the flag for the recurring follow-up stays unset: a coffee click is a
  /// one-time gift and never leads to a monthly ask. Call only after the launch
  /// succeeded.
  Future<void> markCoffeeLinkOpened() async {
    final kind = state.kind;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (kind == SupportPromptKind.recurringFollowUp) {
        await prefs.setBool(_keyFollowUpShown, true);
      } else {
        await prefs.setInt(_keyPostLinkMs, clock.now().millisecondsSinceEpoch);
      }
    } on Exception catch (e) {
      _log.error('markCoffeeLinkOpened failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  /// Whether this build has a usable payment route behind the main action:
  /// an external sponsoring route, or the store's one-time purchase where the
  /// store can sell it right now. Builds without one (fail-closed Linux and
  /// macOS installer builds offer only star and share) get no card.
  Future<bool> _offersPaymentRoute() async {
    final external = ref
        .read(supportCapabilitiesProvider)
        .any(
          (ask) =>
              ask == SupportAsk.githubSponsors ||
              ask == SupportAsk.kofi ||
              ask == SupportAsk.paypal,
        );
    if (external) return true;
    final target = coffeeSupportTarget(
      ref.read(deployChannelProvider),
      ref.read(supportPlatformProvider),
    );
    if (target != CoffeeSupportTarget.storePurchase) return false;
    return ref.read(supportStoreTipAvailableProvider.future);
  }
}

/// Whether the usage alone allows the support card: [_minRecordings]
/// successfully pasted dictations on at least [_minDictationDays] days, the
/// first of them at least [_minDaysInUse] days before [now]. All three values
/// are a hypothesis (Hypothese) to be checked against real use. Pauses, the
/// cap and "Nicht mehr fragen" come on top.
bool supportPromptUsageMet({
  required int recordings,
  required int dictationDays,
  required DateTime? firstDictationDay,
  required DateTime now,
}) =>
    recordings >= _minRecordings &&
    dictationDays >= _minDictationDays &&
    firstDictationDay != null &&
    now.difference(firstDictationDay).inDays >= _minDaysInUse;

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global support prompt provider.
final supportPromptProvider =
    NotifierProvider<SupportPromptNotifier, SupportPromptState>(
      SupportPromptNotifier.new,
    );
