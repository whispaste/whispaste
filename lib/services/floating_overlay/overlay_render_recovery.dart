/// Frame-heartbeat recovery policy for the macOS render engine (WP-84 phase 2,
/// plan item 1).
///
/// The overlay renders in a second Flutter engine whose boot can stall
/// silently (the native shell cannot observe that). After every hidden→visible
/// show the render engine acknowledges its first painted frame. If no
/// acknowledgement arrives within [frameDeadline], the shell is asked to
/// re-boot the render engine, up to [sessionBudget] re-boots per app session.
///
/// Deliberately pure: the caller passes every instant, so the policy is tested
/// with a fake clock and carries no timers of its own.
library;

/// How long a shown render engine may go without a painted frame before the
/// shell is asked to recover it (WP-84 phase 2). Shared by the overlay and the
/// floating button, so both engines are judged by the same threshold.
const Duration kRenderFrameDeadline = Duration(milliseconds: 500);

/// Re-boots one render engine may request per app session (WP-84 phase 2).
/// Never restored: a reset on `ready` caused re-boot cascades.
const int kRenderRebootBudget = 3;

/// Extra time the very first show of a session gets before its frame deadline
/// counts. The render engine is booted lazily at that first show, so its
/// first frame legitimately comes later than any warm show.
const Duration kRenderFirstBootGrace = Duration(seconds: 3);

/// How late a deadline timer may fire before the UI thread is considered
/// blocked. A late fire means the Dart thread itself could not run, so the
/// engine is not judged stuck from that evidence.
const Duration kUiStallTolerance = Duration(milliseconds: 250);

/// What the caller must do after [RenderRecoveryMachine.onDeadline].
enum RenderRecoveryAction {
  /// Nothing to do.
  none,

  /// Re-push the latest state to the engine (stall recovery, first step; only
  /// asked for by machines created with `repushBeforeReboot`). One log entry.
  repush,

  /// Ask the native shell to re-boot the render engine (one log entry).
  reboot,

  /// The session budget is spent. Reported once per session; no further
  /// re-boots are requested.
  budgetExhausted,
}

/// Tracks one show episode at a time and the re-boots spent in this session.
///
/// The budget is intentionally never restored: neither a frame acknowledgement
/// nor a `ready` handshake nor a new show resets it. A reset on `ready` caused
/// re-boot cascades in the field (WP-84 analysis, plan item 4).
class RenderRecoveryMachine {
  RenderRecoveryMachine({
    required this.frameDeadline,
    required this.sessionBudget,
    this.repushBeforeReboot = false,
    this.firstEpisodeGrace = Duration.zero,
  });

  /// Added to the first episode's deadline only (lazy first boot of the
  /// render engine); later episodes use [frameDeadline] alone.
  final Duration firstEpisodeGrace;

  /// How long a shown render engine may go without a painted frame.
  final Duration frameDeadline;

  /// Maximum number of re-boots requested for the whole app session.
  final int sessionBudget;

  /// When set, the first missed deadline of an episode asks for a
  /// [RenderRecoveryAction.repush] instead of a re-boot. A second missed
  /// deadline in the same episode re-boots as usual.
  final bool repushBeforeReboot;

  DateTime? _deadline;
  int _reboots = 0;
  int _episodeStalls = 0;
  bool _exhaustionReported = false;
  bool _firstEpisodeStarted = false;

  /// Re-boots requested so far in this session.
  int get reboots => _reboots;

  /// Whether the current episode has missed a deadline and not yet healed.
  bool get stalled => _episodeStalls > 0;

  /// Whether a deadline is currently running.
  bool get armed => _deadline != null;

  /// The instant the running deadline expires, or null when disarmed.
  DateTime? get deadline => _deadline;

  /// The overlay became visible. Arms the deadline once per episode; a second
  /// show while the deadline runs keeps the original instant.
  void onShown(DateTime now) {
    if (_deadline == null) {
      final grace = _firstEpisodeStarted ? Duration.zero : firstEpisodeGrace;
      _deadline = now.add(frameDeadline + grace);
    }
    _firstEpisodeStarted = true;
  }

  /// A frame was painted: the current episode is healthy.
  void onFrame() {
    _deadline = null;
    _episodeStalls = 0;
  }

  /// The overlay was hidden. A hidden shell is never re-booted.
  void onHidden() {
    _deadline = null;
    _episodeStalls = 0;
  }

  /// Evaluates the running deadline at [now]. Returns [RenderRecoveryAction.none]
  /// while disarmed or before the deadline.
  ///
  /// [lag] is how late the deadline timer fired past its due instant. A lag
  /// above [kUiStallTolerance] means the UI thread was blocked, not the engine:
  /// the deadline restarts from [now] and no budget is spent.
  RenderRecoveryAction onDeadline(
    DateTime now, {
    Duration lag = Duration.zero,
  }) {
    final due = _deadline;
    if (due == null || now.isBefore(due)) return RenderRecoveryAction.none;

    if (lag > kUiStallTolerance) {
      _deadline = now.add(frameDeadline);
      return RenderRecoveryAction.none;
    }

    if (repushBeforeReboot && _episodeStalls == 0) {
      _episodeStalls = 1;
      _deadline = now.add(frameDeadline);
      return RenderRecoveryAction.repush;
    }
    _episodeStalls = 1;

    if (_reboots >= sessionBudget) {
      _deadline = null;
      if (_exhaustionReported) return RenderRecoveryAction.none;
      _exhaustionReported = true;
      return RenderRecoveryAction.budgetExhausted;
    }

    _reboots++;
    // The re-booted engine gets its own full deadline to paint.
    _deadline = now.add(frameDeadline);
    return RenderRecoveryAction.reboot;
  }
}
