import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// A single line of filter chips that scrolls sideways when it is too narrow.
///
/// Wrapping put "Papierkorb" on a second line at 800 px and pushed the list
/// below the fold (UX-031). A trailing fade says there is more, and the
/// scroll follows keyboard focus, so every filter stays reachable.
class WpFilterChipScroller extends StatefulWidget {
  const WpFilterChipScroller({super.key, required this.children});

  final List<Widget> children;

  @override
  State<WpFilterChipScroller> createState() => _WpFilterChipScrollerState();
}

class _WpFilterChipScrollerState extends State<WpFilterChipScroller> {
  final ScrollController _controller = ScrollController();
  bool _moreAhead = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() => _update(_controller.position);

  /// Shows the fade while chips lie beyond the end edge. Also runs when the
  /// row is first laid out or resized, so an overflowing row hints at more
  /// before the user has scrolled at all.
  void _update(ScrollMetrics metrics) {
    final more = metrics.pixels < metrics.maxScrollExtent - 1;
    if (more != _moreAhead) setState(() => _moreAhead = more);
  }

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i > 0) const SizedBox(width: WpSpacing.xs),
          widget.children[i],
        ],
      ],
    );
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: _moreAhead
            ? const [Colors.white, Colors.white, Colors.transparent]
            : const [Colors.white, Colors.white, Colors.white],
        stops: const [0, 0.86, 1],
      ).createShader(rect),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) {
          _update(n.metrics);
          return false;
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(end: WpSpacing.lg),
          child: row,
        ),
      ),
    );
  }
}
