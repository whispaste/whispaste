import 'package:flutter/material.dart';

import '../core/theme/colors.dart';

/// What a [WpStatusDot] says about the thing it is attached to.
enum WpStatusTone {
  /// Ready to work. Accent, not green: green is reserved for the moment after
  /// an action (`test/core/design/earned_green_test.dart`). The dock's ready
  /// state uses [success] instead, which is the one allowlisted green dot.
  ready,

  /// Dock ready state (green), shown only when dictation provably runs
  /// locally ("Lokal bereit", spec §2). Only this primitive may paint `success`
  /// as a dot; every other status dot stays on [ready] (accent). Allowlisted in
  /// `test/core/design/earned_green_test.dart`: "dock ready state, successor of
  /// the status bar".
  success,

  /// Working or waiting on something (amber).
  busy,

  /// Failed or blocked (red).
  error,

  /// Not active; no judgement (muted).
  idle,
}

/// A small coloured dot that carries a status without words, e.g. the
/// transcription engine's readiness next to its name.
///
/// Decorative by default: the text beside it states the status. Pass
/// [semanticsLabel] when the dot is the only carrier of the state.
class WpStatusDot extends StatelessWidget {
  const WpStatusDot({
    super.key,
    required this.tone,
    this.semanticsLabel,
    this.size = defaultSize,
  });

  final WpStatusTone tone;
  final String? semanticsLabel;

  /// Diameter in logical pixels; the default suits inline text.
  final double size;

  static const double defaultSize = 8;

  Color get _color => switch (tone) {
    WpStatusTone.ready => WpColors.accent,
    WpStatusTone.success => WpColors.success,
    WpStatusTone.busy => WpColors.warning,
    WpStatusTone.error => WpColors.error,
    WpStatusTone.idle => WpColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
    return semanticsLabel == null
        ? ExcludeSemantics(child: dot)
        : Semantics(label: semanticsLabel, child: dot);
  }
}
