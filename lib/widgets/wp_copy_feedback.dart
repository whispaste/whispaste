/// Feedback for routine actions where they happened, instead of a toast.
///
/// [copyWithFeedback] writes the clipboard and marks a target;
/// [confirmAtTrigger] marks a target for another routine action (duplicate).
/// A [WpCopyAnchor] around a row or an icon button shows the result beside
/// it, so a menu that closes or a keyboard shortcut still answers at the row
/// it came from. [WpCopyButton] turns its own label into "Copied".
///
/// The note floats in an overlay, so it never moves the list. Every mark
/// carries a fresh sequence number: the tenth copy of the same row replays
/// the short entrance ([WpConfirmPop]) instead of leaving a still note that
/// looks like nothing happened. Under "reduce motion" the note switches in
/// directly.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/clipboard_history/app_clipboard.dart';
import '../services/telemetry_service.dart';
import 'wp_button.dart';

final _log = AppLogger('CopyFeedback');

enum WpCopyOutcome { copied, duplicated, failed }

/// The last routine action: which target it belongs to and how it went.
@immutable
class WpCopyMark {
  const WpCopyMark(this.target, this.outcome, [this.seq = 0]);

  final String target;
  final WpCopyOutcome outcome;

  /// Counts up with every mark, so a repeat of the same action on the same
  /// target is still a new confirmation.
  final int seq;
}

/// Holds the latest [WpCopyMark] until it has been on screen long enough. A new
/// copy replaces the old mark, so at most one confirmation shows at a time.
class WpCopyMarkNotifier extends Notifier<WpCopyMark?> {
  static const copiedFor = Duration(seconds: 2);

  /// Longer, because a failure carries a sentence to read and act on.
  static const failedFor = Duration(seconds: 6);

  Timer? _clear;
  int _seq = 0;

  @override
  WpCopyMark? build() {
    ref.onDispose(() => _clear?.cancel());
    return null;
  }

  void mark(String target, WpCopyOutcome outcome) {
    _clear?.cancel();
    state = WpCopyMark(target, outcome, ++_seq);
    _clear = Timer(
      outcome == WpCopyOutcome.failed ? failedFor : copiedFor,
      () => state = null,
    );
  }
}

final copyMarkProvider = NotifierProvider<WpCopyMarkNotifier, WpCopyMark?>(
  WpCopyMarkNotifier.new,
);

/// Copies [text] and reports the result at [target], also to screen readers.
/// Returns whether the clipboard took it.
///
/// [category] counts the copy in telemetry. Leave it out for free notes,
/// which are on the telemetry negative list (internal-notes).
Future<bool> copyWithFeedback(
  BuildContext context, {
  required String text,
  required String target,
  String? category,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final l10n = L10n.of(context);
  final view = View.of(context);
  final direction = Directionality.of(context);
  var copied = true;
  try {
    await AppClipboard.setText(text);
  } catch (e) {
    // No clipboard (PlatformException, e.g. no X selection owner) or no
    // channel at all (MissingPluginException): every caller fires and
    // forgets, so nothing may escape unanswered. The notice names the way out.
    _log.warning('Clipboard write failed', e);
    copied = false;
  }
  if (copied && category != null) {
    container
        .read(telemetrySessionAggregatorProvider)
        .count(category: category, action: 'copy');
  }
  container
      .read(copyMarkProvider.notifier)
      .mark(target, copied ? WpCopyOutcome.copied : WpCopyOutcome.failed);
  announce(view, copied ? l10n.copyDone : l10n.copyFailedHint, direction);
  return copied;
}

/// Confirms a routine action other than copying (duplicate) at [target],
/// also to screen readers.
void confirmAtTrigger(
  BuildContext context, {
  required String target,
  WpCopyOutcome outcome = WpCopyOutcome.duplicated,
}) {
  final l10n = L10n.of(context);
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(copyMarkProvider.notifier).mark(target, outcome);
  announce(
    View.of(context),
    _noteText(l10n, outcome),
    Directionality.of(context),
  );
}

String _noteText(L10n l10n, WpCopyOutcome? outcome) => switch (outcome) {
  WpCopyOutcome.failed => l10n.copyFailedHint,
  WpCopyOutcome.duplicated => l10n.duplicateDone,
  _ => l10n.copyDone,
};

/// Shows the result of a copy to [target] just below [child].
class WpCopyAnchor extends ConsumerStatefulWidget {
  const WpCopyAnchor({
    super.key,
    required this.target,
    required this.child,
    this.confirm = true,
  });

  final String target;
  final Widget child;

  /// False when [child] confirms a success itself; failures always show here.
  final bool confirm;

  @override
  ConsumerState<WpCopyAnchor> createState() => _WpCopyAnchorState();
}

class _WpCopyAnchorState extends ConsumerState<WpCopyAnchor> {
  /// Share of the window height below which a note no longer fits under a row.
  static const _opensUpwardsFrom = 0.75;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  WpCopyOutcome? _outcome;
  int _seq = 0;
  bool _above = false;
  bool _growFromStart = false;
  double _maxWidth = WpLayout.noteMaxWidth;

  /// Keeps the note inside the window: it opens upwards from low rows, where
  /// it would end under the window edge, and grows from the anchor's start
  /// edge when its end edge leaves too little room.
  void _fitToWindow() {
    final overlay = Overlay.of(context).context.findRenderObject();
    final anchor = context.findRenderObject();
    if (overlay is! RenderBox || anchor is! RenderBox) return;
    final rect =
        anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = overlay.size.width;
    final fromEnd = rtl ? width - rect.left : rect.right;
    final fromStart = rtl ? rect.right : width - rect.left;
    _above = rect.bottom > overlay.size.height * _opensUpwardsFrom;
    _growFromStart = fromEnd < WpLayout.noteMaxWidth;
    _maxWidth = math.min(
      WpLayout.noteMaxWidth,
      (_growFromStart ? fromStart : fromEnd) - WpSpacing.sm,
    );
  }

  void _onMark(WpCopyMark? mark) {
    final mine = mark?.target == widget.target ? mark?.outcome : null;
    final outcome = mine == WpCopyOutcome.copied && !widget.confirm
        ? null
        : mine;
    final seq = outcome == null ? _seq : mark!.seq;
    if (outcome == _outcome && seq == _seq) return;
    if (outcome != null) _fitToWindow();
    setState(() {
      _outcome = outcome;
      _seq = seq;
    });
    outcome == null ? _portal.hide() : _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(copyMarkProvider, (_, mark) => _onMark(mark));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final x = rtl == _growFromStart ? 1.0 : -1.0;
    final y = _above ? -1.0 : 1.0;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => Align(
        alignment: AlignmentDirectional.topStart,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment(x, y),
          followerAnchor: Alignment(x, -y),
          child: _CopyNote(
            target: widget.target,
            outcome: _outcome,
            seq: _seq,
            maxWidth: _maxWidth,
          ),
        ),
      ),
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}

class _CopyNote extends StatelessWidget {
  const _CopyNote({
    required this.target,
    required this.outcome,
    required this.seq,
    required this.maxWidth,
  });

  final String target;
  final WpCopyOutcome? outcome;
  final int seq;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final failed = outcome == WpCopyOutcome.failed;
    // Screen readers already got the announcement; the note must not take
    // clicks meant for the row beneath it.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: WpConfirmPop(
          // A new key per mark replays the entrance on every repeat.
          key: ValueKey('copy-note-pop-$seq'),
          child: ConstrainedBox(
            key: ValueKey('copy-note-$target'),
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WpColors.cardFillElevated,
                borderRadius: WpRadius.borderSm,
                border: Border.all(color: WpColors.borderDefault),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      failed ? LucideIcons.triangleAlert : LucideIcons.check,
                      size: WpIconSize.sm,
                      color: failed ? WpColors.error : WpColors.textPrimary,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Flexible(
                      child: Text(
                        _noteText(l10n, outcome),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WpColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Short confirmation entrance: fades in and settles from 92 % scale within
/// [WpMotion.fast]. Paint-only (opacity and transform), so nothing around it
/// moves. Under "reduce motion" the child stands at once. Give it a new key
/// to replay it.
class WpConfirmPop extends StatefulWidget {
  const WpConfirmPop({super.key, required this.child});

  final Widget child;

  @override
  State<WpConfirmPop> createState() => _WpConfirmPopState();
}

class _WpConfirmPopState extends State<WpConfirmPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: WpMotion.defaultCurve,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.92,
    end: 1,
  ).animate(_curved);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final duration = WpMotion.durationFor(context, WpMotion.fast);
    if (duration == Duration.zero) return;
    _controller.duration = duration;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curved,
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

/// A labelled button that copies and reads "Copied" for a moment.
class WpCopyButton extends ConsumerStatefulWidget {
  const WpCopyButton({
    super.key,
    required this.testId,
    required this.label,
    required this.text,
    required this.variant,
    this.tone = WpButtonTone.accent,
    this.size = WpButtonSize.standard,
    this.icon = LucideIcons.copy,
    this.category,
    this.onCopied,
    this.onBusyChanged,
  });

  /// Also the copy target, so a failure shows at this button.
  final String testId;
  final String label;

  /// Asked at click time, so a report can be built only when it is needed.
  /// Must not throw: a report brings its own fallback.
  final FutureOr<String> Function() text;
  final WpButtonVariant variant;
  final WpButtonTone tone;
  final WpButtonSize size;
  final IconData? icon;
  final String? category;
  final VoidCallback? onCopied;

  /// For a page that explains a slow [text] beside the button.
  final ValueChanged<bool>? onBusyChanged;

  @override
  ConsumerState<WpCopyButton> createState() => _WpCopyButtonState();
}

class _WpCopyButtonState extends ConsumerState<WpCopyButton> {
  bool _busy = false;

  /// The width before the click: "Copied" is shorter than most labels, and
  /// the neighbours must not jump while it shows.
  double? _width;

  void _setBusy(bool busy) {
    setState(() => _busy = busy);
    widget.onBusyChanged?.call(busy);
  }

  Future<void> _copy() async {
    _width = context.size?.width;
    _setBusy(true);
    var copied = false;
    try {
      final text = await widget.text();
      if (!mounted) return;
      copied = await copyWithFeedback(
        context,
        text: text,
        target: widget.testId,
        category: widget.category,
      );
    } finally {
      if (mounted) _setBusy(false);
    }
    if (copied) widget.onCopied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final copied = ref.watch(
      copyMarkProvider.select(
        (mark) =>
            mark?.target == widget.testId &&
            mark?.outcome == WpCopyOutcome.copied,
      ),
    );
    return WpCopyAnchor(
      target: widget.testId,
      confirm: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: copied ? _width ?? 0 : 0),
        child: WpButton(
          testId: widget.testId,
          label: copied ? L10n.of(context).copyDone : widget.label,
          variant: widget.variant,
          tone: widget.tone,
          size: widget.size,
          icon: copied ? LucideIcons.check : widget.icon,
          isLoading: _busy,
          onPressed: _busy ? null : _copy,
        ),
      ),
    );
  }
}
