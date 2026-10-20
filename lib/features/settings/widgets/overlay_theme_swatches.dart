/// Swatch pickers for the overlay theme presets (WP-75, ADR 0024; validity
/// WP-75b).
///
/// Two rows of round swatches: one for the pill/button background, one for
/// the wave colour (both offer Bernstein, WP-75 flat pass). Each swatch is a 48 px hit target (WCAG 2.5.5) with its
/// name printed underneath, so the names are visible without hovering. The
/// rows follow the appearance cards: the arrow keys move focus only, and Enter,
/// Space or a click selects. The colours come from the token-backed presets in
/// [OverlayBackground] and [OverlayWave]; nothing here is a free colour picker.
///
/// A wave that is invalid on the chosen background is disabled and shows the
/// colour it would have. Choosing a background moves an invalid wave to its
/// replacement and says so with a short notice ([pickOverlayBackground]).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/overlay_design_spec.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_focus_ring.dart';

/// Minimum hit target of one swatch.
const double _swatchTarget = 48;

/// Visible disc inside the hit target.
const double _swatchDisc = 32;

/// Minimum width of one swatch column. The column grows with its printed name
/// (UX-040): a fixed width cut the name off at larger text scales.
const double _swatchColumn = 72;

/// Picker for [OverlayBackground].
class WpOverlayBackgroundSwatches extends StatelessWidget {
  const WpOverlayBackgroundSwatches({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final OverlayBackground value;
  final ValueChanged<OverlayBackground> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _SwatchRow(
      items: [
        for (final preset in OverlayBackground.values)
          _SwatchSpec(
            id: 'overlay-background-${preset.value}',
            label: switch (preset) {
              OverlayBackground.marine => l10n.settingsOverlayBackgroundMarine,
              OverlayBackground.graphit =>
                l10n.settingsOverlayBackgroundGraphit,
              OverlayBackground.gletscher =>
                l10n.settingsOverlayBackgroundGletscher,
              OverlayBackground.amber => l10n.settingsOverlayBackgroundAmber,
            },
            selected: preset == value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: preset.surfaceStart,
            ),
            onSelect: () => onChanged(preset),
          ),
      ],
    );
  }
}

/// Localised name of a wave preset.
String overlayWaveName(L10n l10n, OverlayWave wave) {
  final names = <OverlayWave, String>{
    OverlayWave.cyan: l10n.settingsOverlayWaveCyan,
    OverlayWave.violett: l10n.settingsOverlayWaveViolett,
    OverlayWave.neutral: l10n.settingsOverlayWaveNeutral,
    OverlayWave.ink: l10n.settingsOverlayWaveInk,
    OverlayWave.amber: l10n.settingsOverlayWaveAmber,
    OverlayWave.coral: l10n.settingsOverlayWaveCoral,
    OverlayWave.mint: l10n.settingsOverlayWaveMint,
  };
  return names[wave]!;
}

/// Applies a background pick (WP-75b). The wave moves to its deterministic
/// replacement on the new background when it is invalid there, and a short
/// notice names both waves. Used by every place that offers the background row.
void pickOverlayBackground(
  BuildContext context,
  WidgetRef ref,
  AppSettings settings,
  OverlayBackground preset,
) {
  final before = OverlayWave.fromValue(settings.overlay.overlayWave);
  final after = before.validOn(preset);
  ref
      .read(settingsProvider.notifier)
      .updateSettings(
        (s) => s.copyWith(
          overlayBackground: preset.value,
          overlayWave: after.value,
        ),
      );
  if (after == before) return;
  final l10n = L10n.of(context);
  WpToast.show(
    context,
    message: l10n.settingsOverlayWaveReplacedToast(
      overlayWaveName(l10n, before),
      overlayWaveName(l10n, after),
    ),
  );
}

/// Picker for [OverlayWave], drawn for the chosen [background]. Each swatch
/// shows the colour the pill draws on that background, and a wave that is
/// invalid there is disabled.
class WpOverlayWaveSwatches extends StatelessWidget {
  const WpOverlayWaveSwatches({
    super.key,
    required this.value,
    required this.background,
    required this.onChanged,
  });

  final OverlayWave value;
  final OverlayBackground background;
  final ValueChanged<OverlayWave> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _SwatchRow(
      items: [
        for (final preset in OverlayWave.values)
          _SwatchSpec(
            id: 'overlay-wave-${preset.value}',
            label: overlayWaveName(l10n, preset),
            selected: preset == value,
            enabled: preset.isValidOn(background),
            disabledReason: l10n.settingsOverlayWaveUnavailable,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  preset.effectiveOn(background) ??
                  preset.valueOn(background.tone),
            ),
            onSelect: () => onChanged(preset),
          ),
      ],
    );
  }
}

/// One swatch of a [_SwatchRow]. [id] is the stable test and semantics
/// identifier; the widget key derives from it. A disabled swatch can be focused
/// (so its reason is reachable by keyboard) but never selected; [disabledReason]
/// explains why and is printed while the swatch has focus (UX-052).
class _SwatchSpec {
  const _SwatchSpec({
    required this.id,
    required this.label,
    required this.selected,
    required this.decoration,
    required this.onSelect,
    this.enabled = true,
    this.disabledReason,
  });

  final String id;
  final String label;
  final bool selected;
  final bool enabled;
  final String? disabledReason;
  final BoxDecoration decoration;
  final VoidCallback onSelect;
}

/// A row of swatches. Tab reaches the row; the arrow keys, Home and End move
/// focus between swatches without selecting, disabled ones included; Enter,
/// Space or a click select the focused swatch, and a disabled one only takes
/// focus and shows its reason. This is the same behaviour as the appearance
/// cards, so both pickers in the settings page work alike.
class _SwatchRow extends StatefulWidget {
  const _SwatchRow({required this.items});

  final List<_SwatchSpec> items;

  @override
  State<_SwatchRow> createState() => _SwatchRowState();
}

class _SwatchRowState extends State<_SwatchRow> {
  late List<FocusNode> _nodes = _makeNodes(widget.items.length);

  List<FocusNode> _makeNodes(int count) => [
    for (var i = 0; i < count; i++) FocusNode()..addListener(_onFocusChanged),
  ];

  /// Re-renders when focus moves, so a focused disabled swatch shows its
  /// reason (UX-052).
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _SwatchRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final node in _nodes) {
        node.dispose();
      }
      _nodes = _makeNodes(widget.items.length);
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _focusedIndex => _nodes.indexWhere((node) => node.hasFocus);

  /// The swatch next to [from] in direction [step], or null at the end of the
  /// row. Disabled swatches are part of the walk: their reason is reached here.
  int? _neighbour(int from, int step) {
    final i = from + step;
    return i >= 0 && i < _nodes.length ? i : null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final current = _focusedIndex;
    if (current < 0 || _nodes.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final int? target;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      target = _neighbour(current, -1);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      target = _neighbour(current, 1);
    } else if (key == LogicalKeyboardKey.home) {
      target = _neighbour(-1, 1);
    } else if (key == LogicalKeyboardKey.end) {
      target = _neighbour(_nodes.length, -1);
    } else {
      return KeyEventResult.ignored;
    }
    if (target != null && target != current) _nodes[target].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // The reason of a focused disabled swatch, printed under the row (UX-052).
    // Screen readers hear it from the swatch's hint, so it is excluded here.
    final focused = _focusedIndex;
    final reason = focused >= 0 && !widget.items[focused].enabled
        ? widget.items[focused].disabledReason
        : null;
    // Wraps onto a second line instead of overflowing on narrow windows.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                _Swatch(
                  key: ValueKey(widget.items[i].id),
                  focusNode: _nodes[i],
                  id: widget.items[i].id,
                  label: widget.items[i].label,
                  selected: widget.items[i].selected,
                  enabled: widget.items[i].enabled,
                  disabledReason: widget.items[i].disabledReason,
                  decoration: widget.items[i].decoration,
                  onTap: widget.items[i].onSelect,
                ),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: WpSpacing.xs),
            ExcludeSemantics(
              child: Text(
                reason,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFamily: kWpUiFont,
                  fontFamilyFallback: kWpFontFallback,
                  fontSize: WpTypography.small,
                  fontWeight: FontWeight.w400,
                ).copyWith(color: WpColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.focusNode,
    required this.id,
    required this.label,
    required this.selected,
    required this.decoration,
    required this.onTap,
    this.enabled = true,
    this.disabledReason,
  });

  final FocusNode focusNode;
  final String id;
  final String label;
  final bool selected;
  final bool enabled;
  final String? disabledReason;
  final BoxDecoration decoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reason = enabled ? null : disabledReason;
    final target = SizedBox(
      width: _swatchTarget,
      height: _swatchTarget,
      child: Center(
        // A disabled swatch keeps its colour visible but faded, so the user
        // sees what the wave would be and why it cannot be chosen.
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: _swatchDisc,
            height: _swatchDisc,
            decoration: decoration.copyWith(
              // Unselected: a solid 3:1 boundary in both
              // themes. Selected: the accent ring.
              border: Border.all(
                color: selected ? WpColors.accent : WpColors.selectionBorder,
                width: selected ? 2 : 1,
              ),
            ),
          ),
        ),
      ),
    );
    final inkWell = Material(
      color: Colors.transparent,
      child: InkWell(
        focusNode: focusNode,
        customBorder: const CircleBorder(),
        // A disabled swatch takes focus on a tap (and shows its reason)
        // but never selects.
        onTap: enabled ? onTap : focusNode.requestFocus,
        child: target,
      ),
    );
    // The column is at least [_swatchColumn] wide and grows to fit the name,
    // so a name is never cut off at a larger text scale (UX-040). The name may
    // wrap at spaces onto a second line; it is never ellipsised.
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _swatchColumn),
      child: IntrinsicWidth(
        child: MergeSemantics(
          child: Semantics(
            identifier: id,
            button: true,
            enabled: enabled,
            selected: selected,
            label: label,
            hint: reason,
            child: Column(
              children: [
                WpFocusRing(
                  focusNode: focusNode,
                  radius: _swatchTarget / 2,
                  child: reason == null
                      ? inkWell
                      : Tooltip(message: reason, child: inkWell),
                ),
                const SizedBox(height: WpSpacing.xs),
                ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kWpUiFont,
                      fontFamilyFallback: kWpFontFallback,
                      fontSize: WpTypography.small,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? WpColors.accent : WpColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
