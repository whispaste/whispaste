/// The notice bar: what is left of the old toasts.
///
/// A message that belongs to no fixed place (an undo after delete, archive or
/// a Smart Mode edit; a hint at app start; a failure without a page of its
/// own) stands in one bar at the bottom of the content area. The bar takes
/// its own room below the page instead of floating over it, so it never
/// covers a control (#276), and it wears the banner look of the design
/// system, so there is one look for a notice.
///
/// - An undo stays at least [kWpNoticeUndoMinimum], longer while the pointer
///   or the focus is on it; Cmd+Z (macOS) or Ctrl+Z runs it when no text
///   field has the focus.
/// - A hint with a duration closes itself the same way; any other hint, a
///   warning or an error stays until it is closed.
/// - Every notice is read out when it appears; the bar never takes the focus.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/tokens.dart';
import 'onboarding_hold.dart';
import 'wp_banner.dart';
import 'wp_button.dart';
import 'wp_icon_button.dart';

/// What a notice is for; it picks the tone and how long the notice stays.
enum WpNoticeKind {
  /// A done action with a way back. Closes itself.
  undo,

  /// Something to know. Stays until it is closed, or for its
  /// [WpNotice.duration] when it has one.
  hint,

  /// Something that needs attention but did not fail. Stays until it is
  /// closed.
  warning,

  /// Something failed. Stays until it is closed.
  error,
}

/// Shortest time an undo stays on screen.
const kWpNoticeUndoMinimum = Duration(seconds: 10);

/// Time an undo stays after the pointer or the focus has left it.
const kWpNoticeUndoAfterHold = Duration(seconds: 5);

/// Most notices open at once; the oldest that is not an error goes first.
const kWpNoticeLimit = 3;

@immutable
class WpNotice {
  const WpNotice({
    required this.id,
    required this.message,
    this.kind = WpNoticeKind.hint,
    this.nextStep,
    this.actionLabel,
    this.onAction,
    this.actionTestId,
    this.duration,
    this.onDismissed,
  });

  /// Stable name of the situation; `notice-bar-<id>` is its testID.
  final String id;

  /// What happened, in one sentence.
  final String message;
  final WpNoticeKind kind;

  /// What the user can do now; omitted when the message says it already.
  final String? nextStep;

  /// Label of the one action (for an undo: "Undo").
  final String? actionLabel;
  final FutureOr<void> Function()? onAction;

  /// testID of the action; defaults to `notice-bar-action-<id>`.
  final String? actionTestId;

  /// For an undo or a hint: how long it stays, never below
  /// [kWpNoticeUndoMinimum]. A warning or an error ignores it.
  final Duration? duration;

  /// Called once when the notice leaves, however it leaves (time, close,
  /// action, replaced by a newer undo).
  final VoidCallback? onDismissed;

  bool get hasAction => actionLabel != null && onAction != null;

  /// Text read out and shown: cause, then next step.
  String get spoken => nextStep == null ? message : '$message $nextStep';

  WpBannerTone get tone => switch (kind) {
    WpNoticeKind.undo => WpBannerTone.info,
    WpNoticeKind.hint => WpBannerTone.info,
    WpNoticeKind.warning => WpBannerTone.warning,
    WpNoticeKind.error => WpBannerTone.error,
  };
}

/// The open notices, oldest first.
class WpNoticeBarNotifier extends Notifier<List<WpNotice>> {
  final Map<String, Timer> _timers = {};
  final Set<String> _held = {};

  @override
  List<WpNotice> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return const [];
  }

  void show(WpNotice notice) {
    final leaving = <WpNotice>[];
    var next = <WpNotice>[];
    for (final open in state) {
      // One way back at a time: a newer undo replaces the older one, and a
      // notice with the same id replaces its earlier self.
      final replaced =
          open.id == notice.id ||
          (notice.kind == WpNoticeKind.undo && open.kind == WpNoticeKind.undo);
      if (replaced) {
        leaving.add(open);
      } else {
        next.add(open);
      }
    }
    next.add(notice);
    while (next.length > kWpNoticeLimit) {
      // A newer notice never pushes out an open error.
      final index = next.indexWhere((n) => n.kind != WpNoticeKind.error);
      leaving.add(next.removeAt(index < 0 ? 0 : index));
    }
    next = List.unmodifiable(next);
    for (final gone in leaving) {
      _forget(gone.id);
    }
    state = next;
    if (_closesItself(notice)) {
      _schedule(
        notice,
        _max(notice.duration ?? kWpNoticeUndoMinimum, kWpNoticeUndoMinimum),
      );
    }
    for (final gone in leaving) {
      gone.onDismissed?.call();
    }
  }

  /// Closes the notice named [id]; the others stay.
  void dismiss(String id) {
    final notice = _find(id);
    if (notice == null) return;
    _forget(id);
    state = List.unmodifiable([
      for (final other in state)
        if (other.id != id) other,
    ]);
    notice.onDismissed?.call();
  }

  /// Runs the action of the notice named [id] and closes it first, so a
  /// second press (or a shortcut right after the click) cannot run it twice.
  Future<void> runAction(String id) async {
    final notice = _find(id);
    final action = notice?.onAction;
    if (notice == null || action == null) return;
    dismiss(id);
    await action();
  }

  /// Runs the open undo, if any. Returns whether there was one.
  bool runUndo() {
    final undo = state.where((n) => n.kind == WpNoticeKind.undo).lastOrNull;
    if (undo == null || !undo.hasAction) return false;
    unawaited(runAction(undo.id));
    return true;
  }

  /// Pauses the time of [id] while the pointer or the focus is on it.
  void hold(String id) {
    if (!_held.add(id)) return;
    _timers.remove(id)?.cancel();
  }

  /// Resumes the time of [id] with [kWpNoticeUndoAfterHold] left.
  void release(String id) {
    if (!_held.remove(id)) return;
    final notice = _find(id);
    if (notice == null || !_closesItself(notice)) return;
    _schedule(notice, kWpNoticeUndoAfterHold);
  }

  void _schedule(WpNotice notice, Duration after) {
    _timers.remove(notice.id)?.cancel();
    if (_held.contains(notice.id)) return;
    _timers[notice.id] = Timer(after, () {
      _timers.remove(notice.id);
      // Only this very notice; a newer one under the same id keeps its time.
      if (identical(_find(notice.id), notice)) dismiss(notice.id);
    });
  }

  void _forget(String id) {
    _timers.remove(id)?.cancel();
    _held.remove(id);
  }

  static bool _closesItself(WpNotice notice) =>
      notice.kind == WpNoticeKind.undo ||
      (notice.kind == WpNoticeKind.hint && notice.duration != null);

  WpNotice? _find(String id) => state.where((n) => n.id == id).firstOrNull;

  static Duration _max(Duration a, Duration b) =>
      Duration(microseconds: math.max(a.inMicroseconds, b.inMicroseconds));
}

final wpNoticeBarProvider =
    NotifierProvider<WpNoticeBarNotifier, List<WpNotice>>(
      WpNoticeBarNotifier.new,
    );

/// Shows [notice] in the notice bar and reads it out.
///
/// While the onboarding holds messages back ([WpOnboardingHold.holding]) a hint or an
/// error goes to the held messages instead, so it is shown when the
/// onboarding ends; an undo would be stale by then and goes to the bar.
void showWpNotice(BuildContext context, WpNotice notice) {
  if (WpOnboardingHold.holding && notice.kind != WpNoticeKind.undo) {
    WpOnboardingHold.add(
      context,
      message: notice.spoken,
      type: switch (notice.kind) {
        WpNoticeKind.error => WpMessageType.error,
        WpNoticeKind.warning => WpMessageType.warning,
        _ => WpMessageType.info,
      },
      actionLabel: notice.actionLabel,
      actionTestId: notice.actionTestId,
      onAction: notice.onAction == null
          ? null
          : () => unawaited(Future.sync(notice.onAction!)),
      onDismissed: notice.onDismissed,
    );
    return;
  }
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(wpNoticeBarProvider.notifier).show(notice);
  final label = notice.hasAction ? ' ${notice.actionLabel}.' : '';
  announce(
    View.of(context),
    '${notice.spoken}$label',
    Directionality.of(context),
  );
}

/// Whether [platform] uses Cmd (not Ctrl) for undo.
@visibleForTesting
bool wpNoticeUndoUsesMeta(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

/// Whether the focus is in a text field, where Cmd/Ctrl+Z belongs to the
/// text and not to the notice.
bool wpNoticeFocusInText() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorStateOfType<EditableTextState>() != null;
}

/// The bar at the bottom of the content area. Place it once, below the page.
class WpNoticeBar extends ConsumerStatefulWidget {
  const WpNoticeBar({super.key});

  static final Set<_WpNoticeBarState> _mounted = {};

  /// The undo shortcut from outside the widget tree (the macOS menu bar,
  /// whose Cmd+Z never reaches the keyboard handler). Returns whether an undo
  /// ran.
  static bool undoByShortcut() {
    for (final bar in _mounted) {
      if (bar._undoIfFree()) return true;
    }
    return false;
  }

  @override
  ConsumerState<WpNoticeBar> createState() => _WpNoticeBarState();
}

class _WpNoticeBarState extends ConsumerState<WpNoticeBar> {
  @override
  void initState() {
    super.initState();
    WpNoticeBar._mounted.add(this);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WpNoticeBar._mounted.remove(this);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyZ) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    final meta = wpNoticeUndoUsesMeta(defaultTargetPlatform);
    final primary = meta ? keys.isMetaPressed : keys.isControlPressed;
    final other = meta ? keys.isControlPressed : keys.isMetaPressed;
    if (!primary || other || keys.isShiftPressed || keys.isAltPressed) {
      return false;
    }
    return _undoIfFree();
  }

  /// Runs the open undo unless a text field has the focus or a dialog lies
  /// on top of the window (Cmd/Ctrl+Z then belongs there).
  bool _undoIfFree() {
    if (!mounted || wpNoticeFocusInText()) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    return ref.read(wpNoticeBarProvider.notifier).runUndo();
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(wpNoticeBarProvider);
    if (notices.isEmpty) return const SizedBox.shrink();
    return Semantics(
      identifier: 'notice-bar',
      container: true,
      child: Padding(
        key: const ValueKey('notice-bar'),
        padding: const EdgeInsets.fromLTRB(
          WpSpacing.md,
          WpSpacing.sm,
          WpSpacing.md,
          WpSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, notice) in notices.indexed)
              Padding(
                key: ValueKey(notice.id),
                padding: EdgeInsets.only(top: index == 0 ? 0 : WpSpacing.sm),
                child: _NoticeRow(notice: notice),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeRow extends ConsumerStatefulWidget {
  const _NoticeRow({required this.notice});

  final WpNotice notice;

  @override
  ConsumerState<_NoticeRow> createState() => _NoticeRowState();
}

class _NoticeRowState extends ConsumerState<_NoticeRow> {
  /// What had the focus when the notice appeared: the place to go back to
  /// when it is closed from inside, so keyboard and screen reader users are
  /// not thrown to the top of the window (#599).
  FocusNode? _before;
  bool _hovered = false;
  bool _focused = false;
  late final WpNoticeBarNotifier _bar;

  WpNotice get notice => widget.notice;

  @override
  void initState() {
    super.initState();
    _before = FocusManager.instance.primaryFocus;
    _bar = ref.read(wpNoticeBarProvider.notifier);
  }

  void _setHold({bool? hovered, bool? focused}) {
    final wasHeld = _hovered || _focused;
    _hovered = hovered ?? _hovered;
    _focused = focused ?? _focused;
    final isHeld = _hovered || _focused;
    if (isHeld == wasHeld) return;
    if (isHeld) {
      _bar.hold(notice.id);
    } else {
      _bar.release(notice.id);
    }
  }

  void _restoreFocus() {
    final before = _before;
    // The row (and the focused button in it) is gone after this frame; move
    // the focus back to where it was, else on to the next field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary.context != null) return;
      if (before != null && before.context != null && before.canRequestFocus) {
        before.requestFocus();
      } else {
        primary?.nextFocus();
      }
    });
  }

  void _dismiss() {
    _bar.dismiss(notice.id);
    _restoreFocus();
  }

  void _act() {
    unawaited(_bar.runAction(notice.id));
    _restoreFocus();
  }

  @override
  Widget build(BuildContext context) {
    final id = notice.id;
    return MouseRegion(
      onEnter: (_) => _setHold(hovered: true),
      onExit: (_) => _setHold(hovered: false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (has) => _setHold(focused: has),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: WpMotion.durationFor(context, WpMotion.normal),
          curve: WpMotion.defaultCurve,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: Semantics(
            // Read out once by showWpNotice; no live region, or a screen
            // reader would say it twice.
            identifier: 'notice-bar-$id',
            child: WpBanner(
              key: ValueKey('notice-bar-$id'),
              tone: notice.tone,
              message: notice.spoken,
              // A Wrap: with the action and the close cross at a large system
              // text size the row breaks instead of overflowing.
              action: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: WpSpacing.xs,
                runSpacing: WpSpacing.xs,
                children: [
                  if (notice.hasAction)
                    WpButton(
                      testId: notice.actionTestId ?? 'notice-bar-action-$id',
                      label: notice.actionLabel!,
                      variant: WpButtonVariant.ghost,
                      onPressed: _act,
                    ),
                  WpIconButton(
                    key: ValueKey('notice-bar-close-$id'),
                    icon: LucideIcons.x,
                    tooltip: L10n.of(context).actionDismiss,
                    testId: 'notice-bar-close-$id',
                    onPressed: _dismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
