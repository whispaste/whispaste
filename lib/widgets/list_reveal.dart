import 'dart:async';

import 'package:flutter/widgets.dart';

/// Reveal state of a list page. The entry created or saved last is scrolled
/// into view and highlighted for [highlightDuration]; the timer clears the
/// highlight, the scroll position stays where it was.
mixin WpListRevealMixin<T extends StatefulWidget> on State<T> {
  static const highlightDuration = Duration(seconds: 2);

  /// Entry the list scrolls to.
  String? revealedId;

  /// Entry drawn with the highlight; null once the timer has run out.
  String? highlightedId;

  Timer? _highlightTimer;

  void reveal(String id) => _mark(id, scroll: true);

  /// Highlights [id] without scrolling: for a routine action like duplicate,
  /// which confirms at its trigger and must not move the list under the
  /// pointer.
  void highlight(String id) => _mark(id, scroll: false);

  void _mark(String id, {required bool scroll}) {
    _highlightTimer?.cancel();
    setState(() {
      if (scroll) revealedId = id;
      highlightedId = id;
    });
    _highlightTimer = Timer(highlightDuration, () {
      if (mounted) setState(() => highlightedId = null);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }
}
