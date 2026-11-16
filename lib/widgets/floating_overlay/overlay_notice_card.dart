/// The notice card of the floating overlay (overlay F2).
///
/// Replaces the pill while a microphone problem or the duration limit needs a
/// decision: a title, one or two body lines, a footer with the valid keys and
/// up to two buttons, plus the close cross (#781). The window is
/// non-activating on every platform, so a click here never takes focus from
/// the target app.
///
/// Same type and colours as the pill ([OverlayDesignSpec.colorsFor]); amber
/// glyph for a hint, red for an error, flat with no glow.
library;

import 'package:flutter/widgets.dart';

import '../../core/l10n/ltr_isolate.dart';
import '../../core/theme/overlay_design_spec.dart';
import '../../core/theme/theme.dart' show kWpFontFallback;
import '../../services/floating_overlay/overlay_notice.dart';

/// Lines the card's headline may take. Without a body the title carries the
/// whole message: the Esc hint of the discard ask needs the second line, a
/// message card may take three (#453).
int overlayNoticeTitleMaxLines(OverlayNotice notice) {
  if (notice.body.isNotEmpty) return 1;
  return notice.kind == OverlayNoticeKind.message ? 3 : 2;
}

/// Lines the card's body may take before it is cut. A message card gets a
/// third line when the key footer or the button row leaves room for it: with
/// both a third line would not fit the card (#781). A message card without
/// buttons (a skipped paste, #1617) keeps the third line at the largest text
/// scale too.
int overlayNoticeBodyMaxLines(OverlayNotice notice) {
  final hasButtons = notice.actions.any((a) => !a.action.isClose);
  final roomy = notice.footer.isEmpty || !hasButtons;
  return notice.kind == OverlayNoticeKind.message && roomy ? 3 : 2;
}

class WpOverlayNoticeCard extends StatelessWidget {
  const WpOverlayNoticeCard({
    super.key,
    required this.notice,
    required this.colors,
    this.onAction,
  });

  final OverlayNotice notice;
  final OverlayThemeColors colors;

  /// Called with the action of a pressed button; null in static previews.
  final ValueChanged<OverlayNoticeActionId>? onAction;

  @override
  Widget build(BuildContext context) {
    const size = OverlayDesignSpec.noticeCardSize;
    final dismiss = notice.actions.where((a) => a.action.isClose).firstOrNull;
    final buttons = notice.actions.where((a) => !a.action.isClose).toList();
    final glyph = notice.tone == OverlayNoticeTone.error
        ? colors.noticeErrorDot
        : colors.noticeHintDot;

    // The card text follows the system font size up to a fixed cap (#728).
    final media = MediaQuery.maybeOf(context);
    final scaler = (media?.textScaler ?? TextScaler.noScaling).clamp(
      maxScaleFactor: OverlayDesignSpec.noticeMaxTextScale,
    );

    final card = Padding(
      padding: const EdgeInsets.all(OverlayDesignSpec.shadowPadding),
      // Taps on the card's free area are absorbed: they must not reach the
      // pill's body click, which would start or stop a recording.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          width: size.width,
          height: size.height,
          padding: const EdgeInsets.all(OverlayDesignSpec.noticeCardPadding),
          decoration: BoxDecoration(
            // Opaque on glass too: a decision must stay legible over any
            // desktop, and the card covers the pill-shaped native backdrop.
            color: colors.opaqueFill,
            border: Border.all(color: colors.capsuleBorder),
            borderRadius: BorderRadius.circular(
              OverlayDesignSpec.noticeCardRadius,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: OverlayDesignSpec.shadowPadding / 2,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // Clipped, not overflowing: at the largest text scale the text block
          // may touch the card edge, and then it ends there.
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: glyph,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notice.title,
                        // Without a body the title carries the whole message:
                        // the Esc hint of the discard ask needs the second line.
                        maxLines: overlayNoticeTitleMaxLines(notice),
                        overflow: TextOverflow.ellipsis,
                        style: _style(
                          OverlayDesignSpec.noticeTitleFontSize,
                          OverlayDesignSpec.primaryFontWeight,
                        ),
                      ),
                    ),
                    if (dismiss != null)
                      _CloseButton(
                        testName: dismiss.testName,
                        label: dismiss.label,
                        color: colors.ink,
                        onTap: () => onAction?.call(dismiss.action),
                      ),
                  ],
                ),
                if (notice.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notice.body,
                    maxLines: overlayNoticeBodyMaxLines(notice),
                    overflow: TextOverflow.ellipsis,
                    style: _style(
                      OverlayDesignSpec.noticeBodyFontSize,
                      FontWeight.w400,
                    ).copyWith(color: colors.noticeBodyInk),
                  ),
                ],
                const Spacer(),
                if (notice.footer.isNotEmpty) ...[
                  // Never cut by an ellipsis: the longest translations shrink
                  // to the card width instead (#728).
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      notice.footer,
                      key: const ValueKey('overlay-notice-footer'),
                      maxLines: 1,
                      softWrap: false,
                      style: _style(
                        OverlayDesignSpec.noticeFooterFontSize,
                        FontWeight.w400,
                      ).copyWith(color: colors.noticeFooterInk),
                    ),
                  ),
                  const SizedBox(height: OverlayDesignSpec.noticeFooterGap),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final (i, b) in buttons.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      // Shares the row by label width: a short label leaves a
                      // long one its room instead of halving the row.
                      Flexible(
                        flex: _labelWidth(b.fullLabel, scaler),
                        child: Semantics(
                          button: true,
                          identifier: 'overlay-notice-action-${b.testName}',
                          label: b.fullLabel,
                          // A tap action on the node, so a screen reader's
                          // double tap triggers it (#728).
                          onTap: () => onAction?.call(b.action),
                          excludeSemantics: true,
                          child: _NoticeButton(
                            action: b,
                            colors: colors,
                            style: _style(
                              OverlayDesignSpec.noticeBodyFontSize,
                              OverlayDesignSpec.primaryFontWeight,
                            ),
                            onTap: () => onAction?.call(b.action),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The native shell may still have the pill's window for a frame when the
    // card arrives or leaves (#1193). The card keeps its own size and is cut
    // at the window edge then, instead of squeezing its column into an
    // overflow.
    final window = OverlayDesignSpec.noticeWindowSize;
    final framed = LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            constraints.maxWidth >= window.width &&
            constraints.maxHeight >= window.height;
        if (fits) return card;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: window.width,
            maxWidth: window.width,
            minHeight: window.height,
            maxHeight: window.height,
            child: card,
          ),
        );
      },
    );
    return media == null
        ? framed
        : MediaQuery(
            data: media.copyWith(textScaler: scaler),
            child: framed,
          );
  }

  int _labelWidth(String label, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: _style(
          OverlayDesignSpec.noticeBodyFontSize,
          OverlayDesignSpec.primaryFontWeight,
        ),
      ),
      maxLines: 1,
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width.ceil() + 1;
    painter.dispose();
    return width;
  }

  TextStyle _style(double size, FontWeight weight) => TextStyle(
    fontFamily: OverlayDesignSpec.fontFamily,
    fontFamilyFallback: kWpFontFallback,
    fontSize: size,
    fontWeight: weight,
    color: colors.ink,
    height: 1.3,
  );
}

class _NoticeButton extends StatelessWidget {
  const _NoticeButton({
    required this.action,
    required this.colors,
    required this.style,
    required this.onTap,
  });

  final OverlayNoticeAction action;
  final OverlayThemeColors colors;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = action.primary;
    final text = primary ? style.copyWith(color: colors.opaqueFill) : style;
    // The caller wraps the button in its Semantics (label, button role).
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('overlay-notice-action-${action.testName}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: OverlayDesignSpec.noticeButtonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? colors.accent : null,
            border: primary ? null : Border.all(color: colors.capsuleBorder),
            borderRadius: BorderRadius.circular(
              OverlayDesignSpec.noticeButtonHeight / 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text,
                ),
              ),
              // The key way stays whole when the label is cut (#816) and is
              // isolated so "2× F12" keeps its order in right-to-left text.
              if (action.keyHint case final key?)
                Text(' (${ltrIsolate(key)})', maxLines: 1, style: text),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.testName,
    required this.label,
    required this.color,
    required this.onTap,
  });

  /// Action name for the testID: the close of a recording card hides the
  /// hint and is not the dismiss of a card without a recording.
  final String testName;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The render window has no Overlay and the card is a few dozen pixels
    // tall, so a drawn hover tooltip would be cut off at the window edge. The
    // name reaches assistive technology as label and tooltip instead.
    final id = 'overlay-notice-action-$testName';
    return Semantics(
      button: true,
      identifier: id,
      label: label,
      tooltip: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey(id),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: OverlayDesignSpec.noticeButtonHeight,
            height: OverlayDesignSpec.noticeCloseHeight,
            // Drawn, not a glyph: no bundled font carries the cross sign.
            child: Center(
              child: CustomPaint(
                size: const Size.square(10),
                painter: _CrossPainter(color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}
