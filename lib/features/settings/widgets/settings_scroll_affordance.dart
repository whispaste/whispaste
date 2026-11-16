import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

/// Makes a scrolling settings column show that it scrolls (UX-001).
///
/// A visible scrollbar thumb while the content overflows (desktop has no
/// scroll hint otherwise), and a short fade at the bottom edge only while
/// more content lies below the visible part. Both disappear when everything
/// fits, so a short area looks exactly as before.
class SettingsScrollAffordance extends StatefulWidget {
  const SettingsScrollAffordance({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;

  /// Inner padding of the scroll view (the onboarding page uses its own).
  final EdgeInsetsGeometry? padding;

  @override
  State<SettingsScrollAffordance> createState() =>
      _SettingsScrollAffordanceState();
}

class _SettingsScrollAffordanceState extends State<SettingsScrollAffordance> {
  final ScrollController _controller = ScrollController();
  bool _moreBelow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
    // Content can already overflow on the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final more = _controller.position.extentAfter > 0.5;
    if (more != _moreBelow) setState(() => _moreBelow = more);
  }

  @override
  Widget build(BuildContext context) {
    final fade = WpColors.background;
    return Stack(
      children: [
        ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbColor: WidgetStatePropertyAll(WpColors.textSecondary),
            thickness: const WidgetStatePropertyAll(6),
            radius: const Radius.circular(3),
          ),
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            // UX-090: a hairline thumb in the background tone was barely
            // visible at 2.0 text scale. A 6 px thumb in body-text colour reads
            // as a scroll area on both navy and dark frames.
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _update());
                return false;
              },
              child: SingleChildScrollView(
                controller: _controller,
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
        if (_moreBelow)
          Positioned(
            key: const ValueKey('settings-scroll-fade'),
            left: 0,
            right: 0,
            bottom: 0,
            height: WpSpacing.xl,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [fade.withValues(alpha: 0), fade],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
