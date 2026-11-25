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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/l10n/ltr_isolate.dart';
import '../../core/theme/overlay_design_spec.dart';
import '../../services/floating_overlay/overlay_notice.dart';
import '../../services/floating_overlay/overlay_notice_layout.dart';

export '../../services/floating_overlay/overlay_notice_layout.dart'
    show overlayNoticeBodyMaxLines, overlayNoticeTitleMaxLines;

class WpOverlayNoticeCard extends StatelessWidget {
  const WpOverlayNoticeCard({
    super.key,
    required this.notice,
    required this.colors,
    this.onAction,
    this.onEdit,
  });

  final OverlayNotice notice;
  final OverlayThemeColors colors;

  /// Called with the action of a pressed button; null in static previews.
  final ValueChanged<OverlayNoticeActionId>? onAction;

  /// Called with what the edit field reports (#254); null in static
  /// previews.
  final ValueChanged<OverlayNoticeEditEvent>? onEdit;

  @override
  Widget build(BuildContext context) {
    final width = OverlayDesignSpec.noticeCardSize.width;
    final dismiss = notice.actions.where((a) => a.action.isClose).firstOrNull;
    final buttons = notice.actions.where((a) => !a.action.isClose).toList();
    final glyph = notice.tone == OverlayNoticeTone.error
        ? colors.noticeErrorDot
        : colors.noticeHintDot;

    // The card text follows the system font size up to a fixed cap (#728).
    final media = MediaQuery.maybeOf(context);
    final scaler = overlayNoticeScaler(
      media?.textScaler ?? TextScaler.noScaling,
    );
    // Grows with its content instead of cutting it (#1845); the shells get
    // the same height with the snapshot.
    final height = overlayNoticeCardHeight(notice, scaler);
    final stacked = overlayNoticeStacksButtons(notice, scaler);

    final card = Padding(
      padding: const EdgeInsets.all(OverlayDesignSpec.shadowPadding),
      // Taps on the card's free area are absorbed: they must not reach the
      // pill's body click, which would start or stop a recording.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          width: width,
          height: height,
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
                if (notice.edit case final edit?)
                  if (edit.open)
                    _NoticeEditField(
                      edit: edit,
                      colors: colors,
                      style: _style(
                        OverlayDesignSpec.noticeBodyFontSize,
                        FontWeight.w400,
                      ),
                      hintStyle: _style(
                        OverlayDesignSpec.noticeFooterFontSize,
                        FontWeight.w400,
                      ).copyWith(color: colors.noticeFooterInk),
                      onEdit: onEdit,
                    )
                  else
                    _EditToggle(
                      label: edit.toggleLabel,
                      style: _style(
                        OverlayDesignSpec.noticeFooterFontSize,
                        OverlayDesignSpec.primaryFontWeight,
                      ).copyWith(color: colors.accent),
                      onTap: () => onEdit?.call(
                        const OverlayNoticeEditEvent(
                          OverlayNoticeEditKind.open,
                        ),
                      ),
                    ),
                for (final note in notice.notes) ...[
                  const SizedBox(height: 4),
                  // A quiet hint, never cut: it wraps and the card grows.
                  Semantics(
                    identifier: note.id,
                    child: Text(
                      note.text,
                      key: ValueKey(note.id),
                      style: _style(
                        OverlayDesignSpec.noticeFooterFontSize,
                        FontWeight.w400,
                      ).copyWith(color: colors.noticeFooterInk),
                    ),
                  ),
                ],
                const Spacer(),
                if (notice.footer.isNotEmpty) ...[
                  // Never cut and never shrunk below the small type step: a
                  // long footer wraps and the card grows (#1845).
                  Text(
                    notice.footer,
                    key: const ValueKey('overlay-notice-footer'),
                    style: _style(
                      OverlayDesignSpec.noticeFooterFontSize,
                      FontWeight.w400,
                    ).copyWith(color: colors.noticeFooterInk),
                  ),
                  const SizedBox(height: OverlayDesignSpec.noticeFooterGap),
                ],
                if (stacked)
                  // Whole labels on top of each other when they do not fit
                  // side by side (#1845), primary first.
                  for (final (i, b) in buttons.indexed) ...[
                    if (i > 0)
                      const SizedBox(height: OverlayDesignSpec.noticeStackGap),
                    _buttonFor(b),
                  ]
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final (i, b) in buttons.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        // Shares the row by label width: a short label leaves a
                        // long one its room instead of halving the row.
                        Flexible(
                          flex: _labelWidth(b.fullLabel, scaler),
                          child: _buttonFor(b),
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
    final window = OverlayDesignSpec.noticeWindowSizeFor(height);
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

  Widget _buttonFor(OverlayNoticeAction b) => Semantics(
    button: true,
    identifier: 'overlay-notice-action-${b.testName}',
    label: b.fullLabel,
    // A tap action on the node, so a screen reader's double tap triggers it
    // (#728).
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
  );

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

  TextStyle _style(double size, FontWeight weight) =>
      overlayNoticeTextStyle(size, weight).copyWith(color: colors.ink);
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

/// The toggle that turns the draft into the edit field (#254).
class _EditToggle extends StatelessWidget {
  const _EditToggle({
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      button: true,
      identifier: kNoticeEditToggleId,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey(kNoticeEditToggleId),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(label, maxLines: 1, style: style),
        ),
      ),
    ),
  );
}

/// The edit field of the write preview (#254, D21): Enter inserts the text
/// as it stands, Shift+Enter breaks the line, Esc discards. The hint line
/// inside the field says so (R25). The render engine has no Material, so
/// the field is an [EditableText] with the plain-widgets selection gestures
/// and text editing shortcuts.
class _NoticeEditField extends StatefulWidget {
  const _NoticeEditField({
    required this.edit,
    required this.colors,
    required this.style,
    required this.hintStyle,
    required this.onEdit,
  });

  final OverlayNoticeEdit edit;
  final OverlayThemeColors colors;
  final TextStyle style;
  final TextStyle hintStyle;
  final ValueChanged<OverlayNoticeEditEvent>? onEdit;

  @override
  State<_NoticeEditField> createState() => _NoticeEditFieldState();
}

class _NoticeEditFieldState extends State<_NoticeEditField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextEditingController _controller = TextEditingController(
    text: widget.edit.text,
  );
  late final FocusNode _focus = FocusNode(
    debugLabel: kNoticeEditFieldId,
    onKeyEvent: _onKey,
  );
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);

  @override
  final GlobalKey<EditableTextState> editableTextKey =
      GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  StreamSubscription<OverlayNoticeEditKey>? _nativeKeys;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _nativeKeys = OverlayNoticeEditKeys.stream.listen(_onNativeKey);
  }

  /// A key the macOS shell caught before the embedder's text input (#254):
  /// the same as the keys arriving here, with the field's text.
  void _onNativeKey(OverlayNoticeEditKey key) => switch (key) {
    OverlayNoticeEditKey.enter => _emit(
      OverlayNoticeEditEvent(
        OverlayNoticeEditKind.submit,
        text: _controller.text,
      ),
    ),
    OverlayNoticeEditKey.newline => _insertLineBreak(),
    OverlayNoticeEditKey.escape => _emit(
      const OverlayNoticeEditEvent(OverlayNoticeEditKind.cancel),
    ),
  };

  @override
  void didUpdateWidget(_NoticeEditField old) {
    super.didUpdateWidget(old);
    // A new version (a refinement) replaces the text; the same draft drawn
    // again keeps what was typed and the caret.
    if (widget.edit.key != old.edit.key &&
        widget.edit.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.edit.text,
        selection: TextSelection.collapsed(offset: widget.edit.text.length),
      );
    }
    // A new draft behind the same field learns where the focus is.
    if (widget.edit.key != old.edit.key && _focus.hasFocus) _onFocus();
  }

  @override
  void dispose() {
    unawaited(_nativeKeys?.cancel());
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _emit(OverlayNoticeEditEvent event) => widget.onEdit?.call(event);

  void _onFocus() => _emit(
    OverlayNoticeEditEvent(
      OverlayNoticeEditKind.focus,
      focused: _focus.hasFocus,
    ),
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) {
        _emit(const OverlayNoticeEditEvent(OverlayNoticeEditKind.cancel));
      }
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertLineBreak();
    } else if (event is KeyDownEvent) {
      _emit(
        OverlayNoticeEditEvent(
          OverlayNoticeEditKind.submit,
          text: _controller.text,
        ),
      );
    }
    return KeyEventResult.handled;
  }

  void _insertLineBreak() {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(selection.start, selection.end, '\n');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
    _onChanged(text);
  }

  void _onChanged(String text) =>
      _emit(OverlayNoticeEditEvent(OverlayNoticeEditKind.text, text: text));

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final line = scaler.scale(widget.style.fontSize!) * widget.style.height!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        key: const ValueKey(kNoticeEditFieldId),
        padding: const EdgeInsets.all(overlayNoticeEditPadding),
        decoration: BoxDecoration(
          border: Border.all(color: colors.accent),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: kNoticeEditFieldLines * line,
              child: Semantics(
                identifier: kNoticeEditFieldId,
                label: widget.edit.fieldLabel,
                textField: true,
                child: DefaultTextEditingShortcuts(
                  child: _gestures.buildGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    child: EditableText(
                      key: editableTextKey,
                      controller: _controller,
                      focusNode: _focus,
                      style: widget.style,
                      cursorColor: colors.accent,
                      backgroundCursorColor: colors.capsuleBorder,
                      selectionColor: colors.accent.withValues(alpha: 0.3),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      autofocus: true,
                      onChanged: _onChanged,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // The keys of the field, inside it, where the eye is (R25).
            Semantics(
              identifier: kNoticeEditInsertHintId,
              child: Text(
                widget.edit.insertHint,
                key: const ValueKey(kNoticeEditInsertHintId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.hintStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
