/// Premium toast notification widget — slides in from the bottom-right with
/// themed styling, icon, and smooth animation. Replaces default SnackBars.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/telemetry_service.dart';
import 'wp_button.dart';
import 'wp_focus_ring.dart';
import 'wp_toast_dock.dart';
import 'wp_touch_target.dart';

/// Toast severity levels — controls icon, color, and animation style.
enum WpToastType { success, error, info, warning }

/// Copies [text] to the clipboard, counts a `copy` telemetry event under
/// [category], and shows the standard "Copied to clipboard" toast.
///
/// The shared shape behind every list page's row-level copy action
/// (History, Snippets, …) — pulled out once two independent pages needed
/// the identical four lines, rather than duplicated per page.
void copyToClipboardWithToast({
  required BuildContext context,
  required WidgetRef ref,
  required String text,
  required String category,
}) {
  Clipboard.setData(ClipboardData(text: text));
  ref
      .read(telemetrySessionAggregatorProvider)
      .count(category: category, action: 'copy');
  if (!context.mounted) return;
  WpToast.show(
    context,
    message: L10n.of(context).historyCopiedToClipboard,
    type: WpToastType.success,
    duration: const Duration(seconds: 2),
  );
}

/// Bundled label + callback for an actionable toast.
///
/// Use with [WpToast.show]'s [WpToast.show.action] parameter to render a
/// trailing text-button on the toast card. The PRD-driven actions are
/// things like „Einstellungen öffnen", „Erneut versuchen", „Schließen"
/// and „Diagnose kopieren" — each one points the user at a single concrete
/// next step instead of a generic „Etwas ist schiefgelaufen"-Meldung.
///
/// Equivalent to passing the legacy [WpToast.show.actionLabel] /
/// [WpToast.show.onAction] pair, but bundles the two together so call
/// sites cannot forget one half. Tapping the button fires [onPressed] and
/// dismisses the toast.
class WpToastAction {
  const WpToastAction({
    required this.label,
    required this.onPressed,
    this.testId,
  });

  final String label;
  final VoidCallback onPressed;

  /// Stable id for the action button (`ValueKey`), so a call site with several
  /// toasts can address its own action. Falls back to `toast-action`.
  final String? testId;
}

/// Open popup routes (dialogs, menus) per navigator, kept by
/// [WpToastPopupObserver] and read by [WpToast.show].
final Expando<ValueNotifier<int>> _openPopups = Expando('wpToastOpenPopups');

ValueNotifier<int> _openPopupsOf(NavigatorState navigator) =>
    _openPopups[navigator] ??= ValueNotifier<int>(0);

/// Lets toasts step back behind dialogs.
///
/// A navigator keeps overlay entries that are not its own routes on top of
/// every route, so a toast would cover a dialog opened before or after it,
/// down to the dialog's buttons. With this observer on the navigator, a
/// toast raised from a page hides and lets taps through while any popup
/// route is open; one raised from inside a dialog stays visible above it and
/// steps back only behind dialogs opened later.
/// Register a fresh instance in every `MaterialApp.navigatorObservers`.
class WpToastPopupObserver extends NavigatorObserver {
  void _shift(Route<dynamic>? route, int delta) {
    final nav = navigator;
    if (route is! PopupRoute || nav == null) return;
    final open = _openPopupsOf(nav);
    // Navigator callbacks can run during a build; notify after it.
    scheduleMicrotask(
      () => open.value = (open.value + delta).clamp(0, 1 << 20),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _shift(route, 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _shift(route, -1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _shift(route, -1);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _shift(oldRoute, -1);
    _shift(newRoute, 1);
  }
}

/// Show a premium toast notification.
///
/// Usage:
/// ```dart
/// WpToast.show(context, message: 'Copied!', type: WpToastType.success);
/// ```
class WpToast {
  WpToast._();

  static final _log = AppLogger('Toast');

  /// Toasts on screen now, oldest first (UIA-SHL-10).
  static final List<_ActiveToast> _active = [];

  /// Keeps the stack short. At large text size only one toast fits beside the
  /// stacked layout (UX-050), so a new toast replaces the current one.
  /// Otherwise two may show. When the stack is full, a non-error toast
  /// leaves first, so an error is not pushed out by a success. An error
  /// never waits behind a success. Returns false when the new toast must be
  /// dropped to keep an error on screen.
  static bool _makeRoomFor(BuildContext context, WpToastType type) {
    final maxVisible = _ToastCard._isLargeText(context) ? 1 : 2;
    while (_active.length >= maxVisible) {
      final nonError = _active.where((t) => t.type != WpToastType.error);
      if (nonError.isNotEmpty) {
        nonError.first.dismiss();
      } else if (type == WpToastType.error) {
        _active.first.dismiss();
      } else {
        return false;
      }
    }
    return true;
  }

  /// Show a toast.
  ///
  /// Pass [action] (preferred) or the legacy [actionLabel]+[onAction] pair
  /// to render an action button on the toast card. When both are passed,
  /// [action] wins. The action button fires its callback and then
  /// dismisses the toast.
  static void show(
    BuildContext context, {
    required String message,
    WpToastType type = WpToastType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    WpToastAction? action,
    Widget? body,
    String? messageTestId,
    String? testId,
    VoidCallback? onDismissed,
  }) {
    // The bundled [WpToastAction] is the canonical surface — fall back to
    // the legacy split pair so older call sites keep working unchanged.
    final String? resolvedLabel = action?.label ?? actionLabel;
    final VoidCallback? resolvedOnAction = action?.onPressed ?? onAction;
    final String? resolvedTestId = action?.testId;
    // Route toast messages through the logging pipeline so they appear
    // in the `flutter run` terminal in debug mode.
    //
    // Error-toasts go in at warning level so they land as Sentry breadcrumbs
    // (context for any later crash), not as standalone Sentry issues — the
    // overwhelming majority are user-config noise (mute mic, blocked
    // permission), not bugs. The underlying failure that triggered the toast
    // should emit its own captureException at the source if it is actually
    // a bug.
    switch (type) {
      case WpToastType.error:
        _log.warning('TOAST: $message');
      case WpToastType.warning:
        _log.warning('TOAST: $message');
      case WpToastType.success:
        _log.info('TOAST: $message');
      case WpToastType.info:
        _log.info('TOAST: $message');
    }

    if (!_makeRoomFor(context, type)) return;

    // Screen readers get no visual cue that a toast appeared, so announce it
    // explicitly — the toast card itself is only a visual overlay, not a
    // focusable widget a screen reader would land on.
    announce(View.of(context), message, Directionality.of(context));

    final overlay = Overlay.of(context);
    final navigator = Navigator.maybeOf(context);
    final openPopups = navigator == null ? null : _openPopupsOf(navigator);
    // A toast belongs to the surface that raised it: from a page it steps
    // back behind any dialog, from inside a dialog only behind later ones.
    final raisedInPopup = ModalRoute.of(context) is PopupRoute;
    final popupsAtShow = raisedInPopup ? (openPopups?.value ?? 0) : 0;
    late final OverlayEntry entry;
    late final AnimationController controller;
    late final _ToastTimer timer;
    late final _ActiveToast handle;
    var dismissed = false;
    var removed = false;

    // OverlayEntry.remove() also works for an entry that is inserted but not
    // built yet, which `mounted` reports as false. Eviction (UIA-SHL-10) can
    // dismiss a toast in the frame it was raised, so do not wait for a mount.
    void removeEntry() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    void dismiss() {
      _active.remove(handle);
      if (dismissed) return;
      dismissed = true;
      timer.cancel();
      onDismissed?.call();
      try {
        controller.reverse().then((_) {
          try {
            removeEntry();
          } catch (e) {
            _log.debug('Toast overlay entry remove failed (non-fatal): $e');
          }
          try {
            controller.dispose();
          } catch (e) {
            _log.debug(
              'Toast animation controller dispose failed (non-fatal): $e',
            );
          }
        });
      } catch (e) {
        // Controller already disposed or in bad state — force cleanup.
        _log.debug('Toast reverse animation failed, forcing cleanup: $e');
        try {
          removeEntry();
        } catch (e2) {
          _log.debug(
            'Toast force-cleanup entry remove failed (non-fatal): $e2',
          );
        }
      }
    }

    controller = AnimationController(
      vsync: overlay,
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      reverseDuration: WpMotion.durationFor(context, WpMotion.normal),
    );

    // The timer must not outlive the overlay entry: if the host tree goes
    // away before the toast expires (onboarding torn down mid-toast, tests),
    // the pending expiry would fire into a dead entry. The lifetime guard
    // cancels it when the entry's widgets are disposed.
    void disposeTimer() {
      timer.cancel();
      _active.remove(handle);
    }

    entry = OverlayEntry(
      builder: (context) {
        final toast = _WpToastOverlay(
          message: message,
          type: type,
          animation: controller,
          actionLabel: resolvedLabel,
          onAction: resolvedOnAction,
          actionTestId: resolvedTestId,
          onDismiss: dismiss,
          onHover: (value) => timer.hover(value),
          onFocus: (value) => timer.focus(value),
          body: body,
          messageTestId: messageTestId,
          testId: testId,
        );
        if (openPopups == null) {
          return _ToastLifetime(onDispose: disposeTimer, child: toast);
        }
        return _ToastLifetime(
          onDispose: disposeTimer,
          child: ValueListenableBuilder<int>(
            valueListenable: openPopups,
            child: toast,
            // A dialog opened over the toast's surface: step back until it
            // closes. The auto-dismiss timer keeps running.
            builder: (context, open, child) =>
                open > popupsAtShow ? const SizedBox.shrink() : child!,
          ),
        );
      },
    );

    timer = _ToastTimer(
      onExpire: dismiss,
      duration: duration,
      actionable: resolvedOnAction != null,
    );

    handle = _ActiveToast(type, dismiss);
    _active.add(handle);
    overlay.insert(entry);
    controller.forward();
    timer.start();
  }
}

/// Runs [onDispose] when the toast's widgets leave the tree, so its expiry
/// timer is cancelled together with the entry instead of firing later.
class _ToastLifetime extends StatefulWidget {
  const _ToastLifetime({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_ToastLifetime> createState() => _ToastLifetimeState();
}

class _ToastLifetimeState extends State<_ToastLifetime> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

/// One toast on screen, with the way to take it down early (UIA-SHL-10).
class _ActiveToast {
  const _ActiveToast(this.type, this.dismiss);

  final WpToastType type;
  final void Function() dismiss;
}

/// Shortest life of a toast with an action button.
const Duration _actionableMinimum = Duration(seconds: 10);

/// Shortest time a toast stays after the pointer or focus left it, so a
/// hold that ended late does not dismiss it at once.
const Duration _resumeFloor = Duration(seconds: 5);

/// Auto-dismiss timer that holds while the pointer or keyboard focus is on
/// the toast and resumes with the time that was left (WCAG 2.2.1).
class _ToastTimer {
  /// An actionable toast stays long enough to be read and used (WCAG 2.2.1).
  _ToastTimer({
    required this.onExpire,
    required Duration duration,
    required bool actionable,
  }) : _remaining = actionable && duration < _actionableMinimum
           ? _actionableMinimum
           : duration;

  final VoidCallback onExpire;
  Duration _remaining;
  final Stopwatch _running = Stopwatch();
  Timer? _timer;
  bool _held = false;
  bool _hovered = false;
  bool _focused = false;

  void start() => _arm();

  void hover(bool value) {
    _hovered = value;
    hold(_hovered || _focused);
  }

  void focus(bool value) {
    _focused = value;
    hold(_hovered || _focused);
  }

  void hold(bool held) {
    if (held == _held) return;
    _held = held;
    if (held) {
      _disarm();
    } else {
      if (_remaining < _resumeFloor) _remaining = _resumeFloor;
      _arm();
    }
  }

  void cancel() => _disarm();

  void _arm() {
    if (_held || _timer != null) return;
    _running
      ..reset()
      ..start();
    _timer = Timer(_remaining, onExpire);
  }

  void _disarm() {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    _running.stop();
    _remaining -= _running.elapsed;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
  }
}

class _WpToastOverlay extends StatelessWidget {
  const _WpToastOverlay({
    required this.message,
    required this.type,
    required this.animation,
    required this.onDismiss,
    required this.onHover,
    required this.onFocus,
    this.actionLabel,
    this.onAction,
    this.actionTestId,
    this.body,
    this.messageTestId,
    this.testId,
  });

  final String message;
  final WpToastType type;
  final Animation<double> animation;
  final String? messageTestId;
  final VoidCallback onDismiss;

  /// Pointer over the toast (true/false); holds the auto-dismiss timer.
  final ValueChanged<bool> onHover;

  /// Keyboard focus inside the toast (true/false); holds the timer too.
  final ValueChanged<bool> onFocus;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionTestId;

  /// Replaces the icon and message line; see [WpToast.show].
  final Widget? body;

  /// Stable id of the whole card (`ValueKey`), for tests and journeys.
  final String? testId;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      right: WpSpacing.lg,
      left: null,
      // Lifts the card above a bottom action row (see WpToastDockReserve).
      child: ValueListenableBuilder<double>(
        valueListenable: WpToastDock.reserved,
        builder: (context, reserved, child) => Padding(
          padding: EdgeInsets.only(bottom: WpToastDock.bottomFor(reserved)),
          child: child,
        ),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero)
              .animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              ),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: MouseRegion(
              onEnter: (_) => onHover(true),
              onExit: (_) => onHover(false),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: onFocus,
                child: _ToastCard(
                  message: message,
                  type: type,
                  onDismiss: onDismiss,
                  actionLabel: actionLabel,
                  onAction: onAction,
                  actionTestId: actionTestId,
                  body: body,
                  messageTestId: messageTestId,
                  testId: testId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.message,
    required this.type,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    this.actionTestId,
    this.body,
    this.messageTestId,
    this.testId,
  });

  final String message;
  final WpToastType type;
  final VoidCallback onDismiss;
  final String? messageTestId;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionTestId;
  final Widget? body;

  /// Stable id of the whole card (`ValueKey`), for tests and journeys.
  final String? testId;

  /// From this text scale on the action and close buttons move under the
  /// message instead of beside it (UX-050). Beside it they leave the message a
  /// narrow column: at 2.0 the hotkey-fallback text became eight short lines,
  /// and the active combination at its end was lost.
  static bool _isLargeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(100) >= 130;

  /// Line budget for the message, grown in step with the system text size.
  ///
  /// The card is capped at 400 px wide, so a long message is wrapped rather
  /// than widened, and the cap exists to stop a toast from turning into a
  /// wall of text. The budget scales with the text scaler, so raising the text
  /// size does not cut off the tail of the message. The upper clamp keeps a
  /// pathologically long message (an interpolated exception string) from
  /// filling the screen. With the stacked layout (see [_isLargeText]) the
  /// message has the full card width, so the clamp is only reached by strings
  /// far longer than any the app ships.
  ///
  /// Screen-reader users were never affected: the `Semantics(label:)` below and
  /// `sendAnnouncement()` in [WpToast.show] carry the full string.
  /// Whether [message] needs more than two lines at the stacked layout's full
  /// width. Beside an action and the close button the message column is about
  /// half as wide, so such a message would run past the four-line budget and
  /// lose its end (XP-6-05: the Linux paste hint stopped at "braucht einm…").
  static bool _crowdedBesideAction(
    BuildContext context,
    String message,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: message, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout(maxWidth: _stackedMessageWidth);
    final crowded = painter.didExceedMaxLines;
    painter.dispose();
    return crowded;
  }

  /// Whether [label] on the action button leaves the message less than
  /// [_minMessageBesideAction] in the one-line layout. Beside a long label
  /// ("Back to the speech model") the fixed parts alone were wider than the
  /// card, and the row overflowed even with a short message (UIA-RT-01).
  static bool _actionCrowdsMessage(
    BuildContext context,
    String label,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style?.copyWith(
          fontSize: WpTypography.small,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final labelWidth = painter.width;
    painter.dispose();
    // Accent line, icon, the gap before the action, the ghost button's own
    // padding, the gap before the close button and its 48 px tap area.
    const fixed =
        (3 + WpSpacing.sm) +
        (18 + WpSpacing.sm) +
        WpSpacing.sm +
        2 * WpSpacing.xs +
        WpSpacing.xs +
        WpLayout.minTouchTarget;
    return 426 - 2 * WpSpacing.md - fixed - labelWidth <
        _minMessageBesideAction;
  }

  static const double _minMessageBesideAction = 120;

  /// Message width in the stacked layout: the 426 px card minus its padding,
  /// the accent line and the icon (each with its gap).
  static const double _stackedMessageWidth =
      426 - 2 * WpSpacing.md - (3 + WpSpacing.sm) - (18 + WpSpacing.sm);

  static int _maxLines(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    return (4 * scale).ceil().clamp(4, 8);
  }

  (IconData, Color) _iconAndColor() {
    return switch (type) {
      WpToastType.success => (LucideIcons.circleCheck, WpColors.success),
      WpToastType.error => (LucideIcons.circleAlert, WpColors.error),
      WpToastType.warning => (LucideIcons.triangleAlert, WpColors.warning),
      WpToastType.info => (LucideIcons.info, WpColors.accent),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconAndColor();
    // Card material (Ticket 08). Pre-composited rather than translucent: a
    // toast floats over whatever the user happens to have on screen, so the
    // ambient it would let through is unknowable. The rim is the tinted card
    // edge — a neutral `borderDefault` hairline over a chromatic fill is the
    // "reads grey" failure the frost exists to fix.
    final surfaceBg = WpColors.floatingSurface;
    final textPrimary = WpColors.textPrimary;
    final borderColor = WpColors.cardEdgeHighlight;

    // The card row has two layouts: one line (accent, icon, message, buttons)
    // and a stacked one with the buttons below the text. The stacked layout is
    // used when a [body] is given (it is never squeezed by the buttons) and at
    // large text sizes (the message keeps its width, see [_isLargeText]).
    final accentLine = <Widget>[
      // Accent line
      Container(
        width: 3,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: WpSpacing.sm),
    ];
    // labelMedium = Type/label role (13 / 500). Compact line-height (1.3 vs
    // theme's 1.4) preserved for the tight toast card layout.
    final messageStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: textPrimary, height: 1.3);
    final hasAction = actionLabel != null && onAction != null;
    final iconAndMessage = <Widget>[
      // Icon
      Icon(icon, size: WpIconSize.smMd, color: color),
      const SizedBox(width: WpSpacing.sm),
      // Message
      Flexible(
        child: ExcludeSemantics(
          child: Text(
            message,
            key: ValueKey<String>(messageTestId ?? 'toast-message'),
            style: messageStyle,
            maxLines: _maxLines(context),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];
    void fireAction() {
      onAction?.call();
      onDismiss();
    }

    final trailing = <Widget>[
      // Action button (optional)
      if (hasAction) ...[
        const SizedBox(width: WpSpacing.sm),
        // The status colour stays on the icon and the accent line;
        // the action reads as an action, in the one colour every
        // other action in the app uses.
        // The dense label is 32 px high; WpTouchTarget widens the tap area to
        // the 48 px rule, as it does for the close button. The card grows by
        // the same amount, so the message keeps its width.
        Semantics(
          button: true,
          label: actionLabel!,
          child: WpTouchTarget(
            onTap: fireAction,
            child: WpButton(
              key: ValueKey(actionTestId ?? 'toast-action'),
              label: actionLabel!,
              variant: WpButtonVariant.ghost,
              size: WpButtonSize.dense,
              onPressed: fireAction,
            ),
          ),
        ),
      ],
      const SizedBox(width: WpSpacing.xs),
      // Close button
      _ToastCloseButton(
        label: L10n.of(context).actionDismiss,
        onPressed: onDismiss,
      ),
    ];

    // A message is never cut off (UX-050): at large text, and when a long
    // message would be squeezed by an action button, the trailing buttons move
    // under it, and the card grows with the text.
    final stacked =
        body != null ||
        _isLargeText(context) ||
        (hasAction &&
            (_crowdedBesideAction(context, message, messageStyle) ||
                _actionCrowdsMessage(context, actionLabel!, messageStyle)));

    return Semantics(
      key: switch (testId) {
        final id? => ValueKey<String>(id),
        null => null,
      },
      // Not a liveRegion: WpToast.show() already calls sendAnnouncement()
      // explicitly once, precisely when the toast is inserted — combining
      // that with liveRegion risks a double announcement (liveRegion fires
      // its own announcement on semantics-tree changes). The label here is
      // for a screen-reader user who navigates directly to the toast — the
      // rendered message below is excluded so it is not stated twice, and
      // because that `Text` is clipped to `_maxLines` with an ellipsis while
      // this label carries the message whole.
      //
      // Not `MergeSemantics`: a toast can hold an action button and always
      // holds a close button, and merging would swallow both.
      label: message,
      container: true,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          // 400 px of message room, plus the 26 px the 48 px close tap area adds
          // over its 22 px glyph box, so the message wraps exactly as before.
          constraints: const BoxConstraints(maxWidth: 426, minWidth: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: surfaceBg,
              borderRadius: BorderRadius.circular(WpRadius.md),
              border: Border.all(color: borderColor),
              // Exactly one shadow, the overlay token. The toast really does
              // float, so it earns a shadow; it used to carry a second one
              // tinted with the severity colour, which is a coloured light effect (Ticket 08).
              boxShadow: WpShadows.elevated,
            ),
            child: stacked
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ...accentLine,
                          ...(body == null
                              ? iconAndMessage
                              : <Widget>[
                                  Flexible(
                                    child: ExcludeSemantics(child: body!),
                                  ),
                                ]),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: trailing,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [...accentLine, ...iconAndMessage, ...trailing],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Close control on the toast card: a labelled button with the shared focus
/// ring, so keyboard users can reach and see it.
class _ToastCloseButton extends StatefulWidget {
  const _ToastCloseButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_ToastCloseButton> createState() => _ToastCloseButtonState();
}

class _ToastCloseButtonState extends State<_ToastCloseButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpToastClose');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        // A 14 px glyph alone is a 22 px target. WpTouchTarget widens the tap
        // area to the 48 px rule; the card grows by the same 26 px, so the
        // message keeps its width (see the card's maxWidth).
        child: WpTouchTarget(
          onTap: widget.onPressed,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.full,
            child: InkWell(
              onTap: widget.onPressed,
              focusNode: _focusNode,
              borderRadius: BorderRadius.circular(WpRadius.full),
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(WpSpacing.xxs),
                child: Icon(
                  LucideIcons.x,
                  size: WpIconSize.xs,
                  color: WpColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
