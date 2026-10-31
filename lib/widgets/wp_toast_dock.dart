/// Keeps toasts above a bottom action row instead of on top of it.
///
/// A row pinned to the bottom edge (onboarding navigation, a page footer)
/// wraps itself in [WpToastDockReserve]. The reserve reports how far its top
/// edge sits above the window bottom; the toast host lifts itself to clear
/// the highest reported row. Without a reported row the toast keeps its
/// default place.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

abstract final class WpToastDock {
  /// Default distance of a toast from the window bottom, with no row to clear.
  static const double baseBottom = 56;

  /// Space between a toast and the top edge of the row it rises above.
  static const double gap = WpSpacing.sm;

  /// Distance from the window bottom to the top edge of the highest reserved
  /// row, or 0 when none is reserved.
  static final ValueNotifier<double> reserved = ValueNotifier<double>(0);

  static final Map<Object, double> _claims = <Object, double>{};

  /// The bottom offset a toast uses when [reservedTop] is the reserved height.
  static double bottomFor(double reservedTop) =>
      math.max(baseBottom, reservedTop + gap);

  /// Records [fromBottom] (distance from the window bottom to the row's top
  /// edge) for [owner]; a non-positive value removes the claim.
  static void claim(Object owner, double fromBottom) {
    if (fromBottom <= 0) {
      _claims.remove(owner);
    } else {
      _claims[owner] = fromBottom;
    }
    final highest = _claims.values.fold<double>(0, math.max);
    if (reserved.value != highest) reserved.value = highest;
  }
}

/// Marks [child] as a bottom action row that toasts must stay above.
///
/// Only use it for rows that are pinned to the window bottom. A row in the
/// middle of a window would push toasts far up for no reason.
class WpToastDockReserve extends StatefulWidget {
  const WpToastDockReserve({super.key, required this.child, this.animation});

  final Widget child;

  /// Animation that moves [child] (a dialog's open transition): the row is
  /// measured on every tick, so the toast follows it to its resting place.
  final Animation<double>? animation;

  @override
  State<WpToastDockReserve> createState() => _WpToastDockReserveState();
}

class _WpToastDockReserveState extends State<WpToastDockReserve> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.animation?.addListener(_scheduleMeasure);
    _scheduleMeasure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant WpToastDockReserve oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation?.removeListener(_scheduleMeasure);
      widget.animation?.addListener(_scheduleMeasure);
    }
    _scheduleMeasure();
  }

  @override
  void dispose() {
    widget.animation?.removeListener(_scheduleMeasure);
    // Post-frame: the notifier must not change while the tree is unmounting.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WpToastDock.claim(this, 0),
    );
    super.dispose();
  }

  /// Measures after the frame, never during layout or build.
  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      // Measured against the overlay the toast is placed in, not the window:
      // a dialog's MediaQuery can differ from the overlay's size.
      final overlayBox =
          Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
      if (overlayBox == null || !overlayBox.hasSize) return;
      final top = box.localToGlobal(Offset.zero, ancestor: overlayBox).dy;
      WpToastDock.claim(this, overlayBox.size.height - top);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Registers the window size as a dependency: a resize re-measures.
    MediaQuery.sizeOf(context);
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleMeasure();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: RepaintBoundary(key: _boundaryKey, child: widget.child),
      ),
    );
  }
}
