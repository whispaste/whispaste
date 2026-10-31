/// The WhisPaste dialog: one card, one footer, four shapes.
///
/// * Confirm — [showWpConfirmDialog]: Cancel beside a confirming action,
///   `destructive` for deletes, resets and overwrites.
/// * Choice — [showWpChoiceDialog]: named answers, one recommended.
/// * Info / content — [showWpDialog]: any body, one closing action or a few.
/// * Form — [showWpFormDialog] + [WpFormDialogShell]: fields with state.
///
/// Every shape lays out its actions through the same footer (see
/// [WpDialogActionRole]); no dialog builds its own buttons.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/floating_surface.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';
import 'wp_hero_button.dart';
import 'wp_toast_dock.dart';

/// How much room a dialog card asks for.
///
/// A *named* axis rather than a free `width` parameter, for the reason
/// `WpSearchField`'s library docs spell out at length: a free number produces
/// N accidents instead of N decisions, and dialogs are the last place that can
/// afford to drift. Two values is the whole vocabulary — add a third only when
/// a case genuinely cannot be answered by either.
enum WpDialogSize {
  /// The default: a column of short form fields, a confirmation, a message.
  standard,

  /// Twice the measure, for a dialog whose *content is a document* — text the
  /// user writes and re-reads rather than fills in. Currently the snippet
  /// editor, whose body holds multi-paragraph prompt templates and which read
  /// as a slot rather than an editor at [standard].
  wide,
}

/// Width every WhisPaste dialog card shares — content dialogs, confirmations
/// and form dialogs alike. Clamped against the viewport in [_WpDialogSurface].
const double _kDialogWidth = 420;

/// Width of a [WpDialogSize.wide] card. ~85 characters at the 13 dp form
/// metrics, i.e. the same prose measure History caps its transcript at.
const double _kWideDialogWidth = 760;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// What an action in a dialog's footer is to the person deciding. The role,
/// not the call site, decides look, order and keyboard behaviour, so every
/// dialog in the app answers the same way (`lib/COMPONENTS.md`, "Dialogs").
enum WpDialogActionRole {
  /// The answer the dialog recommends. Filled; Enter triggers it while no
  /// control in the dialog holds focus. At most one main action per dialog.
  primary,

  /// An answer that must be given on purpose: agreeing to terms, sharing
  /// data, sending text into another app. Looks like [primary], but Enter
  /// never triggers it — only a click, or Enter/Space on the focused button —
  /// so a key pressed before the dialog was read cannot give it.
  deliberate,

  /// The dialog's answer when that answer deletes, resets or overwrites.
  /// Filled red; Enter never triggers it.
  destructive,

  /// A real other answer. Outlined grey, so the main action stays the one
  /// coloured choice.
  alternative,

  /// Leaving without a change. Beside the main action it is outlined grey, so
  /// both buttons have the same weight of box; in a stack it is a quiet label
  /// at the bottom.
  cancel,

  /// A destructive way out (quit). A quiet red label at the bottom of a
  /// stack, never beside the main action.
  destructiveExit,
}

/// How a dialog's main action looks.
enum WpDialogCta {
  /// Filled cyan [WpButton] — every dialog by default.
  standard,

  /// The amber [WpHeroButton], for a dialog raised over a surface whose own
  /// main action is that button (the first-run setup), so the dialog
  /// continues the surface's language instead of switching colour.
  hero,
}

/// One action in a dialog footer. Without [onPressed] it closes the dialog
/// with [value]; with it, the callback decides (validation, saving).
class WpDialogAction<T> {
  const WpDialogAction({
    required this.label,
    required this.testId,
    this.role = WpDialogActionRole.alternative,
    this.value,
    this.onPressed,
    this.enabled = true,
    this.enabledWhen,
    this.isLoading = false,
  });

  final String label;

  /// Stable id (`<screen>-<element>`), also the button's key.
  final String testId;
  final WpDialogActionRole role;
  final T? value;
  final VoidCallback? onPressed;

  /// Availability as of this build — for footers rebuilt with their form's
  /// state ([WpFormDialogShell]).
  final bool enabled;

  /// Live availability, for a footer that is not rebuilt with the state it
  /// waits on (a [showWpDialog] whose body picks a value). Overrides
  /// [enabled] when set.
  final ValueListenable<bool>? enabledWhen;
  final bool isLoading;

  bool get _isMain =>
      role == WpDialogActionRole.primary ||
      role == WpDialogActionRole.deliberate ||
      role == WpDialogActionRole.destructive;
}

/// Shows a WhisPaste dialog: [title], a scrolling [content] and the standard
/// footer built from [actions] (see [WpDialogActionRole]). Esc and a tap
/// outside return `null`.
///
/// Set [dismissible] to `false` for a dialog the user must not walk away from
/// (a destructive operation in flight, for instance): the barrier stops
/// dismissing on tap and a `PopScope` blocks the back/Esc route pop. Such a
/// dialog is responsible for popping itself once its work is done.
///
/// [useRootNavigator] pushes onto the root navigator — needed when the dialog
/// must outlive a nested navigator (e.g. a settings page being torn down by
/// the very operation the dialog reports on).
///
/// [transition] is the open and close animation; pass a shorter token for a
/// dialog that should appear at once. Reduce motion still makes it instant.
Future<T?> showWpDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<WpDialogAction<T>> actions = const [],
  WpDialogCta cta = WpDialogCta.standard,
  bool dismissible = true,
  bool useRootNavigator = false,
  Duration transition = WpMotion.smooth,
  WpDialogSize size = WpDialogSize.standard,

  /// Key of the dialog card. It sits above the scrolling body, so a test can
  /// look for the scroll view beneath it.
  Key? cardKey,
}) {
  return _showWpRoute<T>(
    context: context,
    dismissible: dismissible,
    useRootNavigator: useRootNavigator,
    transition: transition,
    builder: (ctx, animation) => _WpDialogContainer(
      animation: animation,
      title: title,
      content: content,
      actions: actions,
      cta: cta,
      size: size,
      cardKey: cardKey,
    ),
  );
}

/// Asks to confirm an action: [message], then Cancel beside the confirming
/// button. Returns `true` only on an explicit confirm.
///
/// [destructive] marks an action that deletes, resets or overwrites: the
/// confirming button turns red and Enter no longer triggers it, so a key
/// still held while the dialog opens cannot destroy anything. [message]
/// states what is lost, so callers pass counts and sizes.
///
/// [deliberate] marks an answer that must be given on purpose (consent,
/// sharing data): the button looks like an ordinary confirm, but Enter alone
/// does not give it.
Future<bool> showWpConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
  bool deliberate = false,
  WpDialogCta cta = WpDialogCta.standard,
}) async {
  assert(
    !(destructive && deliberate),
    'Pick one: destructive already ignores Enter.',
  );
  final result = await showWpDialog<bool>(
    context: context,
    title: title,
    content: Text(message),
    cta: cta,
    actions: [
      WpDialogAction(
        label: cancelLabel,
        testId: 'confirm-dialog-cancel',
        role: WpDialogActionRole.cancel,
        value: false,
      ),
      WpDialogAction(
        label: confirmLabel,
        testId: 'confirm-dialog-confirm',
        role: destructive
            ? WpDialogActionRole.destructive
            : deliberate
            ? WpDialogActionRole.deliberate
            : WpDialogActionRole.primary,
        value: true,
      ),
    ],
  );
  return result ?? false;
}

/// Asks for a decision between named answers. Exactly one is the
/// [WpDialogActionRole.primary] recommendation; the footer orders them by
/// role whatever order [choices] come in. Esc and a tap outside return
/// [dismissValue].
Future<T> showWpChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required String body,
  required List<WpDialogAction<T>> choices,
  required T dismissValue,
  WpDialogCta cta = WpDialogCta.standard,
  Key? cardKey,
}) async {
  assert(
    choices.where((c) => c.role == WpDialogActionRole.primary).length == 1,
    'A choice dialog recommends exactly one answer.',
  );
  final answer = await showWpDialog<T>(
    context: context,
    title: title,
    content: Text(body),
    actions: choices,
    cta: cta,
    cardKey: cardKey,
  );
  return answer ?? dismissValue;
}

/// Keeps a form dialog open while it holds typed input that is not saved yet:
/// a tap outside, Esc or system back asks first (UIA-CMP-03). Dismissing
/// without typed input closes at once.
class WpUnsavedInputGuard extends StatelessWidget {
  const WpUnsavedInputGuard({
    super.key,
    required this.dirty,
    required this.child,
  });

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!dirty) {
          Navigator.of(context).pop();
          return;
        }
        final l10n = L10n.of(context);
        final discard = await showWpConfirmDialog(
          context: context,
          title: l10n.unsavedInputTitle,
          message: l10n.unsavedInputMessage,
          confirmLabel: l10n.unsavedInputDiscard,
          cancelLabel: l10n.actionCancel,
          destructive: true,
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}

/// Shows a form dialog with the WhisPaste glass barrier.
///
/// Use for dialogs that hold state of their own — form fields, a selection
/// the footer depends on. The [builder] returns a [WpFormDialogShell] and
/// receives the [Animation] it needs.
Future<T?> showWpFormDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, Animation<double> animation)
  builder,
}) => _showWpRoute<T>(context: context, builder: builder);

/// The one route every dialog opens on: frosted barrier, fade and slide.
Future<T?> _showWpRoute<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, Animation<double> animation)
  builder,
  bool dismissible = true,
  bool useRootNavigator = false,
  Duration transition = WpMotion.smooth,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // painted by the transition builder
    transitionDuration: WpMotion.durationFor(context, transition),
    useRootNavigator: useRootNavigator,
    pageBuilder: (_, a2, a3) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return PopScope(
        canPop: dismissible,
        child: _WpDialogBarrier(
          animation: animation,
          child: builder(ctx, animation),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------

class _WpDialogBarrier extends StatelessWidget {
  const _WpDialogBarrier({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(parent: animation, curve: Curves.easeOut);

    return FadeTransition(
      opacity: opacity,
      child: Stack(
        children: [
          // Barrier layer
          // Paint only: taps fall through to the route's modal barrier,
          // which is what closes a dismissible dialog on a tap outside.
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: wpDialogBarrierColor()),
            ),
          ),
          // Dialog
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog surface — the one card every WhisPaste dialog is built on
// ---------------------------------------------------------------------------

/// The card behind every dialog in the app: pre-composited frost
/// ([WpColors.floatingSurface]), [WpRadius.borderLg], the tinted
/// [WpColors.cardEdgeHighlight] rim, [WpShadows.elevated] — plus the two
/// behaviours every dialog wants and none should re-derive:
///
/// * It grows softly. An [AnimatedContainer] alone cannot animate an intrinsic
///   height change, so the body sits in an [AnimatedSize] — a dialog whose
///   content changes (a form gaining a row, a progress label rewrapping)
///   eases into its new height instead of jumping.
/// * It never runs off screen. Width and height are clamped to the viewport,
///   which is what keeps dialogs whole at large system text sizes; the
///   scrollable body lives in [child] via a [Flexible].
class _WpDialogSurface extends StatelessWidget {
  const _WpDialogSurface({
    required this.animation,
    required this.child,
    this.size = WpDialogSize.standard,
    this.cardKey,
  });

  final Animation<double> animation;
  final Widget child;
  final WpDialogSize size;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final viewport = MediaQuery.sizeOf(context);
    // Leave a gutter so the card never touches the window edge, and never
    // demand more than the window offers.
    final requested = switch (size) {
      WpDialogSize.standard => _kDialogWidth,
      WpDialogSize.wide => _kWideDialogWidth,
    };
    final width = math.max(
      0.0,
      math.min(requested, viewport.width - WpSpacing.xl * 2),
    );
    final maxHeight = math.max(0.0, viewport.height - WpSpacing.xl * 2);

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            key: cardKey,
            duration: WpMotion.durationFor(context, WpMotion.fast),
            curve: WpMotion.defaultCurve,
            width: width,
            constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
            padding: const EdgeInsets.all(WpSpacing.lg),
            // Pre-composited card material: a dialog floats over a
            // 92 %-opaque barrier, so a translucent frost would tint the
            // barrier rather than the ambient and vanish.
            decoration: WpFloatingSurface.decoration,
            child: WpAnimatedSize(
              duration: WpMotion.durationFor(context, WpMotion.fast),
              curve: WpMotion.defaultCurve,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog container — card with slide-up + fade animation
// ---------------------------------------------------------------------------

class _WpDialogContainer extends StatelessWidget {
  const _WpDialogContainer({
    required this.animation,
    required this.title,
    required this.content,
    required this.actions,
    required this.cta,
    required this.size,
    this.cardKey,
  });

  final Animation<double> animation;
  final String title;
  final Widget content;
  final List<WpDialogAction<Object?>> actions;
  final WpDialogCta cta;
  final WpDialogSize size;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _WpDialogSurface(
      animation: animation,
      size: size,
      cardKey: cardKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: WpSpacing.sm),

          // Body — scrolls rather than overflowing once the card hits the
          // viewport ceiling (long content, large system text size). The
          // actions below stay outside it, so they remain visible.
          Flexible(
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyLarge,
              child: _WpDialogScrollBody(child: content),
            ),
          ),

          if (actions.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.lg),
            WpToastDockReserve(
              animation: animation,
              child: _WpDialogActionBar(actions: actions, cta: cta),
            ),
          ],
        ],
      ),
    );
  }
}

/// Scrollable dialog body with a visible scroll indicator. Without the bar a
/// user cannot tell that content lies below the fold (UX-107). The bar paints
/// only when there is something to scroll, so a short body looks unchanged.
class _WpDialogScrollBody extends StatefulWidget {
  const _WpDialogScrollBody({required this.child});

  final Widget child;

  @override
  State<_WpDialogScrollBody> createState() => _WpDialogScrollBodyState();
}

class _WpDialogScrollBodyState extends State<_WpDialogScrollBody> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(controller: _controller, child: widget.child),
  );
}

// ---------------------------------------------------------------------------
// Form dialog shell — the body every form dialog wears
// ---------------------------------------------------------------------------

/// Standard body for a [showWpFormDialog] whose content is a form.
///
/// Carries the same card as every other dialog plus the two things a form
/// dialog needs on top of a plain one: an explanatory [subtitle] under the
/// title (a form asks for input, so it owes the user a sentence on what the
/// input does) and the soft growth of [_WpDialogSurface] for fields and rows
/// that appear as the user types.
class WpFormDialogShell extends StatelessWidget {
  const WpFormDialogShell({
    super.key,
    required this.animation,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.actions,
    this.size = WpDialogSize.standard,
    this.cta = WpDialogCta.standard,
  });

  final Animation<double> animation;
  final String title;

  /// How the main action looks — see [WpDialogCta].
  final WpDialogCta cta;

  /// How much room the card asks for — see [WpDialogSize].
  final WpDialogSize size;

  /// One sentence on what this form does. Required on purpose — the Snippets
  /// dialog shipped without one and read noticeably barer than its twin.
  final String subtitle;

  /// The form fields, laid out in a column.
  final List<Widget> fields;

  /// The footer, laid out by role like every dialog's (see
  /// [WpDialogActionRole]). Rebuilt with the shell, so availability may
  /// follow the form's state.
  final List<WpDialogAction<Object?>> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _WpDialogSurface(
      animation: animation,
      size: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: WpColors.textMuted,
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: fields,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          WpToastDockReserve(
            animation: animation,
            child: _WpDialogActionBar(actions: actions, cta: cta),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action bar — the one footer every dialog wears
// ---------------------------------------------------------------------------

/// Lays out a dialog's actions by role:
///
/// * A main action with Cancel sits in one row, Cancel left, both buttons the
///   same width — two boxes of equal weight, the colour alone says which one
///   is recommended. When either label would not fit half the card (long
///   translation, large text) the pair stacks instead.
/// * Every other set stacks at full width: the main action on top,
///   alternatives below, exits as quiet labels at the bottom.
/// * A lone action is a single button at the end of the row.
///
/// Nothing in the footer takes focus up front: no ring greets a mouse user and
/// a stray Enter cannot pick an answer it did not see. The bar holds the
/// dialog's focus instead, so Enter triggers a [WpDialogActionRole.primary]
/// main action (never a destructive one) until Tab reaches a button.
class _WpDialogActionBar extends StatefulWidget {
  const _WpDialogActionBar({required this.actions, required this.cta});

  final List<WpDialogAction<Object?>> actions;
  final WpDialogCta cta;

  @override
  State<_WpDialogActionBar> createState() => _WpDialogActionBarState();
}

class _WpDialogActionBarState extends State<_WpDialogActionBar> {
  final _focusNode = FocusNode(debugLabel: 'dialog', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    assert(
      widget.actions.where((a) => a._isMain).length <= 1,
      'A dialog has at most one main action.',
    );
    // After the first frame's autofocus requests have been applied (they
    // settle in a microtask queued during build): a field or list that asked
    // for focus keeps it, otherwise the dialog takes it here.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(() {
        if (!mounted) return;
        // Focus still outside the dialog (the trigger on the page below, the
        // route's bare scope) means nothing in it asked for focus.
        final scope = FocusScope.of(context);
        final focused = FocusManager.instance.primaryFocus;
        if (focused == null ||
            focused == scope ||
            !focused.ancestors.contains(scope)) {
          _focusNode.requestFocus();
        }
      }),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  static int _rank(WpDialogAction<Object?> a) => switch (a.role) {
    WpDialogActionRole.primary ||
    WpDialogActionRole.deliberate ||
    WpDialogActionRole.destructive => 0,
    WpDialogActionRole.alternative => 1,
    WpDialogActionRole.cancel => 2,
    WpDialogActionRole.destructiveExit => 3,
  };

  void _press(WpDialogAction<Object?> a) {
    final onPressed = a.onPressed;
    if (onPressed != null) {
      onPressed();
    } else {
      Navigator.of(context).pop(a.value);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Only while the dialog itself holds focus: a focused button or field
    // below handles its own Enter, and that must win.
    if (!node.hasPrimaryFocus ||
        event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    final main = widget.actions
        .where((a) => a.role == WpDialogActionRole.primary)
        .firstOrNull;
    if (main == null ||
        main.isLoading ||
        !(main.enabledWhen?.value ?? main.enabled)) {
      return KeyEventResult.ignored;
    }
    _press(main);
    return KeyEventResult.handled;
  }

  /// Whether both labels fit half the bar on one line.
  bool _pairFits(BuildContext context, double width) {
    final half = (width - WpSpacing.sm) / 2;
    final style = Theme.of(context).textTheme.labelLarge;
    for (final a in widget.actions) {
      final painter = TextPainter(
        text: TextSpan(text: a.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final needed = painter.width + WpSpacing.lg * 2;
      painter.dispose();
      if (needed > half) return false;
    }
    return true;
  }

  Widget _button(WpDialogAction<Object?> a, {required bool inRow}) {
    Widget build(bool enabled) {
      final onPressed = enabled ? () => _press(a) : null;
      final looksPrimary =
          a.role == WpDialogActionRole.primary ||
          a.role == WpDialogActionRole.deliberate;
      if (looksPrimary && widget.cta == WpDialogCta.hero) {
        return KeyedSubtree(
          key: ValueKey<String>(a.testId),
          child: WpHeroButton(
            label: a.label,
            testId: a.testId,
            verticalPadding: WpSpacing.sm,
            onPressed: a.isLoading ? null : onPressed,
          ),
        );
      }
      final (variant, tone) = switch (a.role) {
        WpDialogActionRole.primary || WpDialogActionRole.deliberate => (
          WpButtonVariant.primary,
          WpButtonTone.accent,
        ),
        WpDialogActionRole.destructive => (
          WpButtonVariant.primary,
          WpButtonTone.danger,
        ),
        WpDialogActionRole.alternative => (
          WpButtonVariant.secondary,
          WpButtonTone.neutral,
        ),
        WpDialogActionRole.cancel => (
          inRow ? WpButtonVariant.secondary : WpButtonVariant.ghost,
          WpButtonTone.neutral,
        ),
        WpDialogActionRole.destructiveExit => (
          WpButtonVariant.ghost,
          WpButtonTone.danger,
        ),
      };
      return WpButton(
        testId: a.testId,
        label: a.label,
        variant: variant,
        tone: tone,
        expanded: true,
        isLoading: a.isLoading,
        onPressed: onPressed,
      );
    }

    final enabledWhen = a.enabledWhen;
    if (enabledWhen == null) return build(a.enabled);
    return ValueListenableBuilder<bool>(
      valueListenable: enabledWhen,
      builder: (_, value, _) => build(value),
    );
  }

  Widget _stack(List<WpDialogAction<Object?>> ordered) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, a) in ordered.indexed) ...[
        if (i > 0)
          SizedBox(
            // Exits stand a step apart from the answers above them.
            height: _rank(a) >= 2 && _rank(ordered[i - 1]) < 2
                ? WpSpacing.sm
                : WpSpacing.xs,
          ),
        _button(a, inRow: false),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final ordered = [...widget.actions]
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));
    final isPair =
        ordered.length == 2 &&
        ordered.first._isMain &&
        ordered.last.role == WpDialogActionRole.cancel;

    final Widget bar;
    if (ordered.length == 1) {
      bar = Align(
        alignment: AlignmentDirectional.centerEnd,
        child: IntrinsicWidth(child: _button(ordered.single, inRow: true)),
      );
    } else if (isPair) {
      bar = LayoutBuilder(
        builder: (context, constraints) {
          if (!_pairFits(context, constraints.maxWidth)) return _stack(ordered);
          return Row(
            children: [
              Expanded(child: _button(ordered.last, inRow: true)),
              const SizedBox(width: WpSpacing.sm),
              Expanded(child: _button(ordered.first, inRow: true)),
            ],
          );
        },
      );
    } else {
      bar = _stack(ordered);
    }

    return Focus(focusNode: _focusNode, onKeyEvent: _onKey, child: bar);
  }
}
