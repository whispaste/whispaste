import 'package:flutter/material.dart';

/// Whether [text] does not fit on one line in [maxWidth], measured with the
/// same font the [Text] widget will use (the ambient default text style
/// merged with [style]).
bool isOneLineTruncated(
  BuildContext context, {
  required String text,
  required TextStyle style,
  required TextScaler textScaler,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    maxLines: 1,
    textScaler: textScaler,
    textDirection: Directionality.of(context),
  )..layout(maxWidth: maxWidth);
  try {
    return painter.didExceedMaxLines;
  } finally {
    painter.dispose();
  }
}

/// Shows [message] as a tooltip while [focusNode] has keyboard focus, but
/// only when [isTruncated] reports that the label is cut off, so a sighted
/// keyboard user can read the full name.
///
/// [showOnHover] controls only the touch long-press trigger. Flutter does not
/// apply [TooltipTriggerMode] to mouse pointers, so a mouse hover shows the
/// tooltip in either case.
class WpSidePanelFocusTooltip extends StatefulWidget {
  const WpSidePanelFocusTooltip({
    super.key,
    required this.message,
    required this.focusNode,
    required this.isTruncated,
    required this.child,
    this.showOnHover = true,
  });

  final String message;
  final FocusNode focusNode;

  /// Read on each focus change, so it reflects the latest layout.
  final bool Function() isTruncated;
  final Widget child;
  final bool showOnHover;

  @override
  State<WpSidePanelFocusTooltip> createState() =>
      _WpSidePanelFocusTooltipState();
}

class _WpSidePanelFocusTooltipState extends State<WpSidePanelFocusTooltip> {
  GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(WpSidePanelFocusTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.isTruncated()) return;
    if (widget.focusNode.hasFocus) {
      _tooltipKey.currentState?.ensureTooltipVisible();
    } else {
      // Tooltips have no public dismiss. Recreating the tooltip with a new
      // key removes an open focus tooltip together with its overlay.
      setState(() => _tooltipKey = GlobalKey<TooltipState>());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      triggerMode: widget.showOnHover
          ? TooltipTriggerMode.longPress
          : TooltipTriggerMode.manual,
      child: widget.child,
    );
  }
}
